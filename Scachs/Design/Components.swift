import SwiftUI

// The pieces every screen is built from: the flat field, compact bars with a gold wire, flat panels, the gold plaque and the framed board.

/// The flat ground under every screen.
struct FieldBackground: View {
    var body: some View { Theme.field.allowsHitTesting(false).accessibilityHidden(true) }
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

/// A screen's bar: the name in engraved capitals between its two buttons, on the dark bar, with the gold wire and its lozenge underneath.
struct TopBar<Leading: View, Trailing: View>: View {
    let title: Text
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            title.font(Theme.title(19)).foregroundStyle(Theme.tin).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 52).accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) { leading; Spacer(minLength: 0); trailing }.padding(.horizontal, 4)
        }
        .frame(height: 46).frame(maxWidth: .infinity)
        .background(Theme.fieldDeep.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { BarRule().offset(y: 4.5) }
        .zIndex(1)
    }
}

extension TopBar where Leading == EmptyView, Trailing == EmptyView {
    init(title: Text) { self.init(title: title) { EmptyView() } trailing: { EmptyView() } }
}

/// The wire under a bar, with a lozenge at its centre.
struct BarRule: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.rule).frame(height: 1)
            Rectangle().fill(Theme.gold).frame(width: 6, height: 6).rotationEffect(.degrees(45))
        }
        .frame(height: 9).accessibilityHidden(true)
    }
}

/// A bar's button: an icon in a 44 pt square.
struct BarButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}

extension View {
    /// Pins a TopBar above the content and hides the system bar.
    func topBar<L: View, T: View>(_ title: Text, @ViewBuilder leading: () -> L, @ViewBuilder trailing: () -> T) -> some View {
        let bar = TopBar(title: title, leading: leading, trailing: trailing)
        return safeAreaInset(edge: .top, spacing: 0) { bar }.toolbar(.hidden, for: .navigationBar)
    }
    func topBar(_ title: Text) -> some View { topBar(title, leading: { EmptyView() }, trailing: { EmptyView() }) }
}

/// A section's name between two fading wires, each side marked with a lozenge, and an optional count after it.
struct SectionTitle: View {
    let text: Text
    var detail: Text?
    init(_ key: LocalizedStringKey, detail: Text? = nil, size: CGFloat = 0) { text = Text(key); self.detail = detail }
    init(verbatim: String, detail: Text? = nil, size: CGFloat = 0) { text = Text(verbatim: verbatim); self.detail = detail }

    var body: some View {
        HStack(spacing: 8) {
            wire(LinearGradient(colors: [Theme.rule.opacity(0), Theme.rule], startPoint: .leading, endPoint: .trailing))
            lozenge
            HStack(spacing: 0) {
                text.accessibilityAddTraits(.isHeader)
                if let detail { Text(verbatim: " · ") + detail }
            }
            .font(Theme.title(15)).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.8).layoutPriority(1)
            lozenge
            wire(LinearGradient(colors: [Theme.rule, Theme.rule.opacity(0)], startPoint: .leading, endPoint: .trailing))
        }
        .frame(minHeight: 22)
    }

    private var lozenge: some View { Rectangle().fill(Theme.gold).frame(width: 5, height: 5).rotationEffect(.degrees(45)).accessibilityHidden(true) }
    private func wire(_ g: LinearGradient) -> some View { g.frame(height: 1).frame(maxWidth: .infinity).accessibilityHidden(true) }
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

/// The block above a board: rubric, an engraved title that changes with the moment, and one quiet line.
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
                title.font(Theme.title(20)).foregroundStyle(Theme.tin).lineLimit(1).minimumScaleFactor(0.7).contentTransition(.opacity)
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

/// A plate with its corners bevelled.
struct Plaque: InsettableShape {
    var cut: CGFloat = 7
    var inset: CGFloat = 0
    func inset(by amount: CGFloat) -> Plaque { Plaque(cut: cut, inset: inset + amount) }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset), k = min(cut, r.width / 2, r.height / 2)
        return Path { p in
            p.addLines([CGPoint(x: r.minX + k, y: r.minY), CGPoint(x: r.maxX - k, y: r.minY), CGPoint(x: r.maxX, y: r.minY + k),
                        CGPoint(x: r.maxX, y: r.maxY - k), CGPoint(x: r.maxX - k, y: r.maxY), CGPoint(x: r.minX + k, y: r.maxY),
                        CGPoint(x: r.minX, y: r.maxY - k), CGPoint(x: r.minX, y: r.minY + k)])
            p.closeSubpath()
        }
    }
}

/// A screen's one primary action: a flat gold plaque on a darker edge that it sinks into when pressed. Secondary actions use the dark plate.
struct PlaqueButtonStyle: ButtonStyle {
    var secondary = false
    /// Sized to its label, for a tool row.
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        let face = !enabled ? Theme.panel : secondary ? Theme.fieldLift : Theme.gold
        let edge = !enabled || secondary ? Theme.shadow : Theme.goldLip
        return configuration.label
            .font(Theme.text(compact ? 16 : 18, .semibold))
            .foregroundStyle(!enabled ? Theme.muted : secondary ? Theme.tin : Theme.ink)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, compact ? 18 : 22)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 42 : 50)
            .background {
                ZStack {
                    Plaque(cut: compact ? 6 : 7).fill(edge).offset(y: pressed ? 1.5 : 4)
                    Plaque(cut: compact ? 6 : 7).fill(face)
                }
            }
            .contentShape(Plaque())
            .offset(y: pressed ? 2.5 : 0)
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension ButtonStyle where Self == PlaqueButtonStyle {
    static var plaque: PlaqueButtonStyle { PlaqueButtonStyle() }
    static func plaque(secondary: Bool = false, compact: Bool = false) -> PlaqueButtonStyle { PlaqueButtonStyle(secondary: secondary, compact: compact) }
}

/// A tool under the board: its icon over a short label.
struct ToolButtonStyle: ButtonStyle {
    var on = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ToolLabelStyle(on: on))
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .frame(minWidth: 50, minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct ToolLabelStyle: LabelStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon.font(.system(size: 19, weight: .semibold)).foregroundStyle(on ? Theme.gold : Theme.tin).frame(height: 22)
            configuration.title.font(Theme.text(11, .semibold)).foregroundStyle(on ? Theme.tin : Theme.muted).lineLimit(1)
        }
    }
}

extension ButtonStyle where Self == ToolButtonStyle {
    static var tool: ToolButtonStyle { ToolButtonStyle() }
    static func tool(on: Bool) -> ToolButtonStyle { ToolButtonStyle(on: on) }
}

/// The row of tools under a board, on the dark bar, with the primary action on the right.
struct Dock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 4) { content }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.fieldDeep.ignoresSafeArea(edges: .bottom))
    }
}

extension View {
    /// A flat panel: solid fill, 6 pt corners and a faint gold wire round the edge.
    func panel(_ fill: Color = Theme.panel, padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.gold.opacity(0.13), lineWidth: 1))
    }

    /// The board's frame: a dark bezel, a gold wire just outside the squares and a lozenge at each corner.
    func boardFrame() -> some View {
        self.padding(6)
            .background(Theme.shadow.opacity(0.55))
            .overlay {
                GeometryReader { g in
                    let r = CGRect(origin: .zero, size: g.size).insetBy(dx: 3, dy: 3)
                    Rectangle().strokeBorder(Theme.gold.opacity(0.55), lineWidth: 1).frame(width: r.width, height: r.height).position(x: g.size.width / 2, y: g.size.height / 2)
                    ForEach(0..<4, id: \.self) { i in
                        Rectangle().fill(Theme.gold).frame(width: 6, height: 6).rotationEffect(.degrees(45))
                            .position(x: i % 2 == 0 ? r.minX : r.maxX, y: i < 2 ? r.minY : r.maxY)
                    }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
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

/// A segmented row of section names on a panel; the chosen one on a raised chip.
struct SectionPicker<Value: Hashable>: View {
    let items: [(LocalizedStringKey, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let (title, value) = items[i], on = value == selection
                Button { withAnimation(.easeOut(duration: 0.2)) { selection = value } } label: {
                    Text(title).font(Theme.text(14.5, .semibold)).foregroundStyle(on ? Theme.tin : Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6).fill(Theme.panelHigh)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.rule, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
        .frame(minHeight: 44)
    }
}

/// How far through a lesson or a set: a gold bar on a raised track.
struct BeadProgress: View {
    let count: Int
    let current: Int

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panelHigh)
                Capsule().fill(Theme.gold).frame(width: g.size.width * min(1, CGFloat(current) / CGFloat(max(count, 1))))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.25), value: current)
        .accessibilityElement().accessibilityLabel("Progrés")
        .accessibilityValue(Text("\(min(current, count)) de \(count)"))
    }
}

/// A row's mark: its icon in colour on a square tinted with the same colour.
struct Medallion: View {
    let image: Image
    var color = Theme.gold
    var body: some View {
        image.renderingMode(.template).resizable().scaledToFit().frame(width: 22, height: 22).foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.18)))
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
