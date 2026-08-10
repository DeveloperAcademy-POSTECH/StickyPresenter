# StickyPresenter Todo

## 진행 중
- [x] 타이머 시작/종료 시 앱 크래시 버그 분석 및 수정

## 배포 전 남은 일
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
