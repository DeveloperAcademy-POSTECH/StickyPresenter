import SwiftUI
import AppKit

// MARK: - Note Manager
class NoteManager: ObservableObject {
    static let shared = NoteManager()

    @Published var notes: [StickyNote] = []
    @Published var defaultColor: NoteColor = .yellow

    private var teleprompterPanel: NSPanel?
    private var timerListPanel: NSPanel?
    private var timerWidgetWindows: [UUID: NSWindow] = [:]
    private var timerPresentationWindows: [UUID: NSWindow] = [:]
    let timerListManager = TimerListManager()

    init() {
        timerListManager.onAdd = { [weak self] entry in
            self?.showTimerWidget(for: entry)
        }
        timerListManager.onRemove = { [weak self] entry in
            guard let self else { return }

            // entry.invalidate()는 TimerListManager.remove()에서 이미 호출됨.
            // (isInvalidated = true, ticker 중단 완료)
            // 여기서는 widgetPanel 참조 해제 + 윈도우 정리만 담당.
            entry.widgetPanel = nil

            // dictionary에서 제거해 소유권을 로컬로 이전
            let widgetWindow       = timerWidgetWindows.removeValue(forKey: entry.id)
            let presentationWindow = timerPresentationWindows.removeValue(forKey: entry.id)

            // NSHostingView를 동기적으로 해제 → @ObservedObject 구독 즉시 취소.
            // 이후 entries.removeAll 이 TimerListView 를 재렌더할 때
            // entry.objectWillChange 구독자 목록이 이미 비어있으므로 안전.
            widgetWindow?.contentView = nil
            presentationWindow?.contentView = nil

            // close()는 다음 런루프로 지연 — 빈 window 닫기이므로 SwiftUI 없음.
            DispatchQueue.main.async {
                widgetWindow?.close()
                presentationWindow?.close()
            }
        }
    }

    // MARK: - Create floating panel (no chrome)
    private func createFloatingPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        return panel
    }

    // MARK: - Create timer widget window (NSWindow for AirPlay/screen sharing support)
    private func createTimerWidgetWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.sharingType = .readOnly  // AirPlay / 화면 공유 윈도우 목록에 노출
        window.isReleasedWhenClosed = false  // Swift ARC와 충돌 방지 (이중 해제 크래시)
        return window
    }

    // MARK: - Create timer list panel (with native chrome)
    private func createTimerListPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.title = "Timers"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        return panel
    }

    // MARK: - Add Note
    func addNote(text: String, color: NoteColor, position: CGPoint, size: CGSize = CGSize(width: 280, height: 220)) {
        let note = StickyNote(text: text, color: color, position: position, size: size)
        notes.append(note)
        showNote(note)
    }

    // MARK: - Show Single Note
    func showNote(_ note: StickyNote) {
        if note.panel != nil { note.panel?.orderFront(nil); return }
        let frame = NSRect(x: note.position.x, y: note.position.y, width: note.size.width, height: note.size.height)
        let panel = createFloatingPanel(frame: frame)
        panel.alphaValue = note.opacity
        panel.minSize = NSSize(width: 200, height: 150)
        panel.contentView = NSHostingView(rootView:
            StickyNoteView(note: note, onClose: { [weak self] in
                // 버튼 액션 클로저가 완전히 끝난 뒤 제거 — 동기 호출 시
                // note.panel = nil이 NSPanel을 즉시 해제해 뷰 계층 붕괴 → CRASH
                DispatchQueue.main.async {
                    self?.removeNote(note)
                }
            }, onColorChange: { newColor in
                note.color = newColor
            })
        )
        panel.orderFront(nil)
        note.panel = panel
    }

    func showAllNotes() { for note in notes { showNote(note) } }
    func hideAllNotes() { for note in notes { note.panel?.orderOut(nil) } }

    func removeNote(_ note: StickyNote) {
        let panel = note.panel
        note.panel = nil
        // contentView = nil 동기 실행: SwiftUI 구독 즉시 해제 후 notes 변경
        panel?.contentView = nil
        notes.removeAll { $0.id == note.id }
        DispatchQueue.main.async { panel?.close() }
    }

    func removeAllNotes() {
        let panelsToClose = notes.compactMap { $0.panel }
        for note in notes { note.panel = nil }
        // contentView = nil 동기 실행 후 notes 변경
        panelsToClose.forEach { $0.contentView = nil }
        notes.removeAll()
        DispatchQueue.main.async { panelsToClose.forEach { $0.close() } }
    }

    // MARK: - Global Hotkey toggle (⌘⌃T)
    func toggleTimerHotkey() {
        // 타이머가 없으면 → 설정 뷰 열기
        if timerListManager.entries.isEmpty {
            openTimerList()
            return
        }

        // 위젯 중 하나라도 보이면 → 전체 hide (리스트 패널은 유지)
        let anyWidgetVisible = timerWidgetWindows.values.contains { $0.isVisible }
        if anyWidgetVisible {
            timerWidgetWindows.values.forEach { $0.orderOut(nil) }
            // 설정 뷰는 항상 보이도록
            timerListPanel?.orderFront(nil)
        } else {
            // 숨겨진 위젯 → 다시 보이기 + 설정 뷰 포커스
            timerWidgetWindows.values.forEach { $0.orderFront(nil) }
            timerListPanel?.orderFront(nil)
        }
    }

    // MARK: - Timer List
    func openTimerList() {
        if let existing = timerListPanel {
            existing.orderFront(nil)
            return
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame
        let w: CGFloat = 300, h: CGFloat = 380
        let frame = NSRect(x: sf.maxX - w - 40, y: sf.maxY - h - 80, width: w, height: h)
        let panel = createTimerListPanel(frame: frame)
        panel.minSize = NSSize(width: 260, height: 220)

        panel.contentView = NSHostingView(rootView: TimerListView(manager: timerListManager))
        panel.orderFront(nil)
        timerListPanel = panel

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            self?.timerListPanel = nil
        }
    }

    // MARK: - Timer Widget
    func showTimerWidget(for entry: TimerEntry) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame
        let width: CGFloat = 200
        let height: CGFloat = 290   // 정사각형(200) + 컨트롤 영역(90)
        let offset = CGFloat(timerWidgetWindows.count) * 24
        let x = sf.maxX - width - 360 - offset
        let y = sf.maxY - height - 80 - offset

        let frame = NSRect(x: x, y: y, width: width, height: height)
        let window = createTimerWidgetWindow(frame: frame)
        window.alphaValue = 1.0
        window.minSize = NSSize(width: 200, height: 290)
        window.maxSize = NSSize(width: 200, height: 290)
        window.title = "Timer – \(entry.name)"

        let widgetHostingView = NSHostingView(rootView:
            TimerWidgetView(entry: entry, onClose: { [weak self] in
                DispatchQueue.main.async {
                    self?.timerListManager.remove(entry)
                }
            })
        )
        widgetHostingView.wantsLayer = true
        widgetHostingView.layer?.backgroundColor = CGColor(gray: 0, alpha: 0)
        window.contentView = widgetHostingView
        window.orderFront(nil)
        entry.widgetPanel = window
        timerWidgetWindows[entry.id] = window
    }

    // MARK: - Snap widget next to the timer list panel
    func snapWidgetToPanel(for entry: TimerEntry) {
        guard let widgetPanel = entry.widgetPanel,
              let listPanel = timerListPanel else { return }

        let listFrame = listPanel.frame
        let wSize = widgetPanel.frame.size
        let gap: CGFloat = 8

        // 패널 왼쪽에 붙이되, 인덱스별로 위에서 아래로 쌓기
        let index = CGFloat(timerListManager.entries.firstIndex { $0.id == entry.id } ?? 0)
        let x = listFrame.minX - wSize.width - gap
        let y = listFrame.maxY - wSize.height - index * (wSize.height + gap)

        // 화면 안으로 클램핑
        let sf = (widgetPanel.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let clampedX = max(sf.minX, min(x, sf.maxX - wSize.width))
        let clampedY = max(sf.minY, min(y, sf.maxY - wSize.height))

        widgetPanel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        widgetPanel.orderFront(nil)
        if entry.isWidgetHidden {
            entry.isWidgetHidden = false
        }
    }

    // MARK: - Open timer in a titled window (for AirPlay / screen sharing)
    func openTimerWindow(for entry: TimerEntry) {
        // 이미 열려 있으면 앞으로
        if let existing = timerPresentationWindows[entry.id] {
            existing.orderFront(nil)
            return
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let w: CGFloat = 280, h: CGFloat = 320
        let frame = NSRect(x: sf.midX - w / 2, y: sf.midY - h / 2, width: w, height: h)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = entry.name.isEmpty ? "Timer" : entry.name
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.sharingType = .readOnly
        window.isReleasedWhenClosed = false  // Swift ARC와 충돌 방지 (이중 해제 크래시)

        let hostingView = NSHostingView(rootView:
            TimerWidgetView(entry: entry, onClose: { [weak window] in
                DispatchQueue.main.async { window?.close() }
            })
        )
        window.contentView = hostingView
        window.orderFront(nil)
        timerPresentationWindows[entry.id] = window

        // entry.id(값 타입 UUID)만 캡처 — entry 전체를 strong 캡처하면
        // 타이머가 제거된 뒤에도 observer가 entry를 살려두는 메모리 누수 발생
        let entryId = entry.id
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.timerPresentationWindows.removeValue(forKey: entryId)
        }
    }

    // MARK: - Teleprompter
    func openTeleprompter(with text: String) {
        closeTeleprompter()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame
        let w: CGFloat = 600, h: CGFloat = 400
        let frame = NSRect(x: (sf.width - w) / 2, y: sf.height - h - 80, width: w, height: h)
        let panel = createFloatingPanel(frame: frame)
        panel.alphaValue = 0.88
        panel.minSize = NSSize(width: 400, height: 250)
        panel.contentView = NSHostingView(rootView:
            TeleprompterView(initialText: text, onClose: { [weak self] in
                // SwiftUI 버튼 액션 → 동기 close 시 NSPanel 즉시 해제 → CRASH
                DispatchQueue.main.async { self?.closeTeleprompter() }
            })
        )
        panel.orderFront(nil)
        teleprompterPanel = panel
    }

    private func closeTeleprompter() {
        let panel = teleprompterPanel
        teleprompterPanel = nil
        // contentView = nil 동기 실행 후 close 지연
        panel?.contentView = nil
        DispatchQueue.main.async { panel?.close() }
    }
}
