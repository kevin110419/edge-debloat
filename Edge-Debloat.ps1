#requires -Version 5.1
<#
.SYNOPSIS
    Microsoft Edge 디블로트: MS 서비스 연동, Copilot/AI, 데이터 수집, 광고/뉴스,
    업데이트 및 백그라운드 상주 요소를 끕니다. 1회성 적용을 전제로 하며 백업/복원 기능은 없습니다.

.DESCRIPTION
    Action
      Status   현재 상태를 점검합니다(읽기 전용, 관리자 권한 불필요).
      Apply    (기본값) 디블로트를 적용합니다. Edge 정책은 분류별로 적용 여부를 묻습니다(Y/N).
      Revert   이 스크립트가 바꾼 항목을 Edge 기본값으로 되돌립니다.
      Search      검색 엔진을 추가하고 기본 검색 엔진을 바꿉니다(ManagedSearchEngines 정책).
                  -SearchEngines 를 생략하면 목록에서 고르도록 묻습니다.
      SearchReset Search 로 지정한 검색 엔진 정책을 지웁니다.

    Parts (Apply / Revert 에서 범위를 좁힐 때)
      Policies    edge://policy 에 보이는 정책(Edge, EdgeUpdate)과 Windows 진단 데이터 수준
      Background  업데이트 서비스, 예약 작업, 자동 실행 항목
                  (권한 상승 서비스는 저장 암호 복호화에 필요해 끄지 않습니다)
      Settings    edge://flags (Local State)

.PARAMETER CloseEdge
    Edge 가 실행 중이면 종료합니다(창을 닫아 보고, 남은 프로세스는 강제 종료).

.PARAMETER Force
    질문을 건너뜁니다. Apply 는 모든 정책 분류를 적용하고, Revert 는 확인 없이 진행합니다.

.PARAMETER AllowUpdate
    Apply 에서 Edge 업데이트를 막지 않고 허용합니다. Policies 범위에서는 Edge Update 정책을 지우고,
    Background 범위에서는 업데이트 서비스(edgeupdate, edgeupdatem)를 기본 시작 유형으로 되돌리고
    MicrosoftEdgeUpdate 예약 작업을 켭니다. 그 밖의 디블로트 항목은 그대로 적용합니다.
    Status 에 붙이면 업데이트 항목을 "허용" 기준으로 점검합니다.
    다시 막으려면 -AllowUpdate 없이 Apply 를 실행합니다.

.PARAMETER SearchEngines
    Search 에서 등록할 검색 엔진. 미리 정의된 이름(Google, DuckDuckGo, Brave, Startpage, Bing,
    Ecosia, Naver, Daum) 또는 '이름=URL' 형식의 직접 지정. URL 의 검색어 자리는 {searchTerms} 나 %s.

.PARAMETER DefaultSearch
    Search 에서 기본 검색 엔진으로 쓸 엔진. 생략하면 -SearchEngines 의 첫 번째.
    목록에 없는 엔진을 적으면 목록 맨 앞에 추가합니다.

.PARAMETER SearchPolicy
    Recommended(기본): 사용자가 Edge 설정에서 기본 엔진을 바꾸거나 엔진을 더 추가할 수 있습니다.
    Mandatory: 목록이 고정되고, 사용자는 목록 안에서만 기본 엔진을 고를 수 있습니다.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Status

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Apply -CloseEdge

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Apply -AllowUpdate -Parts Policies,Background

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Search

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Search -SearchEngines DuckDuckGo,Google,'Wiki=https://ko.wikipedia.org/w/index.php?search=%s'

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Edge-Debloat.ps1 Revert -CloseEdge
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Status', 'Apply', 'Revert', 'Search', 'SearchReset')]
    [string]$Action = 'Apply',

    [ValidateSet('Policies', 'Background', 'Settings')]
    [string[]]$Parts = @('Policies', 'Background', 'Settings'),

    [switch]$CloseEdge,
    [switch]$Force,
    [switch]$AllowUpdate,

    [string[]]$SearchEngines,
    [string]$DefaultSearch,

    [ValidateSet('Recommended', 'Mandatory')]
    [string]$SearchPolicy = 'Recommended'
)

$ErrorActionPreference = 'Stop'

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

# 끄지 않고 기본 시작 유형(수동)을 유지할 서비스.
# MicrosoftEdgeElevationService 는 Edge 저장 암호의 앱 바인딩 암호화(v20) 키를 풉니다.
# 이 서비스를 끄면 v20 으로 저장된 암호를 복호화하지 못해, 아이디만 추천되고 비밀번호는 채워지지 않습니다.
$KeepServices = @('MicrosoftEdgeElevationService')

# Edge 업데이트를 맡는 서비스. -AllowUpdate 이면 끄지 않고 기본 시작 유형으로 둡니다.
$UpdateServices = @('edgeupdate', 'edgeupdatem')

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

# Search 에서 고를 수 있는 검색 엔진. 값은 ManagedSearchEngines 의 항목 그대로입니다.
# suggest_url 은 검색어 제안용이며, SearchSuggestEnabled = 0 이 적용돼 있으면 쓰이지 않습니다.
$SearchPresets = [ordered]@{
    Google     = [ordered]@{ name = 'Google';     keyword = 'google.com';     search_url = 'https://www.google.com/search?q={searchTerms}'; suggest_url = 'https://www.google.com/complete/search?client=chrome&q={searchTerms}' }
    DuckDuckGo = [ordered]@{ name = 'DuckDuckGo'; keyword = 'duckduckgo.com'; search_url = 'https://duckduckgo.com/?q={searchTerms}';        suggest_url = 'https://duckduckgo.com/ac/?q={searchTerms}&type=list' }
    Brave      = [ordered]@{ name = 'Brave';      keyword = 'search.brave.com'; search_url = 'https://search.brave.com/search?q={searchTerms}'; suggest_url = 'https://search.brave.com/api/suggest?q={searchTerms}' }
    Startpage  = [ordered]@{ name = 'Startpage';  keyword = 'startpage.com';  search_url = 'https://www.startpage.com/sp/search?query={searchTerms}' }
    Bing       = [ordered]@{ name = 'Bing';       keyword = 'bing.com';       search_url = 'https://www.bing.com/search?q={searchTerms}';   suggest_url = 'https://www.bing.com/osjson.aspx?query={searchTerms}' }
    Ecosia     = [ordered]@{ name = 'Ecosia';     keyword = 'ecosia.org';     search_url = 'https://www.ecosia.org/search?q={searchTerms}'; suggest_url = 'https://ac.ecosia.org/autocomplete?q={searchTerms}&type=list' }
    Naver      = [ordered]@{ name = 'Naver';      keyword = 'naver.com';      search_url = 'https://search.naver.com/search.naver?query={searchTerms}' }
    Daum       = [ordered]@{ name = 'Daum';       keyword = 'daum.net';       search_url = 'https://search.daum.net/search?q={searchTerms}' }
}

$EdgePolicyKey   = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'
$UpdatePolicyKey = 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate'

# ManagedSearchEngines 를 기록하는 위치. Recommended 는 사용자가 Edge 설정에서 바꿀 수 있습니다.
# DefaultSearchProvider* 정책은 도메인/MDM 에 가입한 PC 에서만 적용되므로 쓰지 않습니다.
$SearchPolicyKeys = [ordered]@{
    Recommended = "$EdgePolicyKey\Recommended"
    Mandatory   = $EdgePolicyKey
}
$SearchPolicyLabels = @{
    Recommended = '권장, 사용자가 바꿀 수 있음'
    Mandatory   = '필수, 목록 고정'
}
$TelemetryKey    = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
$RunKey          = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'

$UserData   = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
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
#  Search / SearchReset
# =============================================================================

# 번호, 미리 정의된 이름, '이름=URL' 중 하나를 ManagedSearchEngines 항목으로 바꿉니다.
function ConvertTo-SearchEngine {
    param([string]$Token)
    $token = $Token.Trim()
    if (-not $token) { throw '빈 값입니다' }

    $names = @($SearchPresets.Keys)
    $preset = $null
    if ($token -match '^\d+$') {
        $index = [int]$token - 1
        if ($index -lt 0 -or $index -ge $names.Count) { throw "번호는 1-$($names.Count) 사이여야 합니다: $token" }
        $preset = $SearchPresets[$names[$index]]
    }
    elseif ($token -notmatch '=') {
        $match = @($names | Where-Object { $_ -eq $token })
        if ($match.Count -eq 0) { throw "모르는 검색 엔진입니다: $token (사용 가능: $($names -join ', '), 또는 이름=URL)" }
        $preset = $SearchPresets[$match[0]]
    }
    if ($preset) {
        $copy = [ordered]@{}
        foreach ($key in $preset.Keys) { $copy[$key] = $preset[$key] }
        return $copy
    }

    $name, $url = $token -split '=', 2
    $name = $name.Trim()
    $url  = $url.Trim() -replace '%s', '{searchTerms}'
    if (-not $name) { throw "이름이 비어 있습니다: $token" }
    $uri = $null
    if (-not [uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) {
        throw "http(s) 주소가 아닙니다: $url"
    }
    if ($url -notmatch '\{searchTerms\}') { throw "URL 에 검색어 자리({searchTerms} 또는 %s)가 없습니다: $url" }
    [ordered]@{ name = $name; keyword = ($uri.Host -replace '^www\.', ''); search_url = $url }
}

# 입력 목록을 검색 엔진 목록으로 바꾸고, 기본 엔진에 is_default 를 붙입니다.
function Resolve-SearchEngines {
    param([string[]]$Tokens, [string]$DefaultToken)

    $engines = New-Object System.Collections.ArrayList
    foreach ($token in $Tokens) {
        $engine = ConvertTo-SearchEngine $token
        if (@($engines | Where-Object { $_.keyword -eq $engine.keyword }).Count -gt 0) {
            Write-Step 'WARN' "$($engine.name): 키워드 $($engine.keyword) 가 겹쳐 건너뜁니다"
            continue
        }
        [void]$engines.Add($engine)
    }

    $defaultKeyword = $null
    if ($DefaultToken) {
        $default = ConvertTo-SearchEngine $DefaultToken
        $defaultKeyword = $default.keyword
        if (@($engines | Where-Object { $_.keyword -eq $defaultKeyword }).Count -eq 0) { $engines.Insert(0, $default) }
    }
    if ($engines.Count -eq 0) { throw '검색 엔진을 하나 이상 지정하세요' }
    if (-not $defaultKeyword) { $defaultKeyword = $engines[0].keyword }

    foreach ($engine in $engines) {
        if ($engine.keyword -eq $defaultKeyword) { $engine['is_default'] = $true }
    }
    # 하나씩 내보내므로 받는 쪽에서 @( ) 로 감쌉니다.
    $engines
}

# 지금 기록된 ManagedSearchEngines 를 위치별로 읽습니다.
function Get-SearchEnginePolicies {
    foreach ($mode in $SearchPolicyKeys.Keys) {
        $raw = Get-RegValue $SearchPolicyKeys[$mode] 'ManagedSearchEngines'
        if ($null -eq $raw) { continue }
        $engines = $null
        try { $engines = @(([string]$raw | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_.search_url }) } catch { }
        [pscustomobject]@{ Mode = $mode; Raw = [string]$raw; Engines = $engines }
    }
}

function Show-SearchEngines {
    param($Engines)
    foreach ($engine in $Engines) {
        $mark = if ($engine.is_default) { '* ' } else { '  ' }
        Write-Host ("         {0}{1,-12} {2}" -f $mark, $engine.name, $engine.search_url)
    }
}

# DefaultSearchProvider* 정책 값을 위치별로 찾습니다. 이 정책은 도메인/MDM 에 가입하지 않은 PC 에서는
# 적용되지 않고, DefaultSearchProviderSearchURL 이 있으면 Edge 가 ManagedSearchEngines 도 무시합니다.
function Get-DefaultSearchProviderValues {
    foreach ($key in $SearchPolicyKeys.Values) {
        $item = Get-Item -LiteralPath (ConvertTo-PsRegPath $key) -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($name in @($item.GetValueNames() | Where-Object { $_ -like 'DefaultSearchProvider*' })) {
            [pscustomobject]@{ Key = $key; Name = $name; Value = $item.GetValue($name) }
        }
    }
}

function Test-SearchPolicyConflict {
    foreach ($key in $SearchPolicyKeys.Values) {
        if ($null -ne (Get-RegValue $key 'DefaultSearchProviderSearchURL')) {
            Write-Step 'WARN' "$key 에 DefaultSearchProviderSearchURL 이 있어 ManagedSearchEngines 가 무시됩니다(Search 가 지움)"
        }
    }
}

function Read-SearchSelection {
    Write-Section '검색 엔진 선택'
    $i = 1
    foreach ($name in $SearchPresets.Keys) {
        Write-Host ("  {0}. {1,-11} {2}" -f $i, $name, $SearchPresets[$name].search_url)
        $i++
    }
    Write-Host '  직접 추가하려면 이름=URL 형식으로 적습니다(검색어 자리는 {searchTerms} 또는 %s).'
    Write-Host ''

    while ($true) {
        $default = (Read-Host '기본 검색 엔진 (번호, 이름 또는 이름=URL)').Trim()
        if (-not $default) { continue }
        try { [void](ConvertTo-SearchEngine $default); break }
        catch { Write-Step 'FAIL' $_.Exception.Message }
    }
    while ($true) {
        $more = (Read-Host '함께 등록할 엔진 (쉼표로 구분, Enter = 없음)').Trim()
        $tokens = @($default) + @($more -split ',' | Where-Object { $_.Trim() })
        try { return @(Resolve-SearchEngines $tokens $default) }
        catch { Write-Step 'FAIL' $_.Exception.Message }
    }
}

function Invoke-Search {
    Assert-Admin

    if ($SearchEngines -or $DefaultSearch) {
        try { $engines = @(Resolve-SearchEngines @($SearchEngines) $DefaultSearch) }
        catch { Write-Step 'FAIL' $_.Exception.Message; exit 1 }
    }
    elseif ($Force) {
        Write-Step 'FAIL' '-Force 와 함께 쓸 때는 -SearchEngines 로 검색 엔진을 지정하세요'
        exit 1
    }
    else { $engines = @(Read-SearchSelection) }

    Write-Section "검색 엔진 ($($SearchPolicyLabels[$SearchPolicy]))"
    Show-SearchEngines $engines
    Write-Host '         (* = 기본 검색 엔진)'
    $oldProvider = @(Get-DefaultSearchProviderValues)
    if ($oldProvider.Count -gt 0) {
        Write-Step 'WARN' '아래 DefaultSearchProvider* 정책을 함께 지웁니다(가입하지 않은 PC 에서는 적용되지 않고, 남아 있으면 이 목록이 무시됨)'
        foreach ($value in $oldProvider) { Write-Host "         $($value.Key)\$($value.Name) = $($value.Value)" -ForegroundColor Yellow }
    }
    if (-not (Confirm-Action '이 목록을 정책으로 기록할까요?')) {
        Write-Step 'SKIP' '취소됨'
        return
    }

    [void](Close-Edge)

    Write-Section '검색 엔진 정책'
    foreach ($value in $oldProvider) {
        [void](Remove-RegValue $value.Key $value.Name)
        Write-Step 'OK' "$($value.Name) 삭제"
    }
    $json   = ConvertTo-Json -InputObject @($engines) -Compress -Depth 3
    $target = $SearchPolicyKeys[$SearchPolicy]
    foreach ($mode in $SearchPolicyKeys.Keys) {
        if ($mode -ne $SearchPolicy -and (Remove-RegValue $SearchPolicyKeys[$mode] 'ManagedSearchEngines')) {
            Write-Step 'OK' "$($SearchPolicyKeys[$mode]) 의 ManagedSearchEngines 삭제"
        }
    }
    Set-RegValue $target 'ManagedSearchEngines' $json

    $written = @(Get-SearchEnginePolicies | Where-Object { $_.Mode -eq $SearchPolicy })
    if ($written.Count -ne 1 -or @($written[0].Engines).Count -ne $engines.Count) {
        Write-Step 'FAIL' "기록한 값을 다시 읽지 못했습니다: $target"
        exit 1
    }
    $defaultName = ($engines | Where-Object { $_.is_default } | Select-Object -First 1).name
    Write-Step 'OK' "$target\ManagedSearchEngines: 엔진 $($engines.Count)개, 기본 $defaultName"
    Test-SearchPolicyConflict

    if (Test-EdgeRunning) { Write-Step 'WARN' 'Edge 가 실행 중입니다. 이 정책은 Edge 를 다시 시작해야 반영됩니다' }
    Write-Host ''
    Write-Host '완료. Edge 를 다시 시작한 뒤 edge://settings/search 와 edge://policy 를 확인하세요.' -ForegroundColor Green
}

function Invoke-SearchReset {
    Assert-Admin

    Write-Section '검색 엔진 정책 지우기'
    $current = @(Get-SearchEnginePolicies)
    if ($current.Count -eq 0) {
        Write-Step 'SKIP' '검색 엔진 정책 없음'
        return
    }
    foreach ($policy in $current) {
        Write-Step 'INFO' "$($SearchPolicyKeys[$policy.Mode]) ($($SearchPolicyLabels[$policy.Mode]))"
        Show-SearchEngines $policy.Engines
    }
    if (-not (Confirm-Action '검색 엔진 정책을 지울까요?')) {
        Write-Step 'SKIP' '취소됨'
        return
    }

    [void](Close-Edge)

    foreach ($policy in $current) {
        [void](Remove-RegValue $SearchPolicyKeys[$policy.Mode] 'ManagedSearchEngines')
        Write-Step 'OK' "$($SearchPolicyKeys[$policy.Mode]) 의 ManagedSearchEngines 삭제"
    }
    Write-Host ''
    Write-Host '완료. Edge 를 다시 시작한 뒤 edge://settings/search 에서 기본 검색 엔진을 확인하세요.' -ForegroundColor Green
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

        if ($AllowUpdate) {
            $removed = 0
            foreach ($name in $UpdatePolicies.Keys) { if (Remove-RegValue $UpdatePolicyKey $name) { $removed++ } }
            Write-Step 'OK' "Edge Update 정책 ${removed}개 삭제(업데이트 허용)"
        }
        else {
            foreach ($name in $UpdatePolicies.Keys) { Set-RegValue $UpdatePolicyKey $name $UpdatePolicies[$name] }
            Write-Step 'OK' "Edge Update 정책 $($UpdatePolicies.Count)개 기록"
        }

        # Windows 10/11 의 Edge 는 자체 DiagnosticData 보다 Windows 진단 데이터 수준을 따릅니다.
        Set-RegValue $TelemetryKey 'AllowTelemetry' 0
        Write-Step 'OK' 'Windows 진단 데이터 수준 AllowTelemetry = 0'
    }

    if ($Parts -contains 'Background') {
        Write-Section '서비스'
        $services = Get-EdgeServices
        if ($services.Count -eq 0) { Write-Step 'SKIP' 'Edge 서비스 없음' }
        foreach ($svc in $services) {
            if ($KeepServices -contains $svc.Name) {
                # 이전 버전이 꺼 둔 경우 기본값으로 되살립니다.
                if ($svc.Start -eq 'disabled') {
                    try {
                        Set-ServiceStart $svc.Name $ServiceDefaults[$svc.Name]
                        Write-Step 'OK' "$($svc.Name) -> $($ServiceDefaults[$svc.Name]) (저장 암호 복호화에 필요해 되살림)"
                    }
                    catch { Write-Step 'FAIL' "$($svc.Name): $($_.Exception.Message)" }
                }
                else { Write-Step 'SKIP' "$($svc.Name) (저장 암호 복호화에 필요해 유지)" }
                continue
            }
            if ($AllowUpdate -and $UpdateServices -contains $svc.Name) {
                $default = $ServiceDefaults[$svc.Name]
                try {
                    Set-ServiceStart $svc.Name $default
                    Write-Step 'OK' "$($svc.Name) -> $default (업데이트 허용)"
                }
                catch { Write-Step 'FAIL' "$($svc.Name): $($_.Exception.Message)" }
                continue
            }
            try {
                if ($svc.State -ne 'Stopped') { Stop-Service -Name $svc.Name -Force }
                Set-ServiceStart $svc.Name 'disabled'
                Write-Step 'OK' "$($svc.Name) -> 중지, 사용 안 함"
            }
            catch { Write-Step 'FAIL' "$($svc.Name): $($_.Exception.Message)" }
        }
        if (-not $AllowUpdate) {
            Get-Process -Name MicrosoftEdgeUpdate -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }

        Write-Section '예약 작업'
        $tasks = Get-EdgeTasks
        if ($tasks.Count -eq 0) {
            $note = if ($AllowUpdate) { ' (Edge 업데이트가 실행되면 다시 만들어집니다)' } else { '' }
            Write-Step 'SKIP' "MicrosoftEdgeUpdate 작업 없음$note"
        }
        foreach ($task in $tasks) {
            try {
                if ($AllowUpdate) {
                    $task | Enable-ScheduledTask | Out-Null
                    Write-Step 'OK' "$($task.TaskName) -> 사용(업데이트 허용)"
                }
                else {
                    $task | Disable-ScheduledTask | Out-Null
                    Write-Step 'OK' "$($task.TaskName) -> 사용 안 함"
                }
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
    Write-Host '  - SmartScreen 끄기 edge://settings/privacy (방문 URL 이 MS 로 전송됨. 끄면 피싱 차단도 사라짐)'
    if (@(Get-SearchEnginePolicies).Count -eq 0) {
        Write-Host ''
        Write-Host '기본 검색 엔진은 Search 로 바꿀 수 있습니다: .\Edge-Debloat.ps1 Search'
    }
    Write-Host ''
    Write-Host '완료. Edge 를 다시 시작한 뒤 edge://policy 에서 오류가 없는지 확인하세요.' -ForegroundColor Green
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

    if ($Parts -contains 'Policies') {
        Write-Section '정책'
        $removed = 0
        foreach ($name in @((Get-FlatPolicies).Keys)) { if (Remove-RegValue $EdgePolicyKey $name) { $removed++ } }
        Write-Step 'OK' "Edge 정책 ${removed}개 삭제"
        $removed = 0
        foreach ($name in $UpdatePolicies.Keys) { if (Remove-RegValue $UpdatePolicyKey $name) { $removed++ } }
        Write-Step 'OK' "Edge Update 정책 ${removed}개 삭제"
        $removed = 0
        foreach ($key in $SearchPolicyKeys.Values) { if (Remove-RegValue $key 'ManagedSearchEngines') { $removed++ } }
        if ($removed -gt 0) { Write-Step 'OK' '검색 엔진 정책(ManagedSearchEngines) 삭제' }
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
#  Status
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
    if ($AllowUpdate) {
        $present = @($UpdatePolicies.Keys | Where-Object { $null -ne (Get-RegValue $UpdatePolicyKey $_) })
        if ($present.Count -eq 0) { Write-Step 'OK' 'Edge Update 정책 없음(업데이트 허용)' }
        else { Write-Step 'WARN' "Edge Update 정책이 업데이트를 막고 있음: $($present -join ', ')" }
    }
    else { Show-PolicyGroup 'Edge Update' $UpdatePolicyKey $UpdatePolicies }
    $telemetry = Get-RegValue $TelemetryKey 'AllowTelemetry'
    if ($telemetry -eq 0) { Write-Step 'OK' 'Windows 진단 데이터 수준 AllowTelemetry = 0' }
    else { Write-Step 'WARN' "Windows 진단 데이터 수준 AllowTelemetry = $(if ($null -eq $telemetry) { '없음' } else { $telemetry })" }

    Write-Section '검색 엔진'
    $searchPolicies = @(Get-SearchEnginePolicies)
    if ($searchPolicies.Count -eq 0) { Write-Step 'INFO' '검색 엔진 정책 없음(Edge 설정의 값을 씀, Search 로 지정)' }
    foreach ($policy in $searchPolicies) {
        if ($null -eq $policy.Engines) {
            Write-Step 'WARN' "$($SearchPolicyKeys[$policy.Mode])\ManagedSearchEngines 를 읽을 수 없음(JSON 오류)"
            continue
        }
        $default = @($policy.Engines | Where-Object { $_.is_default })
        $state   = if ($default.Count -eq 1) { 'OK' } else { 'WARN' }
        $name    = if ($default.Count -eq 1) { $default[0].name } else { "기본 엔진이 $($default.Count)개" }
        Write-Step $state "ManagedSearchEngines ($($SearchPolicyLabels[$policy.Mode])): 기본 $name, 엔진 $(@($policy.Engines).Count)개"
        Show-SearchEngines $policy.Engines
    }
    if ($searchPolicies.Count -gt 1) { Write-Step 'WARN' '필수와 권장이 모두 있어 필수 정책이 적용됩니다' }
    Test-SearchPolicyConflict

    Write-Section '서비스'
    $services = Get-EdgeServices
    if ($services.Count -eq 0) { Write-Step 'SKIP' 'Edge 서비스 없음' }
    foreach ($svc in $services) {
        if ($KeepServices -contains $svc.Name) {
            $ok = ($svc.Start -ne 'disabled')
            $note = if ($ok) { ' (유지 대상)' } else { ' (꺼져 있으면 저장 암호를 채우지 못함, Apply 로 되살림)' }
            Write-Step $(if ($ok) { 'OK' } else { 'WARN' }) "$($svc.Name): $($svc.Start), $($svc.State)$note"
            continue
        }
        if ($AllowUpdate -and $UpdateServices -contains $svc.Name) {
            $ok = ($svc.Start -ne 'disabled')
            $note = if ($ok) { ' (업데이트 허용)' } else { ' (꺼져 있어 업데이트 불가)' }
            Write-Step $(if ($ok) { 'OK' } else { 'WARN' }) "$($svc.Name): $($svc.Start), $($svc.State)$note"
            continue
        }
        $ok = ($svc.Start -eq 'disabled' -and $svc.State -eq 'Stopped')
        Write-Step $(if ($ok) { 'OK' } else { 'WARN' }) "$($svc.Name): $($svc.Start), $($svc.State)"
    }

    Write-Section '예약 작업 / 자동 실행'
    $tasks = Get-EdgeTasks
    if ($tasks.Count -eq 0) {
        $line = if ($AllowUpdate) { 'MicrosoftEdgeUpdate 작업 없음(업데이트 후 다시 만들어짐)' } else { 'MicrosoftEdgeUpdate 작업 없음' }
        Write-Step $(if ($AllowUpdate) { 'INFO' } else { 'OK' }) $line
    }
    foreach ($task in $tasks) {
        $disabled = ("$($task.State)" -eq 'Disabled')
        $ok = if ($AllowUpdate) { -not $disabled } else { $disabled }
        Write-Step $(if ($ok) { 'OK' } else { 'WARN' }) "$($task.TaskName): $($task.State)"
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

    Write-Host ''
}

# =============================================================================
#  실행
# =============================================================================

switch ($Action) {
    'Status'      { Invoke-Status }
    'Apply'       { Invoke-Apply }
    'Revert'      { Invoke-Revert }
    'Search'      { Invoke-Search }
    'SearchReset' { Invoke-SearchReset }
}
