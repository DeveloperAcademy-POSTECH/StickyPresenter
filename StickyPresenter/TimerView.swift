import SwiftUI

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

    init(name: String, targetSeconds: TimeInterval) {
        self.name = name
        self.targetSeconds = targetSeconds
    }

    var remaining: TimeInterval { max(0, targetSeconds - elapsed) }
    var isFinished: Bool { elapsed >= targetSeconds }
    var progress: Double { min(1.0, elapsed / max(1, targetSeconds)) }

    func addSeconds(_ s: TimeInterval = 30) {
        guard !isInvalidated else { return }
        targetSeconds += s
    }

    func subtractSeconds(_ s: TimeInterval = 30) {
        guard !isInvalidated else { return }
        elapsed = min(elapsed + s, targetSeconds)
    }

    func addMinute() {
        guard !isInvalidated else { return }
        targetSeconds += 60
    }

    func reset() {
        guard !isInvalidated else { return }
        stopTicker()
        isRunning = false
        elapsed = 0
    }

    func setRunning(_ value: Bool) {
        guard !isInvalidated, value != isRunning else { return }
        isRunning = value
        if value { startTicker() } else { stopTicker() }
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
            if self.elapsed >= self.targetSeconds {
                // invalidate()는 현재 콜백 내부에서 호출해도 안전 (Apple 문서 보장).
                self.stopTicker()
                self.isRunning = false
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
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

// MARK: - Timer List View (main panel)
struct TimerListView: View {
    @ObservedObject var manager: TimerListManager
    @State private var inputText = ""
    @FocusState private var focused: Bool

    private var parsedSeconds: TimeInterval {
        parseTimerInput(inputText.trimmingCharacters(in: .whitespaces))
    }

    private var previewText: String? {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty, parsedSeconds > 0 else { return nil }
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
                        if parsedSeconds > 0 {
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
                    .help("새 스티키 노트")

                    if !manager.entries.isEmpty {
                        Button(action: {
                            for entry in manager.entries {
                                NoteManager.shared.openTimerWindow(for: entry)
                            }
                        }) {
                            Image(systemName: "macwindow.badge.plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .help("새 윈도우로 열기 (화면 공유 / AirPlay)")
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }

                if let preview = previewText {
                    Text(preview)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: parsedSeconds > 0)
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
                        Text("빠른 시작")
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
                    Text("타이머가 없어요")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("프리셋을 누르거나 시간을 직접 입력하세요")
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
        }
        .frame(minWidth: 280, minHeight: 180)
        .background(.regularMaterial)
        .background(ignoresSafeAreaEdges: .all)
    }

    private func submit() {
        let raw = inputText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let secs = parseTimerInput(raw)
        guard secs > 0 else { return }
        let entry = TimerEntry(name: raw, targetSeconds: secs)
        entry.setRunning(true)
        manager.add(entry)
        inputText = ""
        focused = true
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
        return .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(formatTime(entry.remaining))
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.3), value: entry.remaining)
            }

            Spacer()

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    // Play / Pause
                    Button(action: {
                        if entry.isFinished { entry.reset() }
                        entry.toggleRunning()
                    }) {
                        Image(systemName: entry.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    // Snap to panel
                    Button(action: { NoteManager.shared.snapWidgetToPanel(for: entry) }) {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("컨트롤 패널 옆으로 이동")

                    // Hide / Show widget
                    Button(action: {
                        if entry.isWidgetHidden {
                            entry.widgetPanel?.orderFront(nil)
                        } else {
                            entry.widgetPanel?.orderOut(nil)
                        }
                        entry.isWidgetHidden.toggle()
                    }) {
                        Image(systemName: entry.isWidgetHidden ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    // +30s
                    Button(action: { entry.addSeconds() }) {
                        Text("+30s")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    // +1m
                    Button(action: { entry.addMinute() }) {
                        Text("+1m")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    // Close
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(rowBackground)
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
                    Text("타이머 추가")
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

// MARK: - Timer Widget View (floating circular panel)
struct TimerWidgetView: View {
    @ObservedObject var entry: TimerEntry
    let onClose: () -> Void
    @State private var isHovered = false

    private let controlsHeight: CGFloat = 68

    private var ringColor: Color {
        if entry.isFinished { return Color(red: 1, green: 0.22, blue: 0.37) }
        return Color.primary.opacity(0.85)
    }

    var body: some View {
        GeometryReader { geo in
            // 링은 정사각형: 너비와 (높이 - 컨트롤 영역) 중 작은 쪽에 맞춤
            let side = max(120, min(geo.size.width, geo.size.height - controlsHeight))
            let scale = side / 200

            ZStack(alignment: .top) {
                // 배경: 호버 시 아래로 늘어남
                backgroundShape
                    .frame(width: geo.size.width, height: isHovered ? geo.size.height : side)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)

                // 링 + 시간
                ringContent(side: side, scale: scale)
                    .frame(width: geo.size.width, height: side)

                // 컨트롤: 링 아래 고정 영역
                VStack(spacing: 0) {
                    Spacer().frame(height: side)
                    controlsBar
                        .frame(maxWidth: .infinity)
                        .frame(height: controlsHeight)
                }
                .frame(width: geo.size.width, height: side + controlsHeight)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)

                // 리사이즈 그립 힌트 (호버 시)
                if isHovered {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                        .transition(.opacity)
                }
            }
        }
        .onHover { hovering in
            withAnimation { isHovered = hovering }
        }
    }

    // MARK: - Background
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Ring + Time (scale에 비례)
    private func ringContent(side: CGFloat, scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: max(4, 10 * scale))

            Circle()
                .trim(from: 0, to: max(0, 1 - entry.progress))
                .stroke(ringColor, style: StrokeStyle(lineWidth: max(4, 10 * scale), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: entry.progress)

            VStack(spacing: 4) {
                Text(formatTime(entry.remaining))
                    .font(.system(size: max(16, 38 * scale), weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.3), value: entry.remaining)

                if !entry.isRunning && !entry.name.isEmpty {
                    Text(entry.name)
                        .font(.system(size: max(9, 11 * scale), weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: entry.isRunning)
        }
        .padding(max(12, 26 * scale))
    }

    // MARK: - Controls (고정 크기, 4버튼 동일 36×36)
    private var controlsBar: some View {
        HStack(spacing: 10) {
            // -30s
            Button(action: { entry.subtractSeconds() }) {
                Text("-30s")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.09)))
            }
            .buttonStyle(.plain)

            // Play / Pause
            Button(action: {
                if entry.isFinished { entry.reset() }
                entry.toggleRunning()
            }) {
                Image(systemName: entry.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)

            // +30s
            Button(action: { entry.addSeconds() }) {
                Text("+30s")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.09)))
            }
            .buttonStyle(.plain)

            // Close (빨간색)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
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

    private func formatTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
