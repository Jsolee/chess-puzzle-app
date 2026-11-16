import SwiftUI

enum Theme {
    /// The flat ground every screen sits on.
    static let field = Color(hex: 0x13201D)
    /// Bars: top, tab and tool rows.
    static let fieldDeep = Color(hex: 0x0E1816)
    /// Panels, rows and cards, then the raised level inside them (selected chips, tracks).
    static let panel = Color(hex: 0x1B2A27)
    static let fieldLift = Color(hex: 0x24372F)
    static let panelHigh = Color(hex: 0x2F463F)
    static let shadow = Color(hex: 0x030E0C)
    static let warn = Color(hex: 0xEF7D6C)
    static let good = Color(hex: 0x6DBE7E)
    static let goodPanel = Color(hex: 0x1E3A2C)
    static let tileDark = Color(hex: 0x2C6F5E)
    static let tileLight = Color(hex: 0xECE6D6)
    static let tin = Color(hex: 0xF6F1E6)
    static let ink = Color(hex: 0x16121C)
    static let gold = Color(hex: 0xE7B96C)
    /// The darker edge under a gold plate.
    static let goldLip = Color(hex: 0xA47A36)
    static let copper = Color(hex: 0xB5823F)
    static let quiet = Color(hex: 0xF6F1E6).opacity(0.68)
    static let muted = Color(hex: 0x97A9A3)
    static let hairline = Color(hex: 0xF6F1E6).opacity(0.1)
    /// Gold wire at rest: under bars, around panels and the board.
    static let rule = Color(hex: 0xE7B96C).opacity(0.4)

    /// Marcellus SC, engraved capitals for screen, card and section titles. Never numbers or notation.
    static func title(_ size: CGFloat) -> Font {
        .custom("MarcellusSC-Regular", size: size, relativeTo: size >= 22 ? .title2 : size >= 17 ? .headline : .subheadline)
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
