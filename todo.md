# StickyPresenter Todo

## 진행 중
- [x] 타이머 시작/종료 시 앱 크래시 버그 분석 및 수정

## 완료
- [x] 타이머 크래시 버그 수정
  - `@Published var name/targetSeconds/isWidgetHidden` → isInvalidated 가드로 교체
  - Combine 타이머를 isRunning=true일 때만 실행하도록 리팩터링
  - `addSeconds/addMinute/reset`에 isInvalidated 가드 추가
  - `toggleRunning()`이 `setRunning(_:)` 통해 동작하도록 통합
