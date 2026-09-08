import AppKit
import SwiftUI

/// The "zz." mark, shipped in Resources/.
enum Brand {
    static let icon = NSImage(contentsOf: resource("icon"))!

    /// Inside Lidlezz.app the resource bundle sits in Contents/Resources; under `swift run` Bundle.module finds it.
    private static func resource(_ name: String) -> URL {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("lidlezz_LidlezzApp.bundle/Resources/\(name).png"),
           FileManager.default.fileExists(atPath: url.path) { return url }
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources")!
    }

    /// The mark as a menu bar template image: black ink becomes alpha, so it follows the bar's colour.
    static let menuBar: NSImage = {
        let ci = CIImage(cgImage: icon.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIMaskToAlpha")
        let rep = NSCIImageRep(ciImage: ci)
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let inset = rep.size.width * 0.16
        rep.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18),
                 from: NSRect(x: inset, y: inset, width: rep.size.width - 2 * inset, height: rep.size.height - 2 * inset),
                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
