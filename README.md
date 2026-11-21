# Edge Debloat

**English** | [한국어](#korean)

A PowerShell script that turns off Microsoft service integrations, Copilot/AI, data collection, ads and news, automatic updates, and background components in Microsoft Edge. It is a simple debloat tool meant to be applied once, so it has no backup or restore feature. You can return the applied items to Edge defaults with `Revert`.

- Target: Windows 10/11, Windows PowerShell 5.1 or later
- Baseline: Edge 157 (policy names were checked against this version's policy list)

## Preparation

### Allow unsigned scripts

This script is not signed. The default Windows execution policy blocks unsigned scripts, so first turn on the option to **run unsigned scripts**.

- **From Settings**: Settings > System > Advanced ("For developers" on older builds) > PowerShell, turn on the option that changes the execution policy to allow local, unsigned PowerShell scripts to run.
- **From a command**: change the same setting directly in PowerShell.

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This option only allows scripts created locally. If you downloaded the script from the internet, unblock it once.

```powershell
Unblock-File .\Edge-Debloat.ps1
```

### Administrator rights

Every action except `Status` must run in an elevated (administrator) PowerShell.

## Usage

```powershell
.\Edge-Debloat.ps1 <Action> [options]
```

| Action | What it does |
|---|---|
| `Status` | Checks how closely policies, services, scheduled tasks and flags match the target (read-only). |
| `Apply` | Applies the debloat. This is the default when no Action is given. |
| `Revert` | Returns the items this script changed to Edge defaults. |
| `Search` | Adds search engines and changes the default search engine. See [Search engines](#search-engines). |
| `SearchReset` | Removes the search engine policy set by `Search`. |

| Option | Description |
|---|---|
| `-Parts` | Narrows the scope of `Apply` and `Revert`. Choose from `Policies`, `Background` and `Settings`; the default is all of them. |
| `-CloseEdge` | Closes Edge if it is running. It tries closing the windows first, then force-kills any remaining processes. |
| `-Force` | Skips prompts. `Apply` applies every policy category, and `Revert` proceeds without confirmation. |
| `-AllowUpdate` | Makes `Apply` allow Edge updates instead of blocking them. With `Status`, checks the update items against "allowed". See [Allowing updates](#allowing-updates). |
| `-SearchEngines` | Search engines for `Search` to register. List predefined names or `Name=URL` entries, separated by commas. If omitted, you are asked to pick from a list. |
| `-DefaultSearch` | The search engine `Search` sets as the default. If omitted, the first entry of `-SearchEngines`. |
| `-SearchPolicy` | `Recommended` (default) lets users change it in Edge settings; `Mandatory` locks the list. |

### Examples

```powershell
# Check current status
.\Edge-Debloat.ps1 Status

# Apply everything (closing Edge first)
.\Edge-Debloat.ps1 Apply -CloseEdge

# Apply policies only
.\Edge-Debloat.ps1 Apply -Parts Policies

# Allow updates only (answer N to the policy category prompts to keep existing values)
.\Edge-Debloat.ps1 Apply -AllowUpdate -Parts Policies,Background

# Pick search engines from a list
.\Edge-Debloat.ps1 Search

# DuckDuckGo as default, plus Google and a custom engine
.\Edge-Debloat.ps1 Search -SearchEngines DuckDuckGo,Google,'Wikipedia=https://en.wikipedia.org/w/index.php?search=%s'

# Return applied items to Edge defaults
.\Edge-Debloat.ps1 Revert -CloseEdge
```

## What it applies

`Apply` has three parts, which you can pick with `-Parts`.

### Policies

Edge policies are grouped into the 8 categories below, and `Apply` asks whether to apply each one. The default answer is Y, so pressing Enter applies it. Categories you answer N to are left untouched (existing values are not removed either).

| Category | Policies | Contents |
|---|---|---|
| AI / Copilot | 28 | Sidebar, Copilot page context, writing assistance, local AI models, AI history search, image search |
| Account / Sync | 7 | Browser sign-in, automatic sign-in with the MS account saved in Windows, sync, web sign-in integration |
| Telemetry / Personalization | 9 | Diagnostic data, personalization reporting, feedback, experimentation service, Do Not Track requests |
| Add-on services that send input/URLs to MS | 13 | Search suggestions, spell check, translation, navigation error resolution, preloading, online text-to-speech |
| New tab page | 7 | News feed, background image, default sites, quick links, app launcher |
| Ads / Promotions / MS extras | 28 | Bing and default-browser prompts, recommendations, shopping, Rewards, Wallet, games, Drop |
| Background / Component updates | 4 | Startup boost, background mode, launch at Windows startup, component updates |
| Secure DNS | 2 | Turns on DNS over HTTPS in `secure` mode using Cloudflare |

The following values are also written regardless of category.

- **3 Edge Update policies**: turn off automatic updates, periodic update checks, and installation through Edge Update.
- **Windows diagnostic data level**: writes `AllowTelemetry` as 0. Edge on Windows 10/11 follows this value rather than its own diagnostic data policy.

### Background: services and scheduled tasks

- **Services**: stops `edgeupdate` and `edgeupdatem` and sets them to "Disabled".
- **Kept service**: `MicrosoftEdgeElevationService` is not disabled and stays at its default ("Manual"). Edge locks saved passwords with app-bound encryption (`v20`), and this service unlocks that key. If it is disabled, sign-in forms suggest only the username and passwords are not filled in. If an earlier version of this script disabled the service, `Apply` restores it to "Manual".
- **Scheduled tasks**: disables all `MicrosoftEdgeUpdate*` tasks.
- **Autorun entries**: deletes `MicrosoftEdgeAutoLaunch*` entries from the current user's Run key.

### Allowing updates

With `-AllowUpdate`, `Apply` reverses only the update-related items and applies the rest of the debloat as usual.

| Scope | Without `-AllowUpdate` | With `-AllowUpdate` |
|---|---|---|
| `Policies` | Writes the 3 Edge Update policies (`UpdateDefault`, `AutoUpdateCheckPeriodMinutes`, `InstallDefault`) as 0 | Deletes these 3 policies |
| `Background` | Stops `edgeupdate` and `edgeupdatem` and sets them to "Disabled", disables `MicrosoftEdgeUpdate*` tasks | Restores both services to their default startup types (`edgeupdate` Automatic (Delayed Start), `edgeupdatem` Manual) and enables the tasks |

Updates only work once both the policies and the services are released, so apply `Policies` and `Background` together. Including `Policies` prompts for each policy category; categories you answer N to keep their existing values.

```powershell
# Allow updates → update from edge://settings/help → block again
.\Edge-Debloat.ps1 Apply -AllowUpdate -Parts Policies,Background
.\Edge-Debloat.ps1 Apply -Parts Policies,Background
```

If the `MicrosoftEdgeUpdate*` scheduled tasks had been deleted, they are recreated when an update runs. When you block updates again, `Apply` disables these tasks as well.

### Settings: edge://flags

Turns off 9 AI-related flags. This step is skipped while Edge is running, so close Edge or add `-CloseEdge`.

## Search engines

`Search` sets the search engine list and the default search engine through the `ManagedSearchEngines` policy. It does not use the `DefaultSearchProvider*` policies, because those only apply on domain- or MDM-joined PCs. Run it separately from `Apply`.

The predefined engines are listed below. Put their names in `-SearchEngines`, or enter a number or name in the interactive picker.

| Name | Search URL |
|---|---|
| `Google` | `https://www.google.com/search?q={searchTerms}` |
| `DuckDuckGo` | `https://duckduckgo.com/?q={searchTerms}` |
| `Brave` | `https://search.brave.com/search?q={searchTerms}` |
| `Startpage` | `https://www.startpage.com/sp/search?query={searchTerms}` |
| `Bing` | `https://www.bing.com/search?q={searchTerms}` |
| `Ecosia` | `https://www.ecosia.org/search?q={searchTerms}` |
| `Naver` | `https://search.naver.com/search.naver?query={searchTerms}` |
| `Daum` | `https://search.daum.net/search?q={searchTerms}` |

- **Custom engines**: write them as `Name=URL`. Mark the search term with `{searchTerms}` or `%s`; the keyword becomes the URL's host name (without `www.`). The interactive picker splits entries on commas, so use `-SearchEngines` if a URL contains a comma.
- **Default engine**: set it with `-DefaultSearch`; if omitted, the first engine is used. An engine that is not in the list is added to the front.
- **`Recommended` (default)**: written to `HKLM\SOFTWARE\Policies\Microsoft\Edge\Recommended`. Users can change the default engine or add more engines in `edge://settings/search`.
- **`Mandatory`**: written to `HKLM\SOFTWARE\Policies\Microsoft\Edge`. Only the listed engines can be used, and users can only choose the default among them.
- **Changing and removing**: running `Search` again overwrites the whole list with the new values. `SearchReset` or `Revert -Parts Policies` removes this policy.
- **When it takes effect**: Edge must be restarted. `-CloseEdge` closes a running Edge.
- **Existing `DefaultSearchProvider*` policies**: if `DefaultSearchProviderSearchURL` exists, Edge ignores `ManagedSearchEngines`, so `Search` shows any `DefaultSearchProvider*` values already written and removes them as well.
- **When it is ignored**: the policy also does not apply to profiles signed in with a Microsoft account. `Status` checks for both this and the case above.
- **Search suggestions**: some predefined engines include a suggestion URL, but if you applied the "Add-on services that send input/URLs to MS" category (`SearchSuggestEnabled = 0`), suggestions stay off.

## Notes

- **Settings to change yourself**: SmartScreen (`edge://settings/privacy`) cannot be enforced by policy on a personal PC, so change it in Edge settings yourself. The default search engine can be changed with [`Search`](#search-engines). Turning off SmartScreen stops visited URLs from being sent to MS, but also removes phishing and malicious-download protection.
- **Verify the result**: after `Apply`, restart Edge and check `edge://policy` for errors. Policy names may change or disappear in other Edge versions.
- **No security patches**: turning off updates also stops Edge security patches. It is recommended to periodically allow updates with `Apply -AllowUpdate -Parts Policies,Background`, update manually, and then apply again without `-AllowUpdate`. `Revert -Parts Policies` removes all Edge policies, not only the update policies.
- **WebView2 is affected too**: updates for the WebView2 Runtime, which uses the same update service, stop as well.
- **Things may turn back on**: Windows Update or reinstalling/repairing Edge can bring back the services and scheduled tasks. Check with `Status` and run `Apply` again.
- **Secure DNS category**: if you apply other categories but skip only "Secure DNS", Edge treats itself as a managed browser and turns secure DNS off and locks it.
- **No backup**: `Apply` does not save the previous state. `Revert` only returns the items this script changed to Edge defaults; it does not restore values you changed yourself before applying.
- **Elevating with a different account**: the flags (`Local State`) and the current user's autorun entries then belong to that administrator account. This does not apply if your everyday account is in the Administrators group.

---

<a id="korean"></a>

# Edge Debloat

[English](#edge-debloat) | **한국어**

Microsoft Edge에서 MS 서비스 연동, Copilot/AI, 데이터 수집, 광고·뉴스, 자동 업데이트와 백그라운드 상주 요소를 끄는 PowerShell 스크립트입니다. 1회성 적용을 전제로 하는 단순한 디블로트 도구라서 백업·복원 기능은 넣지 않았습니다. 적용한 항목은 `Revert`로 Edge 기본값으로 되돌릴 수 있습니다.

- 대상: Windows 10/11, Windows PowerShell 5.1 이상
- 기준 버전: Edge 157 (정책 이름을 이 버전의 정책 표와 대조함)

## 실행 준비

### 서명하지 않은 스크립트 실행 허용

이 스크립트는 서명돼 있지 않습니다. Windows의 기본 실행 정책은 서명하지 않은 스크립트를 막으므로, 먼저 **서명하지 않은 스크립트 실행** 옵션을 켜야 합니다.

- **설정에서 켜기**: 설정 > 시스템 > 고급(이전 빌드에서는 "개발자용") > PowerShell에서, 서명하지 않은 로컬 PowerShell 스크립트를 실행하도록 실행 정책을 변경하는 옵션을 켭니다.
- **명령으로 켜기**: 같은 설정을 PowerShell에서 직접 바꿉니다.

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

이 옵션은 로컬에서 만든 스크립트만 허용합니다. 스크립트를 인터넷에서 내려받았다면 차단 표시를 한 번 풀어야 합니다.

```powershell
Unblock-File .\Edge-Debloat.ps1
```

### 관리자 권한

`Status`를 뺀 모든 동작은 관리자 권한 PowerShell에서 실행해야 합니다.

## 사용법

```powershell
.\Edge-Debloat.ps1 <Action> [옵션]
```

| Action | 하는 일 |
|---|---|
| `Status` | 정책·서비스·예약 작업·flags가 목표와 얼마나 맞는지 점검합니다(읽기 전용). |
| `Apply` | 디블로트를 적용합니다. Action을 생략하면 이 동작입니다. |
| `Revert` | 이 스크립트가 바꾼 항목을 Edge 기본값으로 되돌립니다. |
| `Search` | 검색 엔진을 추가하고 기본 검색 엔진을 바꿉니다. 자세한 내용은 [검색 엔진](#검색-엔진)을 보세요. |
| `SearchReset` | `Search`로 지정한 검색 엔진 정책을 지웁니다. |

| 옵션 | 설명 |
|---|---|
| `-Parts` | `Apply`·`Revert`의 범위를 좁힙니다. `Policies`, `Background`, `Settings` 중에서 고르며 기본은 전부입니다. |
| `-CloseEdge` | Edge가 실행 중이면 종료합니다. 창을 닫아 보고, 남은 프로세스는 강제 종료합니다. |
| `-Force` | 질문을 건너뜁니다. `Apply`는 모든 정책 분류를 적용하고, `Revert`는 확인 없이 진행합니다. |
| `-AllowUpdate` | `Apply`에서 Edge 업데이트를 막지 않고 허용합니다. `Status`에 붙이면 업데이트 항목을 "허용" 기준으로 점검합니다. 자세한 내용은 [업데이트 허용](#업데이트-허용)을 보세요. |
| `-SearchEngines` | `Search`에서 등록할 검색 엔진입니다. 미리 정의된 이름이나 `이름=URL`을 쉼표로 나열합니다. 생략하면 목록에서 고르도록 묻습니다. |
| `-DefaultSearch` | `Search`에서 기본으로 쓸 검색 엔진입니다. 생략하면 `-SearchEngines`의 첫 번째입니다. |
| `-SearchPolicy` | `Recommended`(기본)는 사용자가 Edge 설정에서 바꿀 수 있고, `Mandatory`는 목록을 고정합니다. |

### 예시

```powershell
# 현재 상태 점검
.\Edge-Debloat.ps1 Status

# 전체 적용 (Edge를 닫고 진행)
.\Edge-Debloat.ps1 Apply -CloseEdge

# 정책만 적용
.\Edge-Debloat.ps1 Apply -Parts Policies

# 업데이트만 허용 (정책 분류 질문에는 N 으로 답하면 기존 값을 그대로 둠)
.\Edge-Debloat.ps1 Apply -AllowUpdate -Parts Policies,Background

# 검색 엔진을 목록에서 골라 지정
.\Edge-Debloat.ps1 Search

# DuckDuckGo 를 기본으로, Google 과 직접 만든 엔진을 함께 등록
.\Edge-Debloat.ps1 Search -SearchEngines DuckDuckGo,Google,'위키백과=https://ko.wikipedia.org/w/index.php?search=%s'

# 적용한 항목을 Edge 기본값으로 되돌림
.\Edge-Debloat.ps1 Revert -CloseEdge
```

## 적용 내용

`Apply`는 세 부분으로 나뉘며 `-Parts`로 고를 수 있습니다.

### Policies: 정책

Edge 정책은 아래 8개 분류로 나뉘어 있고, `Apply`가 분류마다 적용 여부를 묻습니다. 기본값은 Y라서 Enter만 눌러도 적용되며, N을 고른 분류는 건드리지 않습니다(이미 있는 값도 지우지 않습니다).

| 분류 | 정책 수 | 내용 |
|---|---|---|
| AI / Copilot | 28 | 사이드바, Copilot 페이지 컨텍스트, 작성 도우미, 로컬 AI 모델, 기록 AI 검색, 이미지 검색 |
| 계정 / 동기화 | 7 | 브라우저 로그인, Windows에 저장된 MS 계정 자동 연결, 동기화, 웹 로그인 연동 |
| 텔레메트리 / 개인화 | 9 | 진단 데이터, 개인화 보고, 피드백, 실험 서비스, 추적 안 함 요청 |
| 입력/URL을 MS로 보내는 부가 서비스 | 13 | 검색어 제안, 맞춤법 검사, 번역, 탐색 오류 해결, 미리 로드, 온라인 음성 합성 |
| 새 탭 페이지 | 7 | 뉴스 피드, 배경 이미지, 기본 사이트, 빠른 링크, 앱 실행기 |
| 광고 / 권유 / MS 부가 기능 | 28 | Bing·기본 브라우저 복원 권유, 추천, 쇼핑, Rewards, Wallet, 게임, Drop |
| 백그라운드 상주 / 구성 요소 업데이트 | 4 | 시작 부스트, 백그라운드 모드, Windows 시작 시 실행, 구성 요소 업데이트 |
| 보안 DNS | 2 | DNS over HTTPS를 `secure` 모드로 켜고 Cloudflare를 사용 |

분류와 무관하게 다음 값도 함께 기록합니다.

- **Edge Update 정책 3개**: 자동 업데이트, 주기적 업데이트 확인, Edge Update를 통한 설치를 끕니다.
- **Windows 진단 데이터 수준**: `AllowTelemetry`를 0으로 기록합니다. Windows 10/11의 Edge는 자체 진단 데이터 정책보다 이 값을 따릅니다.

### Background: 서비스와 예약 작업

- **서비스**: `edgeupdate`, `edgeupdatem`을 중지하고 "사용 안 함"으로 바꿉니다.
- **유지하는 서비스**: `MicrosoftEdgeElevationService`는 끄지 않고 기본값("수동")으로 둡니다. Edge는 저장한 비밀번호를 앱 바인딩 암호화(`v20`)로 잠그는데, 이 키를 푸는 일을 이 서비스가 맡습니다. 서비스를 끄면 로그인 창에 아이디만 추천되고 비밀번호는 채워지지 않습니다. 이전 버전이 이 서비스를 꺼 두었다면 `Apply`가 "수동"으로 되살립니다.
- **예약 작업**: `MicrosoftEdgeUpdate*` 작업을 모두 비활성화합니다.
- **자동 실행 항목**: 현재 사용자의 Run 키에서 `MicrosoftEdgeAutoLaunch*` 항목을 삭제합니다.

### 업데이트 허용

`-AllowUpdate`를 붙이면 `Apply`가 업데이트 관련 항목만 반대로 처리하고, 나머지 디블로트는 그대로 적용합니다.

| 범위 | `-AllowUpdate` 없이 | `-AllowUpdate`와 함께 |
|---|---|---|
| `Policies` | Edge Update 정책 3개(`UpdateDefault`, `AutoUpdateCheckPeriodMinutes`, `InstallDefault`)를 0으로 기록 | 이 정책 3개를 삭제 |
| `Background` | `edgeupdate`, `edgeupdatem`을 중지하고 "사용 안 함"으로 변경, `MicrosoftEdgeUpdate*` 작업 비활성화 | 두 서비스를 기본 시작 유형(`edgeupdate`는 지연된 자동, `edgeupdatem`은 수동)으로 되돌리고 작업을 활성화 |

업데이트는 정책과 서비스가 모두 풀려야 되므로 `Policies`와 `Background`를 함께 적용하세요. `Policies`를 넣으면 정책 분류마다 적용 여부를 묻는데, N으로 답한 분류는 기존 값을 그대로 둡니다.

```powershell
# 업데이트 허용 → edge://settings/help 에서 업데이트 → 다시 막기
.\Edge-Debloat.ps1 Apply -AllowUpdate -Parts Policies,Background
.\Edge-Debloat.ps1 Apply -Parts Policies,Background
```

`MicrosoftEdgeUpdate*` 예약 작업이 지워져 있었다면 업데이트가 실행될 때 다시 만들어집니다. 다시 막을 때 `Apply`가 이 작업들도 함께 비활성화합니다.

### Settings: edge://flags

AI 관련 flag 9개를 끕니다. Edge가 실행 중이면 이 단계는 건너뛰므로, Edge를 닫거나 `-CloseEdge`를 붙여야 합니다.

## 검색 엔진

`Search`는 `ManagedSearchEngines` 정책으로 검색 엔진 목록과 기본 검색 엔진을 지정합니다. `DefaultSearchProvider*` 정책은 도메인이나 MDM에 가입한 PC에서만 적용되므로 쓰지 않습니다. `Apply`와 따로 실행합니다.

미리 정의된 엔진은 아래와 같습니다. `-SearchEngines`에 이름을 적거나, 대화형 선택에서 번호나 이름을 입력합니다.

| 이름 | 검색 URL |
|---|---|
| `Google` | `https://www.google.com/search?q={searchTerms}` |
| `DuckDuckGo` | `https://duckduckgo.com/?q={searchTerms}` |
| `Brave` | `https://search.brave.com/search?q={searchTerms}` |
| `Startpage` | `https://www.startpage.com/sp/search?query={searchTerms}` |
| `Bing` | `https://www.bing.com/search?q={searchTerms}` |
| `Ecosia` | `https://www.ecosia.org/search?q={searchTerms}` |
| `Naver` | `https://search.naver.com/search.naver?query={searchTerms}` |
| `Daum` | `https://search.daum.net/search?q={searchTerms}` |

- **직접 추가**: `이름=URL` 형식으로 적습니다. 검색어 자리는 `{searchTerms}`나 `%s`로 표시하고, 키워드는 URL의 호스트 이름(`www.` 제외)이 됩니다. 대화형 선택에서는 쉼표로 항목을 나누므로 URL에 쉼표가 있으면 `-SearchEngines`로 지정하세요.
- **기본 엔진**: `-DefaultSearch`로 정하고, 생략하면 첫 번째 엔진입니다. 목록에 없는 엔진을 적으면 맨 앞에 추가합니다.
- **`Recommended`(기본)**: `HKLM\SOFTWARE\Policies\Microsoft\Edge\Recommended`에 기록합니다. 사용자가 `edge://settings/search`에서 기본 엔진을 바꾸거나 엔진을 더 추가할 수 있습니다.
- **`Mandatory`**: `HKLM\SOFTWARE\Policies\Microsoft\Edge`에 기록합니다. 목록에 있는 엔진만 쓸 수 있고, 사용자는 그 안에서 기본 엔진만 고를 수 있습니다.
- **바꾸기와 지우기**: `Search`를 다시 실행하면 목록 전체를 새 값으로 덮어씁니다. `SearchReset`이나 `Revert -Parts Policies`는 이 정책을 지웁니다.
- **반영 시점**: Edge를 다시 시작해야 반영됩니다. `-CloseEdge`를 붙이면 실행 중인 Edge를 닫습니다.
- **기존 `DefaultSearchProvider*` 정책**: `DefaultSearchProviderSearchURL`이 있으면 Edge가 `ManagedSearchEngines`를 무시하므로, `Search`는 이미 기록된 `DefaultSearchProvider*` 값을 보여 준 뒤 함께 지웁니다.
- **무시되는 경우**: Microsoft 계정으로 로그인한 프로필에도 적용되지 않습니다. `Status`가 두 경우를 함께 점검합니다.
- **검색어 제안**: 미리 정의된 엔진 일부에는 제안 URL이 들어 있지만, "입력/URL을 MS로 보내는 부가 서비스" 분류(`SearchSuggestEnabled = 0`)를 적용했다면 제안은 꺼진 상태로 남습니다.

## 알아둘 점

- **직접 해야 하는 설정**: SmartScreen(`edge://settings/privacy`)은 개인 PC에서 정책으로 강제할 수 없어 Edge 설정에서 직접 바꿔야 합니다. 기본 검색 엔진은 [`Search`](#검색-엔진)로 바꿀 수 있습니다. SmartScreen을 끄면 방문 URL이 MS로 전송되지 않지만 피싱·악성 다운로드 차단도 사라집니다.
- **적용 확인**: `Apply` 뒤 Edge를 다시 시작하고 `edge://policy`에서 오류가 없는지 확인하세요. Edge 버전이 달라지면 정책 이름이 바뀌거나 없어질 수 있습니다.
- **보안 패치 중단**: 업데이트를 끄면 Edge의 보안 패치도 받지 못합니다. 주기적으로 `Apply -AllowUpdate -Parts Policies,Background`로 업데이트를 허용해 수동으로 업데이트한 뒤, `-AllowUpdate` 없이 다시 적용하는 것을 권합니다. `Revert -Parts Policies`는 업데이트 정책뿐 아니라 Edge 정책 전체를 지웁니다.
- **WebView2도 영향**: 같은 업데이트 서비스를 쓰는 WebView2 런타임의 업데이트도 함께 멈춥니다.
- **다시 켜질 수 있음**: Windows 업데이트나 Edge 재설치·복구가 서비스와 예약 작업을 되살릴 수 있습니다. `Status`로 확인하고 `Apply`를 다시 실행하면 됩니다.
- **보안 DNS 분류**: 다른 분류를 적용하면서 "보안 DNS"만 빼면, Edge가 관리되는 브라우저로 판단해 보안 DNS를 끄고 잠급니다.
- **백업 없음**: `Apply`는 적용 전 상태를 저장하지 않습니다. `Revert`는 이 스크립트가 바꾼 항목을 Edge 기본값으로 되돌릴 뿐, 적용 전에 직접 바꿔 둔 값까지 되살리지는 않습니다.
- **다른 계정으로 관리자 권한을 얻은 경우**: flags(`Local State`)와 현재 사용자의 자동 실행 항목이 그 관리자 계정의 것을 가리킵니다. 평소 쓰는 계정이 관리자 그룹에 속해 있으면 해당되지 않습니다.
