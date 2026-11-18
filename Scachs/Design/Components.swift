import SwiftUI

// The pieces every screen is built from, in the grammar of a ruled page: ink ground, hairline boxes with square corners, one gold,
// textura for headlines, spaced rubric capitals with a pilcrow for labels, and the manicule for what leads somewhere.

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

/// A label in the manner of a rubric: a gold pilcrow, then spaced capitals.
struct RubricLabel: View {
    let text: Text
    var color = Theme.muted
    var size: CGFloat = 11
    init(_ key: LocalizedStringKey, color: Color = Theme.muted, size: CGFloat = 11) { text = Text(key); self.color = color; self.size = size }
    init(verbatim: String, color: Color = Theme.muted, size: CGFloat = 11) { text = Text(verbatim: verbatim); self.color = color; self.size = size }
    init(text: Text, color: Color = Theme.muted, size: CGFloat = 11) { self.text = text; self.color = color; self.size = size }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "¶").foregroundStyle(Theme.gold).accessibilityHidden(true)
            text.foregroundStyle(color).textCase(.uppercase).tracking(size * 0.2)
        }
        .font(Theme.label(size)).lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// The pointing hand from the margins: what leads somewhere.
struct Manicule: View {
    var color = Theme.gold
    var body: some View { Text(verbatim: "\u{261E}\u{FE0E}").font(.system(size: 19)).foregroundStyle(color).accessibilityHidden(true) }
}

/// A headline in textura with its first letter in gold, as a rubricated initial.
struct BigTitle: View {
    let text: String
    var size: CGFloat = 46
    init(_ resource: LocalizedStringResource, size: CGFloat = 46) { text = String(localized: resource); self.size = size }
    init(verbatim: String, size: CGFloat = 46) { text = verbatim; self.size = size }

    var body: some View {
        (Text(verbatim: String(text.prefix(1))).foregroundColor(Theme.gold) + Text(verbatim: String(text.dropFirst())).foregroundColor(Theme.tin))
            .font(Theme.title(size)).lineLimit(1).minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore).accessibilityLabel(Text(verbatim: text)).accessibilityAddTraits(.isHeader)
    }
}

/// A screen's bar: its buttons, the name as a rubric in the middle, a hairline under it. With a headline, the name is set big in textura instead.
struct TopBar<Leading: View, Trailing: View>: View {
    let title: Text
    var headline: LocalizedStringResource?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if headline == nil {
                    RubricLabel(text: title, color: Theme.tin, size: 12).padding(.horizontal, 52).accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 0) { leading; Spacer(minLength: 0); trailing }.padding(.horizontal, 4)
            }
            .frame(height: 44).frame(maxWidth: .infinity)
            if let headline { BigTitle(headline).padding(.horizontal, 16).padding(.top, -6).padding(.bottom, 8) }
        }
        .background(Theme.field.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { BarRule() }
        .zIndex(1)
    }
}

extension TopBar where Leading == EmptyView, Trailing == EmptyView {
    init(title: Text) { self.init(title: title) { EmptyView() } trailing: { EmptyView() } }
}

/// The hairline under a bar.
struct BarRule: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1).accessibilityHidden(true) }
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

    /// Like `topBar`, with the screen's name set big in textura under the buttons.
    func headlineBar<L: View, T: View>(_ headline: LocalizedStringResource, @ViewBuilder leading: () -> L, @ViewBuilder trailing: () -> T) -> some View {
        let bar = TopBar(title: Text(headline), headline: headline, leading: leading, trailing: trailing)
        return safeAreaInset(edge: .top, spacing: 0) { bar }.toolbar(.hidden, for: .navigationBar)
    }
    func headlineBar(_ headline: LocalizedStringResource) -> some View { headlineBar(headline, leading: { EmptyView() }, trailing: { EmptyView() }) }
}

/// A section's name as a rubric, with an optional count on the right.
struct SectionTitle: View {
    let text: Text
    var detail: Text?
    init(_ key: LocalizedStringKey, detail: Text? = nil, size: CGFloat = 0) { text = Text(key); self.detail = detail }
    init(verbatim: String, detail: Text? = nil, size: CGFloat = 0) { text = Text(verbatim: verbatim); self.detail = detail }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            RubricLabel(text: text).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail { detail.font(Theme.label(11)).tracking(2).foregroundStyle(Theme.muted) }
        }
        .frame(minHeight: 22)
    }
}

/// Small gold capitals above a board's title: where you are and what it's about.
struct Rubric: View {
    let text: Text
    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }
    var body: some View {
        RubricLabel(text: text)
    }
}

/// The block above a board: rubric, a textura title that changes with the moment, and one quiet line.
struct BoardHeader<Trailing: View>: View {
    var rubric: Text?
    let title: Text
    var subtitle: Text?
    var warn = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rubric { RubricLabel(text: rubric) }
            HStack(alignment: .firstTextBaseline) {
                title.font(Theme.title(28)).foregroundStyle(Theme.tin).lineLimit(1).minimumScaleFactor(0.6).contentTransition(.opacity)
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

/// A screen's one primary action: a flat slab of gold, its label in textura and the manicule at the end.
/// Secondary and disabled actions are a hairline box with the label in rubric capitals.
struct PlaqueButtonStyle: ButtonStyle {
    var secondary = false
    /// Sized to its label, for a tool row.
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        let solid = enabled && !secondary
        return HStack(spacing: 10) {
            configuration.label
                .font(solid ? Theme.title(compact ? 18 : 22) : Theme.label(compact ? 11.5 : 12.5))
                .tracking(solid ? 0 : 2)
                .textCase(solid ? nil : .uppercase)
            if !compact { Spacer(minLength: 8); Manicule(color: solid ? Theme.onGold : Theme.gold) }
        }
        .foregroundStyle(solid ? Theme.onGold : enabled ? Theme.tin : Theme.muted)
        .lineLimit(1).minimumScaleFactor(0.75)
        .padding(.horizontal, compact ? 14 : 16)
        .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 44 : 50)
        .background(solid ? (pressed ? Theme.goldLip : Theme.gold) : (pressed ? Theme.fieldLift : Color.clear))
        .overlay { if !solid { Rectangle().strokeBorder(Theme.hairline, lineWidth: 1) } }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension ButtonStyle where Self == PlaqueButtonStyle {
    static var plaque: PlaqueButtonStyle { PlaqueButtonStyle() }
    static func plaque(secondary: Bool = false, compact: Bool = false) -> PlaqueButtonStyle { PlaqueButtonStyle(secondary: secondary, compact: compact) }
}

/// A tool under the board: a hairline box with its icon over a short rubric label. Gold when it's on.
struct ToolButtonStyle: ButtonStyle {
    var on = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ToolLabelStyle(on: on))
            .padding(.horizontal, 3)
            .frame(minWidth: 50, minHeight: 48)
            .background(on || configuration.isPressed ? Theme.fieldLift : Color.clear)
            .overlay(Rectangle().strokeBorder(on ? Theme.gold : Theme.hairline, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct ToolLabelStyle: LabelStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            configuration.icon.font(.system(size: 16, weight: .semibold)).foregroundStyle(on ? Theme.gold : Theme.tin).frame(height: 18)
            configuration.title.font(Theme.label(9)).tracking(1).textCase(.uppercase).foregroundStyle(on ? Theme.tin : Theme.muted).lineLimit(1)
        }
    }
}

extension ButtonStyle where Self == ToolButtonStyle {
    static var tool: ToolButtonStyle { ToolButtonStyle() }
    static func tool(on: Bool) -> ToolButtonStyle { ToolButtonStyle(on: on) }
}

/// The row of tools under a board, under a hairline, with the primary action on the right.
struct Dock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 5) { content }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.field.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { BarRule() }
    }
}

extension View {
    /// A box on the page: solid fill, square corners and a hairline round it.
    func panel(_ fill: Color = Theme.panel, padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(Rectangle().fill(fill))
            .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// The board in its box: a hairline round it, a little away from the squares.
    func boardFrame() -> some View {
        self.padding(5)
            .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false).accessibilityHidden(true))
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

/// A segmented row of section names in a hairline box; the chosen one filled with gold.
struct SectionPicker<Value: Hashable>: View {
    let items: [(LocalizedStringKey, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let (title, value) = items[i], on = value == selection
                Button { withAnimation(.easeOut(duration: 0.2)) { selection = value } } label: {
                    Text(title).font(Theme.label(12)).tracking(1.6).textCase(.uppercase).foregroundStyle(on ? Theme.onGold : Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? Theme.gold : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
        .frame(minHeight: 44)
    }
}

/// How far through a lesson or a set: a thin gold rule over a hairline.
struct BeadProgress: View {
    let count: Int
    let current: Int

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.hairline)
                Rectangle().fill(Theme.gold).frame(width: g.size.width * min(1, CGFloat(current) / CGFloat(max(count, 1))))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.25), value: current)
        .accessibilityElement().accessibilityLabel("Progrés")
        .accessibilityValue(Text("\(min(current, count)) de \(count)"))
    }
}

/// A row's mark: its icon in colour in a hairline square.
struct Medallion: View {
    let image: Image
    var color = Theme.gold
    var body: some View {
        image.renderingMode(.template).resizable().scaledToFit().frame(width: 20, height: 20).foregroundStyle(color)
            .frame(width: 40, height: 40)
            .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
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
