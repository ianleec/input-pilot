import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let background = NSBezierPath(roundedRect: NSRect(x: 34, y: 34, width: 956, height: 956), xRadius: 218, yRadius: 218)
        NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.84, alpha: 1), ending: NSColor(calibratedRed: 0.04, green: 0.65, blue: 0.68, alpha: 1))!.draw(in: background, angle: 45)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        ("IP" as NSString).draw(in: NSRect(x: 60, y: 360, width: 904, height: 380), withAttributes: [.font: NSFont.systemFont(ofSize: 360, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        ("⇄" as NSString).draw(in: NSRect(x: 60, y: 160, width: 904, height: 270), withAttributes: [.font: NSFont.systemFont(ofSize: 228, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .paragraphStyle: paragraph])
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
