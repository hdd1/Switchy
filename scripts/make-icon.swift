// Рисует иконку Switchy и собирает Support/AppIcon.icns (+ Support/AppIcon.png 1024×1024 для README).
//
// Запуск из корня проекта:  swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon() {
    // Подложка по сетке иконок macOS: 824×824 в центре холста 1024, скругление ~185.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 28
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.set()
    color(0x4F46E5).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0x6D28D9), color(0x4F46E5), color(0x0EA5E9)])!.draw(in: shape, angle: -55)
    // Мягкий блик сверху.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: shape, angle: -90)

    // Круговые стрелки «переключить».
    let center = NSPoint(x: 512, y: 512)
    let radius: CGFloat = 285
    let white = color(0xF1F3FF) // непрозрачный: полупрозрачный даёт пятно на стыке дуги и наконечника
    white.setStroke()
    white.setFill()

    func arrow(from start: CGFloat, to end: CGFloat) {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        arc.lineWidth = 34
        arc.lineCapStyle = .round
        arc.stroke()

        // Наконечник: по касательной к движению по часовой стрелке.
        let t = end * .pi / 180
        let tip = NSPoint(x: center.x + radius * cos(t), y: center.y + radius * sin(t))
        let dir = NSPoint(x: sin(t), y: -cos(t))
        let normal = NSPoint(x: -dir.y, y: dir.x)
        let head = NSBezierPath()
        head.move(to: NSPoint(x: tip.x + dir.x * 46, y: tip.y + dir.y * 46))
        head.line(to: NSPoint(x: tip.x - dir.x * 14 + normal.x * 44, y: tip.y - dir.y * 14 + normal.y * 44))
        head.line(to: NSPoint(x: tip.x - dir.x * 14 - normal.x * 44, y: tip.y - dir.y * 14 - normal.y * 44))
        head.close()
        head.fill()
    }
    arrow(from: 158, to: 28)   // сверху, слева направо
    arrow(from: 338, to: 208)  // снизу, справа налево

    // Буквы: латинская A и кириллическая Я.
    let base = NSFont.systemFont(ofSize: 250, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 250) } ?? base
    func letter(_ text: String, centerX: CGFloat, alpha: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        string.draw(at: NSPoint(x: centerX - size.width / 2, y: 512 - size.height / 2 + 8))
    }
    letter("A", centerX: 418, alpha: 1)
    letter("Я", centerX: 610, alpha: 0.82)
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas) // рисуем в координатах 1024, масштабируется в pixels
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let support = root.appendingPathComponent("Support")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Switchy.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try writePNG(render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(render(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try writePNG(render(pixels: 1024), to: support.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", support.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Готово: Support/AppIcon.icns, Support/AppIcon.png" : "iconutil завершился с ошибкой")
