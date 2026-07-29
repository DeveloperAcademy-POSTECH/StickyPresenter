import SwiftUI
import AppKit

// MARK: - Widget Theme
enum WidgetTheme: String, CaseIterable {
    case system   // 시스템 외형 따름
    case light    // 밝은 테마
    case dark     // 어두운(반전) 테마

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var next: WidgetTheme {
        switch self {
        case .system: return .light
        case .light:  return .dark
        case .dark:   return .system
        }
    }
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
    // 위젯 테마 (시스템 / 라이트 / 다크 반전)
    var theme: WidgetTheme = .system {
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
                self.playFinishSound()   // 완료 청각 피드백 (위젯이 숨겨져 있어도 울림)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
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

                    Color.clear.frame(maxWidth: .infinity, minHeight: 0)

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
// 네이티브 가장자리 리사이즈와 동일한 이벤트 레이트로 윈도우를 조절하고,
// 시작 시점의 가로:세로 비율을 보존한다.
struct NativeResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ResizeHandleNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    override func resetCursorRects() {
        // 대각 리사이즈에 대응하는 공개 커서가 없어 crosshair로 표시
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }

        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation          // 화면 좌표(좌하단 원점)
        let aspect = startFrame.width / startFrame.height
        let minSize = window.minSize

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
                let dx = mouse.x - startMouse.x
                let dy = mouse.y - startMouse.y          // 위로 +, 아래로 -

                // 정사각형 위젯이므로 끌어당기는 축(가로/세로)이 커서를 그대로 따라오도록
                // 두 후보 스케일 중 큰 쪽 채택 → 드래그한 만큼 크기가 변함.
                let candW = startFrame.width + dx
                let candH = startFrame.height - dy   // 아래로 끌면 dy<0 → 높이 증가
                let scale = max(candW / startFrame.width, candH / startFrame.height)

                var newW = startFrame.width * scale
                var newH = newW / aspect
                // 최소 크기 클램프 (비율 유지)
                if newW < minSize.width  { newW = minSize.width;  newH = newW / aspect }
                if newH < minSize.height { newH = minSize.height; newW = newH * aspect }

                let newY = startFrame.maxY - newH         // 상단 가장자리 고정
                window.setFrame(
                    NSRect(x: startFrame.origin.x, y: newY, width: newW, height: newH),
                    display: true
                )

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
    @State private var pulseTask: Task<Void, Never>? = nil
    @Environment(\.colorScheme) private var systemScheme

    /// 완료 시 테두리가 깜빡이는 최대 횟수 (이후에는 고정 표시)
    private static let finishPulseCount = 5
    private static let finishPulseDuration: Double = 0.5

    // MARK: - Theme palette
    private var isDark: Bool {
        switch entry.theme {
        case .system: return systemScheme == .dark
        case .light:  return false
        case .dark:   return true
        }
    }
    private var bgColor: Color {
        isDark ? Color(red: 0.13, green: 0.13, blue: 0.14)
               : Color(red: 0.98, green: 0.98, blue: 0.99)
    }
    private var textColor: Color { isDark ? .white : .black }
    private var trackColor: Color { (isDark ? Color.white : Color.black).opacity(0.12) }

    private var ringColor: Color {
        if entry.isFinished { return Color(red: 1, green: 0.22, blue: 0.37) }
        return textColor.opacity(0.85)
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
                if entry.isFinished {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color(red: 1, green: 0.22, blue: 0.37),
                                      lineWidth: max(3, 6 * scale))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .opacity(finishPulse ? 0.9 : 0.15)
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
        .onAppear { updatePulse(entry.isFinished) }
        .onDisappear { pulseTask?.cancel(); pulseTask = nil }
    }

    // 완료 시 빨간 테두리 펄스 애니메이션 시작/정지
    // 최대 finishPulseCount 회만 깜빡인 뒤, 완료 상태를 알리는 테두리를 고정으로 남긴다.
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
            // 깜빡임 종료 — 테두리는 켜진 상태로 고정
            withAnimation(.easeInOut(duration: step)) { finishPulse = true }
        }
    }

    // MARK: - Resize handle (우하단)
    // 시각 표시는 SwiftUI(우하단 모서리 모양), 실제 리사이즈는 OS 이벤트 추적 루프를 도는 투명 NSView가 담당.
    private var resizeHandle: some View {
        ZStack(alignment: .bottomTrailing) {
            // 투명 핸들: mouseDown 시 trackEvents로 네이티브 레이트의 리사이즈 수행
            NativeResizeHandle()

            CornerGrip()
                .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.secondary)
                .frame(width: 13, height: 13)
                .padding(4)
                .allowsHitTesting(false)
        }
        .frame(width: 28, height: 28)
        .padding(5)
        .help("Drag to resize")
    }

    // MARK: - Background
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(bgColor)
    }

    // MARK: - Ring + Time (scale에 비례)
    private func ringContent(side: CGFloat, scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: max(4, 10 * scale))

            Circle()
                .trim(from: 0, to: max(0, 1 - entry.progress))
                .stroke(ringColor, style: StrokeStyle(lineWidth: max(4, 10 * scale), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: entry.progress)

            VStack(spacing: 4) {
                Text(formatTime(entry.remaining))
                    .font(.system(size: max(16, 38 * scale), weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.3), value: entry.remaining)

                if !entry.isRunning && !entry.name.isEmpty {
                    Text(entry.name)
                        .font(.system(size: max(9, 11 * scale), weight: .medium))
                        .foregroundStyle(textColor.opacity(0.6))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: entry.isRunning)
        }
        .padding(max(12, 26 * scale))
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
