import Foundation

/// 앱의 타이머 상태를 위젯이 읽을 수 있는 형태로 App Group에 반영한다.
///
/// 매 초 호출할 필요는 없다. 위젯은 `endDate`를 받아 스스로 카운트다운하므로,
/// 시작/정지·시간 조정·리셋·완료처럼 **상태가 바뀌는 시점**에만 갱신하면 된다.
enum WidgetSync {

    /// 위젯에 노출할 대표 타이머.
    /// 발표 중에는 돌아가는 타이머가 관심 대상이므로 실행 중인 것을 우선하고,
    /// 없으면 목록의 첫 번째를 쓴다.
    static func primaryEntry(in entries: [TimerEntry]) -> TimerEntry? {
        entries.first { $0.isRunning } ?? entries.first
    }

    /// 현재 타이머 목록을 기준으로 스냅샷을 다시 기록한다.
    static func refresh() {
        let entries = NoteManager.shared.timerListManager.entries
        SharedTimerStore.save(primaryEntry(in: entries)?.snapshot)
    }
}

extension TimerEntry {
    /// 위젯으로 넘길 직렬화 가능한 상태.
    var snapshot: TimerSnapshot {
        TimerSnapshot(
            // 뽀모도로는 이름에 현재 구간(Focus/Break)이 붙는다.
            name: displayName,
            targetSeconds: targetSeconds,
            remaining: remaining,
            isRunning: isRunning,
            // 실행 중일 때만 종료 시각을 계산해 넘긴다.
            // 위젯은 이 값으로 타임라인 갱신 없이 초 단위 카운트다운을 그린다.
            endDate: isRunning ? Date().addingTimeInterval(remaining) : nil
        )
    }
}
