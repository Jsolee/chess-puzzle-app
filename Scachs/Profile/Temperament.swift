import SwiftUI

/// Which medieval figure your games look like. It's read from the games, never asked: how you open, how fast you play,
/// how often you go for the king, how long you hold on. Each trait is scaled 0 to 1 against what club games usually show.
struct Temperament: Equatable, Sendable {
    enum Figure: String, CaseIterable, Sendable { case knight, castellan, astrologer, messenger, smith, pilgrim, squire }

    struct Traits: Equatable, Sendable {
        var attack = 0.0, solidity = 0.0, precision = 0.0, speed = 0.0, patience = 0.0, variety = 0.0
    }

    /// The raw counts behind the traits, kept for the lines that prove them.
    struct Counts: Equatable, Sendable {
        var games = 0, gambits = 0, ownMoves = 0, sharpMoves = 0, castledEarly = 0, quickLosses = 0
        var fast = 0, long = 0, longWins = 0, families = 0, reviewed = 0, accuracy = 0.0
    }

    static let gamesNeeded = 8

    let figure: Figure
    let traits: Traits
    let counts: Counts

    init(games: [ImportedGame], openings: Openings = .shared) {
        var c = Counts()
        var speed = 0.0
        var families = Set<String>()
        for game in games {
            guard let side = game.mySide, let pgn = PGN.parse(game.pgn).first, pgn.hasStandardStart, pgn.moves.count >= 10 else { continue }
            c.games += 1
            let mine = pgn.moves.enumerated().filter { ($0.offset % 2 == 0) == (side == .white) }.map(\.element.san)
            let opening = mine.prefix(15)
            c.ownMoves += opening.count
            c.sharpMoves += opening.filter { $0.contains("x") || $0.contains("+") }.count
            if mine.prefix(10).contains(where: { $0.hasPrefix("O-O") }) { c.castledEarly += 1 }
            let won = game.result == (side == .white ? "1-0" : "0-1")
            let lost = game.result == (side == .white ? "0-1" : "1-0")
            if lost && pgn.moves.count < 50 { c.quickLosses += 1 }
            if pgn.moves.count >= 80 { c.long += 1; if won { c.longWins += 1 } }
            switch game.timeClass {
            case .ultraBullet, .bullet: speed += 1; c.fast += 1
            case .blitz: speed += 0.55; c.fast += 1
            case .rapid: speed += 0.15
            default: break
            }
            if let name = openings.name(start: .start, moves: pgn.moves.map(\.move))?.name {
                families.insert(Atlas.family(name))
                if name.contains("Gambit") && !name.hasPrefix("Queen's Gambit") { c.gambits += 1 }
            }
            if let accuracy = game.myAccuracy { c.reviewed += 1; c.accuracy += accuracy }
        }
        c.families = families.count
        if c.reviewed > 0 { c.accuracy /= Double(c.reviewed) }
        counts = c

        func unit(_ x: Double) -> Double { min(max(x, 0), 1) }
        let n = Double(max(c.games, 1))
        var t = Traits()
        // Anchored so a typical club player lands near 0.2 on each, and only a real leaning goes past 0.5.
        t.attack = 0.6 * unit((Double(c.sharpMoves) / Double(max(c.ownMoves, 1)) - 0.18) / 0.22) + 0.4 * unit(Double(c.gambits) / n / 0.35)
        t.solidity = 0.5 * unit((Double(c.castledEarly) / n - 0.55) / 0.4) + 0.5 * unit((0.2 - Double(c.quickLosses) / n) / 0.2)
        t.precision = c.reviewed >= 3 ? unit((c.accuracy - 75) / 15) : 0
        t.speed = unit((speed / n - 0.5) / 0.5)
        t.patience = 0.6 * unit((Double(c.long) / n - 0.25) / 0.35) + 0.4 * (c.long > 0 ? unit((Double(c.longWins) / Double(c.long) - 0.4) / 0.4) : 0)
        t.variety = unit((Double(c.families) / n.squareRoot() - 1.4) / 1.6)
        traits = t

        // ponytail: one figure per strongest trait; a blend ("knight with a castellan's caution") if people ask for more.
        guard c.games >= Self.gamesNeeded else { figure = .squire; return }
        let ranked: [(Figure, Double)] = [(.knight, t.attack), (.castellan, t.solidity), (.astrologer, t.precision),
                                          (.messenger, t.speed), (.smith, t.patience), (.pilgrim, t.variety)]
        figure = ranked.max { $0.1 < $1.1 }!.0
    }

    /// The figure first, then the next strongest trait, each with what in your games shows it.
    var evidence: [String] {
        guard figure != .squire else { return [] }
        let order: [(Figure, Double)] = [(.knight, traits.attack), (.castellan, traits.solidity), (.astrologer, traits.precision),
                                         (.messenger, traits.speed), (.smith, traits.patience), (.pilgrim, traits.variety)]
        let second = order.filter { $0.0 != figure && $0.1 > 0.2 }.max { $0.1 < $1.1 }?.0
        return ([figure] + (second.map { [$0] } ?? [])).compactMap(line)
    }

    private func line(_ figure: Figure) -> String? {
        let c = counts
        switch figure {
        case .knight:
            if c.gambits > 0 { return String(localized: "\(c.gambits) de \(c.games) partides obren amb un gambit.") }
            let every = Int((Double(c.ownMoves) / Double(max(c.sharpMoves, 1))).rounded())
            return String(localized: "A l'obertura, una de cada \(every) jugades teves és una captura o un escac.")
        case .castellan: return String(localized: "Enroques abans de la jugada 10 en \(c.castledEarly) de \(c.games) partides.")
        case .astrologer: return String(localized: "Precisió mitjana de \(Int(c.accuracy.rounded())) a les partides analitzades.")
        case .messenger: return String(localized: "\(c.fast) de \(c.games) partides són de bala o blitz.")
        case .smith: return String(localized: "\(c.long) de \(c.games) partides passen de la jugada 40, i en guanyes \(c.longWins).")
        case .pilgrim: return String(localized: "Has jugat \(c.families) obertures diferents en \(c.games) partides.")
        case .squire: return nil
        }
    }
}

extension Temperament.Figure {
    var name: LocalizedStringKey {
        switch self {
        case .knight: "El Cavaller"
        case .castellan: "El Castellà"
        case .astrologer: "L'Astròleg"
        case .messenger: "El Missatger"
        case .smith: "El Ferrer"
        case .pilgrim: "El Pelegrí"
        case .squire: "L'Escuder"
        }
    }

    var portrait: LocalizedStringKey {
        switch self {
        case .knight: "Surts a buscar el rei des de les primeres jugades. Gambits, escacs i captures: prefereixes una posició viva a una de tranquil·la."
        case .castellan: "Primer, les muralles. Poses el rei a recer aviat, no regales res i esperes que l'altre s'equivoqui."
        case .astrologer: "Calcules abans de moure. Les teves jugades s'acosten a les del motor més del que és habitual."
        case .messenger: "Jugues ràpid i amb instint. Per a tu, el rellotge és part del joc."
        case .smith: "Forges les victòries a cops lents. Les teves partides s'allarguen, i als finals t'hi trobes bé."
        case .pilgrim: "Fas molts camins. Canvies d'obertura sovint, i cada partida és un viatge diferent."
        case .squire: "Encara t'estàs formant. Quan Scachs tingui unes quantes partides teves, el teu escut prendrà forma."
        }
    }

    /// The arms in words, the way heralds write them.
    var blazon: LocalizedStringKey {
        switch self {
        case .knight: "De gules, un cavall d'or."
        case .castellan: "D'atzur, una torre d'argent."
        case .astrologer: "De porpra, un alfil d'or."
        case .messenger: "D'or, una dama de sable."
        case .smith: "De sable, un rei d'or."
        case .pilgrim: "De sinople, un peó d'argent."
        case .squire: "Escut per pintar."
        }
    }

    /// Enamel field and the metal of the charge. Metal on colour, colour on metal, as the rule of tincture asks.
    var tinctures: (field: Color, charge: Color, piece: String?) {
        switch self {
        case .knight: (Color(hex: 0x9E2A1C), Theme.gold, "n")
        case .castellan: (Color(hex: 0x24477E), Theme.tin, "r")
        case .astrologer: (Color(hex: 0x5E2F62), Theme.gold, "b")
        case .messenger: (Theme.gold, Theme.ink, "q")
        case .smith: (Theme.ink, Theme.gold, "k")
        case .pilgrim: (Color(hex: 0x1D6150), Theme.tin, "p")
        case .squire: (Theme.fieldDeep, Theme.tin, nil)
        }
    }
}

/// An enamelled heater shield in a gold wire, like the pieces, with the figure's piece as its charge.
struct Crest: View {
    let figure: Temperament.Figure
    var width: CGFloat = 88

    var body: some View {
        let t = figure.tinctures, k = width / 88
        ZStack {
            Crest.shield.fill(t.field)
            Crest.shield.fill(LinearGradient(colors: [Theme.tin.opacity(0.16), .clear, Theme.ink.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let piece = t.piece {
                Image(uiImage: PieceImage.load("fig" + piece)).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(t.charge).frame(height: 54 * k).offset(y: -4 * k)
            } else {
                Crest.shield.inset(by: 9 * k).stroke(Theme.tin.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            Crest.shield.stroke(Theme.gold, lineWidth: 2.5 * k.squareRoot())
        }
        .frame(width: width, height: width * 104 / 88)
        .accessibilityHidden(true)
    }

    static let shield = HeaterShield()

    struct HeaterShield: InsettableShape {
        var inset: CGFloat = 0
        func inset(by amount: CGFloat) -> HeaterShield { HeaterShield(inset: inset + amount) }
        func path(in rect: CGRect) -> Path {
            let r = rect.insetBy(dx: inset, dy: inset)
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
            p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.78), control2: CGPoint(x: r.midX + r.width * 0.22, y: r.maxY - r.height * 0.06))
            p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.42), control1: CGPoint(x: r.midX - r.width * 0.22, y: r.maxY - r.height * 0.06), control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.78))
            p.closeSubpath()
            return p
        }
    }
}

/// The top of the profile: your arms, who that is, and what in your games says so.
struct TemperamentBlock: View {
    @State private var temperament: Temperament?

    /// The arms beside who that is, on a panel, then the portrait and the two figures it rests on.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = temperament {
                HStack(alignment: .center, spacing: 14) {
                    Crest(figure: t.figure, width: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("El teu temperament").font(Theme.text(12, .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.muted)
                        Text(t.figure.name).font(Theme.title(23)).foregroundStyle(Theme.tin).lineLimit(1).minimumScaleFactor(0.7)
                        Text(t.figure.blazon).font(Theme.text(14, .medium)).foregroundStyle(Theme.gold)
                    }
                }
                Text(t.figure.portrait).font(Theme.text(15)).foregroundStyle(Theme.quiet).fixedSize(horizontal: false, vertical: true)
                if t.figure == .squire {
                    Text("\(t.counts.games) de \(Temperament.gamesNeeded) partides.").font(Theme.text(15)).foregroundStyle(Theme.muted)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        figure("\(t.counts.families)", Text("obertures diferents en \(t.counts.games) partides"))
                        if t.counts.reviewed > 0 {
                            figure("\(Int(t.counts.accuracy.rounded()))", Text("de precisió mitjana a les partides analitzades"))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Color.clear.frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(padding: 14)
        .accessibilityElement(children: .combine)
        .task {
            let games = GameLibrary.shared.games
            let read = await Task.detached(priority: .utility) { Temperament(games: games) }.value
            withAnimation(.easeOut(duration: 0.2)) { temperament = read }
        }
    }

    private func figure(_ number: String, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: number).font(Theme.text(24, .semibold)).foregroundStyle(Theme.tin)
            label.font(Theme.text(13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}
