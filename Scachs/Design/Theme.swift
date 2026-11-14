import SwiftUI

enum Theme {
    static let field = Color(hex: 0x0F3A33)
    static let fieldDeep = Color(hex: 0x0B2C27)
    static let fieldLift = Color(hex: 0x154B41)
    /// Where the field ends under the lamp, and the lamp's own green.
    static let fieldLow = Color(hex: 0x092722)
    static let lamp = Color(hex: 0x2E8470)
    static let shadow = Color(hex: 0x030E0C)
    static let warn = Color(hex: 0xEF7D6C)
    static let tileDark = Color(hex: 0x2C6F5E)
    static let tileLight = Color(hex: 0xECE6D6)
    static let tin = Color(hex: 0xF6F1E6)
    static let ink = Color(hex: 0x16121C)
    static let gold = Color(hex: 0xE7B96C)
    static let copper = Color(hex: 0xB5823F)
    static let quiet = Color(hex: 0xF6F1E6).opacity(0.68)
    static let hairline = Color(hex: 0xF6F1E6).opacity(0.14)

    /// Grenze Gotisch. Display only: 28 pt and up, never notation.
    static func display(_ size: CGFloat) -> Font { .custom("GrenzeGotisch-Medium", fixedSize: size) }
    /// Ysabeau Office, tabular digits by default.
    static func text(_ size: CGFloat, _ weight: TextWeight = .regular) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: size >= 22 ? .title3 : size >= 16 ? .body : .footnote)
    }
    enum TextWeight: String {
        case regular = "YsabeauOffice-Regular", medium = "YsabeauOffice-Medium", semibold = "YsabeauOffice-SemiBold"
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
