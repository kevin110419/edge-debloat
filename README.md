# Edge Debloat

Microsoft Edge에서 MS 서비스 연동, Copilot/AI, 데이터 수집, 광고·뉴스, 자동 업데이트와 백그라운드 상주 요소를 끄는 PowerShell 스크립트입니다. `edge://policy`와 `edge://flags`를 포함한 Edge 설정을 백업하고 복원하는 기능도 들어 있습니다.

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

`Status`와 `List`를 뺀 모든 동작은 관리자 권한 PowerShell에서 실행해야 합니다. `Backup`은 일반 권한으로도 되지만 예약 작업 목록이 빠질 수 있습니다.

## 사용법

```powershell
.\Edge-Debloat.ps1 <Action> [옵션]
```

| Action | 하는 일 |
|---|---|
| `Status` | 정책·서비스·예약 작업·flags가 목표와 얼마나 맞는지 점검합니다(읽기 전용). 생략하면 이 동작입니다. |
| `Apply` | 디블로트를 적용합니다. 직전 상태를 자동으로 백업합니다. |
| `Backup` | 현재 상태를 백업 폴더에 저장합니다. |
| `Restore` | 백업 시점의 상태로 되돌립니다. 기본은 가장 최근 백업입니다. |
| `Revert` | 이 스크립트가 바꾼 항목을 Edge 기본값으로 되돌립니다. 백업이 없어도 됩니다. |
| `List` | 백업 목록을 보여 줍니다. |
| `Schedule` | 자동 백업 일정을 Windows 예약 작업으로 등록합니다. 기본은 매일, 14개 보존입니다. |
| `Unschedule` | 자동 백업 일정을 삭제합니다. 이미 만든 백업은 그대로 둡니다. |

| 옵션 | 설명 |
|---|---|
| `-Parts` | `Apply`·`Restore`·`Revert`의 범위를 좁힙니다. `Policies`, `Background`, `Settings` 중에서 고르며 기본은 전부입니다. |
| `-CloseEdge` | Edge가 실행 중이면 종료합니다. 창을 닫아 보고, 남은 프로세스는 강제 종료합니다. |
| `-BackupRoot` | 백업을 저장하고 찾는 폴더입니다. 생략하면 사용자의 "문서" 폴더 아래 `Edge-Debloat-Backups`입니다. |
| `-BackupPath` | `Restore`에 쓸 백업입니다. 폴더 경로나 백업 폴더 아래의 폴더 이름을 적습니다. |
| `-Label` | `Backup` 폴더 이름 뒤에 붙일 설명입니다. |
| `-Interval` | `Schedule`의 자동 백업 주기입니다. `Hourly`, `Daily`, `Weekly` 중에서 고르며 기본은 `Daily`입니다. |
| `-At` | `Schedule`의 실행 시각(`HH:mm`)입니다. 기본은 `12:00`입니다. |
| `-DayOfWeek` | `-Interval Weekly`일 때의 요일입니다. 기본은 `Sunday`입니다. |
| `-Keep` | 보존할 백업 개수입니다. 기본은 14이고, 0이면 지우지 않습니다. |
| `-NoBackup` | `Apply`·`Restore`·`Revert` 직전의 자동 백업을 건너뜁니다. |
| `-Force` | 질문을 건너뜁니다. `Apply`는 모든 정책 분류를 적용하고, `Restore`·`Revert`는 확인 없이 진행합니다. |

### 예시

```powershell
# 현재 상태 점검
.\Edge-Debloat.ps1 Status

# 전체 적용 (Edge를 닫고 진행)
.\Edge-Debloat.ps1 Apply -CloseEdge

# 정책만 적용
.\Edge-Debloat.ps1 Apply -Parts Policies

# 이름을 붙여 백업
.\Edge-Debloat.ps1 Backup -Label before-reinstall

# 다른 폴더에 백업
.\Edge-Debloat.ps1 Backup -BackupRoot D:\Backups\Edge

# 자동 백업 등록 (매일 12:00, 14개 보존)
.\Edge-Debloat.ps1 Schedule

# 매주 월요일 09:00, 8개 보존으로 등록
.\Edge-Debloat.ps1 Schedule -Interval Weekly -DayOfWeek Monday -At 09:00 -Keep 8

# 자동 백업 해제
.\Edge-Debloat.ps1 Unschedule

# 가장 최근 백업으로 복원
.\Edge-Debloat.ps1 Restore -CloseEdge

# 특정 백업에서 정책만 복원
.\Edge-Debloat.ps1 Restore -BackupPath 20261114-120000-before-reinstall -Parts Policies
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

- **서비스**: `edgeupdate`, `edgeupdatem`, `MicrosoftEdgeElevationService`를 중지하고 "사용 안 함"으로 바꿉니다.
- **예약 작업**: `MicrosoftEdgeUpdate*` 작업을 모두 비활성화합니다.
- **자동 실행 항목**: 현재 사용자의 Run 키에서 `MicrosoftEdgeAutoLaunch*` 항목을 삭제합니다.

### Settings: edge://flags

AI 관련 flag 9개를 끕니다. Edge가 실행 중이면 이 단계는 건너뛰므로, Edge를 닫거나 `-CloseEdge`를 붙여야 합니다.

## 백업과 복원

백업 폴더는 기본적으로 사용자의 "문서" 폴더 아래 `Edge-Debloat-Backups`이고, `-BackupRoot`로 바꿀 수 있습니다. "문서"가 OneDrive 등으로 옮겨져 있으면 옮겨진 위치를 따릅니다. `-BackupRoot`는 `Backup`뿐 아니라 `List`, `Restore`, 그리고 `Apply`·`Restore`·`Revert`의 자동 백업에도 적용되므로, 다른 폴더에 저장한 백업을 찾을 때도 같은 값을 줘야 합니다.

`Backup`은 그 아래 `<날짜-시각>[-라벨]\` 폴더에 아래 내용을 저장합니다.

| 범위 | 저장하는 것 |
|---|---|
| `edge://policy` | Edge와 EdgeUpdate 정책 키(HKLM, HKCU) 전체, Windows `AllowTelemetry` 값 |
| `edge://flags`와 설정 | `Local State`, 프로필별 `Preferences`와 `Secure Preferences`, `HKCU\Software\Microsoft\Edge` 키 |
| 백그라운드 | 서비스 시작 유형, 예약 작업 상태, 자동 실행 항목 |

폴더 안의 `policies.json`과 `flags.txt`는 내용을 눈으로 확인하기 위한 목록입니다.

`Restore`는 백업에 있던 키를 통째로 교체하므로, 백업 이후에 추가한 정책은 사라집니다. 프로필 설정을 복원할 때는 Edge가 닫혀 있어야 하며, 복원 직전 상태도 자동으로 백업됩니다.

즐겨찾기, 방문 기록, 비밀번호, 검색 엔진 목록은 설정값이 아니라서 백업하지 않습니다.

### 자동 백업과 보존 개수

`Schedule`은 `Edge-Debloat Backup`이라는 Windows 예약 작업을 등록합니다. 다시 실행하면 기존 일정을 새 값으로 덮어쓰고, `Status`가 일정과 다음 실행 시각, 마지막 실행 결과를 보여 줍니다.

- **일정**: `-Interval`(기본 `Daily`), `-At`(기본 `12:00`), `-DayOfWeek`(주간일 때, 기본 `Sunday`)로 정합니다. 그 시각에 PC가 꺼져 있었다면 켜진 뒤에 실행됩니다.
- **보존 개수**: `-Keep`(기본 14)을 넘으면 오래된 자동 백업부터 지웁니다. 0이면 지우지 않습니다.
- **지우는 범위**: 같은 라벨의 백업끼리만 셉니다. 자동 백업은 라벨이 `auto`라서, 직접 만든 백업이나 `pre-apply`·`pre-restore` 백업은 지우지 않습니다.
- **직접 백업할 때**: `Backup`은 `-Keep`을 직접 적었을 때만 정리합니다. 예를 들어 `Backup -Label weekly -Keep 4`는 `weekly` 백업을 4개만 남깁니다.
- **실행 계정**: 등록한 사용자가 로그온해 있을 때만 실행됩니다. 관리자 권한 없이 등록할 수도 있지만, 그 경우 자동 백업에서 예약 작업 목록이 빠질 수 있습니다.
- **경로 고정**: 스크립트 위치와 `-BackupRoot` 값이 등록 시점에 예약 작업에 기록됩니다. 스크립트를 옮기거나 백업 폴더를 바꾸려면 `Schedule`을 다시 실행하세요.

## 알아둘 점

- **직접 해야 하는 설정**: 기본 검색 엔진(`edge://settings/search`)과 SmartScreen(`edge://settings/privacy`)은 개인 PC에서 정책으로 강제할 수 없어 Edge 설정에서 직접 바꿔야 합니다. SmartScreen을 끄면 방문 URL이 MS로 전송되지 않지만 피싱·악성 다운로드 차단도 사라집니다.
- **적용 확인**: `Apply` 뒤 Edge를 다시 시작하고 `edge://policy`에서 오류가 없는지 확인하세요. Edge 버전이 달라지면 정책 이름이 바뀌거나 없어질 수 있습니다.
- **보안 패치 중단**: 업데이트를 끄면 Edge의 보안 패치도 받지 못합니다. 주기적으로 `Revert -Parts Background,Policies` 후 수동으로 업데이트하는 것을 권합니다.
- **WebView2도 영향**: 같은 업데이트 서비스를 쓰는 WebView2 런타임의 업데이트도 함께 멈춥니다.
- **다시 켜질 수 있음**: Windows 업데이트나 Edge 재설치·복구가 서비스와 예약 작업을 되살릴 수 있습니다. `Status`로 확인하고 `Apply`를 다시 실행하면 됩니다.
- **보안 DNS 분류**: 다른 분류를 적용하면서 "보안 DNS"만 빼면, Edge가 관리되는 브라우저로 판단해 보안 DNS를 끄고 잠급니다.
- **다른 PC로 복원**: `Secure Preferences`는 PC에 묶인 무결성 값으로 보호되므로, 다른 PC에 복원하면 일부 설정이 초기화될 수 있습니다.
- **백업 폴더는 개인 데이터**: 확장 설정 등 프로필 정보가 들어 있습니다. "문서"가 OneDrive와 동기화되고 있다면 백업도 함께 업로드되므로, 원하지 않으면 `-BackupRoot`로 다른 폴더를 지정하세요. 저장소 안의 `backups/`는 `.gitignore`에 등록돼 있습니다.
- **다른 계정으로 관리자 권한을 얻은 경우**: "문서"와 프로필 설정이 그 관리자 계정의 것을 가리킵니다. 평소 쓰는 계정이 관리자 그룹에 속해 있으면 해당되지 않습니다.
