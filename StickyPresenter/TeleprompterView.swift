import SwiftUI

// MARK: - Teleprompter View
struct TeleprompterView: View {
    @State private var text: String
    @State private var isScrolling = false
    @State private var scrollSpeed: Double = 30.0 // pixels per second
    @State private var fontSize: CGFloat = 24
    @State private var opacity: Double = 0.88
    @State private var isMirrored = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isEditing = false
    
    let onClose: () -> Void
    
    private let timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()
    
    init(initialText: String, onClose: @escaping () -> Void) {
        _text = State(initialValue: initialText)
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            teleprompterHeader
            
            // Content
            teleprompterContent
            
            // Controls
            teleprompterControls
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Header
    private var teleprompterHeader: some View {
        HStack {
            Button(action: onClose) {
                Circle()
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("📺 TELEPROMPTER")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Button(action: { isEditing.toggle() }) {
                Image(systemName: isEditing ? "eye" : "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(isEditing ? "Preview mode" : "Edit text")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }
    
    // MARK: - Content
    private var teleprompterContent: some View {
        Group {
            if isEditing {
                TextEditor(text: $text)
                    .font(.system(size: fontSize))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(text)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundColor(.white)
                            .lineSpacing(fontSize * 0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
                            .id("teleprompterText")
                            .offset(y: -scrollOffset)
                    }
                    .onReceive(timer) { _ in
                        if isScrolling {
                            scrollOffset += scrollSpeed / 60.0
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { isScrolling = false }
        // Gradient overlay for readability
        .overlay(
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
                
                Spacer()
                
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
            }
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Controls
    private var teleprompterControls: some View {
        VStack(spacing: 8) {
            // Play/Pause + Reset
            HStack(spacing: 16) {
                Button(action: { scrollOffset = 0 }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                
                Button(action: { isScrolling.toggle() }) {
                    Image(systemName: isScrolling ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                
                Button(action: { isMirrored.toggle() }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(isMirrored ? .yellow : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Mirror text (for teleprompter glass)")
            }
            
            // Speed slider
            HStack(spacing: 8) {
                Image(systemName: "tortoise")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                
                Slider(value: $scrollSpeed, in: 5...120, step: 5)
                    .tint(.green)
                
                Image(systemName: "hare")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                
                Text("\(Int(scrollSpeed))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 24)
            }
            
            // Font size
            HStack(spacing: 8) {
                Text("Font")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))

                Button(action: { fontSize = max(14, fontSize - 2) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)

                Text("\(Int(fontSize))pt")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 34)

                Button(action: { fontSize = min(48, fontSize + 2) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
    }
}
