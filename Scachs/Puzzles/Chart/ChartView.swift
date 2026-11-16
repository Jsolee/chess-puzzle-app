import SwiftUI

/// La carta: the chart of puzzle themes, full screen like the Atlas.
struct ChartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @AppStorage("chartHeld") private var heldStore = ""
    @AppStorage("chartRank") private var seenRank = 0
    @State private var base: Image?
    @State private var selected: SeaChart.Territory?
    @State private var focus: Focus?
    @State private var rankUp: Int?
    @State private var position = ScrollPosition()

    private struct Focus: Identifiable { let theme: String; var id: String { theme } }
    private var world: SeaChart.World { SeaChart.world }
    @MainActor private static var cache: [CGFloat: Image] = [:]

    var body: some View {
        let standings = SeaChart.standings(Progress.shared.attempts)
        let held = Set(heldStore.split(separator: ",").map(String.init)).union(standings.filter { $0.value.state == .held }.keys)
        let states = SeaChart.states(standings, held: held)
        let rank = SeaChart.rank(held: held.count)
        let target = Self.target(world, states, standings)
        GeometryReader { geo in
            let unit = (geo.size.width * 1.55 / SeaChart.size.width).rounded(toPlaces: 3)
            VStack(alignment: .leading, spacing: 0) {
                Rubric(verbatim: String(localized: "\(String(localized: SeaChart.ranks[rank].name)) · \(held.count) de \(SeaChart.themes.count) terres dominades"))
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
                map(unit: unit, states: states, target: target)
                    .mask(TornEdge())
                    .overlay(alignment: .bottom) {
                        if let target {
                            Button { focus = Focus(theme: target.id) } label: { Text("Cap a: \(target.name) · tres puzzles").lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 12) }
                                .buttonStyle(.plaque).padding(.horizontal, 20).padding(.bottom, 12)
                        }
                    }
            }
            .task(id: unit) {
                if let hit = Self.cache[unit] { base = hit } else {
                    await Task.yield()
                    base = ChartPainter.base(world, unit: unit, scale: min(displayScale, 2.5))
                    Self.cache[unit] = base
                }
                let at = target?.seed ?? CGPoint(x: 360, y: 760)
                position.scrollTo(point: CGPoint(x: max(0, at.x * unit - geo.size.width / 2), y: max(0, at.y * unit - geo.size.height * 0.4)))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .fieldBackground()
        .topBar(Text("La carta")) { BarButton(systemImage: "xmark", label: "Tanca") { dismiss() } } trailing: { EmptyView() }
        .sheet(item: $selected) { t in
            TerritorySheet(territory: t, state: states[t.id] ?? .fog, standing: standings[t.id] ?? SeaChart.Standing()) { selected = nil; focus = Focus(theme: t.id) }
        }
        .fullScreenCover(item: $focus) { PuzzleView(focus: [$0.theme]) }
        .overlay { if let r = rankUp { RankUp(rank: r, held: held.count) { withAnimation(.easeOut(duration: 0.25)) { rankUp = nil } }.transition(.opacity) } }
        .onAppear { remember(held: held, rank: rank) }
        .onChange(of: held.count) { remember(held: held, rank: rank) }
    }

    private func map(unit: CGFloat, states: [String: SeaChart.State], target: SeaChart.Territory?) -> some View {
        let size = CGSize(width: SeaChart.size.width * unit, height: SeaChart.size.height * unit), world = world, picked = selected?.id
        return ScrollView([.horizontal, .vertical], showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                if let base { base.resizable().frame(width: size.width, height: size.height) } else { ChartPainter.vellum.frame(width: size.width, height: size.height) }
                Canvas { ctx, _ in
                    ctx.scaleBy(x: unit, y: unit)
                    ChartPainter.drawState(&ctx, world, states: states, selected: picked, target: target)
                }
                .frame(width: size.width, height: size.height)
                BeastLayer(unit: unit, still: reduceMotion)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in selected = world.territory(at: CGPoint(x: p.x / unit, y: p.y / unit)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("La carta dels temes")
            .accessibilityValue(Text("\(states.values.filter { $0 == .held }.count) de \(SeaChart.themes.count) terres dominades"))
        }
        .scrollPosition($position)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Where the dotted route goes: the charted land closest to its flag, or else the nearest one still in fog.
    static func target(_ world: SeaChart.World, _ states: [String: SeaChart.State], _ standings: [String: SeaChart.Standing]) -> SeaChart.Territory? {
        let charted = world.territories.filter { states[$0.id] == .charted }
        if let near = charted.max(by: { (standings[$0.id]?.towardsHeld ?? 0, -$0.h) < (standings[$1.id]?.towardsHeld ?? 0, -$1.h) }) { return near }
        return world.territories.filter { states[$0.id] == .fog }.min { $0.h < $1.h }
    }

    /// Plants new flags for good and shows the rank screen once per new rank.
    private func remember(held: Set<String>, rank: Int) {
        let joined = held.sorted().joined(separator: ",")
        if joined != heldStore { heldStore = joined }
        if rank > seenRank { seenRank = rank; withAnimation(.easeOut(duration: 0.25)) { rankUp = rank } }
    }
}

/// The beasts, each in its own small canvas so only their corners redraw, about thirty times a second.
private struct BeastLayer: View {
    let unit: CGFloat
    let still: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            ZStack(alignment: .topLeading) {
                ForEach(ChartBeasts.all.indices, id: \.self) { i in
                    let b = ChartBeasts.all[i]
                    Canvas { ctx, _ in ctx.scaleBy(x: unit, y: unit); ctx.translateBy(x: -b.box.minX, y: -b.box.minY); b.draw(&ctx, t) }
                        .frame(width: b.box.width * unit, height: b.box.height * unit)
                        .offset(x: b.box.minX * unit, y: b.box.minY * unit)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The top of the vellum, torn by hand like the Atlas.
private struct TornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 0, y: rect.maxY))
        for x in stride(from: 0, through: rect.width, by: 3) { p.addLine(to: CGPoint(x: x, y: 2 + SeaChart.Noise.fbm(x * 0.04, 1, 19, 3) * 7)) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.closeSubpath()
        return p
    }
}

private struct TerritorySheet: View {
    let territory: SeaChart.Territory
    let state: SeaChart.State
    let standing: SeaChart.Standing
    let explore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rubric(verbatim: "\(String(localized: territory.realmName)) · \(String(localized: stateName))")
            Text(verbatim: territory.name).font(Theme.title(24)).foregroundStyle(Theme.tin).lineLimit(2).minimumScaleFactor(0.7).padding(.top, 8)
            GoldRule().padding(.top, 4)
            Text(text).font(Theme.text(17)).foregroundStyle(Theme.tin.opacity(0.9)).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            if state != .held {
                BeadProgress(count: state == .fog ? 3 : 10, current: state == .fog ? standing.tried : standing.towardsHeld).padding(.top, 18)
                Text(state == .fog ? "\(standing.tried) de 3 per cartografiar-la" : "\(standing.towardsHeld) de 10 cap a dominar-la")
                    .font(Theme.text(14)).foregroundStyle(Theme.quiet).padding(.top, 4)
            }
            Spacer(minLength: 18)
            Button(action: explore) { Text(state == .fog ? "Explora: tres puzzles" : "Tres puzzles més") }.buttonStyle(.plaque)
        }
        .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 12)
        .fieldBackground()
        .presentationDetents([.height(350)])
        .presentationDragIndicator(.visible)
    }

    private var stateName: LocalizedStringResource {
        switch state { case .fog: "Per explorar"; case .charted: "Cartografiada"; case .held: "Dominada" }
    }
    private var text: LocalizedStringKey {
        switch state {
        case .fog: "Encara no hi has entrat. Tres puzzles d'aquest tema a la teva mida la treuen de la boira."
        case .charted: "\(standing.solved) resolts. Per dominar-la, una mica més per sobre del que toca al teu nivell."
        case .held: "\(standing.solved) resolts, per sobre del teu nivell. La bandera ja hi és, i no se'n va."
        }
    }
}

/// A rank's mark: an enamel disc in a gold wire, with its instrument.
struct RankEmblem: View {
    let rank: Int
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: 0x3D8A74), Color(hex: 0x1C5A4B), Color(hex: 0x0F4037)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.8))
            Circle().strokeBorder(Theme.gold, lineWidth: max(1.5, size * 0.026))
            Circle().inset(by: size * 0.09).stroke(Theme.gold.opacity(0.55), lineWidth: 1)
            symbol.foregroundStyle(Theme.gold).frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    @ViewBuilder private var symbol: some View {
        switch rank {
        case 0: Image(systemName: "oar.2.crossed").resizable().scaledToFit()
        case 1: Image(systemName: "water.waves").resizable().scaledToFit()
        case 2: Image(systemName: "scope").resizable().scaledToFit()
        case 3: Image(systemName: "sailboat").resizable().scaledToFit()
        default: Image("icon.rose").renderingMode(.template).resizable().scaledToFit()
        }
    }
}

/// Once per new rank, like the seal of a lesson learnt.
private struct RankUp: View {
    let rank: Int
    let held: Int
    let done: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RankEmblem(rank: rank, size: 180).scaleEffect(shown ? 1 : 1.3).opacity(shown ? 1 : 0)
            Text("Ara ets").font(Theme.text(17)).foregroundStyle(Theme.quiet).padding(.top, 26)
            Text(SeaChart.ranks[rank].name).font(Theme.title(36)).foregroundStyle(Theme.tin)
            Group {
                if rank + 1 < SeaChart.ranks.count {
                    Text("Domines \(held) terres de la carta. El rang següent, \(String(localized: SeaChart.ranks[rank + 1].name)), arriba a les \(SeaChart.ranks[rank + 1].at).")
                } else {
                    Text("Domines \(held) terres de la carta.")
                }
            }
            .font(Theme.text(17)).foregroundStyle(Theme.tin.opacity(0.88)).multilineTextAlignment(.center).padding(.top, 12)
            Spacer()
            Button(action: done) { Text("Continua") }.buttonStyle(.plaque).padding(.bottom, 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {}
        .fieldBackground()
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { shown = true }; Haptics.capture(); Sound.capture() }
    }
}

private extension CGFloat {
    func rounded(toPlaces n: Int) -> CGFloat { let m = pow(10, CGFloat(n)); return (self * m).rounded() / m }
}
