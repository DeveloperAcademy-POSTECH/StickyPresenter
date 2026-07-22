import SwiftUI
import AppKit
import LeeoKit

// MARK: - App Entry Point
@main
struct StickyPresenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        LeeoEngagement.shared.registerLaunch()
    }

    var body: some Scene {
        Settings {
            EmptyView()
                .leeoSatisfactionCheck(StickyPresenterSpec.self)
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var noteManager = NoteManager.shared
    var settingsWindow: NSWindow?
    
    // 앱이 이미 실행 중인 상태에서 Finder/Launchpad로 다시 열 때 호출
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        noteManager.openTimerList()
        if !flag { noteManager.showAllNotes() }
        return true
    }

    // 창이 모두 닫혀도 메뉴바 앱으로 계속 실행
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalHotkey()

        // Hide dock icon — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // 최초 실행 시에만 사용법 스티키 노트 표시
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            noteManager.addNote(
                text: "👋 StickyPresenter Guide\n\n📌 Drag to move a note\n🖱 Hover to show controls\n🎨 Adjust color · opacity · font size\n🔒 Lock button prevents editing\n\n⌘⌃N  New sticky note\n⌘⌃T  Open timers\n⌘⌃P  Teleprompter\n⌘⌃S  Show all notes\n⌘⌃H  Hide all notes\n\n💡 You can also create a sticky note\n   right from the timer controls!",
                color: .yellow,
                position: CGPoint(x: screenFrame.minX + 60, y: screenFrame.midY - 100)
            )
        } else {
            noteManager.showAllNotes()
        }

        // 앱 시작 시 타이머 항상 열기
        noteManager.openTimerList()
    }

    // MARK: - Global Hotkeys (⌘⌃ prefix for all)
    private func setupGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleHotkeyEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event
        }
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.command, .control] else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch event.keyCode {
            case 45: self.addNewNote()           // ⌘⌃N
            case 9:  self.addNoteFromClipboard() // ⌘⌃V
            case 35: self.openTeleprompter()     // ⌘⌃P
            case 17: self.noteManager.toggleTimerHotkey() // ⌘⌃T
            case 1:  self.noteManager.showAllNotes()      // ⌘⌃S
            case 4:  self.noteManager.hideAllNotes()      // ⌘⌃H
            default: break
            }
        }
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "StickyPresenter")
            button.image?.size = NSSize(width: 18, height: 18)
        }
        
        let menu = NSMenu()
        
        let newNoteItem = NSMenuItem(title: "📌 New Sticky Note", action: #selector(addNewNote), keyEquivalent: "n")
        newNoteItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(newNoteItem)

        let clipboardItem = NSMenuItem(title: "📋 New from Clipboard", action: #selector(addNoteFromClipboard), keyEquivalent: "v")
        clipboardItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(clipboardItem)

        menu.addItem(NSMenuItem.separator())

        let teleprompterItem = NSMenuItem(title: "📺 Teleprompter Mode", action: #selector(openTeleprompter), keyEquivalent: "p")
        teleprompterItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(teleprompterItem)

        let timerItem = NSMenuItem(title: "⏱ Timers", action: #selector(openTimer), keyEquivalent: "t")
        timerItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(timerItem)

        menu.addItem(NSMenuItem.separator())

        let showItem = NSMenuItem(title: "👁 Show All Notes", action: #selector(showAllNotes), keyEquivalent: "s")
        showItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(showItem)

        let hideItem = NSMenuItem(title: "🙈 Hide All Notes", action: #selector(hideAllNotes), keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(hideItem)
        menu.addItem(NSMenuItem.separator())
        
        // Color submenu
        let colorMenu = NSMenu()
        let colors: [(String, NoteColor)] = [
            ("🟡 Yellow", .yellow),
            ("🩷 Pink", .pink),
            ("🟢 Green", .green),
            ("🔵 Blue", .blue),
            ("🟣 Purple", .purple),
            ("🟠 Orange", .orange),
        ]
        for (title, color) in colors {
            let item = NSMenuItem(title: title, action: #selector(setNextNoteColor(_:)), keyEquivalent: "")
            item.representedObject = color
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "🎨 Default Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "🗑 Remove All Notes", action: #selector(removeAllNotes), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // MARK: - Contact the Developer
        let contactMenu = NSMenu()
        contactMenu.addItem(NSMenuItem(title: "✉️ Email (leeo@kakao.com)", action: #selector(contactByEmail), keyEquivalent: ""))
        contactMenu.addItem(NSMenuItem(title: "📷 Instagram DM (@lee25_ios)", action: #selector(contactByInstagram), keyEquivalent: ""))
        let contactItem = NSMenuItem(title: "💬 Contact the Developer", action: nil, keyEquivalent: "")
        contactItem.submenu = contactMenu
        menu.addItem(contactItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit StickyPresenter", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func addNewNote() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let randomX = CGFloat.random(in: screenFrame.minX + 50...screenFrame.maxX - 300)
        let randomY = CGFloat.random(in: screenFrame.minY + 50...screenFrame.maxY - 250)
        
        noteManager.addNote(
            text: "",
            color: noteManager.defaultColor,
            position: CGPoint(x: randomX, y: randomY)
        )
    }
    
    @objc func addNoteFromClipboard() {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string) ?? ""
        
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let randomX = CGFloat.random(in: screenFrame.minX + 50...screenFrame.maxX - 300)
        let randomY = CGFloat.random(in: screenFrame.minY + 50...screenFrame.maxY - 250)
        
        noteManager.addNote(
            text: text,
            color: noteManager.defaultColor,
            position: CGPoint(x: randomX, y: randomY)
        )
    }
    
    @objc func openTimer() {
        noteManager.openTimerList()
    }

    @objc func openTeleprompter() {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string) ?? "Paste your script here...\n\nThe teleprompter will auto-scroll through your text.\n\nUse the controls to adjust speed and font size."
        noteManager.openTeleprompter(with: text)
    }
    
    @objc func showAllNotes() {
        noteManager.showAllNotes()
    }
    
    @objc func hideAllNotes() {
        noteManager.hideAllNotes()
    }
    
    @objc func setNextNoteColor(_ sender: NSMenuItem) {
        if let color = sender.representedObject as? NoteColor {
            noteManager.defaultColor = color
        }
    }
    
    @objc func removeAllNotes() {
        let alert = NSAlert()
        alert.messageText = "Remove All Notes?"
        alert.informativeText = "This will permanently delete all sticky notes."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            noteManager.removeAllNotes()
        }
    }
    
    // MARK: - Contact the Developer
    @objc func contactByEmail() {
        if let url = URL(string: "mailto:leeo@kakao.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func contactByInstagram() {
        if let url = URL(string: "https://instagram.com/lee25_ios") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
