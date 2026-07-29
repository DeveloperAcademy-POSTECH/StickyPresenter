import Foundation

/// 앱 → 위젯으로 전달되는 타이머 상태 스냅샷.
///
/// 위젯은 앱과 별도 프로세스에서 동작하므로 `NoteManager.shared` 같은 메모리 상태를 볼 수 없다.
/// 앱이 상태가 바뀔 때마다 이 값을 App Group에 직렬화해 두고, 위젯이 그것을 읽어 그린다.
struct TimerSnapshot: Codable, Equatable {
    var name: String
    var targetSeconds: TimeInterval
    /// 스냅샷을 기록한 시점의 남은 시간(초).
    /// 실행 중인 타이머는 시간이 지나면 이 값이 낡으므로 `remaining(at:)`를 쓸 것.
    var remaining: TimeInterval
    var isRunning: Bool
    /// 실행 중일 때 타이머가 끝나는 시각. 정지 상태면 nil.
    ///
    /// 위젯은 이 값으로 `Text(_:style:.timer)`와 `ProgressView(timerInterval:)`를 그린다.
    /// 두 뷰 모두 타임라인을 다시 만들지 않고도 초 단위로 스스로 갱신되므로,
    /// 1초마다 타임라인을 재생성하는(위젯 예산상 불가능한) 방식을 피할 수 있다.
    var endDate: Date?

    init(
        name: String,
        targetSeconds: TimeInterval,
        remaining: TimeInterval,
        isRunning: Bool,
        endDate: Date?
    ) {
        self.name = name
        self.targetSeconds = targetSeconds
        self.remaining = remaining
        self.isRunning = isRunning
        self.endDate = endDate
    }

    /// 주어진 시각 기준의 남은 시간.
    /// 실행 중이면 `endDate`로부터 실시간 계산하고, 정지 상태면 기록된 값을 그대로 쓴다.
    func remaining(at date: Date) -> TimeInterval {
        guard isRunning, let endDate else { return max(0, remaining) }
        return max(0, endDate.timeIntervalSince(date))
    }

    func isFinished(at date: Date) -> Bool {
        remaining(at: date) <= 0
    }

    /// 0...1 진행률. targetSeconds가 0이면 진행률을 정의할 수 없으므로 0으로 둔다.
    func progress(at date: Date) -> Double {
        guard targetSeconds > 0 else { return 0 }
        let elapsed = targetSeconds - remaining(at: date)
        return min(1, max(0, elapsed / targetSeconds))
    }

    /// 카운트다운 표기(H:MM:SS 또는 M:SS). 정지 상태와 완료 상태에서 사용한다.
    /// 실행 중에는 `Text(endDate, style: .timer)`가 이 역할을 대신한다.
    static func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

extension TimerSnapshot {
    /// 위젯 갤러리 미리보기 / placeholder 용 샘플.
    static let preview = TimerSnapshot(
        name: "발표 리허설",
        targetSeconds: 20 * 60,
        remaining: 12 * 60 + 34,
        isRunning: false,
        endDate: nil
    )
}
