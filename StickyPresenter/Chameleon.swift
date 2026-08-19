import SwiftUI
import AppKit
import ScreenCaptureKit

// MARK: - Chameleon
// 타이머 창 뒤에 실제로 깔린 화면 색을 읽어 배경색으로 쓰고,
// 나머지 요소(링·글자)는 그 배경의 보색으로 칠한다.
//
// ScreenCaptureKit을 쓰므로 **화면 기록 권한**이 필요하다. 권한이 없으면
// 샘플링이 조용히 실패하고 위젯은 기존 시스템 테마로 되돌아간다.

// MARK: - Palette
/// 샘플링한 배경색 하나로부터 위젯이 쓸 색 전부를 만들어낸다.
struct ChameleonPalette {
    let background: Color
    /// 링·글자에 쓰는 보색. 배경 대비 확실히 읽히도록 명도를 조정한 값이다.
    let accent: Color
    /// 링의 남은 구간(트랙) — 보색을 옅게 깔아 배경에 묻히지 않게 한다.
    let track: Color
    /// 배경이 어두운지 — 기존 테마 로직(그림자 등)과 맞추기 위해 노출한다.
    let isDark: Bool

    init(background bg: NSColor) {
        let srgb = bg.usingColorSpace(.sRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // 사람 눈 기준 밝기. 단순 평균이 아니라 녹색에 가중치를 줘야
        // 노랑 배경에 흰 글자를 얹는 식의 실수가 안 난다.
        let lum = 0.2126 * srgb.redComponent
                + 0.7152 * srgb.greenComponent
                + 0.0722 * srgb.blueComponent
        let dark = lum < 0.5

        self.background = Color(nsColor: srgb)
        self.isDark = dark

        let accentColor: NSColor
        if s < 0.12 {
            // 무채색(흰 문서·검은 배경 등) 위에서는 색상환을 돌려봐야 의미가 없다.
            // 보색 대신 명암 대비로 간다.
            accentColor = dark ? .white : NSColor(white: 0.12, alpha: 1)
        } else {
            // 색상환 반대편 = 보색.
            let complementHue = (h + 0.5).truncatingRemainder(dividingBy: 1.0)
            // 채도는 확보하고, 명도는 배경 반대쪽 끝으로 밀어 대비를 만든다.
            // 보색이라도 명도가 비슷하면 글자가 안 읽힌다.
            accentColor = NSColor(hue: complementHue,
                                  saturation: min(1.0, max(0.75, s * 1.3)),
                                  brightness: dark ? min(1.0, max(0.88, b * 1.8)) : max(0.30, min(0.42, b * 0.5)),
                                  alpha: 1)
        }
        self.accent = Color(nsColor: accentColor)
        self.track = Color(nsColor: accentColor).opacity(0.18)
    }
}

// MARK: - Sampler
@MainActor
final class ChameleonSampler {
    static let shared = ChameleonSampler()
    private init() {}

    /// 화면 기록 권한을 받지 못한 상태인지. UI에서 안내 문구를 띄우는 데 쓴다.
    private(set) var isDenied = false

    /// 권한을 확인하고, 아직 안 물어봤으면 시스템 프롬프트를 띄운다.
    /// 한 번 거부하면 이후로는 프롬프트가 안 뜨므로 사용자가 시스템 설정에서 직접 켜야 한다.
    @discardableResult
    func ensureAuthorization() -> Bool {
        if CGPreflightScreenCaptureAccess() { isDenied = false; return true }
        let granted = CGRequestScreenCaptureAccess()
        isDenied = !granted
        return granted
    }

    /// `window` 뒤에 깔린 화면의 평균색.
    ///
    /// `excluded` 에는 **반드시 자기 자신을 포함한 카멜레온 창 전부**를 넣어야 한다.
    /// 빠뜨리면 자기가 칠한 색을 다시 읽어 칠하는 피드백 루프가 생겨 색이 발산한다.
    func averageColorBehind(_ window: NSWindow, excluding excluded: [NSWindow]) async -> NSColor? {
        guard window.isVisible,
              let screen = window.screen,
              let displayID = screen.displayID else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { return nil }

            let excludedIDs = Set(excluded.map { CGWindowID($0.windowNumber) })
            let filter = SCContentFilter(
                display: display,
                excludingWindows: content.windows.filter { excludedIDs.contains($0.windowID) }
            )

            let config = SCStreamConfiguration()
            config.sourceRect = Self.displayLocalRect(of: window.frame, on: screen)
            // 창 하나 영역만 아주 작게 뜬다. 1×1로 바로 받지 않고 조금 크게 받아
            // 우리가 평균을 내는 편이 캡처 구현에 덜 의존적이다.
            config.width = 24
            config.height = 24
            config.showsCursor = false
            config.scalesToFit = true
            config.captureResolution = .nominal

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
            isDenied = false
            return Self.averageColor(of: image)
        } catch {
            // 권한 거부도 여기로 떨어진다. 조용히 실패시키고 기존 테마로 돌아가게 둔다.
            isDenied = !CGPreflightScreenCaptureAccess()
            return nil
        }
    }

    /// AppKit 전역 좌표(좌하단 원점)의 사각형을 해당 디스플레이 기준 좌상단 원점 좌표로 변환.
    /// `SCStreamConfiguration.sourceRect` 이 그 좌표계를 쓴다.
    private static func displayLocalRect(of frame: NSRect, on screen: NSScreen) -> CGRect {
        let sf = screen.frame
        return CGRect(x: frame.minX - sf.minX,
                      y: sf.maxY - frame.maxY,     // 좌하단 원점 → 좌상단 원점
                      width: frame.width,
                      height: frame.height)
    }

    /// 이미지를 1×1로 그려 평균색을 얻는다. 픽셀을 직접 순회하지 않아도
    /// CoreGraphics가 축소하면서 평균을 내주고, 원본 픽셀 포맷에도 영향받지 않는다.
    private static func averageColor(of image: CGImage) -> NSColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &pixel,
                                  width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let alpha = CGFloat(pixel[3]) / 255
        guard alpha > 0.01 else { return nil }   // 완전 투명이면 읽을 색이 없다
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255 / alpha,
                       green:   CGFloat(pixel[1]) / 255 / alpha,
                       blue:    CGFloat(pixel[2]) / 255 / alpha,
                       alpha: 1)
    }
}

// MARK: - Window reader
/// SwiftUI 뷰가 올라가 있는 NSWindow를 알아내기 위한 최소한의 다리.
/// 샘플링하려면 창의 화면상 위치가 필요한데 SwiftUI만으로는 알 수 없다.
struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // makeNSView 시점에는 아직 창에 붙기 전이라 다음 런루프에 읽는다.
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
