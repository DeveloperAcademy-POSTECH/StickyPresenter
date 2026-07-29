# StickyPresenter Todo

## 진행 중
- [x] 타이머 시작/종료 시 앱 크래시 버그 분석 및 수정

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
- [x] 타이머 크래시 버그 수정
  - `@Published var name/targetSeconds/isWidgetHidden` → isInvalidated 가드로 교체
  - Combine 타이머를 isRunning=true일 때만 실행하도록 리팩터링
  - `addSeconds/addMinute/reset`에 isInvalidated 가드 추가
  - `toggleRunning()`이 `setRunning(_:)` 통해 동작하도록 통합
