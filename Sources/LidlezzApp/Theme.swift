import SwiftUI

enum Theme {
    static let green = Color(red: 0x30 / 255, green: 0xd1 / 255, blue: 0x58 / 255)
    static let orange = Color(red: 1, green: 0x9f / 255, blue: 0x0a / 255)
    static let red = Color(red: 1, green: 0x45 / 255, blue: 0x3a / 255)
    static let card = Color.primary.opacity(0.06)
    static let mono = Font.system(size: 12, design: .monospaced)

    static func temperature(_ c: Double) -> Color {
        c >= 95 ? red : c >= 85 ? orange : green
    }
}

struct IconTile: View {
    var size: CGFloat = 30
    var body: some View {
        Image(nsImage: Brand.icon).resizable().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(Color.primary.opacity(0.1)))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11)).kerning(0.4).foregroundStyle(.secondary)
    }
}
