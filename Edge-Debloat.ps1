#requires -Version 5.1
<#
.SYNOPSIS
    Microsoft Edge 디블로트: MS 서비스 연동, Copilot/AI, 데이터 수집, 광고/뉴스,
    업데이트 및 백그라운드 상주 요소를 끄고, Edge 설정 전체를 백업/복원합니다.

.DESCRIPTION
    Action
      Status   현재 상태를 점검합니다(읽기 전용, 관리자 권한 불필요).
      Apply    (기본값) 디블로트를 적용합니다. Edge 정책은 분류별로 적용 여부를 묻고(Y/N),
               적용 직전 상태를 자동으로 백업합니다.
      Backup   정책, 서비스, 예약 작업, flags, 프로필 설정을 백업 폴더에 저장합니다.
      Restore  백업 시점의 상태로 되돌립니다(기본: 가장 최근 백업).
      Revert   이 스크립트가 바꾼 항목을 Edge 기본값으로 되돌립니다(백업 불필요).
      List     백업 목록을 보여 줍니다.
      Schedule    자동 백업 일정을 Windows 예약 작업으로 등록합니다(기본: 매일, 14개 보존).
      Unschedule  자동 백업 일정을 삭제합니다.

    Parts (Apply / Restore / Revert 에서 범위를 좁힐 때)
      Policies    edge://policy 에 보이는 정책(Edge, EdgeUpdate)과 Windows 진단 데이터 수준
      Background  업데이트/권한 상승 서비스, 예약 작업, 자동 실행 항목
      Settings    edge://flags 와 프로필 설정(Local State, Preferences, Secure Preferences)

.PARAMETER BackupRoot
    백업을 저장하고 찾는 폴더. 생략하면 사용자의 '문서' 폴더 아래 Edge-Debloat-Backups.
    Backup 뿐 아니라 List, Restore, 그리고 Apply / Restore / Revert 의 자동 백업에도 적용됩니다.

.PARAMETER BackupPath
    Restore 에 쓸 백업. 폴더 경로 또는 백업 폴더 아래의 폴더 이름. 생략하면 가장 최근 백업.

.PARAMETER Label
    Backup 폴더 이름 뒤에 붙일 설명.

.PARAMETER Interval
    Schedule 의 자동 백업 주기. Hourly, Daily, Weekly 중 하나. 기본 Daily.

.PARAMETER At
    Schedule 의 실행 시각(HH:mm). 기본 12:00. 그 시각에 PC 가 꺼져 있었다면 켜진 뒤에 실행됩니다.

.PARAMETER DayOfWeek
    Interval 이 Weekly 일 때의 요일. 기본 Sunday.

.PARAMETER Keep
    보존할 백업 개수. 기본 14, 0 이면 지우지 않습니다. 같은 라벨의 백업끼리만 세어 오래된 것부터
    지우므로, 자동 백업(라벨 auto)의 정리가 직접 만든 백업이나 pre-apply 백업을 지우지 않습니다.
    Schedule 에서는 항상 적용되고, Backup 에서는 -Keep 을 직접 적었을 때만 적용됩니다.

.PARAMETER CloseEdge
    Edge 가 실행 중이면 종료합니다(창을 닫아 보고, 남은 프로세스는 강제 종료).

.PARAMETER NoBackup
    Apply / Restore / Revert 직전의 자동 백업을 건너뜁니다.

.PARAMETER Force
    질문을 건너뜁니다. Apply 는 모든 정책 분류를 적용하고, Restore / Revert 는 확인 없이 진행합니다.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Status

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Apply -CloseEdge

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Backup -Label before-reinstall

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Backup -BackupRoot D:\Backups\Edge

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Schedule

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Schedule -Interval Weekly -DayOfWeek Monday -At 09:00 -Keep 8

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Restore -BackupPath 20261114-120000-before-reinstall -CloseEdge
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Status', 'Apply', 'Backup', 'Restore', 'Revert', 'List', 'Schedule', 'Unschedule')]
    [string]$Action = 'Apply',

    [string]$BackupRoot,
    [string]$BackupPath,
    [string]$Label,

    [ValidateSet('Hourly', 'Daily', 'Weekly')]
    [string]$Interval = 'Daily',

    [ValidatePattern('^([01]?\d|2[0-3]):[0-5]\d$')]
    [string]$At = '12:00',

    [System.DayOfWeek]$DayOfWeek = 'Sunday',

    [ValidateRange(0, 1000)]
    [int]$Keep = 14,

    [ValidateSet('Policies', 'Background', 'Settings')]
    [string[]]$Parts = @('Policies', 'Background', 'Settings'),

    [switch]$CloseEdge,
    [switch]$NoBackup,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Backup 은 -Keep 을 직접 적었을 때만 오래된 백업을 정리합니다.
$KeepSpecified = $PSBoundParameters.ContainsKey('Keep')

# 자동 백업 예약 작업의 이름과, 자동 백업에 붙는 라벨.
$BackupTaskName = 'Edge-Debloat Backup'
$AutoLabel      = 'auto'

# =============================================================================
#  정의
# =============================================================================

# Edge 정책 (HKLM\SOFTWARE\Policies\Microsoft\Edge).
# 정수는 REG_DWORD, 문자열은 REG_SZ 로 기록합니다.
# "기존" 은 policies.json 에서 정상 적용이 확인된 값, "추가" 는 Edge 157 의 정책 표에
# 이름이 있는 것만 골라 더한 값입니다.
$EdgePolicies = [ordered]@{

    'AI / Copilot' = [ordered]@{
        # 기존
        HubsSidebarEnabled                         = 0   # 사이드바 전체(Copilot 포함)
        CopilotPageContext                         = 0
        Microsoft365CopilotChatIconEnabled         = 0
        ComposeInlineEnabled                       = 0
        GenAILocalFoundationalModelSettings        = 1   # 1 = 로컬 AI 모델 다운로드 안 함
        BuiltInAIAPIsEnabled                       = 0
        EdgeHistoryAISearchEnabled                 = 0
        AIGenThemesEnabled                         = 0
        TabServicesEnabled                         = 0
        TextPredictionEnabled                      = 0
        VisualSearchEnabled                        = 0
        NewTabPageBingChatEnabled                  = 0
        # 추가
        AllowBrowsingWithCopilot                   = 0
        CopilotNewTabPageEnabled                   = 0
        CopilotAddressBarSuggestionsEnabled        = 0
        CopilotMultitabEnabled                     = 0
        CopilotCoworkToolActionsEnabled            = 0
        CopilotOnSensitiveContentEnabled           = 0
        CopilotPageContextEnabled                  = 0
        EdgeEntraCopilotPageContext                = 0
        EdgeEntraCopilotPageContextIncludesHistory = 0
        ShareBrowsingHistoryWithCopilotSearchAllowed = 0
        M365LinksAutoOpenCopilotEnabled            = 0
        StandaloneHubsSidebarEnabled               = 0
        SearchInSidebarEnabled                     = 2   # 2 = 사이드바 검색 끔
        DevToolsGenAiSettings                      = 2   # 2 = DevTools AI 기능 끔
        EdgeAutofillMlEnabled                      = 0
        SearchForImageEnabled                      = 0
    }

    '계정 / 동기화' = [ordered]@{
        # 기존
        BrowserSignin                              = 0
        ImplicitSignInEnabled                      = 0   # Windows 에 저장된 MS 계정 자동 연결 차단
        SyncDisabled                               = 1
        # 추가
        WebToBrowserSignInEnabled                  = 0
        SeamlessWebToBrowserSignInEnabled          = 0
        MSAWebSiteSSOUsingThisProfileAllowed       = 0
        AADWebSiteSSOUsingThisProfileEnabled       = 0
    }

    '텔레메트리 / 개인화' = [ordered]@{
        # 기존
        DiagnosticData                             = 0
        PersonalizationReportingEnabled            = 0
        UserFeedbackAllowed                        = 0
        ExperimentationAndConfigurationServiceControl = 0
        EdgeAssetDeliveryServiceEnabled            = 0
        # 추가
        UrlDiagnosticDataEnabled                   = 0
        Edge3PSerpTelemetryEnabled                 = 0
        ConfigureDoNotTrack                        = 1
        PaymentMethodQueryEnabled                  = 0
    }

    '입력/URL 을 MS 로 보내는 부가 서비스' = [ordered]@{
        # 기존
        SearchSuggestEnabled                       = 0
        MicrosoftEditorProofingEnabled             = 0
        TranslateEnabled                           = 0
        ResolveNavigationErrorsUseWebService       = 0
        AlternateErrorPagesEnabled                 = 0
        NetworkPredictionOptions                   = 2   # 2 = 미리 로드/미리 연결 안 함
        TyposquattingCheckerEnabled                = 0
        # 추가
        MicrosoftEditorSynonymsEnabled             = 0
        ConfigureOnlineTextToSpeech                = 0
        EdgeReadingModeServiceBasedExtractionEnabled = 0
        AddressBarTrendingSuggestEnabled           = 0
        SmartScreenDnsRequestsEnabled              = 0
        ScarewareBlockerSendDetectedSitesToSmartScreenEnabled = 0
    }

    '새 탭 페이지' = [ordered]@{
        # 기존
        NewTabPageContentEnabled                   = 0   # 뉴스 피드
        NewTabPageAllowedBackgroundTypes           = 3   # 3 = 배경 이미지/동영상 없음
        NewTabPageHideDefaultTopSites              = 1
        NewTabPageQuickLinksEnabled                = 0
        NewTabPagePrerenderEnabled                 = 0
        # 추가
        NewTabPageAppLauncherEnabled               = 0
        NewTabPageSearchBox                        = 'redirect'   # 새 탭 검색을 주소 표시줄 엔진으로
    }

    '광고 / 권유 / MS 부가 기능' = [ordered]@{
        # 기존
        DefaultBrowserSettingsCampaignEnabled      = 0   # Bing/기본 브라우저 복원 권유
        ShowRecommendationsEnabled                 = 0
        SpotlightExperiencesAndRecommendationsEnabled = 0
        EdgeShoppingAssistantEnabled               = 0
        ShowMicrosoftRewards                       = 0
        EdgeWalletCheckoutEnabled                  = 0
        MicrosoftEdgeInsiderPromotionEnabled       = 0
        # 추가
        HideFirstRunExperience                     = 1
        AutoImportAtFirstRun                       = 4   # 4 = 다른 브라우저에서 자동으로 가져오지 않음
        PromotionalTabsEnabled                     = 0
        PinningWizardAllowed                       = 0
        GuidedSwitchEnabled                        = 0
        ShowPDFDefaultRecommendationsEnabled       = 0
        ShowAcrobatSubscriptionButton              = 0
        ShowOfficeShortcutInFavoritesBar           = 0
        PinBrowserEssentialsToolbarButton          = 0
        PersonalizeTopSitesInCustomizeSidebarEnabled = 0
        QuickSearchShowMiniMenu                    = 0
        SearchbarAllowed                           = 0
        SearchbarIsEnabledOnStartup                = 0
        WalletDonationEnabled                      = 0
        EdgeWalletEtreeEnabled                     = 0
        AllowGamesMenu                             = 0
        EdgeEDropEnabled                           = 0
        UploadFromPhoneEnabled                     = 0
        SharedLinksEnabled                         = 0
        InAppSupportEnabled                        = 0
        FamilySafetySettingsEnabled                = 0
    }

    '백그라운드 상주 / 구성 요소 업데이트' = [ordered]@{
        # 기존
        StartupBoostEnabled                        = 0
        BackgroundModeEnabled                      = 0
        # 추가
        LaunchEdgeOnWindowsStartupEnabled          = 0
        ComponentUpdatesEnabled                    = 0   # 구성 요소 백그라운드 업데이트
    }

    # 정책이 하나라도 걸리면 Edge 가 보안 DNS 를 끄고 잠그므로 정책으로 직접 켭니다.
    '보안 DNS' = [ordered]@{
        DnsOverHttpsMode                           = 'secure'
        DnsOverHttpsTemplates                      = 'https://cloudflare-dns.com/dns-query'
    }
}

# Edge Update 정책 (HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate).
$UpdatePolicies = [ordered]@{
    UpdateDefault                = 0   # 모든 채널 업데이트 끔
    AutoUpdateCheckPeriodMinutes = 0   # 주기적 업데이트 확인 끔
    InstallDefault               = 0   # Edge Update 를 통한 설치 끔
}

# 서비스와 Revert 때 되돌릴 기본 시작 유형.
$ServiceDefaults = [ordered]@{
    'edgeupdate'                    = 'delayed-auto'
    'edgeupdatem'                   = 'demand'
    'MicrosoftEdgeElevationService' = 'demand'
}

# edge://flags. "이름@번호" 에서 번호는 드롭다운 순서입니다(일반 flag 는 1 = Enabled, 2 = Disabled).
# edge-ai-search 는 선택지가 여러 개인 flag 로, Edge 157 에서 고른 값을 그대로 옮긴 것입니다.
$Flags = @(
    'edge-ai-explain-devtools@2'
    'edge-ai-search@5'
    'edge-copilot-bridge-cowork@2'
    'edge-copilot-mode@2'
    'edge-devtools-css-copilot@2'
    'edge-llm-prompt-api-for-default@2'
    'edge-llm-rewriter-api-for-default@2'
    'edge-llm-summarization-api-for-default@2'
    'edge-llm-writer-api-for-default@2'
)

$EdgePolicyKey   = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'
$UpdatePolicyKey = 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate'
$TelemetryKey    = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
$RunKey          = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'

# 백업/복원 때 통째로 내보내는 레지스트리 키.
$RegistryKeys = @(
    @{ Id = 'policy-edge-hklm';       Part = 'Policies'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge' }
    @{ Id = 'policy-edgeupdate-hklm'; Part = 'Policies'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' }
    @{ Id = 'policy-edge-hkcu';       Part = 'Policies'; Key = 'HKCU\SOFTWARE\Policies\Microsoft\Edge' }
    @{ Id = 'policy-edgeupdate-hkcu'; Part = 'Policies'; Key = 'HKCU\SOFTWARE\Policies\Microsoft\EdgeUpdate' }
    # Secure Preferences 의 무결성 값(PreferenceMACs)이 여기에 있어 프로필 설정과 한 묶음입니다.
    @{ Id = 'edge-user-hkcu';         Part = 'Settings'; Key = 'HKCU\SOFTWARE\Microsoft\Edge' }
)

# 프로필 폴더마다 백업하는 설정 파일.
$ProfileFiles = @('Preferences', 'Secure Preferences')

# 백업 폴더: -BackupRoot 로 지정하고, 생략하면 '문서' 아래 Edge-Debloat-Backups 입니다.
# '문서' 가 OneDrive 등으로 옮겨져 있으면 옮겨진 위치를 따릅니다.
if ($BackupRoot) {
    $BackupRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BackupRoot)
}
else {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if (-not $documents) { $documents = Join-Path $env:USERPROFILE 'Documents' }
    $BackupRoot = Join-Path $documents 'Edge-Debloat-Backups'
}
$UserData   =Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

# =============================================================================
#  공통 함수
# =============================================================================

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Status, [string]$Message)
    $color = switch ($Status) {
        'OK'   { 'Green' }
        'SKIP' { 'DarkGray' }
        'INFO' { 'Gray' }
        'FAIL' { 'Red' }
        default { 'Yellow' }
    }
    Write-Host ('[{0,-4}] {1}' -f $Status, $Message) -ForegroundColor $color
}

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-Admin)) {
        Write-Host "'$Action' 은 관리자 권한 PowerShell 에서 실행해야 합니다." -ForegroundColor Red
        exit 1
    }
}

function Confirm-Action {
    param([string]$Question)
    if ($Force) { return $true }
    $answer = Read-Host "$Question (y/N)"
    $answer -match '^(y|yes)$'
}

# 표준 오류를 PowerShell 오류로 바꾸지 않고 외부 명령을 실행합니다.
function Invoke-Native {
    param([string]$File, [string[]]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $File
    $psi.Arguments = ($Arguments | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join ' '
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out  = $proc.StandardOutput.ReadToEnd()
    $err  = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = ($out + $err).Trim() }
}

function ConvertTo-PsRegPath {
    param([string]$Key)
    'Registry::' + ($Key -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU\\', 'HKEY_CURRENT_USER\')
}

function Test-RegKey {
    param([string]$Key)
    Test-Path -LiteralPath (ConvertTo-PsRegPath $Key)
}

function Get-RegValue {
    param([string]$Key, [string]$Name)
    $item = Get-Item -LiteralPath (ConvertTo-PsRegPath $Key) -ErrorAction SilentlyContinue
    if ($item) { $item.GetValue($Name, $null) }
}

function Set-RegValue {
    param([string]$Key, [string]$Name, $Value)
    $path = ConvertTo-PsRegPath $Key
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    $type = if ($Value -is [string]) { 'String' } else { 'DWord' }
    New-ItemProperty -LiteralPath $path -Name $Name -Value $Value -PropertyType $type -Force | Out-Null
}

function Remove-RegValue {
    param([string]$Key, [string]$Name)
    if ($null -eq (Get-RegValue $Key $Name)) { return $false }
    Remove-ItemProperty -LiteralPath (ConvertTo-PsRegPath $Key) -Name $Name -Force
    $true
}

function Get-FlatPolicies {
    $flat = [ordered]@{}
    foreach ($group in $EdgePolicies.Keys) {
        foreach ($name in $EdgePolicies[$group].Keys) { $flat[$name] = $EdgePolicies[$group][$name] }
    }
    $flat
}

# Edge 정책 분류마다 적용 여부를 묻고, 적용할 분류 이름을 돌려줍니다.
# 기본값은 Y 라서 빈 Enter 는 적용으로 처리하고, -Force 면 묻지 않고 전부 적용합니다.
function Select-PolicyGroups {
    if ($Force) { return @($EdgePolicies.Keys) }

    Write-Section '적용할 정책 분류 선택'
    $selected = @()
    foreach ($group in $EdgePolicies.Keys) {
        do {
            $answer = (Read-Host "$group ($($EdgePolicies[$group].Count)개) 적용할까요? (Y/n)").Trim()
        } while ($answer -notmatch '^[yn]?$')
        if ($answer -notmatch '^n$') { $selected += $group }
    }
    $selected
}

function Get-EdgeVersion {
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $root) { continue }
        $exe = Join-Path $root 'Microsoft\Edge\Application\msedge.exe'
        if (Test-Path -LiteralPath $exe) { return (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion }
    }
    $null
}

function Test-EdgeRunning {
    [bool](Get-Process -Name msedge -ErrorAction SilentlyContinue)
}

# Edge 가 닫혀 있으면 $true. -CloseEdge 가 있으면 닫기를 시도합니다.
function Close-Edge {
    if (-not (Test-EdgeRunning)) { return $true }
    if (-not $CloseEdge) { return $false }
    Get-Process -Name msedge -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        ForEach-Object { [void]$_.CloseMainWindow() }
    for ($i = 0; $i -lt 20 -and (Test-EdgeRunning); $i++) { Start-Sleep -Milliseconds 250 }
    Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and (Test-EdgeRunning); $i++) { Start-Sleep -Milliseconds 250 }
    -not (Test-EdgeRunning)
}

function Get-ProfileDirs {
    if (-not (Test-Path -LiteralPath $UserData)) { return @() }
    @(Get-ChildItem -LiteralPath $UserData -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Preferences') } |
            ForEach-Object { $_.Name })
}

# --- 서비스 / 예약 작업 -------------------------------------------------------

function Get-EdgeServices {
    @(Get-CimInstance Win32_Service -Filter "Name LIKE 'edgeupdate%' OR Name LIKE 'MicrosoftEdgeElevationService%'" |
            ForEach-Object {
                $reg = "HKLM\SYSTEM\CurrentControlSet\Services\$($_.Name)"
                $mode = switch ($_.StartMode) {
                    'Disabled' { 'disabled' }
                    'Manual'   { 'demand' }
                    default    { if ((Get-RegValue $reg 'DelayedAutostart') -eq 1) { 'delayed-auto' } else { 'auto' } }
                }
                [pscustomobject]@{ Name = $_.Name; Start = $mode; State = $_.State }
            })
}

function Set-ServiceStart {
    param([string]$Name, [string]$Start)
    $result = Invoke-Native 'sc.exe' @('config', $Name, 'start=', $Start)
    if ($result.ExitCode -ne 0) { throw "sc.exe config 실패: $($result.Output)" }
}

function Get-EdgeTasks {
    @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MicrosoftEdgeUpdate*' })
}

function Get-EdgeRunEntries {
    $item = Get-Item -LiteralPath (ConvertTo-PsRegPath $RunKey) -ErrorAction SilentlyContinue
    if (-not $item) { return @() }
    @($item.GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' } |
            ForEach-Object { [pscustomobject]@{ Name = $_; Value = [string]$item.GetValue($_) } })
}

# --- edge://flags (Local State 의 browser.enabled_labs_experiments) -----------

$FlagsPattern = [regex]'"enabled_labs_experiments"\s*:\s*\[(?<body>[^\]]*)\]'

function Get-EdgeFlags {
    $path = Join-Path $UserData 'Local State'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $match = $FlagsPattern.Match([IO.File]::ReadAllText($path, $Utf8NoBom))
    if (-not $match.Success) { return @() }
    @([regex]::Matches($match.Groups['body'].Value, '"([^"\\]+)"') | ForEach-Object { $_.Groups[1].Value })
}

# Local State 에서 flags 배열만 바꿉니다. 이 파일에는 저장된 비밀번호/쿠키의 암호화 키도
# 들어 있으므로, 다른 부분은 한 글자도 건드리지 않고 결과를 다시 파싱해 검증한 뒤에만 씁니다.
function Update-EdgeFlags {
    param([string[]]$Set = @(), [string[]]$RemoveNames = @(), [string]$Path = (Join-Path $UserData 'Local State'))

    $path = $Path
    if (-not (Test-Path -LiteralPath $path)) { return 'Local State 파일이 없습니다(Edge 를 한 번 실행한 뒤 다시 시도)' }

    $text    = [IO.File]::ReadAllText($path, $Utf8NoBom)
    $found = $FlagsPattern.Matches($text)
    if ($found.Count -gt 1) { return 'flags 항목이 여러 개라 수정하지 않았습니다' }

    $current = @()
    if ($found.Count -eq 1) {
        $current = @([regex]::Matches($found[0].Groups['body'].Value, '"([^"\\]+)"') | ForEach-Object { $_.Groups[1].Value })
    }
    $dropNames = @($Set | ForEach-Object { ($_ -split '@')[0] }) + @($RemoveNames)
    $kept      = @($current | Where-Object { $dropNames -notcontains ($_ -split '@')[0] })
    $new       = @(@($kept) + @($Set) | Sort-Object -Unique)

    if ((@($current | Sort-Object) -join '|') -eq ($new -join '|')) { return 'unchanged' }

    $json = '"enabled_labs_experiments":[' + (($new | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']'
    if ($found.Count -eq 1) {
        $m = $found[0]
        $newText = $text.Substring(0, $m.Index) + $json + $text.Substring($m.Index + $m.Length)
    }
    else {
        $anchor = '"browser":{'
        $index  = $text.IndexOf($anchor)
        if ($index -lt 0) { return 'Local State 에 browser 항목이 없어 수정하지 않았습니다' }
        $insertAt = $index + $anchor.Length
        $sep      = if ($text[$insertAt] -eq '}') { '' } else { ',' }
        $newText  = $text.Insert($insertAt, $json + $sep)
    }

    try {
        $before = $text    | ConvertFrom-Json
        $after  = $newText | ConvertFrom-Json
    }
    catch {
        return "Local State 를 검증할 수 없어 수정하지 않았습니다: $($_.Exception.Message)"
    }
    $written = @($after.browser.enabled_labs_experiments | Sort-Object) -join '|'
    if ($written -ne ($new -join '|')) { return '검증 실패(flags 불일치)로 수정하지 않았습니다' }
    if ([string]$before.os_crypt.encrypted_key -ne [string]$after.os_crypt.encrypted_key) {
        return '검증 실패(암호화 키 불일치)로 수정하지 않았습니다'
    }

    $temp = "$path.edge-debloat.tmp"
    [IO.File]::WriteAllText($temp, $newText, $Utf8NoBom)
    Move-Item -LiteralPath $temp -Destination $path -Force
    'changed'
}

# =============================================================================
#  Backup
# =============================================================================

function New-EdgeBackup {
    param([string]$BackupLabel)

    $name = Get-Date -Format 'yyyyMMdd-HHmmss'
    if ($BackupLabel) { $name += '-' + ($BackupLabel -replace '[^\w\-\.]', '_') }
    $dir = Join-Path $BackupRoot $name
    New-Item -ItemType Directory -Path (Join-Path $dir 'registry') -Force | Out-Null

    Write-Section "백업: $name"

    if (-not (Test-Admin)) {
        Write-Step 'WARN' '관리자 권한이 아니라 예약 작업 목록이 빠질 수 있습니다'
    }
    $edgeRunning = Test-EdgeRunning
    if ($edgeRunning) {
        Write-Step 'WARN' 'Edge 실행 중: 방금 바꾼 설정은 아직 파일에 기록되지 않았을 수 있습니다'
    }

    # 레지스트리 키
    $registry = @()
    foreach ($entry in $RegistryKeys) {
        $existed = Test-RegKey $entry.Key
        if ($existed) {
            $file   = Join-Path $dir "registry\$($entry.Id).reg"
            $result = Invoke-Native 'reg.exe' @('export', $entry.Key, $file, '/y')
            if ($result.ExitCode -ne 0) { throw "reg export 실패 ($($entry.Key)): $($result.Output)" }
            Write-Step 'OK' "레지스트리 $($entry.Key)"
        }
        else {
            Write-Step 'SKIP' "레지스트리 $($entry.Key) (없음)"
        }
        $registry += [ordered]@{ Id = $entry.Id; Part = $entry.Part; Key = $entry.Key; Existed = $existed }
    }

    # 사람이 읽기 위한 정책 목록
    $policySnapshot = [ordered]@{}
    $policyItem = Get-Item -LiteralPath (ConvertTo-PsRegPath $EdgePolicyKey) -ErrorAction SilentlyContinue
    if ($policyItem) {
        foreach ($valueName in ($policyItem.GetValueNames() | Sort-Object)) {
            $policySnapshot[$valueName] = $policyItem.GetValue($valueName)
        }
    }
    [IO.File]::WriteAllText((Join-Path $dir 'policies.json'), ($policySnapshot | ConvertTo-Json), $Utf8NoBom)

    # 서비스 / 예약 작업 / 자동 실행
    $services = @(Get-EdgeServices | ForEach-Object { [ordered]@{ Name = $_.Name; Start = $_.Start } })
    Write-Step 'OK' "서비스 $($services.Count)개"
    $tasks = @(Get-EdgeTasks | ForEach-Object {
            [ordered]@{ TaskPath = $_.TaskPath; TaskName = $_.TaskName; Enabled = ("$($_.State)" -ne 'Disabled') }
        })
    Write-Step 'OK' "예약 작업 $($tasks.Count)개"
    $runEntries = @(Get-EdgeRunEntries | ForEach-Object { [ordered]@{ Name = $_.Name; Value = $_.Value } })

    # 프로필 설정 파일
    $files = @()
    if (Test-Path -LiteralPath $UserData) {
        $relPaths = @('Local State')
        foreach ($profileDir in (Get-ProfileDirs)) {
            foreach ($fileName in $ProfileFiles) { $relPaths += (Join-Path $profileDir $fileName) }
        }
        foreach ($rel in $relPaths) {
            $source = Join-Path $UserData $rel
            if (-not (Test-Path -LiteralPath $source)) { continue }
            $target = Join-Path $dir (Join-Path 'userdata' $rel)
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
            $files += $rel
        }
        Write-Step 'OK' "설정 파일 $($files.Count)개 (flags 포함)"
    }
    else {
        Write-Step 'SKIP' 'Edge 사용자 데이터 폴더 없음'
    }

    $flags = @(Get-EdgeFlags)
    [IO.File]::WriteAllLines((Join-Path $dir 'flags.txt'), [string[]]$flags, $Utf8NoBom)

    $manifest = [ordered]@{
        Created        = (Get-Date).ToString('s')
        Label          = $BackupLabel
        EdgeVersion    = Get-EdgeVersion
        User           = "$env:USERDOMAIN\$env:USERNAME"
        UserData       = $UserData
        EdgeWasRunning = $edgeRunning
        Registry       = $registry
        AllowTelemetry = Get-RegValue $TelemetryKey 'AllowTelemetry'
        Services       = $services
        Tasks          = $tasks
        RunEntries     = $runEntries
        Files          = $files
        Flags          = $flags
    }
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), ($manifest | ConvertTo-Json -Depth 6), $Utf8NoBom)

    Write-Step 'OK' "저장 위치: $dir"
    $dir
}

function Get-EdgeBackups {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { return @() }
    @(Get-ChildItem -LiteralPath $BackupRoot -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json') } |
            Sort-Object Name)
}

function Read-Manifest {
    param([string]$Dir)
    [IO.File]::ReadAllText((Join-Path $Dir 'manifest.json'), $Utf8NoBom) | ConvertFrom-Json
}

# 같은 라벨의 백업 중 최근 $Count 개만 남기고 오래된 것부터 지웁니다.
# 이 스크립트가 만든 폴더(날짜-시각 이름 + manifest.json)만 대상입니다.
function Remove-OldBackups {
    param([string]$BackupLabel, [int]$Count)
    if ($Count -le 0) { return }

    $same = @(Get-EdgeBackups | Where-Object {
            if ($_.Name -notmatch '^\d{8}-\d{6}') { return $false }
            try { [string](Read-Manifest $_.FullName).Label -eq [string]$BackupLabel } catch { $false }
        })
    $excess = $same.Count - $Count
    if ($excess -le 0) { return }

    foreach ($old in $same[0..($excess - 1)]) {
        try {
            Remove-Item -LiteralPath $old.FullName -Recurse -Force
            Write-Step 'OK' "오래된 백업 삭제: $($old.Name)"
        }
        catch { Write-Step 'FAIL' "$($old.Name) 삭제 실패: $($_.Exception.Message)" }
    }
}

# =============================================================================
#  Schedule / Unschedule
# =============================================================================

function Get-ScheduleSummary {
    $when = switch ($Interval) {
        'Hourly' { "매시간 (기준 $At)" }
        'Daily'  { "매일 $At" }
        'Weekly' { "매주 $DayOfWeek $At" }
    }
    "$when, 보존 $(if ($Keep -gt 0) { "${Keep}개" } else { '무제한' })"
}

function Invoke-Schedule {
    $time    = [datetime]::Today.Add([timespan]::Parse($At))
    $trigger = switch ($Interval) {
        'Hourly' { New-ScheduledTaskTrigger -Once -At $time -RepetitionInterval (New-TimeSpan -Hours 1) }
        'Daily'  { New-ScheduledTaskTrigger -Daily -At $time }
        'Weekly' { New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $time }
    }

    # 경로 끝의 \ 는 닫는 따옴표를 이스케이프하므로 떼어 냅니다.
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" Backup -Label {1} -Keep {2} -BackupRoot "{3}"' -f `
        $PSCommandPath, $AutoLabel, $Keep, $BackupRoot.TrimEnd('\')
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments

    # 프로필 설정과 HKCU 를 읽어야 하므로 지금 사용자로, 로그온해 있을 때만 실행합니다.
    $isAdmin   = Test-Admin
    $runLevel  = if ($isAdmin) { 'Highest' } else { 'Limited' }
    $user      = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $runLevel
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Write-Section '자동 백업 일정'
    Register-ScheduledTask -TaskName $BackupTaskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description "Edge-Debloat 자동 백업: $(Get-ScheduleSummary)" -Force | Out-Null

    Write-Step 'OK' "등록: $(Get-ScheduleSummary)"
    Write-Step 'INFO' "실행 계정: $user"
    Write-Step 'INFO' "저장 위치: $BackupRoot"
    Write-Step 'INFO' "스크립트: $PSCommandPath (옮기면 Schedule 을 다시 실행해야 함)"
    if (-not $isAdmin) {
        Write-Step 'WARN' '관리자 권한 없이 등록해, 자동 백업에서 예약 작업 목록이 빠질 수 있습니다'
    }
}

function Invoke-Unschedule {
    Write-Section '자동 백업 일정'
    if (-not (Get-ScheduledTask -TaskName $BackupTaskName -ErrorAction SilentlyContinue)) {
        Write-Step 'SKIP' '등록된 일정 없음'
        return
    }
    Unregister-ScheduledTask -TaskName $BackupTaskName -Confirm:$false
    Write-Step 'OK' '일정 삭제(이미 만든 백업은 그대로 둠)'
}

function Resolve-Backup {
    if ($BackupPath) {
        foreach ($candidate in @($BackupPath, (Join-Path $BackupRoot $BackupPath))) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'manifest.json')) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
        throw "백업을 찾을 수 없습니다: $BackupPath"
    }
    $all = Get-EdgeBackups
    if ($all.Count -eq 0) { throw "백업이 없습니다: $BackupRoot" }
    $all[-1].FullName
}

# =============================================================================
#  Apply
# =============================================================================

function Invoke-Apply {
    Assert-Admin

    # 무언가를 바꾸기 전에 먼저 묻습니다.
    $selectedGroups = @()
    if ($Parts -contains 'Policies') { $selectedGroups = @(Select-PolicyGroups) }

    $edgeClosed = $true
    if ($Parts -contains 'Settings') { $edgeClosed = Close-Edge }

    if (-not $NoBackup) { New-EdgeBackup -BackupLabel 'pre-apply' | Out-Null }

    if ($Parts -contains 'Policies') {
        Write-Section '정책'
        foreach ($group in $EdgePolicies.Keys) {
            if ($selectedGroups -notcontains $group) {
                Write-Step 'SKIP' "$group (선택 안 함, 기존 값은 그대로 둠)"
                continue
            }
            foreach ($name in $EdgePolicies[$group].Keys) {
                Set-RegValue $EdgePolicyKey $name $EdgePolicies[$group][$name]
            }
            Write-Step 'OK' "$group $($EdgePolicies[$group].Count)개 기록"
        }

        foreach ($name in $UpdatePolicies.Keys) { Set-RegValue $UpdatePolicyKey $name $UpdatePolicies[$name] }
        Write-Step 'OK' "Edge Update 정책 $($UpdatePolicies.Count)개 기록"

        # Windows 10/11 의 Edge 는 자체 DiagnosticData 보다 Windows 진단 데이터 수준을 따릅니다.
        Set-RegValue $TelemetryKey 'AllowTelemetry' 0
        Write-Step 'OK' 'Windows 진단 데이터 수준 AllowTelemetry = 0'
    }

    if ($Parts -contains 'Background') {
        Write-Section '서비스'
        $services = Get-EdgeServices
        if ($services.Count -eq 0) { Write-Step 'SKIP' 'Edge 서비스 없음' }
        foreach ($svc in $services) {
            try {
                if ($svc.State -ne 'Stopped') { Stop-Service -Name $svc.Name -Force }
                Set-ServiceStart $svc.Name 'disabled'
                Write-Step 'OK' "$($svc.Name) -> 중지, 사용 안 함"
            }
            catch { Write-Step 'FAIL' "$($svc.Name): $($_.Exception.Message)" }
        }
        Get-Process -Name MicrosoftEdgeUpdate -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        Write-Section '예약 작업'
        $tasks = Get-EdgeTasks
        if ($tasks.Count -eq 0) { Write-Step 'SKIP' 'MicrosoftEdgeUpdate 작업 없음' }
        foreach ($task in $tasks) {
            try {
                $task | Disable-ScheduledTask | Out-Null
                Write-Step 'OK' "$($task.TaskName) -> 사용 안 함"
            }
            catch { Write-Step 'FAIL' "$($task.TaskName): $($_.Exception.Message)" }
        }

        Write-Section '자동 실행 항목'
        $entries = Get-EdgeRunEntries
        if ($entries.Count -eq 0) { Write-Step 'SKIP' 'MicrosoftEdgeAutoLaunch 항목 없음' }
        foreach ($entry in $entries) {
            [void](Remove-RegValue $RunKey $entry.Name)
            Write-Step 'OK' "삭제: $($entry.Name)"
        }
    }

    if ($Parts -contains 'Settings') {
        Write-Section 'edge://flags'
        if (-not $edgeClosed) {
            Write-Step 'WARN' 'Edge 실행 중이라 flags 는 건너뜁니다. Edge 를 닫거나 -CloseEdge 로 다시 실행하세요'
        }
        else {
            $result = Update-EdgeFlags -Set $Flags
            switch ($result) {
                'changed'   { Write-Step 'OK' "flags $($Flags.Count)개 설정" }
                'unchanged' { Write-Step 'SKIP' 'flags 가 이미 설정돼 있음' }
                default     { Write-Step 'WARN' $result }
            }
        }
    }

    Write-Section '직접 해야 하는 설정'
    Write-Host '아래 항목은 개인 PC 에서 정책으로 강제할 수 없어 Edge 설정에서 직접 바꿔야 합니다.'
    Write-Host '  - 검색 엔진        edge://settings/search'
    Write-Host '  - SmartScreen 끄기 edge://settings/privacy (방문 URL 이 MS 로 전송됨. 끄면 피싱 차단도 사라짐)'
    Write-Host ''
    Write-Host '완료. Edge 를 다시 시작한 뒤 edge://policy 에서 오류가 없는지 확인하세요.' -ForegroundColor Green
}

# =============================================================================
#  Restore
# =============================================================================

function Invoke-Restore {
    Assert-Admin

    $dir      = Resolve-Backup
    $manifest = Read-Manifest $dir

    Write-Section "복원: $(Split-Path $dir -Leaf)"
    Write-Step 'INFO' "백업 시각 $($manifest.Created), Edge $($manifest.EdgeVersion), 사용자 $($manifest.User)"
    Write-Step 'INFO' "범위: $($Parts -join ', ')"

    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    if ($manifest.User -ne $currentUser) {
        Write-Step 'WARN' "백업한 사용자($($manifest.User))와 지금 사용자($currentUser)가 다릅니다. 프로필 설정은 지금 사용자에게 복원됩니다"
    }
    $currentVersion = Get-EdgeVersion
    if ($currentVersion -and $manifest.EdgeVersion -and $currentVersion -ne $manifest.EdgeVersion) {
        Write-Step 'WARN' "Edge 버전이 다릅니다(백업 $($manifest.EdgeVersion), 현재 $currentVersion)"
    }

    if (-not (Confirm-Action '현재 상태를 이 백업으로 덮어쓸까요?')) {
        Write-Step 'SKIP' '취소됨'
        return
    }

    if ($Parts -contains 'Settings') {
        if (-not (Close-Edge)) {
            Write-Step 'FAIL' 'Edge 가 실행 중입니다. Edge 를 닫거나 -CloseEdge 를 붙이세요. 아무것도 바꾸지 않았습니다'
            exit 1
        }
    }

    if (-not $NoBackup) { New-EdgeBackup -BackupLabel 'pre-restore' | Out-Null }

    Write-Section '레지스트리'
    foreach ($entry in @($manifest.Registry)) {
        if ($Parts -notcontains $entry.Part) { continue }
        if (Test-RegKey $entry.Key) {
            $result = Invoke-Native 'reg.exe' @('delete', $entry.Key, '/f')
            if ($result.ExitCode -ne 0) { Write-Step 'FAIL' "$($entry.Key) 삭제 실패: $($result.Output)"; continue }
        }
        if ($entry.Existed) {
            $file   = Join-Path $dir "registry\$($entry.Id).reg"
            $result = Invoke-Native 'reg.exe' @('import', $file)
            if ($result.ExitCode -ne 0) { Write-Step 'FAIL' "$($entry.Key) 가져오기 실패: $($result.Output)"; continue }
            Write-Step 'OK' "$($entry.Key) 복원"
        }
        else {
            Write-Step 'OK' "$($entry.Key) 제거(백업 시점에 없었음)"
        }
    }

    if ($Parts -contains 'Policies') {
        if ($null -ne $manifest.AllowTelemetry) {
            Set-RegValue $TelemetryKey 'AllowTelemetry' ([int]$manifest.AllowTelemetry)
            Write-Step 'OK' "AllowTelemetry = $($manifest.AllowTelemetry)"
        }
        elseif (Remove-RegValue $TelemetryKey 'AllowTelemetry') {
            Write-Step 'OK' 'AllowTelemetry 제거(백업 시점에 없었음)'
        }
    }

    if ($Parts -contains 'Background') {
        Write-Section '서비스 / 예약 작업 / 자동 실행'
        foreach ($svc in @($manifest.Services)) {
            if (-not (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue)) {
                Write-Step 'SKIP' "$($svc.Name) (설치돼 있지 않음)"
                continue
            }
            try {
                Set-ServiceStart $svc.Name $svc.Start
                Write-Step 'OK' "$($svc.Name) -> $($svc.Start)"
            }
            catch { Write-Step 'FAIL' "$($svc.Name): $($_.Exception.Message)" }
        }
        foreach ($saved in @($manifest.Tasks)) {
            $task = Get-ScheduledTask -TaskPath $saved.TaskPath -TaskName $saved.TaskName -ErrorAction SilentlyContinue
            if (-not $task) { Write-Step 'SKIP' "$($saved.TaskName) (없음)"; continue }
            try {
                if ($saved.Enabled) { $task | Enable-ScheduledTask | Out-Null } else { $task | Disable-ScheduledTask | Out-Null }
                Write-Step 'OK' "$($saved.TaskName) -> $(if ($saved.Enabled) { '사용' } else { '사용 안 함' })"
            }
            catch { Write-Step 'FAIL' "$($saved.TaskName): $($_.Exception.Message)" }
        }
        foreach ($entry in (Get-EdgeRunEntries)) { [void](Remove-RegValue $RunKey $entry.Name) }
        foreach ($entry in @($manifest.RunEntries)) {
            Set-RegValue $RunKey $entry.Name ([string]$entry.Value)
            Write-Step 'OK' "자동 실행 항목 복원: $($entry.Name)"
        }
    }

    if ($Parts -contains 'Settings') {
        Write-Section '프로필 설정 (flags 포함)'
        foreach ($rel in @($manifest.Files)) {
            $source = Join-Path $dir (Join-Path 'userdata' $rel)
            $target = Join-Path $UserData $rel
            if (-not (Test-Path -LiteralPath $source)) { Write-Step 'FAIL' "$rel (백업에 파일 없음)"; continue }
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
            Write-Step 'OK' $rel
        }
    }

    Write-Host ''
    Write-Host '복원 완료. Edge 를 시작해 edge://policy 와 edge://flags 를 확인하세요.' -ForegroundColor Green
}

# =============================================================================
#  Revert
# =============================================================================

function Invoke-Revert {
    Assert-Admin

    Write-Section 'Edge 기본값으로 되돌리기'
    Write-Step 'INFO' "범위: $($Parts -join ', ')"
    if (-not (Confirm-Action '이 스크립트가 적용한 항목을 Edge 기본값으로 되돌릴까요?')) {
        Write-Step 'SKIP' '취소됨'
        return
    }

    $edgeClosed = $true
    if ($Parts -contains 'Settings') { $edgeClosed = Close-Edge }

    if (-not $NoBackup) { New-EdgeBackup -BackupLabel 'pre-revert' | Out-Null }

    if ($Parts -contains 'Policies') {
        Write-Section '정책'
        $removed = 0
        foreach ($name in @((Get-FlatPolicies).Keys)) { if (Remove-RegValue $EdgePolicyKey $name) { $removed++ } }
        Write-Step 'OK' "Edge 정책 ${removed}개 삭제"
        $removed = 0
        foreach ($name in $UpdatePolicies.Keys) { if (Remove-RegValue $UpdatePolicyKey $name) { $removed++ } }
        Write-Step 'OK' "Edge Update 정책 ${removed}개 삭제"
        Write-Step 'INFO' 'Windows 진단 데이터 수준(AllowTelemetry)은 Windows 전체 설정이라 그대로 둡니다'
    }

    if ($Parts -contains 'Background') {
        Write-Section '서비스 / 예약 작업'
        foreach ($svc in (Get-EdgeServices)) {
            $default = $ServiceDefaults[$svc.Name]
            if (-not $default) { $default = 'demand' }
            try {
                Set-ServiceStart $svc.Name $default
                Write-Step 'OK' "$($svc.Name) -> $default"
            }
            catch { Write-Step 'FAIL' "$($svc.Name): $($_.Exception.Message)" }
        }
        foreach ($task in (Get-EdgeTasks)) {
            try {
                $task | Enable-ScheduledTask | Out-Null
                Write-Step 'OK' "$($task.TaskName) -> 사용"
            }
            catch { Write-Step 'FAIL' "$($task.TaskName): $($_.Exception.Message)" }
        }
    }

    if ($Parts -contains 'Settings') {
        Write-Section 'edge://flags'
        if (-not $edgeClosed) {
            Write-Step 'WARN' 'Edge 실행 중이라 flags 는 건너뜁니다. Edge 를 닫거나 -CloseEdge 로 다시 실행하세요'
        }
        else {
            $result = Update-EdgeFlags -RemoveNames @($Flags | ForEach-Object { ($_ -split '@')[0] })
            switch ($result) {
                'changed'   { Write-Step 'OK' '이 스크립트의 flags 를 기본값으로 되돌림' }
                'unchanged' { Write-Step 'SKIP' '되돌릴 flags 없음' }
                default     { Write-Step 'WARN' $result }
            }
        }
    }

    Write-Host ''
    Write-Host '완료. Edge 를 다시 시작하세요.' -ForegroundColor Green
}

# =============================================================================
#  Status / List
# =============================================================================

function Show-PolicyGroup {
    param([string]$Title, [string]$Key, [System.Collections.IDictionary]$Desired)
    $bad = @()
    foreach ($name in $Desired.Keys) {
        $have = Get-RegValue $Key $name
        if ($null -eq $have) { $bad += "$name (없음, 목표 $($Desired[$name]))" }
        elseif ("$have" -ne "$($Desired[$name])") { $bad += "$name (현재 $have, 목표 $($Desired[$name]))" }
    }
    if ($bad.Count -eq 0) {
        Write-Step 'OK' "$Title $($Desired.Count)/$($Desired.Count)"
    }
    else {
        Write-Step 'WARN' "$Title $($Desired.Count - $bad.Count)/$($Desired.Count)"
        foreach ($line in $bad) { Write-Host "         $line" -ForegroundColor Yellow }
    }
}

function Invoke-Status {
    Write-Section 'Edge'
    $version = Get-EdgeVersion
    Write-Step 'INFO' "버전: $(if ($version) { $version } else { '설치돼 있지 않음' })"
    Write-Step 'INFO' "실행 중: $(if (Test-EdgeRunning) { '예' } else { '아니오' })"
    Write-Step 'INFO' "사용자 데이터: $UserData"
    Write-Step 'INFO' "프로필: $((Get-ProfileDirs) -join ', ')"
    if (-not (Test-Admin)) { Write-Step 'INFO' '관리자 권한이 아니라 예약 작업은 일부만 보일 수 있습니다' }

    Write-Section '정책'
    foreach ($group in $EdgePolicies.Keys) { Show-PolicyGroup $group $EdgePolicyKey $EdgePolicies[$group] }
    Show-PolicyGroup 'Edge Update' $UpdatePolicyKey $UpdatePolicies
    $telemetry = Get-RegValue $TelemetryKey 'AllowTelemetry'
    if ($telemetry -eq 0) { Write-Step 'OK' 'Windows 진단 데이터 수준 AllowTelemetry = 0' }
    else { Write-Step 'WARN' "Windows 진단 데이터 수준 AllowTelemetry = $(if ($null -eq $telemetry) { '없음' } else { $telemetry })" }

    Write-Section '서비스'
    $services = Get-EdgeServices
    if ($services.Count -eq 0) { Write-Step 'SKIP' 'Edge 서비스 없음' }
    foreach ($svc in $services) {
        $ok = ($svc.Start -eq 'disabled' -and $svc.State -eq 'Stopped')
        Write-Step $(if ($ok) { 'OK' } else { 'WARN' }) "$($svc.Name): $($svc.Start), $($svc.State)"
    }

    Write-Section '예약 작업 / 자동 실행'
    $tasks = Get-EdgeTasks
    if ($tasks.Count -eq 0) { Write-Step 'OK' 'MicrosoftEdgeUpdate 작업 없음' }
    foreach ($task in $tasks) {
        $disabled = ("$($task.State)" -eq 'Disabled')
        Write-Step $(if ($disabled) { 'OK' } else { 'WARN' }) "$($task.TaskName): $($task.State)"
    }
    $entries = Get-EdgeRunEntries
    if ($entries.Count -eq 0) { Write-Step 'OK' 'MicrosoftEdgeAutoLaunch 항목 없음' }
    foreach ($entry in $entries) { Write-Step 'WARN' "자동 실행 항목: $($entry.Name)" }

    Write-Section 'edge://flags'
    $current = @(Get-EdgeFlags)
    $missing = @($Flags | Where-Object { $current -notcontains $_ })
    if ($missing.Count -eq 0) { Write-Step 'OK' "flags $($Flags.Count)/$($Flags.Count)" }
    else {
        Write-Step 'WARN' "flags $($Flags.Count - $missing.Count)/$($Flags.Count)"
        foreach ($flag in $missing) { Write-Host "         $flag" -ForegroundColor Yellow }
    }
    $others = @($current | Where-Object { $Flags -notcontains $_ })
    if ($others.Count -gt 0) { Write-Step 'INFO' "그 밖에 바꾼 flags: $($others -join ', ')" }

    Write-Section '백업'
    $backups = Get-EdgeBackups
    Write-Step 'INFO' "위치: $BackupRoot"
    $backupTask = Get-ScheduledTask -TaskName $BackupTaskName -ErrorAction SilentlyContinue
    if (-not $backupTask) {
        Write-Step 'INFO' '자동 백업 일정 없음(Schedule 로 등록)'
    }
    else {
        $taskInfo = $backupTask | Get-ScheduledTaskInfo
        Write-Step $(if ("$($backupTask.State)" -eq 'Disabled') { 'WARN' } else { 'OK' }) "$($backupTask.Description) [$($backupTask.State)]"
        Write-Step 'INFO' "다음 실행: $($taskInfo.NextRunTime)"
        # 267011 = 아직 한 번도 실행되지 않음
        if ($taskInfo.LastTaskResult -ne 267011) {
            Write-Step $(if ($taskInfo.LastTaskResult -eq 0) { 'INFO' } else { 'WARN' }) "마지막 실행: $($taskInfo.LastRunTime), 결과 코드 $($taskInfo.LastTaskResult)"
        }
    }
    if ($backups.Count -eq 0) { Write-Step 'INFO' '백업 없음' }
    else { Write-Step 'INFO' "$($backups.Count)개, 최근: $($backups[-1].Name)" }
    Write-Host ''
}

function Invoke-List {
    $backups = Get-EdgeBackups
    if ($backups.Count -eq 0) {
        Write-Host "백업이 없습니다: $BackupRoot"
        return
    }
    $backups | ForEach-Object {
        $manifest = Read-Manifest $_.FullName
        [pscustomobject]@{
            Name     = $_.Name
            Created  = $manifest.Created
            Edge     = $manifest.EdgeVersion
            Policies = @((Get-Content -LiteralPath (Join-Path $_.FullName 'policies.json') -Raw | ConvertFrom-Json).PSObject.Properties).Count
            Flags    = @($manifest.Flags).Count
            Files    = @($manifest.Files).Count
        }
    } | Format-Table -AutoSize
}

# =============================================================================
#  실행
# =============================================================================

switch ($Action) {
    'Status'  { Invoke-Status }
    'Apply'   { Invoke-Apply }
    'Backup'  {
        New-EdgeBackup -BackupLabel $Label | Out-Null
        if ($KeepSpecified) { Remove-OldBackups -BackupLabel $Label -Count $Keep }
    }
    'Schedule'   { Invoke-Schedule }
    'Unschedule' { Invoke-Unschedule }
    'Restore' { Invoke-Restore }
    'Revert'  { Invoke-Revert }
    'List'    { Invoke-List }
}
