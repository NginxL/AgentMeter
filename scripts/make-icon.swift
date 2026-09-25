import AppKit

// Original artwork, generated locally with system frameworks and no source assets.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make-icon.swift <output.iconset>\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876),
                            xRadius: 204, yRadius: 204)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(calibratedRed: 0.04, green: 0.12, blue: 0.18, alpha: 1).setFill()
    tile.fill()
    NSShadow().set()
    NSGradient(starting: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.27, alpha: 1),
               ending: NSColor(calibratedRed: 0.025, green: 0.075, blue: 0.14, alpha: 1))!
        .draw(in: tile, angle: -70)

    let columns: [(x: CGFloat, height: CGFloat, fill: CGFloat)] = [
        (252, 300, 182), (448, 434, 314), (644, 568, 446)
    ]
    for column in columns {
        let track = NSBezierPath(roundedRect: NSRect(x: column.x, y: 230, width: 128, height: column.height),
                                 xRadius: 64, yRadius: 64)
        NSColor(calibratedRed: 0.38, green: 0.71, blue: 0.71, alpha: 0.19).setFill()
        track.fill()
        let meter = NSBezierPath(roundedRect: NSRect(x: column.x, y: 230, width: 128, height: column.fill),
                                 xRadius: 64, yRadius: 64)
        NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.81, blue: 0.72, alpha: 1),
                   ending: NSColor(calibratedRed: 0.70, green: 0.98, blue: 0.86, alpha: 1))!
            .draw(in: meter, angle: 90)
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
