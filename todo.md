# StickyPresenter Todo

## 진행 중
- [x] 타이머 시작/종료 시 앱 크래시 버그 분석 및 수정

## 배포 전 남은 일
- [ ] Xcode → Signing & Capabilities에서 **App Groups capability 추가** (앱·WidgetExtension 두 타겟 모두)
  - 현재 어떤 프로비저닝 프로필에도 `QGAQ3AY3R3.group.com.leeo.StickyPresenter`가 없음
  - 로컬 개발 실행은 되지만 **App Store 배포 서명은 실패**함
  - 포털에서 수동 등록하면 "already been used" 오류 — Xcode에서 추가할 것
- [ ] 알림 센터 위젯 실제 렌더링 확인 (코드/빌드는 검증했으나 화면 미확인)
- [ ] `v1.0.2` 태그 생성

## 완료
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
