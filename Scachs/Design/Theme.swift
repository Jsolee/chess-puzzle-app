import SwiftUI

enum Theme {
    /// The ground every screen sits on, bars included: green-black ink.
    static let field = Color(hex: 0x0D1311)
    static let fieldDeep = Color(hex: 0x0D1311)
    /// Boxes, then the raised level inside them (selected chips, tracks).
    static let panel = Color(hex: 0x141C19)
    static let fieldLift = Color(hex: 0x1B2622)
    static let panelHigh = Color(hex: 0x26322D)
    static let shadow = Color(hex: 0x030E0C)
    static let warn = Color(hex: 0xEF7D6C)
    static let good = Color(hex: 0x6DBE7E)
    static let goodPanel = Color(hex: 0x16291F)
    static let tileDark = Color(hex: 0x2C6F5E)
    static let tileLight = Color(hex: 0xECE6D6)
    static let tin = Color(hex: 0xF1ECE0)
    static let ink = Color(hex: 0x16121C)
    static let gold = Color(hex: 0xE7B96C)
    /// Text on gold.
    static let onGold = Color(hex: 0x1A1307)
    /// Gold under a finger.
    static let goldLip = Color(hex: 0xC99B52)
    static let copper = Color(hex: 0xB5823F)
    static let quiet = Color(hex: 0xF1ECE0).opacity(0.7)
    static let muted = Color(hex: 0x8FA39C)
    /// The ruling of the page: every box, bar and separator.
    static let hairline = Color(hex: 0x26322D)
    static let rule = Color(hex: 0x26322D)

    /// Grenze Gotisch Black: textura for headlines and the big moments. 18 pt and up, never numbers or notation.
    static func title(_ size: CGFloat) -> Font {
        .custom("GrenzeGotisch-Black", size: size, relativeTo: size >= 28 ? .largeTitle : size >= 20 ? .title2 : .headline)
    }
    /// Marcellus SC: the rubric labels, set in spaced capitals. Pair with `.tracking(label: size)`.
    static func label(_ size: CGFloat = 11) -> Font {
        .custom("MarcellusSC-Regular", size: size, relativeTo: .caption)
    }
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
