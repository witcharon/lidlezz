// Renders Resources/icon.png into an .iconset with transparent rounded corners. Usage: swift make-icon.swift <in.png> <out.iconset>
import AppKit
let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: px, height: px)
        NSBezierPath(roundedRect: rect, xRadius: Double(px) * 0.225, yRadius: Double(px) * 0.225).addClip()
        src.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
