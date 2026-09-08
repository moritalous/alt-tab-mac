// アプリアイコンを描画して icon/AppIcon.icns を生成するスクリプト
// 実行: swift icon/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// macOS 風の角丸（少し内側に余白を取る）
let inset: CGFloat = size * 0.06
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

// 影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
bg.fill()
ctx.restoreGState()

// 背景グラデーション（青 → 藍）
bg.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.86, alpha: 1),
])!
gradient.draw(in: rect, angle: -90)

// ウィンドウカードを描くヘルパー
func drawWindow(_ r: CGRect, alpha: CGFloat, titleBar: Bool) {
    let radius = r.width * 0.08
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -r.height * 0.03), blur: r.height * 0.08, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    ctx.restoreGState()

    if titleBar {
        // タイトルバー（薄いグレー）
        let bar = CGRect(x: r.minX, y: r.maxY - r.height * 0.18, width: r.width, height: r.height * 0.18)
        ctx.saveGState()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip()
        NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
        bar.fill()
        ctx.restoreGState()
        // 信号機ボタン
        let dot = bar.height * 0.34
        let colors: [NSColor] = [
            NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.80, blue: 0.35, alpha: 1),
        ]
        for (i, c) in colors.enumerated() {
            c.setFill()
            let x = bar.minX + bar.height * 0.45 + CGFloat(i) * dot * 1.6
            NSBezierPath(ovalIn: CGRect(x: x, y: bar.midY - dot / 2, width: dot, height: dot)).fill()
        }
    }
}

// 後ろのウィンドウ（半透明）、前のウィンドウ（不透明）
let w = rect.width * 0.50
let h = w * 0.72
drawWindow(CGRect(x: rect.midX - w * 0.62, y: rect.midY - h * 0.28, width: w, height: h), alpha: 0.55, titleBar: false)
drawWindow(CGRect(x: rect.midX - w * 0.38, y: rect.midY - h * 0.62, width: w, height: h), alpha: 1.0, titleBar: true)

// Tab 矢印 (⇥) を前面ウィンドウの本体部分に描く
let front = CGRect(x: rect.midX - w * 0.38, y: rect.midY - h * 0.62, width: w, height: h)
let body = CGRect(x: front.minX, y: front.minY, width: front.width, height: front.height * 0.82)
let arrowColor = NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.86, alpha: 1)
let lw = body.height * 0.09
let cx = body.midX, cy = body.midY
let arrowLen = body.width * 0.46
let path = NSBezierPath()
path.lineWidth = lw
path.lineCapStyle = .round
path.lineJoinStyle = .round
// 横線
path.move(to: CGPoint(x: cx - arrowLen / 2, y: cy))
path.line(to: CGPoint(x: cx + arrowLen / 2 - lw * 1.2, y: cy))
// 矢じり
let head = body.height * 0.22
path.move(to: CGPoint(x: cx + arrowLen / 2 - lw * 1.2 - head, y: cy + head))
path.line(to: CGPoint(x: cx + arrowLen / 2 - lw * 1.2, y: cy))
path.line(to: CGPoint(x: cx + arrowLen / 2 - lw * 1.2 - head, y: cy - head))
// 縦棒（Tab 記号の止め）
path.move(to: CGPoint(x: cx + arrowLen / 2 + lw * 0.3, y: cy + head * 1.05))
path.line(to: CGPoint(x: cx + arrowLen / 2 + lw * 0.3, y: cy - head * 1.05))
arrowColor.setStroke()
path.stroke()

image.unlockFocus()

// PNG 書き出し
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon/icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
