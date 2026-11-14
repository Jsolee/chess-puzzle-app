import SwiftUI

// The pieces every screen is built from: the lamplit field, the gold wire, the tin cartouche and the wire controls.

/// The verd field under a lamp: light falls from the top, the bottom goes deep, and a fine grain keeps it from looking printed.
struct FieldBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Theme.field, location: 0.48), .init(color: Theme.fieldLow, location: 1)], startPoint: .top, endPoint: .bottom)
            // An ellipse of light from the top centre, wider than the screen, gone by a third of the way down.
            Canvas { ctx, size in
                let ry = size.height * 0.37, rx = size.width * 0.925
                ctx.translateBy(x: size.width / 2, y: 0)
                ctx.scaleBy(x: rx / ry, y: 1)
                ctx.fill(Path(CGRect(x: -ry, y: 0, width: ry * 2, height: ry)),
                         with: .radialGradient(Gradient(colors: [Theme.lamp.opacity(0.62), Theme.lamp.opacity(0)]), center: .zero, startRadius: 0, endRadius: ry))
            }
            Image(uiImage: Self.grain).resizable(resizingMode: .tile).opacity(0.09)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// White specks with random alpha, at screen scale so the tile reads as grain, not as a pattern.
    static let grain: UIImage = {
        let side = 96
        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = UInt8(max(0, Int(rng.next() % 256) - 70) * 255 / 185)
            bytes[i] = a; bytes[i + 1] = a; bytes[i + 2] = a; bytes[i + 3] = a
        }
        let ctx = CGContext(data: &bytes, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = ctx?.makeImage() else { return UIImage() }
        return UIImage(cgImage: image, scale: 3, orientation: .up)
    }()
}

extension View {
    func fieldBackground() -> some View { background(FieldBackground().ignoresSafeArea()) }
}

/// A gold wire with a lozenge at its head, under screen titles and section titles.
struct GoldRule: View {
    var section = false
    var centered = false

    var body: some View {
        HStack(spacing: 5) {
            if centered { wire(fadingIn: true) }
            Rectangle().fill(Theme.gold).frame(width: 5, height: 5).rotationEffect(.degrees(45)).frame(width: 8, height: 8)
            wire(fadingIn: false).frame(maxWidth: centered ? .infinity : section ? 210 : 290, alignment: .leading)
        }
        .frame(height: 9)
        .opacity(section ? 0.7 : 1)
        .accessibilityHidden(true)
    }

    private func wire(fadingIn: Bool) -> some View {
        LinearGradient(colors: fadingIn ? [Theme.gold.opacity(0), Theme.gold] : [Theme.gold, Theme.gold.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
    }
}

/// A screen's name, in blackletter with its wire.
struct ScreenTitle: View {
    let text: Text
    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            text.font(Theme.display(52)).foregroundStyle(Theme.tin).accessibilityAddTraits(.isHeader)
            GoldRule()
        }
    }
}

/// A section's name, with an optional count on the right, and a shorter wire.
struct SectionTitle: View {
    let text: Text
    var detail: Text?
    var size: CGFloat = 30
    init(_ key: LocalizedStringKey, detail: Text? = nil, size: CGFloat = 30) { text = Text(key); self.detail = detail; self.size = size }
    init(verbatim: String, detail: Text? = nil, size: CGFloat = 30) { text = Text(verbatim: verbatim); self.detail = detail; self.size = size }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                text.font(Theme.display(size)).foregroundStyle(Theme.tin).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                detail?.font(Theme.text(15)).foregroundStyle(Theme.quiet)
            }
            GoldRule(section: true)
        }
    }
}

/// Small gold capitals above a board's title: where you are and what it's about.
struct Rubric: View {
    let text: Text
    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }
    var body: some View {
        text.font(Theme.text(12.5, .semibold)).tracking(1.75).textCase(.uppercase).foregroundStyle(Theme.gold).lineLimit(1)
    }
}

/// The block above a board: rubric, a blackletter title that changes with the moment, and one quiet line.
struct BoardHeader<Trailing: View>: View {
    var rubric: Text?
    let title: Text
    var subtitle: Text?
    var warn = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rubric { rubric.font(Theme.text(12.5, .semibold)).tracking(1.75).textCase(.uppercase).foregroundStyle(Theme.gold).lineLimit(1) }
            HStack(alignment: .firstTextBaseline) {
                title.font(Theme.display(40)).foregroundStyle(Theme.tin).lineLimit(1).minimumScaleFactor(0.6).contentTransition(.opacity)
                Spacer(minLength: 8)
                trailing
            }
            if let subtitle {
                subtitle.font(Theme.text(16)).foregroundStyle(warn ? Theme.warn : Theme.quiet).contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension BoardHeader where Trailing == EmptyView {
    init(rubric: Text? = nil, title: Text, subtitle: Text? = nil, warn: Bool = false) {
        self.init(rubric: rubric, title: title, subtitle: subtitle, warn: warn) { EmptyView() }
    }
}

/// A tin plate with its corners cut in, like a cartouche, and a bronze wire inside the edge.
struct Cartouche: InsettableShape {
    var radius: CGFloat = 10
    var inset: CGFloat = 0
    func inset(by amount: CGFloat) -> Cartouche { Cartouche(radius: radius, inset: inset + amount) }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset), k = min(radius, r.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + k, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - k, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX, y: r.minY), radius: k, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - k))
        p.addArc(center: CGPoint(x: r.maxX, y: r.maxY), radius: k, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: r.minX + k, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX, y: r.maxY), radius: k, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + k))
        p.addArc(center: CGPoint(x: r.minX, y: r.minY), radius: k, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// The screen's one primary action. Gold only for the answer that was right.
struct CartoucheButtonStyle: ButtonStyle {
    var gold = false
    /// Sized to its label, for a toolbar row.
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.text(compact ? 16 : 18, .semibold)).foregroundStyle(Theme.ink)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 40 : 52)
            .background {
                ZStack {
                    Cartouche().fill(gold ? Theme.gold : Theme.tin)
                    Cartouche(inset: 4).stroke(Theme.copper, lineWidth: 1)
                }
                .shadow(color: Theme.shadow.opacity(0.35), radius: 4, y: 2)
            }
            .contentShape(Cartouche())
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CartoucheButtonStyle {
    static var cartouche: CartoucheButtonStyle { CartoucheButtonStyle() }
    static func cartouche(gold: Bool) -> CartoucheButtonStyle { CartoucheButtonStyle(gold: gold) }
}

/// A switch drawn in wire: a hollow bead when off, a tin bead in a gold track when on.
struct WireToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Theme.gold.opacity(0.2) : Theme.fieldDeep)
                    Capsule().strokeBorder(configuration.isOn ? Theme.gold : Theme.tin.opacity(0.4), lineWidth: 1.25)
                    Group {
                        if configuration.isOn {
                            Circle().fill(Theme.tin).overlay(Circle().strokeBorder(Theme.copper, lineWidth: 1.5))
                        } else {
                            Circle().strokeBorder(Theme.tin.opacity(0.55), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 18, height: 18).padding(.horizontal, 5)
                }
                .frame(width: 50, height: 28)
                .animation(.easeOut(duration: 0.2), value: configuration.isOn)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A row of section names; the chosen one in tin with a gold wire and a lozenge under it.
struct SectionPicker<Value: Hashable>: View {
    let items: [(LocalizedStringKey, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 24) {
            ForEach(items.indices, id: \.self) { i in
                let (title, value) = items[i], on = value == selection
                Button { withAnimation(.easeOut(duration: 0.2)) { selection = value } } label: {
                    Text(title).font(Theme.text(17, on ? .semibold : .medium)).foregroundStyle(on ? Theme.tin : Theme.quiet)
                        .overlay(alignment: .bottom) {
                            if on {
                                ZStack {
                                    Rectangle().fill(Theme.gold).frame(height: 1)
                                    Rectangle().fill(Theme.gold).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                                }
                                .offset(y: 9).transition(.opacity)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// How far through a lesson: beads on a wire, gold where you've been, a ringed bead where you are.
struct BeadProgress: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                if i > 0 { Spacer(minLength: 2) }
                bead(i)
            }
        }
        .frame(height: 22)
        .background(Rectangle().fill(Theme.gold.opacity(0.45)).frame(height: 1).padding(.horizontal, 4))
        .animation(.easeOut(duration: 0.25), value: current)
        .accessibilityElement().accessibilityLabel("Progrés")
        .accessibilityValue(Text("\(min(current, count)) de \(count)"))
    }

    @ViewBuilder private func bead(_ i: Int) -> some View {
        if i < current {
            Circle().fill(Theme.gold).frame(width: 9, height: 9)
        } else if i == current {
            Circle().fill(Theme.field).frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1.5))
                .overlay(Circle().fill(Theme.gold).frame(width: 7, height: 7))
        } else {
            Circle().fill(Theme.field).frame(width: 9, height: 9).overlay(Circle().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1.25))
        }
    }
}

/// A row's mark: its icon in gold inside a ringed disc.
struct Medallion: View {
    let image: Image
    var body: some View {
        image.renderingMode(.template).resizable().scaledToFit().frame(width: 19, height: 19).foregroundStyle(Theme.gold)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Theme.fieldLift))
            .overlay(Circle().strokeBorder(Theme.gold.opacity(0.75), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The way out of a full-screen page, the same everywhere.
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Tanca")
    }
}
