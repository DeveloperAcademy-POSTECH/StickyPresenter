import SwiftUI
import AppKit

// MARK: - Widget Size
/// 타이머 창 프리셋 크기. 모서리 드래그로 자유롭게 조절할 수도 있지만,
/// 발표 중에 정확히 같은 크기로 되돌리기는 어렵다. S/M/L 로 한 번에 맞춘다.
enum WidgetSize: String, CaseIterable {
    case small  = "S"
    case medium = "M"
    case large  = "L"

    /// 콘텐츠 한 변의 길이(pt). 창은 항상 정사각형이다.
    var side: CGFloat {
        switch self {
        case .small:  return 200   // 기본값 — 슬라이드 구석에 놓아도 안 거슬리는 크기
        case .medium: return 300
        case .large:  return 420   // 화면 공유·먼 거리에서 읽히는 크기
        }
    }
}

// MARK: - Widget Theme
enum WidgetTheme: String, CaseIterable {
    case system     // 시스템 외형 따름
    case light      // 밝은 테마
    case dark       // 어두운(반전) 테마
    case chameleon  // 창 뒤 화면 색을 읽어 배경으로 쓰고, 나머지는 그 보색으로

    var icon: String {
        switch self {
        case .system:    return "circle.lefthalf.filled"
        case .light:     return "sun.max.fill"
        case .dark:      return "moon.fill"
        case .chameleon: return "eyedropper.halffull"
        }
    }

    var next: WidgetTheme {
        switch self {
        case .system:    return .light
        case .light:     return .dark
        case .dark:      return .chameleon
        case .chameleon: return .system
        }
    }
}

// MARK: - Pomodoro
/// 뽀모도로 구간 — 집중과 휴식 둘뿐이며 서로를 무한히 오간다.
enum PomodoroPhase {
    case focus
    case rest

    var title: String { self == .focus ? "Focus" : "Break" }
    var icon: String { self == .focus ? "brain.head.profile" : "cup.and.saucer.fill" }
    var next: PomodoroPhase { self == .focus ? .rest : .focus }

    /// 집중은 토마토색, 휴식은 민트색 — 위젯을 흘깃 봐도 지금이 어느 구간인지 알 수 있게.
    var color: Color {
        self == .focus
            ? Color(red: 0.91, green: 0.30, blue: 0.24)
            : Color(red: 0.16, green: 0.68, blue: 0.53)
    }
}

/// 집중 ↔ 휴식 길이. 이 설정을 가진 타이머는 완료 없이 두 구간을 계속 반복한다.
struct PomodoroConfig: Equatable {
    var focusSeconds: TimeInterval
    var breakSeconds: TimeInterval

    func seconds(for phase: PomodoroPhase) -> TimeInterval {
        max(1, phase == .focus ? focusSeconds : breakSeconds)
    }

    /// "25m/5m" 형태의 짧은 이름 (행·위젯 제목용)
    var label: String { "\(Self.shortUnit(focusSeconds))/\(Self.shortUnit(breakSeconds))" }

    private static func shortUnit(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        if total % 60 == 0 { return "\(total / 60)m" }
        return total >= 60 ? String(format: "%d:%02d", total / 60, total % 60) : "\(total)s"
    }

    /// 메뉴바 · ⌘⌃B로 시작하는 기본값 (25분 집중 / 5분 휴식)
    static let classic = PomodoroConfig(focusSeconds: 25 * 60, breakSeconds: 5 * 60)
}

// MARK: - Timer Entry (Model)
class TimerEntry: ObservableObject, Identifiable {
    let id = UUID()

    // 모든 프로퍼티를 수동 willSet으로 관리 — invalidate() 이후 objectWillChange 발행을 전면 차단.
    // @Published는 isInvalidated 검사를 우회하므로 사용 금지.
    var name: String {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    var targetSeconds: TimeInterval {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    var isWidgetHidden: Bool = false {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    // 패널 행 hover 시 위젯에 점선 테두리를 띄워 위치를 알려줌
    var isLocating: Bool = false {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    // 위젯 테마 (시스템 / 라이트 / 다크 반전 / 카멜레온)
    var theme: WidgetTheme = .system {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    /// 마지막으로 고른 프리셋 크기. 모서리 드래그로 직접 조절하면 이 값과 어긋날 수 있고,
    /// 그때는 S/M/L 버튼이 "그 크기로 되돌리는" 역할을 한다.
    var widgetSize: WidgetSize = .small {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    /// 뽀모도로 설정. nil이면 한 번 울리고 끝나는 일반 타이머.
    var pomodoro: PomodoroConfig? {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    /// 현재 구간(집중/휴식). 일반 타이머에서는 쓰이지 않는다.
    private(set) var phase: PomodoroPhase = .focus {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    /// 지금까지 끝낸 집중 구간 수 — 몇 번째 뽀모도로인지 표시용.
    private(set) var completedFocusCount: Int = 0 {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }

    weak var widgetPanel: NSWindow?

    private(set) var elapsed: TimeInterval = 0 {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }
    private(set) var isRunning: Bool = false {
        willSet { if !isInvalidated { objectWillChange.send() } }
    }

    private(set) var isInvalidated = false

    // Foundation Timer 사용 — Combine Timer는 cancel() 이후에도 이미 RunLoop 콜백 큐에
    // 들어간 이벤트가 Combine subscriber 목록을 순회할 수 있어,
    // SwiftUI가 @ObservedObject 구독을 해제하는 타이밍과 충돌 시 crash 발생.
    // Foundation Timer.invalidate()는 RunLoop에서 즉시 동기적으로 제거되므로 안전함.
    private var ticker: Foundation.Timer?

    init(name: String, targetSeconds: TimeInterval, pomodoro: PomodoroConfig? = nil) {
        self.name = name
        self.targetSeconds = targetSeconds
        self.pomodoro = pomodoro
    }

    var isPomodoro: Bool { pomodoro != nil }

    var remaining: TimeInterval { max(0, targetSeconds - elapsed) }
    /// 뽀모도로는 구간이 끝나도 곧바로 다음 구간으로 넘어가므로 "완료" 상태가 없다.
    var isFinished: Bool { !isPomodoro && elapsed >= targetSeconds }
    var progress: Double { min(1.0, elapsed / max(1, targetSeconds)) }

    /// 위젯·창 제목에 쓰는 이름. 뽀모도로는 현재 구간을 함께 보여준다.
    var displayName: String {
        guard isPomodoro else { return name }
        return name.isEmpty ? phase.title : "\(name) · \(phase.title)"
    }

    /// 몇 번째 집중 구간인지 (휴식 중이면 방금 끝낸 집중 번호)
    var cycleNumber: Int {
        phase == .focus ? completedFocusCount + 1 : max(1, completedFocusCount)
    }

    func addSeconds(_ s: TimeInterval = 30) {
        guard !isInvalidated else { return }
        targetSeconds += s
        WidgetSync.refresh()
    }

    func subtractSeconds(_ s: TimeInterval = 30) {
        guard !isInvalidated else { return }
        elapsed = min(elapsed + s, targetSeconds)
        WidgetSync.refresh()
    }

    func addMinute() {
        guard !isInvalidated else { return }
        targetSeconds += 60
        WidgetSync.refresh()
    }

    func reset() {
        guard !isInvalidated else { return }
        stopTicker()
        isRunning = false
        elapsed = 0
        // 뽀모도로는 첫 집중 구간부터 다시 — 사이클 수도 0으로 되돌린다.
        if let config = pomodoro {
            phase = .focus
            completedFocusCount = 0
            targetSeconds = config.seconds(for: .focus)
        }
        WidgetSync.refresh()
        MusicPlayer.shared.syncWithTimers()
    }

    func setRunning(_ value: Bool) {
        guard !isInvalidated, value != isRunning else { return }
        isRunning = value
        if value { startTicker() } else { stopTicker() }
        WidgetSync.refresh()
        MusicPlayer.shared.syncWithTimers()
    }

    func toggleRunning() {
        setRunning(!isRunning)
    }

    // MARK: - Internal ticker lifecycle

    private func startTicker() {
        guard ticker == nil else { return }
        // Timer(timeInterval:repeats:block:)으로 생성 후 .common 모드로 직접 등록.
        // .common은 UI 인터랙션 중에도 타이머가 발화하도록 함.
        let t = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.isInvalidated else { return }
            self.elapsed += 1
            guard self.elapsed >= self.targetSeconds else { return }

            // 뽀모도로는 멈추지 않는다 — 집중이 끝나면 휴식으로, 휴식이 끝나면 다시 집중으로.
            if let config = self.pomodoro {
                self.advancePomodoroPhase(config)
                return
            }

            // invalidate()는 현재 콜백 내부에서 호출해도 안전 (Apple 문서 보장).
            self.stopTicker()
            self.isRunning = false
            self.playFinishSound()   // 완료 청각 피드백 (위젯이 숨겨져 있어도 울림)
            WidgetSync.refresh()     // 데스크톱 위젯을 "완료" 표시로 전환
            // 완료 차임이 배경음악에 묻히지 않도록 페이드아웃
            MusicPlayer.shared.syncWithTimers()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// 현재 구간을 끝내고 반대 구간으로 넘어간다.
    /// ticker는 멈추지 않으므로 사용자가 일시정지하거나 삭제할 때까지 무한히 반복된다.
    private func advancePomodoroPhase(_ config: PomodoroConfig) {
        if phase == .focus { completedFocusCount += 1 }
        phase = phase.next
        targetSeconds = config.seconds(for: phase)
        elapsed = 0
        playPhaseChangeSound(entering: phase)
        WidgetSync.refresh()
        // isRunning은 계속 true이므로 배경음악은 끊기지 않는다 (syncWithTimers 불필요).
    }

    /// 구간 전환 알림음 — 집중 시작과 휴식 시작을 다른 소리로 구분한다.
    private func playPhaseChangeSound(entering phase: PomodoroPhase) {
        let sound = phase == .focus ? "Submarine" : "Glass"
        for i in 0..<2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                NSSound(named: NSSound.Name(sound))?.play()
            }
        }
    }

    /// 완료 차임을 0.6초 간격으로 3회 재생해 주의를 끈다.
    private func playFinishSound() {
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
        }
    }

    /// 제거 전 호출: isInvalidated = true로 objectWillChange를 영구 차단하고
    /// Foundation Timer를 RunLoop에서 즉시 제거. 이후 어떤 프로퍼티 변경도
    /// SwiftUI 재렌더를 유발하지 않음.
    func invalidate() {
        isInvalidated = true
        stopTicker()
    }
}

// MARK: - Timer List Manager
class TimerListManager: ObservableObject {
    @Published var entries: [TimerEntry] = []
    var onAdd: ((TimerEntry) -> Void)?
    var onRemove: ((TimerEntry) -> Void)?

    func add(_ entry: TimerEntry) {
        entries.append(entry)
        onAdd?(entry)
        WidgetSync.refresh()
    }

    func remove(_ entry: TimerEntry) {
        // 타이머를 지금 즉시 중단 — async 대기 시간(최대 ~수 ms) 사이에
        // Foundation ticker가 발화해 objectWillChange 를 전송하면
        // SwiftUI 가 이미 해제 중인 @ObservedObject 구독자를 순회하다 crash.
        // isInvalidated = true 도 함께 세팅되므로 이후 어떤 프로퍼티 변경도 UI를 갱신하지 않음.
        entry.invalidate()

        // SwiftUI 버튼 액션 클로저가 살아있는 동안 window나 entries를 건드리면
        // 뷰 계층이 해제되면서 crash — 다음 런루프로 미룸
        DispatchQueue.main.async {
            self.onRemove?(entry)
            self.entries.removeAll { $0.id == entry.id }
            WidgetSync.refresh()
            MusicPlayer.shared.syncWithTimers()
        }
    }
}

// MARK: - Parse input text → seconds
func parseTimerInput(_ raw: String) -> TimeInterval {
    let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard !text.isEmpty else { return 0 }

    // 1. 콜론 형식: M:SS 또는 H:MM:SS
    let colonRegex = try? NSRegularExpression(pattern: "^(\\d+):(\\d{1,2})(?::(\\d{1,2}))?$")
    if let match = colonRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
        let vals = (1...3).compactMap { i -> Double? in
            guard let r = Range(match.range(at: i), in: text) else { return nil }
            return Double(text[r])
        }
        if vals.count == 2 { return vals[0] * 60 + vals[1] }
        if vals.count == 3 { return vals[0] * 3600 + vals[1] * 60 + vals[2] }
    }

    // 2. 단어/축약 형식
    var total: TimeInterval = 0
    let patterns: [(String, TimeInterval)] = [
        ("(\\d+)\\s*hours?",     3600),
        ("(\\d+)\\s*hr",         3600),
        ("(\\d+)\\s*h(?![a-z])", 3600),
        ("(\\d+)\\s*minutes?",   60),
        ("(\\d+)\\s*mins?",      60),
        ("(\\d+)\\s*m(?![a-z])", 60),
        ("(\\d+)\\s*seconds?",   1),
        ("(\\d+)\\s*secs?",      1),
        ("(\\d+)\\s*s(?![a-z])", 1),
    ]
    for (pattern, mul) in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(match.range(at: 1), in: text), let v = Double(text[r]) {
                total += v * mul
            }
        }
    }
    if total > 0 { return total }

    // 3. 순수 숫자 → 분
    if let v = Double(text), v > 0 { return v * 60 }

    return 0
}

// MARK: - Parse pomodoro input ("25/5", "50m / 10m", "1:30/5")
/// 슬래시로 나뉜 두 시간을 각각 집중·휴식으로 읽는다. 한쪽이라도 해석되지 않으면 nil.
func parsePomodoroInput(_ raw: String) -> PomodoroConfig? {
    let parts = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let focus = parseTimerInput(String(parts[0]))
    let rest  = parseTimerInput(String(parts[1]))
    guard focus > 0, rest > 0 else { return nil }
    return PomodoroConfig(focusSeconds: focus, breakSeconds: rest)
}

// MARK: - Timer List View (main panel)
struct TimerListView: View {
    @ObservedObject var manager: TimerListManager
    @State private var inputText = ""
    @FocusState private var focused: Bool

    private var parsedSeconds: TimeInterval {
        parseTimerInput(inputText.trimmingCharacters(in: .whitespaces))
    }

    /// "25/5" 처럼 슬래시가 들어간 입력은 뽀모도로로 해석한다.
    private var parsedPomodoro: PomodoroConfig? {
        parsePomodoroInput(inputText.trimmingCharacters(in: .whitespaces))
    }

    private var hasValidInput: Bool { parsedSeconds > 0 || parsedPomodoro != nil }

    private var previewText: String? {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let p = parsedPomodoro {
            return "↻ Focus \(formatPreviewTime(p.focusSeconds)) · Break \(formatPreviewTime(p.breakSeconds))"
        }
        guard parsedSeconds > 0 else { return nil }
        return "→ " + formatPreviewTime(parsedSeconds)
    }

    private func formatPreviewTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)hr") }
        if m > 0 { parts.append("\(m)min") }
        if s > 0 { parts.append("\(s)sec") }
        return parts.isEmpty ? "0sec" : parts.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Input bar + 새 노트 버튼
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // 텍스트필드 + 제출 버튼
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("5:30  ·  1h 20m  ·  45s  ·  10", text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($focused)
                            .onSubmit { submit() }

                        // 유효한 입력이 있을 때만 제출 버튼 등장
                        if hasValidInput {
                            Button(action: submit) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))

                    Button(action: addNewStickyNote) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(red: 0.95, green: 0.85, blue: 0.40))
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 1.0, green: 0.95, blue: 0.70)))
                    }
                    .buttonStyle(.plain)
                    .help("New Sticky Note")
                    // 윈도우로 열기 버튼은 각 타이머 행으로 이동 (해당 타이머만 윈도우로 열림)
                }

                if let preview = previewText {
                    Text(preview)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hasValidInput)
            .animation(.easeInOut(duration: 0.15), value: previewText)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // 프리셋 버튼
            VStack(alignment: .leading, spacing: 6) {
                if manager.entries.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 10, weight: .medium))
                        Text("Quick Start")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .padding(.leading, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 8) {
                    ForEach([("3m", 180.0), ("5m", 300.0), ("10m", 600.0), ("15m", 900.0)], id: \.0) { label, secs in
                        Button(action: {
                            let entry = TimerEntry(name: label, targetSeconds: secs)
                            entry.setRunning(true)
                            manager.add(entry)
                        }) {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(manager.entries.isEmpty ? Color.accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(manager.entries.isEmpty
                                              ? Color.accentColor.opacity(0.12)
                                              : Color.primary.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(manager.entries.isEmpty
                                                              ? Color.accentColor.opacity(0.3)
                                                              : Color.clear, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: manager.entries.isEmpty)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Timer list
            if manager.entries.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "timer")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.quaternary)
                    Text("No timers")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("Tap a preset or enter a time")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(manager.entries) { entry in
                            TimerRowView(entry: entry) {
                                manager.remove(entry)
                            }
                        }

                        // 타이머 추가 행
                        AddTimerRow(presets: [("3m", 180.0), ("5m", 300.0), ("10m", 600.0), ("15m", 900.0)]) { secs, label in
                            let entry = TimerEntry(name: label, targetSeconds: secs)
                            entry.setRunning(true)
                            manager.add(entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

            // 배경음악 바 — 분위기 선택 · 재생 · 볼륨
            MusicBar()
        }
        .frame(minWidth: 280, minHeight: 180)
        .background(.regularMaterial)
        .background(ignoresSafeAreaEdges: .all)
    }

    private func submit() {
        let raw = inputText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }

        // 슬래시 입력("25/5")은 뽀모도로로 만든다.
        if let config = parsePomodoroInput(raw) {
            addPomodoro(config)
            inputText = ""
            focused = true
            return
        }

        let secs = parseTimerInput(raw)
        guard secs > 0 else { return }
        let entry = TimerEntry(name: raw, targetSeconds: secs)
        entry.setRunning(true)
        manager.add(entry)
        inputText = ""
        focused = true
    }

    /// 집중 구간부터 시작하는 뽀모도로 타이머를 추가한다.
    private func addPomodoro(_ config: PomodoroConfig) {
        let entry = TimerEntry(
            name: config.label,
            targetSeconds: config.seconds(for: .focus),
            pomodoro: config
        )
        entry.setRunning(true)
        manager.add(entry)
    }

    private func addNewStickyNote() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let randomX = CGFloat.random(in: screenFrame.minX + 50...screenFrame.maxX - 300)
        let randomY = CGFloat.random(in: screenFrame.minY + 50...screenFrame.maxY - 250)
        NoteManager.shared.addNote(
            text: "",
            color: NoteManager.shared.defaultColor,
            position: CGPoint(x: randomX, y: randomY)
        )
    }
}

// MARK: - Timer Row View (list item)
struct TimerRowView: View {
    @ObservedObject var entry: TimerEntry
    let onRemove: () -> Void

    private var timeColor: Color {
        if entry.isFinished { return Color(red: 1, green: 0.22, blue: 0.37) }
        // 뽀모도로는 남은 시간 색으로 지금이 집중인지 휴식인지 알려준다.
        if entry.isPomodoro { return entry.phase.color }
        return .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                if entry.isPomodoro {
                    pomodoroLabel
                } else {
                    Text(entry.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(formatTime(entry.remaining))
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.3), value: entry.remaining)
            }

            // 모든 컨트롤 버튼을 3m/5m 프리셋과 동일한 디자인(둥근 사각형 cornerRadius 8)으로 통일
            VStack(spacing: 6) {
                // 1행 — 시간 조절: 일시정지를 가운데 두고 좌우에 -30s / +30s
                HStack(spacing: 6) {
                    Button(action: { entry.subtractSeconds() }) {
                        Text("−30s").modifier(CtrlButtonStyle(fg: .secondary, bg: Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if entry.isFinished { entry.reset() }
                        entry.toggleRunning()
                    }) {
                        Image(systemName: entry.isRunning ? "pause.fill" : "play.fill")
                            .modifier(CtrlButtonStyle(fg: .primary, bg: Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)

                    Button(action: { entry.addSeconds() }) {
                        Text("+30s").modifier(CtrlButtonStyle(fg: .secondary, bg: Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                // 2행 — 위젯 제어: 감추기/표시 · 불러오기 · 윈도우
                HStack(spacing: 6) {
                    // 위젯 표시/감추기 토글 (눈동자 통합)
                    Button(action: toggleWidgetVisibility) {
                        Text(entry.isWidgetHidden ? "Show" : "Hide")
                            .modifier(CtrlButtonStyle(
                                fg: entry.isWidgetHidden ? .secondary : Color.accentColor,
                                bg: entry.isWidgetHidden ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Show / hide widget")

                    // 불러오기: 위젯을 패널 옆으로 정렬해 앞으로 (화면 밖으로 사라졌을 때 되찾기)
                    Button(action: { NoteManager.shared.snapWidgetToPanel(for: entry) }) {
                        Text("Align").modifier(CtrlButtonStyle(fg: .secondary, bg: Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Align widget next to the panel")

                    // 윈도우: 이 타이머를 별도 윈도우로 열기 (화면 공유 / AirPlay)
                    Button(action: { NoteManager.shared.openTimerWindow(for: entry) }) {
                        Text("Window").modifier(CtrlButtonStyle(fg: .secondary, bg: Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Open in a window (screen share / AirPlay)")
                }

                // 3행 — 테마 · (빈칸) · 삭제
                HStack(spacing: 6) {
                    // 테마 전환 (시스템 → 라이트 → 다크 순환)
                    Button(action: { entry.theme = entry.theme.next }) {
                        Image(systemName: entry.theme.icon)
                            .modifier(CtrlButtonStyle(fg: .secondary, bg: Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Theme: \(entry.theme.rawValue)")

                    // 프리셋 크기 S / M / L
                    HStack(spacing: 3) {
                        ForEach(WidgetSize.allCases, id: \.self) { size in
                            let isCurrent = entry.widgetSize == size
                            Button(action: { NoteManager.shared.setWidgetSize(size, for: entry) }) {
                                Text(size.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                                    .frame(width: 26, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isCurrent ? Color.accentColor.opacity(0.12)
                                                            : Color.primary.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Widget size: \(size.rawValue) (\(Int(size.side))pt)")
                        }
                    }

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .modifier(CtrlButtonStyle(fg: .white, bg: Color(red: 1, green: 0.27, blue: 0.23)))
                    }
                    .buttonStyle(.plain)
                    .help("Delete timer")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(rowBackground)
        .contentShape(Rectangle())   // 셀 전체(빈 공간 포함)에서 hover 감지
        // 행 hover 시 해당 위젯에 점선 테두리(위치 표시). 감추기 상태면 hover 동안 잠깐 띄움.
        .onHover { hovering in
            entry.isLocating = hovering
            if entry.isWidgetHidden {
                if hovering { entry.widgetPanel?.orderFront(nil) }
                else { entry.widgetPanel?.orderOut(nil) }
            }
        }
    }

    // 뽀모도로 행 머리말 — 구간 배지 + 설정값 + 몇 번째 사이클인지
    private var pomodoroLabel: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                Image(systemName: entry.phase.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(entry.phase.title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(entry.phase.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(entry.phase.color.opacity(0.14)))

            Text("\(entry.name) · #\(entry.cycleNumber)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .animation(.easeInOut(duration: 0.2), value: entry.phase)
    }

    // 표시/감추기 토글: Show는 숨긴 그 자리에서 그대로 다시 보이게 함 (위치 이동 없음).
    // 위치 정렬은 Align 버튼 전용.
    private func toggleWidgetVisibility() {
        if entry.isWidgetHidden {
            entry.widgetPanel?.orderFront(nil)
            entry.isWidgetHidden = false
        } else {
            entry.widgetPanel?.orderOut(nil)
            entry.isWidgetHidden = true
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Rounded Rect Progress Shape
// 진행 표시를 원이 아니라 **창 자신의 둥근 사각형 윤곽**으로 그린다.
//
// 사각형을 쓰는 진짜 이유는 모양이 달라서가 아니라 **네 꼭짓점이 눈금 역할**을 하기 때문이다.
// 원에는 기준점이 없어서 "지금 몇 % 지났나"를 각도로 눈대중해야 한다.
// 좌상단 꼭짓점에서 출발해 시계방향으로 돌면 꼭짓점이 정확히 0 / 25 / 50 / 75% 에 떨어진다.
// (둘레 = 4 × (직선 + 호) 이고 꼭짓점 사이 간격이 정확히 그 1/4이다)
//
//        0%
//        ┌────────┐ 25%
//        │        │
//        │        │
//   75%  └────────┘ 50%
//
// "오른쪽 변을 타고 있으면 1/4 ~ 1/2 사이" 처럼 숫자를 읽지 않고도 구간이 파악된다.
// 발표 중 흘긋 보는 용도에서는 이게 남은 시간 숫자보다 빠르다.
//
// 덤으로 정사각형 창에서 원이 버리던 네 모서리 공간이 살아나 숫자를 크게 쓸 수 있다.
struct RoundedRectProgress: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        // 반지름이 변 길이의 절반을 넘으면 모서리가 겹쳐 경로가 뒤집힌다.
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)

        let topLeft     = CGPoint(x: rect.minX + r, y: rect.minY + r)
        let topRight    = CGPoint(x: rect.maxX - r, y: rect.minY + r)
        let bottomRight = CGPoint(x: rect.maxX - r, y: rect.maxY - r)
        let bottomLeft  = CGPoint(x: rect.minX + r, y: rect.maxY - r)

        // y축이 아래로 향하는 좌표계라 각도가 커질수록 화면상 시계방향으로 돈다.
        // 좌상단 꼭짓점의 "대각선 지점"인 225°에서 출발해야 꼭짓점이 1/4 눈금에 맞는다.
        func point(_ center: CGPoint, _ degrees: CGFloat) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        }

        var p = Path()
        p.move(to: point(topLeft, 225))
        p.addArc(center: topLeft, radius: r,
                 startAngle: .degrees(225), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: topRight, radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)   // 25%가 이 호의 한가운데
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: bottomRight, radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)      // 50%
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: bottomLeft, radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)    // 75%
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: topLeft, radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(225), clockwise: false)   // 출발점으로 복귀
        return p
    }
}

// MARK: - Corner Grip Shape (우하단 모서리: 둥글게 휘는 코너 브래킷)
// 직각 대신 위젯의 둥근 모서리를 따라 흐르는 곡선으로 그려 "잡아당기는" 느낌을 준다.
struct CornerGrip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) * 0.85   // 곡률 — 클수록 더 둥글게
        // 오른쪽 변 ↓ → 둥근 코너 → 아래쪽 변 ←
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)   // 모서리 꼭짓점이 제어점
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

// MARK: - Native Resize Handle
// 투명 NSView. mouseDown 시 OS 이벤트 추적 루프(trackEvents)를 돌려
// 네이티브 가장자리 리사이즈와 동일한 이벤트 레이트로 윈도우를 조절한다.
// 창은 항상 정사각형으로 유지되며, 크기는 마우스의 세로 이동량에만 비례한다.
struct NativeResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ResizeHandleNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    // 이 값이 true(투명 뷰의 기본값)면 isMovableByWindowBackground 창에서 AppKit이
    // 그립 위 클릭까지 "창 끌기"로 가져가, 리사이즈 대신(또는 리사이즈와 동시에) 창이 이동한다.
    // 리사이즈 핸들에서는 반드시 꺼야 한다.
    override var mouseDownCanMoveWindow: Bool { false }

    /// 마우스 수직 이동량 대비 창이 자라는 비율. 1.0 이면 마우스와 1:1.
    /// **아래로 100 끌면 100 자란다 (화면상 커서와 같은 픽셀만큼).**
    ///
    /// 1:1은 실측상 정확했지만("마우스Δy=75.3 → 크기 200→276") 손으로 써보니 너무 빨랐다.
    /// 창이 200pt로 작아서 같은 75pt라도 원래 크기의 +38%가 되고, Retina에서는
    /// 픽셀 152개가 늘어나 체감이 훨씬 크기 때문이다.
    /// 참고로 macOS 네이티브 비율고정 창(정사영 방식)은 정사각형·수직 드래그에서 정확히 0.5다.
    ///
    /// 손으로 맞춘 값이다: 1.0 → 0.5 → 0.25 → 0.4 → 0.45 → 0.6 → 다시 1.0.
    /// 1.0 이 자연스러운 기준점인 이유: 마우스 좌표는 pt 단위인데 Retina 화면은 1pt = 2px 라,
    /// 0.6 이면 커서가 화면에서 100px 움직일 때 창은 60px 만 자라 "손보다 덜 따라온다"고 느껴진다.
    /// 1.0 이면 화면상 커서 이동 픽셀 수와 창이 자라는 픽셀 수가 일치한다.
    /// 더 필요하면 1.0 을 넘겨도 된다 (1.5 → 100 끌면 150).
    /// 조절이 필요하면 이 상수만 바꾸면 된다 (0.3 → 100 끌면 30, 0.5 → 100 끌면 50).
    private static let resizeGain: CGFloat = 1.0

    override func resetCursorRects() {
        // 대각 리사이즈에 대응하는 공개 커서가 없어 crosshair로 표시
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        // 비율은 반드시 **콘텐츠** 기준으로 잡는다.
        // 제목표시줄이 있는 창(Window 버튼으로 여는 창)에서 창 프레임 기준으로 계산하면
        // 프레임 비율(콘텐츠+타이틀바)을 유지하려다 콘텐츠가 정사각형에서 어긋나고,
        // 그 어긋난 만큼 창이 끈 것보다 커진다. 테두리 없는 위젯은 콘텐츠 = 프레임이라 동일하게 동작.
        let startContent = window.contentRect(forFrameRect: window.frame)
        let chromeHeight = window.frame.height - startContent.height   // 제목표시줄 높이 (위젯은 0)
        let startMouse = NSEvent.mouseLocation          // 화면 좌표(좌하단 원점)
        // 타이머 위젯은 **항상 정사각형**이 요구사항이므로 현재 크기에서 비율을 유도하지 않는다.
        // 유도하면 창이 한 번이라도 정사각형에서 벗어났을 때 그 비율이 그대로 굳어버린다.
        // 1로 고정하면 어긋난 창도 첫 리사이즈에서 정사각형으로 되돌아온다(self-healing).
        let aspect: CGFloat = 1
        // 최소 크기도 콘텐츠 기준으로 환산 — 프레임 기준 값을 그대로 쓰면 타이틀바만큼 과하게 잘린다.
        let minSize = NSSize(
            width:  max(80, window.minSize.width),
            height: max(80, window.minSize.height - chromeHeight)
        )

        let content = window.contentView
        content?.viewWillStartLiveResize()

        // OS 이벤트 큐를 직접 소비하는 중첩 추적 루프 — DragGesture보다 촘촘함
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked else { stop.pointee = true; return }

            switch tracked.type {
            case .leftMouseUp:
                stop.pointee = true

            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dH = startMouse.y - mouse.y          // 아래로 끌면 +

                // 크기는 **마우스의 수직 이동량만** 으로 결정하고, 너비는 비율(정사각형)대로 따라간다.
                // 자라는 양은 resizeGain 배 — 아래로 100 끌면 100 자란다. 세로 이동량에만 비례하므로
                // 배율이 얼마든 "끈 만큼에 비례해서" 커지는 예측 가능한 움직임은 유지된다.
                //
                // 가로 이동량은 의도적으로 무시한다. 비율이 고정된 이상 모서리가 포인터를 항상
                // 따라가는 것은 기하학적으로 불가능하고(가능한 위치는 Δ가로 = aspect × Δ세로
                // 직선 위뿐), 정사영처럼 두 축을 섞으면 세로로만 끌었을 때 절반만 자라 답답해진다.
                // 세로 하나만 기준으로 삼으면 "끈 만큼 높이가 커지고 너비는 비율만큼"이라
                // 움직임이 그대로 예측된다. 가로 드래그가 크기를 바꾸지 않는 것은 의도된 동작.
                var newH = startContent.height + dH * Self.resizeGain
                var newW = newH * aspect
                // 최소 크기 클램프 (비율 유지)
                if newW < minSize.width  { newW = minSize.width;  newH = newW / aspect }
                if newH < minSize.height { newH = minSize.height; newW = newH * aspect }

                // 콘텐츠 사각형을 만들어 프레임으로 환산 — **좌상단 모서리 고정**.
                // 우하단을 끌면 좌상단이 제자리에 있는 것이 표준 리사이즈 동작이므로 이쪽으로 확정.
                // 창은 오른쪽·아래로 자란다.
                //
                // 알려진 특성(버그 아님): 좌상단 고정 + 정사각형이면 우하단 그립은 항상 45°
                // 대각선으로 움직인다. 마우스를 45°보다 가파르게 끌면 그립이 마우스보다 멀리 간다
                // (아래로만 100 끌면 그립은 141 이동). 우상단 고정으로 바꾸면 사라지지만
                // 그때는 창이 왼쪽으로 퍼져 표준 동작에서 벗어나므로 채택하지 않았다.
                let newContent = NSRect(
                    x: startContent.origin.x,
                    y: startContent.maxY - newH,
                    width: newW,
                    height: newH
                )
                window.setFrame(window.frameRect(forContentRect: newContent), display: true)

            default:
                break
            }
        }

        content?.viewDidEndLiveResize()
    }
}

// MARK: - 컨트롤 버튼 공통 스타일 (3m/5m 프리셋과 동일: 둥근 사각형 cornerRadius 8)
struct CtrlButtonStyle: ViewModifier {
    var fg: Color
    var bg: Color
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fg)
            .lineLimit(1)            // 한 줄로 (불러오기 등 줄바꿈 방지)
            // 텍스트·아이콘 내용 높이가 달라도 동일하게 보이도록 고정 크기
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(bg))
    }
}

// MARK: - Add Timer Row (inline quick-add inside list)
struct AddTimerRow: View {
    let presets: [(String, Double)]
    let onAdd: (Double, String) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            // 토글 버튼
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.accentColor.opacity(0.12)))
                    Text("Add Timer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(isExpanded ? 0.08 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // 펼쳐지면 프리셋 버튼 표시
            if isExpanded {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { label, secs in
                        Button(action: {
                            onAdd(secs, label)
                            withAnimation { isExpanded = false }
                        }) {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Timer Widget View (floating display — 시간만 표시, 액션은 패널에서)
struct TimerWidgetView: View {
    @ObservedObject var entry: TimerEntry
    var onClose: (() -> Void)? = nil   // windowed 모드에서만 닫기 버튼 표시
    @State private var isHovered = false
    @State private var finishPulse = false   // 완료 시 빨간 테두리 펄스
    // 카멜레온 모드용 — 이 뷰가 올라간 창과, 그 뒤 화면에서 읽어낸 팔레트
    @State private var hostWindow: NSWindow?
    @State private var sampledPalette: ChameleonPalette?
    // 1/4 지점 통과 피드백 — 지금 반짝이는 꼭짓점(1=25%, 2=50%, 3=75%)과 그 애니메이션 상태
    @State private var flashQuarter: Int?
    @State private var flashScale: CGFloat = 1
    @State private var flashOpacity: Double = 0
    @State private var flashTask: Task<Void, Never>?
    /// 마지막으로 지나간 1/4 구간. 되감기(초기화)로 줄어들 때는 반짝이지 않는다.
    @State private var lastQuarter = 0
    @State private var pulseTask: Task<Void, Never>? = nil
    @Environment(\.colorScheme) private var systemScheme

    /// 완료 시 테두리가 깜빡이는 최대 횟수 (이후에는 고정 표시)
    private static let finishPulseCount = 5
    private static let finishPulseDuration: Double = 0.5

    // MARK: - Theme palette
    /// 카멜레온 모드에서 화면을 읽어 만든 팔레트. 아직 못 읽었으면 nil이고,
    /// 그동안(그리고 권한이 없을 때는 계속) 기존 시스템 테마로 그린다.
    private var chameleon: ChameleonPalette? {
        entry.theme == .chameleon ? sampledPalette : nil
    }

    private var isDark: Bool {
        if let chameleon { return chameleon.isDark }
        switch entry.theme {
        case .system:    return systemScheme == .dark
        case .light:     return false
        case .dark:      return true
        case .chameleon: return systemScheme == .dark   // 샘플링 전 임시
        }
    }
    private var bgColor: Color {
        if let chameleon { return chameleon.background }
        return isDark ? Color(red: 0.13, green: 0.13, blue: 0.14)
                      : Color(red: 0.98, green: 0.98, blue: 0.99)
    }
    /// 링·글자 색. 카멜레온 모드에서는 배경의 **보색**이다.
    private var textColor: Color {
        if let chameleon { return chameleon.accent }
        return isDark ? .white : .black
    }
    private var trackColor: Color {
        if let chameleon { return chameleon.track }
        return (isDark ? Color.white : Color.black).opacity(0.12)
    }

    private var ringColor: Color {
        if entry.isFinished { return adapted(Color(red: 1, green: 0.22, blue: 0.37)) }
        // 뽀모도로는 링 색으로 집중/휴식을 구분한다.
        if entry.isPomodoro { return phaseColor }
        return textColor.opacity(0.85)
    }

    /// 뽀모도로 구간 색. 카멜레온 모드에서는 대비가 확보된 값으로 바뀐다.
    private var phaseColor: Color { adapted(entry.phase.color) }

    /// 카멜레온 모드에서 **의미가 붙은 고정 색**(뽀모도로 구간색, 완료 빨강)을
    /// 배경 위에서 읽히도록 조정한다. 색상은 그대로 두고 채도·명도만 바뀌므로
    /// 집중이 붉은 계열, 휴식이 초록 계열이라는 구분은 유지된다.
    /// 조정하지 않으면 비슷한 색의 화면 위에서 링이 통째로 묻힌다.
    private func adapted(_ color: Color) -> Color {
        guard let chameleon else { return color }
        return chameleon.readable(NSColor(color))
    }

    var body: some View {
        GeometryReader { geo in
            // 정사각형 링: 너비/높이 중 작은 쪽에 맞춤
            let side = max(80, min(geo.size.width, geo.size.height))
            let scale = side / 200

            // 감추기 상태에서 위치 확인(peek) 중이면 점선 테두리만 보여줌
            let isHiddenPeek = entry.isWidgetHidden && entry.isLocating

            ZStack {
                backgroundShape
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(isHiddenPeek ? 0 : 1)

                // 링 + 시간 (위젯은 시간만 보여줌)
                ringContent(side: side, scale: scale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(isHiddenPeek ? 0 : 1)

                // 위치 표시 점선 테두리 — 감춤 상태에서 행 hover 시에만
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(isHiddenPeek ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHiddenPeek)

                // 완료 시각 피드백 — 빨간 테두리 펄스
                // 깜빡임이 끝나면 완전히 사라진다 (opacity 0) — 시선을 계속 붙잡지 않도록.
                if entry.isFinished {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color(red: 1, green: 0.22, blue: 0.37),
                                      lineWidth: max(3, 6 * scale))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(finishPulse ? 0.9 : 0)
                }

                // 리사이즈 그립 (호버 시 등장) — 드래그하면 윈도우 크기 조절
                if isHovered {
                    resizeHandle
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.opacity)
                }

                // 닫기 버튼 (windowed 모드, 호버 시 우상단)
                if isHovered, let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                }
            }
        }
        .onHover { hovering in
            withAnimation { isHovered = hovering }
        }
        .onChange(of: entry.isFinished) { finished in updatePulse(finished) }
        .onChange(of: entry.progress) { progress in handleQuarter(progress) }
        .onAppear {
            updatePulse(entry.isFinished)
            // 이미 진행 중인 타이머를 다시 열었을 때 지나간 구간이 몰아서 반짝이지 않도록 맞춰둔다.
            lastQuarter = Int(entry.progress * 4)
        }
        .onDisappear {
            pulseTask?.cancel(); pulseTask = nil
            flashTask?.cancel(); flashTask = nil
        }
        // 샘플링하려면 창의 화면상 위치가 필요한데 SwiftUI만으로는 알 수 없다.
        .background(WindowReader { window in
            if hostWindow !== window { hostWindow = window }
        })
        // 카멜레온 모드일 때만 도는 폴링 루프. 테마가 바뀌면 .task(id:)가 알아서 재시작한다.
        .task(id: entry.theme) { await runChameleonLoop() }
    }

    // MARK: - 1/4 지점 통과 피드백

    /// 진행률이 1/4 경계를 넘어설 때만 반짝인다.
    private func handleQuarter(_ progress: Double) {
        let quarter = Int(progress * 4)
        // 초기화·되감기로 진행률이 줄면 조용히 기준만 되돌린다.
        guard quarter > lastQuarter else {
            if quarter < lastQuarter { lastQuarter = quarter }
            return
        }
        lastQuarter = quarter
        // 100%(=4)는 완료 펄스가 따로 알려주므로 여기서는 다루지 않는다.
        guard (1...3).contains(quarter) else { return }
        flash(quarter)
    }

    private func flash(_ quarter: Int) {
        flashTask?.cancel()
        flashQuarter = quarter
        flashScale = 0.4
        flashOpacity = 0

        // 튀어나오고 → 잠깐 머물고 → 커지며 사라진다.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            flashScale = 1
            flashOpacity = 1
        }
        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.75)) {
                flashOpacity = 0
                flashScale = 1.9
            }
            try? await Task.sleep(nanoseconds: 750_000_000)
            if Task.isCancelled { return }
            flashQuarter = nil
        }
    }

    /// 1/4 을 지나는 **그 순간 진행 선의 끝**이 놓이는 꼭짓점.
    ///
    /// 선은 `trim(from: 0, to: 1 - progress)` 라 끝점이 경로를 거슬러 물러난다.
    /// 진행이 25% 면 끝점은 경로의 75% 지점에 있으므로, 점을 진행률과 같은 쪽
    /// (1/4=우상단)에 찍으면 선 끝과 반대 방향으로 돌아 어긋나 보인다.
    ///   진행 25% → 좌하단, 50% → 우하단, 75% → 우상단
    ///
    /// 꼭짓점은 모서리 호의 한가운데(대각선 지점)라 각 변에서 `r × (1 − √2/2)` 안쪽이다.
    private static func vanishingPoint(quarter: Int, innerSide: CGFloat, radius: CGFloat) -> CGPoint {
        let r = min(radius, innerSide / 2)
        let d = r * (1 - CGFloat(2).squareRoot() / 2)
        switch quarter {
        case 1:  return CGPoint(x: d, y: innerSide - d)              // 25% → 좌하단
        case 2:  return CGPoint(x: innerSide - d, y: innerSide - d)  // 50% → 우하단
        default: return CGPoint(x: innerSide - d, y: d)              // 75% → 우상단
        }
    }

    /// 1/4 점 색 — 회색 계열.
    ///
    /// 처음엔 앰버를 썼지만, 밝은 배경에서 대비를 맞추려고 명도를 낮추면 갈색이 된다.
    /// 무채색은 그런 변질이 없다. 다만 진행 선(검정/흰색)과 구분돼야 하므로
    /// 검정·흰색으로 튀지 않고 **중간 회색에 최대한 가까운** 값을 고른다.
    private var quarterDotColor: Color {
        if let chameleon { return chameleon.readableGray() }
        return isDark ? Color(white: 0.78) : Color(white: 0.42)
    }

    // MARK: - Chameleon
    /// 창 뒤 화면색을 주기적으로 읽어 팔레트를 갱신한다.
    /// 카멜레온 모드가 아니면 즉시 끝나고, 읽은 색은 기존 테마 대신 쓰인다.
    private func runChameleonLoop() async {
        guard entry.theme == .chameleon else {
            sampledPalette = nil
            return
        }
        // 모드로 들어오는 순간 권한을 확인한다 — 없으면 시스템 프롬프트가 뜬다.
        await ChameleonSampler.shared.ensureAuthorization()

        while !Task.isCancelled {
            if let window = hostWindow {
                // 자기 자신을 포함한 타이머 창 전부를 캡처에서 뺀다.
                // 빠뜨리면 자기가 칠한 색을 다시 읽어 칠하는 피드백 루프가 생긴다.
                let excluded = NoteManager.shared.allTimerWindows()
                if let color = await ChameleonSampler.shared.averageColorBehind(window, excluding: excluded) {
                    let palette = ChameleonPalette(background: color)
                    withAnimation(.easeInOut(duration: 0.45)) { sampledPalette = palette }
                }
            }
            // 0.9초 주기 — 발표 중 슬라이드가 넘어가는 속도에는 충분하고
            // 매 프레임 캡처하는 것에 비하면 배터리 부담이 거의 없다.
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
    }

    // 완료 시 빨간 테두리 펄스 애니메이션 시작/정지
    // 최대 finishPulseCount 회만 깜빡인 뒤 테두리를 완전히 지운다 — 발표 중 시선을 계속 붙잡지 않도록.
    private func updatePulse(_ finished: Bool) {
        pulseTask?.cancel()
        pulseTask = nil

        guard finished else {
            withAnimation(.easeInOut(duration: 0.2)) { finishPulse = false }
            return
        }

        finishPulse = false
        let step = Self.finishPulseDuration
        let nanos = UInt64(step * 1_000_000_000)

        pulseTask = Task { @MainActor in
            for _ in 0..<Self.finishPulseCount {
                withAnimation(.easeInOut(duration: step)) { finishPulse = true }
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }

                withAnimation(.easeInOut(duration: step)) { finishPulse = false }
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
            }
            // 깜빡임 종료 — 테두리를 남기지 않고 꺼진 상태로 끝낸다.
            // 루프 마지막 단계가 이미 false이므로 별도 처리 없이 그대로 둔다.
        }
    }

    // MARK: - Resize handle (우하단)
    // 시각 표시는 SwiftUI(우하단 모서리 모양), 실제 리사이즈는 OS 이벤트 추적 루프를 도는 투명 NSView가 담당.
    private var resizeHandle: some View {
        ZStack(alignment: .bottomTrailing) {
            // 투명 핸들: mouseDown 시 trackEvents로 네이티브 레이트의 리사이즈 수행.
            // 창 모서리까지 빈틈없이 닿아야 한다 — 틈을 두면 그 부분은
            // isMovableByWindowBackground 영역이라 리사이즈 대신 창이 끌려간다.
            NativeResizeHandle()

            CornerGrip()
                .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.secondary)
                .frame(width: 13, height: 13)
                .padding(9)          // 그립 그림만 안쪽으로 — 히트 영역은 모서리까지 유지
                .allowsHitTesting(false)
        }
        // 히트 영역 48×48. 이 바깥은 전부 isMovableByWindowBackground 영역이라
        // 빗나가면 리사이즈가 아니라 "창 이동"이 되고, 그러면 좌상단이 마우스를 따라 움직인다.
        // 33이면 둥근 모서리에서 빗나가기 쉬워 키웠다. (그림은 여전히 13×13)
        .frame(width: 48, height: 48)
        .help("Drag to resize")
    }

    // MARK: - Background
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(bgColor)
    }

    // MARK: - Ring + Time (scale에 비례)
    private func ringContent(side: CGFloat, scale: CGFloat) -> some View {
        let lineWidth = max(4, 10 * scale)
        // 배경(cornerRadius 24)과 동심을 이루도록 인셋만큼 반지름을 줄인다.
        let inset = lineWidth / 2 + max(3, 7 * scale)
        let radius = max(6, 24 - inset)

        return ZStack {
            RoundedRectProgress(cornerRadius: radius)
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

            RoundedRectProgress(cornerRadius: radius)
                .trim(from: 0, to: max(0, 1 - entry.progress))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .animation(.linear(duration: 1), value: entry.progress)

            // 1/4 지점을 지나는 순간 그 꼭짓점에서 점이 튀었다가 사라진다.
            // 숫자를 읽지 않아도 "방금 4분의 1이 지났다"가 눈에 걸리게 하는 장치다.
            if let quarter = flashQuarter {
                Circle()
                    .fill(quarterDotColor)
                    .frame(width: max(8, 17 * scale), height: max(8, 17 * scale))
                    .scaleEffect(flashScale)
                    .opacity(flashOpacity)
                    .position(Self.vanishingPoint(quarter: quarter,
                                                  innerSide: max(1, side - inset * 2),
                                                  radius: radius))
                    .allowsHitTesting(false)
            }

            VStack(spacing: 4) {
                // 윤곽선으로 옮기면서 내부가 통째로 비었으므로 숫자를 크게 쓴다 (38 → 52).
                // 창이 작아도 넘치지 않도록 한 줄 고정 + 축소 허용.
                Text(formatTime(entry.remaining))
                    .font(.system(size: max(18, 52 * scale), weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.3), value: entry.remaining)

                // 뽀모도로는 실행 중에도 현재 구간을 계속 보여준다 — 남은 시간만으로는
                // 지금이 집중인지 휴식인지 알 수 없기 때문.
                if entry.isPomodoro {
                    HStack(spacing: 3) {
                        Image(systemName: entry.phase.icon)
                            .font(.system(size: max(8, 10 * scale), weight: .bold))
                        Text("\(entry.phase.title) · #\(entry.cycleNumber)")
                            .font(.system(size: max(9, 12 * scale), weight: .semibold))
                    }
                    .foregroundStyle(phaseColor)
                    .lineLimit(1)
                } else if !entry.isRunning && !entry.name.isEmpty {
                    Text(entry.name)
                        .font(.system(size: max(9, 11 * scale), weight: .medium))
                        .foregroundStyle(textColor.opacity(0.6))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: entry.isRunning)
            .animation(.easeInOut(duration: 0.25), value: entry.phase)
            // 숫자가 윤곽선에 닿지 않도록 선 두께만큼 안쪽으로
            .padding(.horizontal, lineWidth + max(4, 8 * scale))
        }
        .padding(inset)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
