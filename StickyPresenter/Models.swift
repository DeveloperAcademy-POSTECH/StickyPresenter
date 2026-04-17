import SwiftUI
import AppKit

// MARK: - Note Color
enum NoteColor: String, CaseIterable, Codable {
    case yellow, pink, green, blue, purple, orange
    
    var background: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.95, blue: 0.70)
        case .pink:   return Color(red: 1.0, green: 0.82, blue: 0.86)
        case .green:  return Color(red: 0.78, green: 0.95, blue: 0.78)
        case .blue:   return Color(red: 0.78, green: 0.88, blue: 1.0)
        case .purple: return Color(red: 0.88, green: 0.80, blue: 1.0)
        case .orange: return Color(red: 1.0, green: 0.88, blue: 0.72)
        }
    }
    
    var headerColor: Color {
        switch self {
        case .yellow: return Color(red: 0.95, green: 0.85, blue: 0.40)
        case .pink:   return Color(red: 0.95, green: 0.60, blue: 0.70)
        case .green:  return Color(red: 0.50, green: 0.82, blue: 0.50)
        case .blue:   return Color(red: 0.50, green: 0.70, blue: 0.95)
        case .purple: return Color(red: 0.70, green: 0.55, blue: 0.95)
        case .orange: return Color(red: 0.95, green: 0.70, blue: 0.40)
        }
    }
    
    var textColor: Color {
        return Color(red: 0.2, green: 0.2, blue: 0.2)
    }
    
    var nsBackground: NSColor {
        switch self {
        case .yellow: return NSColor(red: 1.0, green: 0.95, blue: 0.70, alpha: 1.0)
        case .pink:   return NSColor(red: 1.0, green: 0.82, blue: 0.86, alpha: 1.0)
        case .green:  return NSColor(red: 0.78, green: 0.95, blue: 0.78, alpha: 1.0)
        case .blue:   return NSColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 1.0)
        case .purple: return NSColor(red: 0.88, green: 0.80, blue: 1.0, alpha: 1.0)
        case .orange: return NSColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1.0)
        }
    }
}

// MARK: - Sticky Note Model
class StickyNote: ObservableObject, Identifiable {
    let id: UUID
    @Published var text: String
    @Published var color: NoteColor
    @Published var position: CGPoint
    @Published var size: CGSize
    @Published var opacity: Double
    @Published var fontSize: CGFloat
    @Published var isLocked: Bool
    @Published var isPinned: Bool
    
    var panel: NSPanel?
    
    init(
        id: UUID = UUID(),
        text: String = "",
        color: NoteColor = .yellow,
        position: CGPoint = CGPoint(x: 200, y: 200),
        size: CGSize = CGSize(width: 280, height: 220),
        opacity: Double = 0.92,
        fontSize: CGFloat = 14,
        isLocked: Bool = false,
        isPinned: Bool = true
    ) {
        self.id = id
        self.text = text
        self.color = color
        self.position = position
        self.size = size
        self.opacity = opacity
        self.fontSize = fontSize
        self.isLocked = isLocked
        self.isPinned = isPinned
    }
}
