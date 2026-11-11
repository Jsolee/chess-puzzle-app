import SwiftUI

enum Roman {
    static func numeral(_ n: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var rest = max(n, 1), out = ""
        for (value, letters) in table { while rest >= value { out += letters; rest -= value } }
        return out
    }
}

/// A lesson's seal: red wax with an uneven edge, a pressed ring and its numeral. Each numeral spills its wax its own way.
struct WaxSeal: View {
    let numeral: String
    var size: CGFloat = 60
    static let wax = Color(hex: 0x9E2A1C)
    static let shade = Color(hex: 0x6B1A10)
    static let shine = Color(hex: 0xC9563F)

    var body: some View {
        let blob = WaxBlob(seed: numeral.unicodeScalars.reduce(7) { $0 &* 31 &+ Int($1.value) })
        ZStack {
            blob.fill(Self.wax)
            blob.fill(RadialGradient(colors: [Self.shine.opacity(0.55), .clear], center: UnitPoint(x: 0.34, y: 0.3), startRadius: 0, endRadius: size * 0.55))
            blob.stroke(Self.shade.opacity(0.7), lineWidth: max(size * 0.018, 1))
            Circle().inset(by: size * 0.15).stroke(Self.shade, lineWidth: max(size * 0.03, 1.2))
            Circle().inset(by: size * 0.15).stroke(Self.shine.opacity(0.6), lineWidth: max(size * 0.012, 0.6)).offset(x: size * 0.008, y: size * 0.012)
            Text(verbatim: numeral)
                .font(Theme.text(size * (numeral.count > 3 ? 0.2 : 0.27), .semibold))
                .foregroundStyle(Self.shade)
                .shadow(color: Self.shine.opacity(0.7), radius: 0, x: size * 0.006, y: size * 0.01)
                .lineLimit(1).minimumScaleFactor(0.5).frame(width: size * 0.6)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WaxBlob: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        let lobes = 14
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        let points = (0..<lobes).map { i -> CGPoint in
            let wobble = sin(Double(seed % 997) * 0.37 + Double(i) * 2.1) * 0.5 + 0.5
            let reach = r * (0.9 + 0.1 * wobble)
            let a = Double(i) / Double(lobes) * 2 * .pi
            return CGPoint(x: c.x + reach * cos(a), y: c.y + reach * sin(a))
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var p = Path()
        p.move(to: mid(points[lobes - 1], points[0]))
        for i in 0..<lobes { p.addQuadCurve(to: mid(points[i], points[(i + 1) % lobes]), control: points[i]) }
        p.closeSubpath()
        return p
    }
}
