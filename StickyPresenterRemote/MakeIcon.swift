import AppKit
import CoreGraphics

// StickyPresenter 리모컨 앱 아이콘 생성기.
// Mac 앱 아이콘에서 그라데이션 색을 직접 뽑아 써서 두 앱이 형제로 보이게 한다.
// 모티프는 앱의 새 정체성인 "둥근 사각형 진행 표시 + 1/4 지점 점".

let macIconPath = "/Users/leeo/Documents/workspace/code/StickyPresenter/StickyPresenter/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

// MARK: Mac 아이콘에서 그라데이션 양 끝 색 샘플링

func sample(_ image: CGImage, atX xf: CGFloat, y yf: CGFloat) -> CGColor {
    let x = Int(CGFloat(image.width) * xf), y = Int(CGFloat(image.height) * yf)
    var px = [UInt8](repeating: 0, count: 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(image.height - y - 1),
                               width: CGFloat(image.width), height: CGFloat(image.height)))
    let a = max(CGFloat(px[3]) / 255, 0.0001)
    return CGColor(srgbRed: CGFloat(px[0]) / 255 / a,
                   green: CGFloat(px[1]) / 255 / a,
                   blue: CGFloat(px[2]) / 255 / a, alpha: 1)
}

guard let src = NSImage(contentsOfFile: macIconPath),
      let macIcon = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Mac 아이콘을 읽지 못했습니다: \(macIconPath)")
}

// 모서리는 둥글게 깎여 투명하므로 안쪽에서 샘플링한다.
let topColor = sample(macIcon, atX: 0.5, y: 0.12)
let bottomColor = sample(macIcon, atX: 0.5, y: 0.88)

func desc(_ c: CGColor) -> String {
    let comps = c.components ?? [0, 0, 0]
    return String(format: "#%02X%02X%02X", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
}
print("샘플링한 그라데이션: 위 \(desc(topColor)) → 아래 \(desc(bottomColor))")

// MARK: 아이콘 그리기

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// iOS 아이콘은 정사각 불투명 이미지여야 한다 — 모서리 둥글리기는 시스템이 한다.
let gradient = CGGradient(colorsSpace: space, colors: [topColor, bottomColor] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0),
                       options: [])

// 진행 표시 — 앱 안의 RoundedRectProgress 와 같은 구조.
// 좌상단 꼭짓점에서 출발해 시계방향, 절반(우하단 꼭짓점)까지 차 있는 모습.
let inset: CGFloat = S * 0.205
let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius = rect.width * 0.235
let lineWidth = S * 0.078

let left = rect.minX + radius, right = rect.maxX - radius
let bottom = rect.minY + radius, top = rect.maxY - radius
func rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
func apex(_ cx: CGFloat, _ cy: CGFloat, _ deg: CGFloat) -> CGPoint {
    CGPoint(x: cx + radius * cos(rad(deg)), y: cy + radius * sin(rad(deg)))
}

// CoreGraphics 는 y축이 위로 향하므로 각도가 줄어드는 방향이 화면상 시계방향이다.
// 트랙 — 닫힌 윤곽. 닫혀 있어야 "무엇의 일부인지"가 한눈에 읽힌다.
let track = CGMutablePath()
track.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.34))
ctx.setLineWidth(lineWidth)
ctx.addPath(track)
ctx.strokePath()

// 진행분 — 좌상단 꼭짓점(135°)에서 우하단 꼭짓점(-45°)까지 정확히 절반.
let progress = CGMutablePath()
progress.move(to: apex(left, top, 135))
progress.addArc(center: CGPoint(x: left, y: top), radius: radius,
                startAngle: rad(135), endAngle: rad(90), clockwise: true)
progress.addLine(to: CGPoint(x: right, y: rect.maxY))
progress.addArc(center: CGPoint(x: right, y: top), radius: radius,
                startAngle: rad(90), endAngle: rad(0), clockwise: true)
progress.addLine(to: CGPoint(x: rect.maxX, y: bottom))
progress.addArc(center: CGPoint(x: right, y: bottom), radius: radius,
                startAngle: rad(0), endAngle: rad(-45), clockwise: true)

ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(progress)
ctx.strokePath()

// 1/4 지점 점 — 앱에서 25% 를 지날 때 튀는 그 점. 우상단 꼭짓점에 놓는다.
// 획 위에 겹치므로 배경색 링을 한 겹 깔아 분리한다. 안 그러면 뭉쳐서 혹처럼 보인다.
let dot = apex(right, top, 45)
let dotRadius = lineWidth * 0.80
ctx.setFillColor(CGColor(srgbRed: 1, green: 0.804, blue: 0.29, alpha: 1))
ctx.fillEllipse(in: CGRect(x: dot.x - dotRadius - lineWidth * 0.20,
                           y: dot.y - dotRadius - lineWidth * 0.20,
                           width: (dotRadius + lineWidth * 0.20) * 2,
                           height: (dotRadius + lineWidth * 0.20) * 2))
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius,
                           width: dotRadius * 2, height: dotRadius * 2))

guard let image = ctx.makeImage() else { fatalError("이미지 생성 실패") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 인코딩 실패") }
try! data.write(to: URL(fileURLWithPath: outPath))
print("생성: \(outPath) (\(Int(S))×\(Int(S)))")
