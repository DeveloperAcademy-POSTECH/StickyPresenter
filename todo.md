# StickyPresenter Todo

## 진행 중
- [x] 뽀모도로 타이머 (집중 ↔ 휴식 무한 반복) — 1.0.4
- [x] 타이머 시작/종료 시 앱 크래시 버그 분석 및 수정

## 배포 전 남은 일
- ⚠️ **빌드 번호는 절대 되돌리지 말 것** — `CFBundleVersion` 은 `MARKETING_VERSION` 과 무관하게
  앱 전체에서 단조 증가해야 한다. 1.0.5 를 빌드 1로 올렸다가 업로드가 거절됐다
  ("must contain a higher version than that of the previously uploaded version [6]").
  1.0.4 가 6 이었으므로 1.0.5 는 **7**. 다음 업로드는 8 이상.
  올릴 때는 `StickyPresenter/Info.plist` 와 `project.yml`(WidgetExtension) 두 곳을 함께.
- [ ] `v1.0.4` 태그 생성 (버전 상향·릴리즈 노트는 완료)
- [ ] 실제 앱에서 손으로 확인 (계산은 격리 하네스로 검증함)
  - 뽀모도로 구간 전환 (메뉴바 🍅 · ⌘⌃B · 입력창 `25/5`)
  - Window 창 우하단 모서리 드래그 감각 (아래 "리사이즈 감각" 항목의 기대 동작대로인지)
- [ ] 배포본에 음원을 **번들할지** 결정
  - 현재 16곡은 로컬 앱 컨테이너에만 있음 — 리포지토리·앱 번들에는 없음
  - 전 곡 Kevin MacLeod / CC-BY 4.0 → 번들 시 앱 내 크레딧 표기 화면 필요 (`CREDITS.txt` 참고)
  - 번들하지 않는다면 첫 실행 안내(`README.txt`)만으로 충분한지 확인
- [ ] Xcode → Signing & Capabilities에서 **App Groups capability 추가** (앱·WidgetExtension 두 타겟 모두)
  - 현재 어떤 프로비저닝 프로필에도 `QGAQ3AY3R3.group.com.leeo.StickyPresenter`가 없음
  - 로컬 개발 실행은 되지만 **App Store 배포 서명은 실패**함
  - 포털에서 수동 등록하면 "already been used" 오류 — Xcode에서 추가할 것
- [ ] 알림 센터 위젯 실제 렌더링 확인 (코드/빌드는 검증했으나 화면 미확인)
- [ ] `v1.0.3` 태그 생성 (버전 상향·릴리즈 노트는 완료)

## 완료
- [x] iOS 리모컨 앱 (MultipeerConnectivity) — `StickyPresenterRemote/` (1.0.4)
  - **별도 Xcode 프로젝트**다. 기존 프로젝트는 파일 동기화 그룹을 안 쓰고 pbxproj 수동 편집이
    필요해서, iOS 타겟을 끼워 넣는 대신 `xcodegen`(`project.yml`)으로 새 프로젝트를 만들었다.
    수정 후에는 `cd StickyPresenterRemote && xcodegen generate` 를 다시 돌릴 것.
  - 프로토콜은 `Shared/RemoteProtocol.swift` **한 파일을 두 프로젝트가 함께 참조**한다
    (복사본을 두면 한쪽만 고쳤을 때 디코딩이 조용히 깨진다).
  - Mac = 광고자(`RemoteControlHost`), iOS = 탐색자(`RemoteClient`). 초대는 자동 수락 —
    발표 직전에 수락 다이얼로그를 띄우면 오히려 방해가 된다.
  - 상태는 1초마다 **전체**를 `.unreliable` 로 브로드캐스트. 델타 동기화는 복잡도만 늘고,
    패킷을 놓쳐도 다음 초에 저절로 복구된다. 명령은 재전송이 없으므로 `.reliable`.
  - 지원 명령: 재생/일시정지, ±30s, 초기화, 크기 S/M/L, 테마 순환, 감추기/표시, 정렬, 삭제,
    프리셋 추가(3m/5m/10m/15m).
  - **권한 설정이 핵심** — 빠지면 상대를 아예 못 찾는다
    - macOS entitlements: `network.client`, `network.server` 추가함
    - 양쪽 Info.plist: `NSBonjourServices` (`_sp-timer._tcp` / `._udp`), `NSLocalNetworkUsageDescription`
    - 서비스 타입 `sp-timer` 는 1~15자·소문자/숫자/하이픈 제약을 지킨 값
  - [x] **연결 확인 완료** — iOS 시뮬레이터 ↔ Mac 앱이 정상 동작한다(시뮬레이터가 호스트
        네트워크를 공유하므로 MultipeerConnectivity 가 그대로 붙는다). 타이머 목록·남은 시간이
        실시간으로 흐르고 명령도 반영된다. 앱 이름은 **Remote Controller**.
  - [ ] iPhone 실기기 확인은 아직 — Wi-Fi 환경이 다르므로 발표 전 한 번은 실기기로 볼 것
  - [ ] 리모컨 앱 서명·번들ID(`com.leeo.StickyPresenter.Remote`) 배포 계획 미정
- [x] 타이머 창 프리셋 크기 S/M/L (1.0.4)
  - `WidgetSize` (S 200 / M 300 / L 420pt). 타이머 행 3번째 줄에 세그먼트 버튼으로 배치
  - `NoteManager.setWidgetSize(_:for:)` — **좌상단 고정**으로 모서리 드래그와 같은 기준.
    위젯 창과 (열려 있으면) 제목 있는 창을 함께 맞춘다
  - 모서리 드래그로 직접 조절하면 `entry.widgetSize` 와 어긋날 수 있다. 그때 S/M/L 은
    "그 크기로 되돌리는" 버튼으로 동작한다 — 의도된 것
- [x] 카멜레온 모드 — 창 뒤 화면색을 읽어 배경으로, 나머지는 보색으로 (1.0.4)
  - `StickyPresenter/Chameleon.swift` 신규. `WidgetTheme` 에 `.chameleon` 추가
    (테마 버튼 순환: 시스템 → 라이트 → 다크 → 카멜레온, 아이콘 `eyedropper.halffull`)
  - ScreenCaptureKit `SCScreenshotManager.captureImage` 로 0.9초마다 창 영역만 캡처 →
    24×24 로 받아 1×1 로 그려 평균색 추출 → 배경색, 링·글자는 그 **보색**
  - 보색 계산의 함정 둘
    - 색상환 반대편만 쓰면 명도가 비슷할 때 글자가 안 읽힘 → 명도를 배경 반대쪽 끝으로 밀고 채도 확보
    - 무채색(흰 문서·검은 배경) 위에서는 보색이 무의미 → 명암 대비(흰/검)로 폴백
  - **피드백 루프 주의**: `SCContentFilter(display:excludingWindows:)` 에 자기 자신을 포함한
    타이머 창 전부(`NoteManager.allTimerWindows()`)를 넣어야 한다. 빠뜨리면 자기가 칠한 색을
    다시 읽어 칠해 색이 발산한다.
  - **화면 기록 권한 필요.** 첫 전환 시 `CGRequestScreenCaptureAccess()` 로 프롬프트.
    허용 후 앱 재시작해야 실제 캡처됨. 권한 없으면 조용히 실패하고 기존 테마로 그림.
  - [ ] App Store 심사 시 화면 기록 권한 사용 사유 설명 필요할 수 있음 — 배포 전 확인
  - [ ] 새 파일은 `project.pbxproj` 에 수동 등록했음(동기화 그룹 아님). 이후 파일 추가 시 동일하게 처리
- [x] 타이머 창 리사이즈 재작업 (1.0.4)
  - 대상: Timers → `3m`/`5m` 등을 누르면 뜨는 **테두리 없는 정사각형 타이머 창** (`showTimerWidget`).
    알림센터 위젯(`WidgetExtension`)이 아니다. 그립은 우하단.
  - 확정된 동작
    - 항상 정사각형 (`aspect`를 현재 크기에서 유도하지 않고 `1`로 고정 → 어긋나도 자동 복귀)
    - 크기는 **마우스 세로 이동량에만** 비례. 가로 드래그는 크기를 바꾸지 않는다(의도된 동작)
    - **좌상단 고정** — 우하단을 끌면 좌상단이 제자리 (표준 리사이즈 동작)
    - **`ResizeHandleNSView.resizeGain` = 1.0** — 아래로 100 끌면 100 자람. 속도는 이 상수만 조정
      (1.0 → 0.5 → 0.25 → 0.4 → 0.45 → 0.6 → 다시 1.0 에서 확정)
    - 1.0 이 기준점인 이유: 마우스 좌표는 pt 단위인데 Retina는 1pt = 2px 라, 0.6 이면 커서가
      화면에서 100px 움직일 때 창은 60px 만 자라 "손보다 덜 따라온다"고 느껴진다.
      1.0 이면 화면상 커서 이동 픽셀 수와 창이 자라는 픽셀 수가 일치한다.
  - 수정한 실제 결함
    - `mouseDownCanMoveWindow`를 `false`로 override. 투명 NSView는 기본 `true`라
      `isMovableByWindowBackground` 창에서 AppKit이 그립 클릭까지 "창 끌기"로 가져갈 수 있었다.
      → 리사이즈 대신(또는 동시에) 창이 이동하던 원인으로 추정
    - 그립 히트 영역 33×33 → 48×48 (빗나가면 창 이동이 되어버림)
    - 위젯 창 `NSHostingView.sizingOptions = []` — 제목 있는 창에만 있고 빠져 있던 것
  - 실측 기록 (임시 NSLog 계측, 커밋 전 제거함)
    - `마우스Δy=75.3 → 크기 200→276 (1.01배)`, 놓은 뒤 1초까지 크기 변화 없음
    - 좌상단: 크기 200→276 동안 `(952.0, 902.0)` 유지, 밀림 `x=0.0 y=0.0`
    - → 계산 자체에는 버그가 없었고, 체감 문제(증가 속도)와 AppKit 창 끌기 개입이 원인
  - 알려진 특성(버그 아님): 좌상단 고정 + 정사각형이면 우하단 그립은 45° 대각선으로 움직여서,
    마우스를 45°보다 가파르게 끌면 그립이 마우스를 앞지른다. 우상단 고정으로 바꾸면 사라지지만
    창이 왼쪽으로 퍼져 표준 동작에서 벗어나므로 기각(시도 후 되돌림).
  - 기각한 대안: 정사영(= macOS 네이티브 방식), 주축 선택,
    `.resizable`+`contentAspectRatio` 로 AppKit 위임(잡는 영역이 가장자리 ~5px 띠)
  - [ ] **`mouseDownCanMoveWindow` 수정 효과는 아직 사용자 확인 전** — 다음 실행 때 검증할 것
- [x] Window 창 모서리 리사이즈가 마우스보다 크게 자라던 문제 (1.0.4)
  - 원인 (1) `ResizeHandleNSView`가 **창 프레임** 기준으로 비율을 잡음 — 제목표시줄(32pt)이 섞여
    aspect가 200/232=0.862가 되고, 대각선으로 100 끌면 콘텐츠가 92×107로 자람 (세로 +6.8% 초과)
  - 원인 (2) `contentAspectRatio 1:1`이 그 어긋난 콘텐츠를 다시 정사각형으로 늘려 초과분이 가로까지 전파
  - 원인 (3) `.resizable` 이 AppKit 자체 리사이즈 띠를 그립 위에 겹쳐 설치 (위젯 창에서 고쳤던 것과 동일)
  - 수정: 핸들을 `contentRect(forFrameRect:)` / `frameRect(forContentRect:)` 기준으로 계산,
    presentation 창에서 `.resizable` 과 `contentAspectRatio` 제거. 테두리 없는 위젯은 chrome=0이라 동작 동일
- [x] 뽀모도로 타이머 (1.0.4)
  - 타이머 패널 UI에는 넣지 않음 — 진입점은 메뉴바 🍅 Pomodoro(⌘⌃B)와 `25/5` 입력 두 가지
  - `TimerView.swift` — `PomodoroPhase`(focus/rest), `PomodoroConfig`(집중·휴식 길이)
  - `TimerEntry.pomodoro`가 있으면 구간이 끝나도 ticker를 멈추지 않고 `advancePomodoroPhase`로 반대 구간 전환 → 무한 반복
    `isRunning`이 계속 true라 배경음악도 끊기지 않음 (`syncWithTimers` 호출 불필요)
  - `isFinished`는 뽀모도로에서 항상 false — 완료 빨간 테두리·완료음이 뜨지 않게. 대신 구간 전환음(Submarine/Glass) 2회
  - 입력 `25/5` → `parsePomodoroInput` (슬래시 양쪽을 기존 `parseTimerInput`으로 해석)
  - 구간 색: 집중 토마토 / 휴식 민트 — 행 남은 시간·위젯 링·배지에 공통 적용, `#n` 사이클 표시
  - 메뉴바 `🍅 Pomodoro (25/5)` + ⌘⌃B(keyCode 11), `NoteManager.startPomodoro(_:)`
  - 알림 센터 위젯 스냅샷 이름은 `displayName`(예: `25m/5m · Focus`)
- [x] 타이머 배경음악 (분위기별 파일 기반 플레이어)
  - `TimerMusic.swift` — `MusicMood`(집중/차분/재즈/활기), `MusicLibrary`, `MusicPlayer`, `MusicBar`
  - 음원은 번들하지 않고 앱 컨테이너 `Application Support/StickyPresenter/Music/<분위기>` 를 스캔
  - 첫 실행 시 폴더 4개 + `README.txt`(합법 출처 목록) 자동 생성. UI·안내문 전부 영어
  - 음원 확보: archive.org는 라이선스가 업로더 자기신고라 오표기(상업 음원)가 섞여 실패 → 폐기
    Incompetech(Kevin MacLeod, 전 곡 저작자 본인이 CC-BY 4.0 공개)로 교체해 분위기별 4곡씩 확보
  - 시작/정지는 0.8초 페이드, 곡 사이는 페이드 없이 이어 붙임 (`fadeGain` × `volume`)
  - "타이머와 함께 재생" — `setRunning`/`reset`/완료/`remove` 4곳에서 `syncWithTimers()` 호출
- [x] 위젯 모서리 리사이즈가 커서와 어긋나던 문제 (원인 2개)
  - (1) 계산: `max(candW/W, candH/H)` → 마우스 이동량을 비율 유지 직선에 정사영 (`ResizeHandleNSView`)
    한 축만 끌 때 반대 축이 과하게 늘어나던 현상, 축소가 둔하던 비대칭 해소
  - (2) 리사이저 중복: 위젯 창의 `.resizable` 이 AppKit 자체 리사이즈 띠를 우하단 그립 위에 겹쳐 설치.
    AppKit은 반대 모서리 고정 + `aspectRatio` 적용, 우리 핸들은 상단 고정 → **누른 지점에 따라 동작이 달랐음**
    · 위젯 창 styleMask 에서 `.resizable` 제거 (`createTimerWidgetWindow`)
    · 이제 무의미해진 `window.aspectRatio` 제거 — 비율은 핸들이 직접 유지
    · 그립과 창 모서리 사이 5pt 틈 제거 (`padding(5)` 삭제, frame 28→33, 그림만 안쪽으로)
      틈은 `isMovableByWindowBackground` 영역이라 누르면 리사이즈 대신 창이 끌려갔음
- [x] 타이머 완료 테두리를 깜빡임 후 완전히 지움 (`opacity 0.15 → 0`, 끝에 켜두던 처리 삭제)
- [x] Git 상태 정리 (stash pop 충돌 해소)
  - `project.pbxproj` 충돌 4곳 수동 병합: 원격 LeeoKit(2.6.0) + DevelopmentTeam 유지, Widget 타겟 추가분 보존
  - 정의 없이 참조만 남은 `Packages` 그룹 제거 (dangling reference)
  - 적용 완료된 `stash@{0}` 삭제, `AUTO_MERGE`/`REBASE_HEAD` 잔여 ref 정리
- [x] 타이머 완료 시 빨간 테두리 깜빡임을 5회로 제한
  - `repeatForever` → 취소 가능한 `Task` 기반 5회 루프 (`TimerWidgetView.updatePulse`)
  - 깜빡임 종료 후 테두리는 켜진 상태로 고정 (완료 상태는 계속 인지 가능)
  - `onDisappear`에서 펄스 Task 취소
- [x] Widget 익스텐션 빌드 오류 수정
  - `struct Widget: Widget` → `StickyPresenterWidget`, `struct WidgetBundle: WidgetBundle` → `StickyPresenterWidgetBundle` (WidgetKit 프로토콜명 충돌)
  - 위젯 번들 ID를 `com.leeo.StickyPresenter.Widget`으로 정정 (부모 앱 접두사 불일치)
- [x] 발표 타이머 알림 센터 위젯 구현
  - `Shared/` (TimerSnapshot, SharedTimerStore) — 앱·위젯 공용 App Group 계층
  - `WidgetSync` — 상태 변화 시점에만 기록. 초 단위 갱신은 위젯이 `endDate`로 자체 처리
  - 앱 종료 시 스냅샷 삭제 — 유령 카운트다운 방지
  - `project.yml`에 WidgetExtension 타겟 정의 (xcodegen 재생성 시 소실되던 문제 해결)
  - 위젯 배포 타겟 26.2 → 14.0 (앱 본체와 정렬)
- [x] 타이머 크래시 버그 수정
  - `@Published var name/targetSeconds/isWidgetHidden` → isInvalidated 가드로 교체
  - Combine 타이머를 isRunning=true일 때만 실행하도록 리팩터링
  - `addSeconds/addMinute/reset`에 isInvalidated 가드 추가
  - `toggleRunning()`이 `setRunning(_:)` 통해 동작하도록 통합
