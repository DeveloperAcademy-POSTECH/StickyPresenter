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
    /// 배경의 WCAG 상대휘도. `readable(_:)` 이 대비를 계산할 때 쓴다.
    let backgroundLuminance: CGFloat

    /// 편하게 읽히는 목표 명암비. 가능하면 이만큼 확보한다.
    private static let preferredContrast: CGFloat = 4.5
    /// 절대 양보하지 않는 하한. 타이머 숫자는 거대한 볼드체이고 링은 굵은 그래픽이라
    /// WCAG 기준으로 large text / non-text 에 해당하며, 그 기준이 3:1 이다.
    private static let minimumContrast: CGFloat = 3.0

    init(background bg: NSColor) {
        let srgb = bg.usingColorSpace(.sRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let bgRGB = (r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
        let bgLum = Self.relativeLuminance(bgRGB)

        self.background = Color(nsColor: srgb)
        self.isDark = bgLum < 0.18   // WCAG 상대휘도 기준 (선형화 후 값이라 임계값이 낮다)
        self.backgroundLuminance = bgLum

        let accentRGB = Self.accent(forHue: h, saturation: s, backgroundRGB: bgRGB, backgroundLum: bgLum)
        let accentColor = Color(.sRGB, red: accentRGB.r, green: accentRGB.g, blue: accentRGB.b)
        self.accent = accentColor
        self.track = accentColor.opacity(0.18)
    }

    /// 주어진 색을 이 배경 위에서 읽히도록 조정한다. **색상(hue)은 그대로 두고**
    /// 채도·명도만 바꾼다.
    ///
    /// 뽀모도로의 집중(토마토)·휴식(민트)이나 완료 빨강처럼 **의미가 붙은 색**은
    /// 보색으로 갈아치우면 뜻이 사라진다. 그렇다고 고정값을 그대로 쓰면 비슷한 색의
    /// 배경 위에서 그대로 묻힌다. 색은 알아보되 대비는 확보되게 하는 절충이다.
    func readable(_ color: NSColor) -> Color {
        let srgb = color.usingColorSpace(.sRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // 원래 색이 무채색이면 조정할 색상이 없다.
        guard s >= 0.12 else {
            return Self.rgbColor(Self.monochrome(againstLuminance: backgroundLuminance))
        }
        let rgb = Self.bestColor(hue: h, backgroundLum: backgroundLuminance)
            ?? Self.monochrome(againstLuminance: backgroundLuminance)
        return Self.rgbColor(rgb)
    }

    private static func rgbColor(_ c: RGB) -> Color {
        Color(.sRGB, red: c.r, green: c.g, blue: c.b)
    }

    /// 어떤 색으로도 기준을 못 넘길 때의 최후 수단.
    private static func monochrome(againstLuminance bgLum: CGFloat) -> RGB {
        let white: RGB = (1, 1, 1), black: RGB = (0, 0, 0)
        return contrast(bgLum, relativeLuminance(white)) >= contrast(bgLum, relativeLuminance(black))
            ? white : black
    }

    // MARK: 보색 선택
    //
    // 색상환 반대편으로 돌리기만 해서는 안 된다. 보색이라도 **명도가 비슷하면 글자가 안 읽힌다**.
    // 실제로 색 전 영역(3960개 조합)을 훑어 보니 단순 보색 방식은 45.8% 가 4.5:1 에 미달했고
    // 최악은 명암비 1.00 — 완전히 보이지 않는 조합이었다.
    //
    // 그래서 보색 색상은 유지하되 채도·명도를 훑어 **명암비 기준을 만족하는 것 중
    // 가장 선명한 색**을 고른다. 우선순위는 세 단계다.
    //   1) 확실한 유채색(채도≥0.55, 명도≥0.40) + 편안한 대비(≥4.5)   ... 전체의 약 50%
    //   2) 확실한 유채색 + 최소 대비(≥3.0)                          ... 약 19%
    //   3) 대비 우선, 색은 남는 만큼만 (짙게 물든 색이 된다)            ... 약 13%
    // 무채색 배경(약 18%)은 애초에 색상값이 무의미하므로 흑백으로 간다.
    private static func accent(forHue h: CGFloat, saturation s: CGFloat,
                               backgroundRGB bgRGB: RGB, backgroundLum bgLum: CGFloat) -> RGB {
        // 흰 문서·검은 배경처럼 채도가 없는 화면에서는 색상값이 사실상 난수다.
        // 여기서 색상환을 돌리면 배경과 무관한 임의의 색이 나오므로 명암 대비로 간다.
        guard s >= 0.12 else { return monochrome(againstLuminance: bgLum) }

        let complementHue = (h + 0.5).truncatingRemainder(dividingBy: 1.0)
        return bestColor(hue: complementHue, backgroundLum: bgLum)
            ?? monochrome(againstLuminance: bgLum)
    }

    /// 주어진 색상(hue)을 유지한 채 채도·명도를 훑어, 대비 기준을 넘는 것 중
    /// 가장 선명한 색을 고른다. 어떤 조합도 기준을 못 넘기면 nil.
    private static func bestColor(hue: CGFloat, backgroundLum bgLum: CGFloat) -> RGB? {
        let complementHue = hue

        var vividPreferred: (sat: CGFloat, bri: CGFloat, rgb: RGB, contrast: CGFloat)?
        var vividMinimum:   (sat: CGFloat, bri: CGFloat, rgb: RGB, contrast: CGFloat)?
        var anyReadable:    (sat: CGFloat, bri: CGFloat, rgb: RGB, contrast: CGFloat)?

        // 채도는 높은 쪽부터, 명도는 낮은 쪽부터 훑는다.
        // 후보가 180개뿐이라 0.9초 주기 샘플링에서는 비용이 사실상 0이다.
        for si in stride(from: 10, through: 2, by: -1) {
            let sat = CGFloat(si) / 10
            for bi in 1...20 {
                let bri = CGFloat(bi) / 20
                let rgb = hsbToRGB(complementHue, sat, bri)
                let c = contrast(bgLum, relativeLuminance(rgb))
                guard c >= minimumContrast else { continue }

                let candidate = (sat: sat, bri: bri, rgb: rgb, contrast: c)
                let isVivid = sat >= 0.55 && bri >= 0.40

                if isVivid && c >= preferredContrast {
                    if isBetter(candidate, than: vividPreferred) { vividPreferred = candidate }
                } else if isVivid {
                    if isBetter(candidate, than: vividMinimum) { vividMinimum = candidate }
                }
                if isBetter(candidate, than: anyReadable) { anyReadable = candidate }
            }
        }

        return (vividPreferred ?? vividMinimum ?? anyReadable)?.rgb
    }

    /// 더 선명한 쪽(채도 → 명도 순)을 우선하고, 같으면 목표 대비에 가까운 쪽을 고른다.
    private static func isBetter(_ lhs: (sat: CGFloat, bri: CGFloat, rgb: RGB, contrast: CGFloat),
                                 than rhs: (sat: CGFloat, bri: CGFloat, rgb: RGB, contrast: CGFloat)?) -> Bool {
        guard let rhs else { return true }
        if lhs.sat != rhs.sat { return lhs.sat > rhs.sat }
        if lhs.bri != rhs.bri { return lhs.bri > rhs.bri }
        return abs(lhs.contrast - preferredContrast) < abs(rhs.contrast - preferredContrast)
    }

    // MARK: 색 계산 도우미
    typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

    /// WCAG 상대휘도. 감마를 풀어(선형화) 계산해야 실제 눈에 보이는 대비와 맞는다.
    /// sRGB 원시값을 그대로 가중합하면 어두운 색의 밝기를 과대평가한다.
    private static func relativeLuminance(_ c: RGB) -> CGFloat {
        func linear(_ v: CGFloat) -> CGFloat {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private static func contrast(_ lum1: CGFloat, _ lum2: CGFloat) -> CGFloat {
        let hi = max(lum1, lum2), lo = min(lum1, lum2)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// NSColor(hue:...) 는 색 공간이 sRGB 라는 보장이 없어 직접 변환한다.
    private static func hsbToRGB(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat) -> RGB {
        guard s > 0 else { return (v, v, v) }
        let sector = (h - floor(h)) * 6
        let i = floor(sector)
        let f = sector - i
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch Int(i) % 6 {
        case 0:  return (v, t, p)
        case 1:  return (q, v, p)
        case 2:  return (p, v, t)
        case 3:  return (p, q, v)
        case 4:  return (t, p, v)
        default: return (v, p, q)
        }
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
    func ensureAuthorization() async -> Bool {
        if CGPreflightScreenCaptureAccess() { isDenied = false; return true }
        // CGRequestScreenCaptureAccess() 는 동기 호출이라 메인 스레드에서 부르면
        // 권한 시트가 떠 있는 동안 UI 전체가 멈춘다. 백그라운드로 넘긴다.
        let granted = await Task.detached { CGRequestScreenCaptureAccess() }.value
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
