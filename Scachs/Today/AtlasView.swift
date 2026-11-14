import SwiftUI

/// Your openings as a medieval sea chart: one landmass per first move, a territory per opening, and dragons where you keep losing.
struct AtlasRegion: Identifiable, Equatable {
    var name: String
    var land: Land
    var wins = 0, draws = 0, losses = 0

    var id: String { name }
    var games: Int { wins + draws + losses }
    var score: Double { games == 0 ? 0 : (Double(wins) + Double(draws) / 2) / Double(games) }
    /// Enough games to mean something, and most of them lost. Few games prove nothing, however they went.
    var isDragon: Bool { games >= Atlas.dragonGames && score < Atlas.dragonScore }
}

enum Land: String, CaseIterable { case kingPawn, queenPawn, flank }

enum Atlas {
    static let dragonGames = 3
    static let dragonScore = 0.35

    /// The main names of each landmass, drawn faintly until you've been there: part of a chart is what's still unknown.
    private static let known: [Land: [String]] = [
        .kingPawn: ["Sicilian Defense", "French Defense", "Caro-Kann Defense", "Italian Game", "Ruy Lopez", "Scandinavian Defense", "Pirc Defense", "Alekhine Defense", "Scotch Game", "Russian Game", "King's Gambit", "Vienna Game"],
        .queenPawn: ["Queen's Gambit Declined", "Queen's Gambit Accepted", "Slav Defense", "King's Indian Defense", "Nimzo-Indian Defense", "Queen's Indian Defense", "Grünfeld Defense", "Dutch Defense", "London System", "Benoni Defense", "Catalan Opening"],
        .flank: ["English Opening", "Réti Opening", "Bird Opening", "King's Indian Attack", "Nimzo-Larsen Attack"],
    ]

    static func family(_ name: String) -> String {
        let family = String(name.split(separator: ":").first ?? Substring(name)).trimmingCharacters(in: .whitespaces)
        return family.hasPrefix("King's Gambit") ? "King's Gambit" : family
    }

    static func land(firstMove: String?) -> Land {
        switch firstMove {
        case "e2e4": .kingPawn
        case "d2d4": .queenPawn
        default: .flank
        }
    }

    /// Every family you've played with this colour, plus the known ones you haven't, in a stable order.
    static func regions(games: [ImportedGame], side: Side, openings: Openings = .shared) -> [AtlasRegion] {
        var regions: [String: AtlasRegion] = [:]
        for (land, names) in known { for name in names { regions[name] = AtlasRegion(name: name, land: land) } }
        for game in games where game.mySide == side {
            guard let pgn = PGN.parse(game.pgn).first, pgn.hasStandardStart, let first = pgn.moves.first?.move,
                  let entry = openings.name(start: .start, moves: pgn.moves.map(\.move)) else { continue }
            let name = family(entry.name)
            var region = regions[name] ?? AtlasRegion(name: name, land: land(firstMove: first.uci))
            switch (game.result, side) {
            case ("1-0", .white), ("0-1", .black): region.wins += 1
            case ("1/2-1/2", _): region.draws += 1
            case ("*", _): break
            default: region.losses += 1
            }
            regions[name] = region
        }
        return regions.values.sorted { $0.name < $1.name }
    }
}

struct AtlasView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var side: Side = .white
    @State private var selected: AtlasRegion?
    @State private var regions: [AtlasRegion] = []
    @State private var chart: AtlasChart?
    @State private var highlight: CGImage?
    @State private var sheetSize: CGSize = .zero
    @State private var painted: [String: ([AtlasRegion], AtlasChart?)] = [:]
    private static let aspect: CGFloat = 1.28

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Tanca").padding(.horizontal, 20)
                HStack(alignment: .firstTextBaseline) {
                    ScreenTitle("L'Atles")
                    Spacer()
                    sideButton("Blanques", .white)
                    sideButton("Negres", .black)
                }
                .padding(.horizontal, 20).padding(.bottom, 6)
                sheet
                detail.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fieldBackground()
        .task(id: "\(side == .white)\(Int(sheetSize.width))") { await paint() }
    }

    private func paint() async {
        guard sheetSize.width > 0 else { return }
        let key = "\(side == .white)\(Int(sheetSize.width))"
        var result = painted[key]
        if result == nil {
            let games = GameLibrary.shared.games, side = side, size = sheetSize, scale = min(displayScale, 2.5)
            let fresh = await Task.detached(priority: .userInitiated) { () -> ([AtlasRegion], AtlasChart?) in
                let regions = Atlas.regions(games: games, side: side)
                return (regions, AtlasPainter.paint(regions: regions, size: size, scale: scale))
            }.value
            guard !Task.isCancelled else { return }
            painted[key] = fresh
            result = fresh
        }
        withAnimation(.easeOut(duration: 0.25)) {
            regions = result?.0 ?? []
            chart = result?.1
            selected = nil
            highlight = nil
        }
    }

    private func sideButton(_ title: LocalizedStringKey, _ value: Side) -> some View {
        Button { side = value } label: {
            Text(title).font(Theme.text(16, .semibold)).foregroundStyle(side == value ? Theme.gold : Theme.quiet).frame(minHeight: 44).padding(.leading, 10)
        }
    }

    // MARK: The sheet

    private var sheet: some View {
        GeometryReader { geo in
            ZStack {
                if let chart {
                    Image(decorative: chart.image, scale: chart.scale).resizable().transition(.opacity)
                    if let highlight {
                        Image(decorative: highlight, scale: chart.scale).resizable().blendMode(.multiply).transition(.opacity)
                    }
                    Canvas { context, size in drawInk(chart, in: &context, size: size) }
                        .contentShape(Rectangle())
                        .onTapGesture { point in select(chart.place(at: point), in: chart) }
                        .accessibilityRepresentation {
                            VStack {
                                ForEach(chart.places.sorted { $0.region.games > $1.region.games }, id: \.region.name) { place in
                                    Button(place.region.name) { select(place, in: chart) }
                                }
                            }
                        }
                } else {
                    ProgressView().tint(Theme.gold)
                }
            }
            .onAppear { sheetSize = geo.size }
            .onChange(of: geo.size) { _, size in sheetSize = size }
        }
        .aspectRatio(1 / Self.aspect, contentMode: .fit)
    }

    private func select(_ place: AtlasChart.Place?, in chart: AtlasChart) {
        withAnimation(.easeOut(duration: 0.2)) {
            selected = place?.region
            highlight = place.flatMap { chart.highlight($0.region) }
        }
        Haptics.tap(0.2, sharpness: 0.3)
    }

    // MARK: Ink on top of the painting

    private static let ink = Color(red: 0.10, green: 0.09, blue: 0.11)
    private static let red = Color(red: 0.62, green: 0.16, blue: 0.09)
    private static let green = Color(red: 0.08, green: 0.30, blue: 0.25)
    private static let leaf = Color(red: 0.72, green: 0.53, blue: 0.22)
    private static let skin = Color(red: 0.871, green: 0.812, blue: 0.690)

    private func drawInk(_ chart: AtlasChart, in context: inout GraphicsContext, size: CGSize) {
        drawRhumbs(&context, size)
        drawTitles(chart, &context)
        for place in chart.places { drawName(place, &context) }
        let dragons = chart.places.filter { $0.dragon != nil }
        for place in dragons { drawDragon(at: place.dragon!, &context) }
        if let worst = dragons.max(by: { $0.region.losses < $1.region.losses })?.dragon {
            context.draw(Text("Aquí hi ha dracs").font(Theme.text(10, .medium)).foregroundColor(Self.red), at: CGPoint(x: worst.x, y: worst.y + 18))
        }
        drawRose(&context, at: CGPoint(x: size.width * AtlasPainter.rose.x, y: size.height * AtlasPainter.rose.y), radius: size.width * AtlasPainter.rose.radius)
        drawScale(chart, &context, size)
        drawBorder(&context, size)
    }

    /// The web of lines every portolan carries, in the traditional three inks: black for the eight winds, green for the half winds, red for the quarters.
    private func drawRhumbs(_ context: inout GraphicsContext, _ size: CGSize) {
        var copy = context
        copy.blendMode = .multiply
        copy.clip(to: Path(CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 16)))
        let centre = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let radius = size.width * 0.46
        let nodes = (0..<16).map { i -> CGPoint in
            let a = Double(i) / 16 * 2 * .pi
            return CGPoint(x: centre.x + radius * cos(a), y: centre.y + radius * sin(a))
        }
        for colour in 0..<3 {
            var lines = Path()
            for origin in nodes + [centre] {
                for i in 0..<32 where (colour == 0 ? i % 4 == 0 : colour == 1 ? i % 4 == 2 : i % 2 == 1) {
                    let a = Double(i) / 32 * 2 * .pi
                    lines.move(to: origin)
                    lines.addLine(to: CGPoint(x: origin.x + size.width * 1.6 * cos(a), y: origin.y + size.width * 1.6 * sin(a)))
                }
            }
            let tone = colour == 0 ? Self.ink.opacity(0.13) : colour == 1 ? Self.green.opacity(0.15) : Self.red.opacity(0.11)
            copy.stroke(lines, with: .color(tone), lineWidth: 0.4)
        }
    }

    private func drawTitles(_ chart: AtlasChart, _ context: inout GraphicsContext) {
        let titles: [(Land, LocalizedStringKey)] = [(.kingPawn, "Peó de rei"), (.queenPawn, "Peó de dama"), (.flank, "Flancs")]
        for (land, title) in titles {
            guard let at = chart.titles[land] else { continue }
            context.draw(Text(title).font(Theme.display(28)).foregroundColor(Self.ink.opacity(0.5)), at: at)
        }
    }

    private func drawName(_ place: AtlasChart.Place, _ context: inout GraphicsContext) {
        let region = place.region, played = region.games > 0
        var name = region.name.replacingOccurrences(of: " Defense", with: "").replacingOccurrences(of: " Opening", with: "").replacingOccurrences(of: " Game", with: "").replacingOccurrences(of: " Attack", with: "")
        var size: CGFloat = played ? 11 : 9.5
        func label() -> GraphicsContext.ResolvedText {
            context.resolve(Text(verbatim: name).font(Theme.text(size, played ? .semibold : .regular)).foregroundColor(played ? Self.ink : Self.ink.opacity(0.62)))
        }
        func width() -> CGFloat { label().measure(in: CGSize(width: 400, height: 40)).width }
        if width() > place.room {
            name = name.replacingOccurrences(of: "Queen's Gambit", with: "QG").replacingOccurrences(of: "Queen's", with: "Q.").replacingOccurrences(of: "King's", with: "K.").replacingOccurrences(of: " System", with: "").replacingOccurrences(of: "Nimzo-Larsen", with: "Larsen")
        }
        if width() > place.room { size = max(size * place.room / width(), 8) }
        var copy = context
        copy.translateBy(x: place.point.x, y: place.point.y)
        copy.rotate(by: .radians(place.angle))
        copy.draw(label(), at: .zero)
        if played {
            var flag = context
            flag.translateBy(x: place.point.x + 7 * sin(place.angle), y: place.point.y - 7 * cos(place.angle))
            drawPennant(games: region.games, &flag)
        }
    }

    /// A little flag on each place you've actually played, taller the more you've been there.
    private func drawPennant(games: Int, _ context: inout GraphicsContext) {
        let height = 7 + min(CGFloat(games), 8) * 0.7
        var pole = Path()
        pole.move(to: .zero)
        pole.addLine(to: CGPoint(x: 0, y: -height))
        context.stroke(pole, with: .color(Self.ink), lineWidth: 0.7)
        var flag = Path()
        flag.move(to: CGPoint(x: 0, y: -height))
        flag.addQuadCurve(to: CGPoint(x: 7.5, y: -height + 1.8), control: CGPoint(x: 4, y: -height - 1.4))
        flag.addQuadCurve(to: CGPoint(x: 0, y: -height + 3.8), control: CGPoint(x: 3.6, y: -height + 3.8))
        flag.closeSubpath()
        context.fill(flag, with: .color(Self.ink))
    }

    /// A sea serpent out of a bestiary: a forked tail, two coils breaking the water, a finned neck and open jaws.
    private func drawDragon(at point: CGPoint, _ context: inout GraphicsContext) {
        var c = context
        c.translateBy(x: point.x - 30, y: point.y + 6)
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        var body = Path(), fins = Path()
        body.move(to: P(3, 0))
        body.addQuadCurve(to: P(-1, -8), control: P(-1, -4))
        body.addQuadCurve(to: P(-6, -11), control: P(-4, -8))
        body.addQuadCurve(to: P(0, -10.5), control: P(-3, -11.5))
        body.addQuadCurve(to: P(3, -14), control: P(2, -11.5))
        body.addQuadCurve(to: P(1.5, -7), control: P(3.5, -9.5))
        body.addQuadCurve(to: P(7, 0), control: P(2.5, -3))
        body.closeSubpath()
        for start in [CGFloat(10), 26] {
            let width: CGFloat = 14, thick: CGFloat = 3.4, rise: CGFloat = 15
            body.move(to: P(start, 0))
            body.addCurve(to: P(start + width, 0), control1: P(start + 1, -rise), control2: P(start + width - 1, -rise))
            body.addLine(to: P(start + width - thick, 0))
            body.addCurve(to: P(start + thick, 0), control1: P(start + width - thick - 0.5, -(rise - thick * 1.5)), control2: P(start + thick + 0.5, -(rise - thick * 1.5)))
            body.closeSubpath()
            fins.addLines([P(start + width / 2 - 3, -10.6), P(start + width / 2 + 0.6, -14.6), P(start + width / 2 + 3, -10.6)])
            fins.closeSubpath()
        }
        body.move(to: P(43, 0))
        body.addCurve(to: P(49, -17), control1: P(44, -8), control2: P(45, -14))
        body.addQuadCurve(to: P(60, -16.5), control: P(54, -21.5))
        body.addLine(to: P(54, -14.8))
        body.addLine(to: P(59, -11.5))
        body.addQuadCurve(to: P(53, -11.5), control: P(56, -10))
        body.addCurve(to: P(51, 0), control1: P(50, -8), control2: P(52, -4))
        body.closeSubpath()
        fins.addLines([P(46, -12), P(42.6, -14.6), P(45.6, -8)])
        fins.closeSubpath()
        fins.addLines([P(47.6, -16), P(45, -19.6), P(49.4, -18)])
        fins.closeSubpath()
        var tongue = Path()
        tongue.addLines([P(56, -13.4), P(62, -13.2), P(64, -14.8)])
        tongue.move(to: P(62, -13.2))
        tongue.addLine(to: P(64, -11.8))
        c.stroke(tongue, with: .color(Self.red), lineWidth: 0.6)
        c.fill(body, with: .color(Self.red))
        c.stroke(body, with: .color(Self.ink), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
        c.fill(fins, with: .color(Self.ink))
        c.fill(Path(ellipseIn: CGRect(x: 52.2, y: -18.4, width: 2, height: 2)), with: .color(Self.skin))
        var waves = Path()
        for wave in 0..<5 {
            let start = -7 + CGFloat(wave) * 14
            waves.move(to: P(start, 3))
            waves.addQuadCurve(to: P(start + 12, 3), control: P(start + 6, 0))
        }
        c.stroke(waves, with: .color(Self.ink.opacity(0.7)), lineWidth: 0.6)
    }

    /// The wind rose of the Mallorcan school, with the winds' Catalan initials: Tramuntana, Gregal, Llevant, Xaloc, Migjorn, Llebeig, Ponent, Mestral.
    private func drawRose(_ context: inout GraphicsContext, at centre: CGPoint, radius: CGFloat) {
        func kite(_ angle: Double, length: CGFloat, width: CGFloat, left: Color, right: Color) {
            let tip = CGPoint(x: centre.x + length * cos(angle), y: centre.y + length * sin(angle))
            let l = CGPoint(x: centre.x + width * cos(angle - .pi / 2), y: centre.y + width * sin(angle - .pi / 2))
            let r = CGPoint(x: centre.x + width * cos(angle + .pi / 2), y: centre.y + width * sin(angle + .pi / 2))
            var a = Path(); a.addLines([centre, l, tip]); a.closeSubpath()
            var b = Path(); b.addLines([centre, r, tip]); b.closeSubpath()
            context.fill(a, with: .color(left))
            context.fill(b, with: .color(right))
        }
        var ring = Path(ellipseIn: CGRect(x: centre.x - radius * 0.72, y: centre.y - radius * 0.72, width: radius * 1.44, height: radius * 1.44))
        ring.addEllipse(in: CGRect(x: centre.x - radius * 0.68, y: centre.y - radius * 0.68, width: radius * 1.36, height: radius * 1.36))
        context.stroke(ring, with: .color(Self.ink.opacity(0.7)), lineWidth: 0.45)
        for i in 0..<16 where i % 2 == 1 {
            kite(Double(i) / 16 * 2 * .pi - .pi / 2, length: radius * 0.58, width: radius * 0.05, left: Self.red, right: Self.red.opacity(0.55))
        }
        for i in 0..<8 where i % 2 == 1 {
            kite(Double(i) / 8 * 2 * .pi - .pi / 2, length: radius * 0.8, width: radius * 0.09, left: Self.green, right: Self.skin)
        }
        for i in 0..<4 {
            kite(Double(i) / 4 * 2 * .pi - .pi / 2, length: radius, width: radius * 0.13, left: Self.ink, right: Self.leaf)
        }
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 2, y: centre.y - 2, width: 4, height: 4)), with: .color(Self.skin))
        for (i, wind) in ["T", "G", "L", "X", "M", "Ll", "P", "M"].enumerated() {
            let a = Double(i) / 8 * 2 * .pi - .pi / 2
            let at = CGPoint(x: centre.x + (radius + 8) * cos(a), y: centre.y + (radius + 8) * sin(a))
            context.draw(Text(verbatim: wind).font(Theme.text(9, .semibold)).foregroundColor(i == 0 ? Self.red : Self.ink), at: at)
        }
    }

    /// A chart's scale bar, only here it measures your games.
    private func drawScale(_ chart: AtlasChart, _ context: inout GraphicsContext, _ size: CGSize) {
        let total = chart.places.reduce(0) { $0 + $1.region.games }
        guard total > 0 else { return }
        let segment: CGFloat = 11, count = 6
        let origin = CGPoint(x: size.width - 26 - segment * CGFloat(count), y: size.height - 32)
        for i in 0..<count {
            let rect = CGRect(x: origin.x + CGFloat(i) * segment, y: origin.y, width: segment, height: 3.5)
            if i % 2 == 0 { context.fill(Path(rect), with: .color(Self.ink)) } else { context.stroke(Path(rect), with: .color(Self.ink), lineWidth: 0.5) }
        }
        context.draw(Text("\(total) partides").font(Theme.text(10, .medium)).foregroundColor(Self.ink), at: CGPoint(x: origin.x + segment * CGFloat(count) / 2, y: origin.y - 8))
    }

    /// The graduated border of a sea chart, which on this one is the edge of a chessboard.
    private func drawBorder(_ context: inout GraphicsContext, _ size: CGSize) {
        let inset: CGFloat = 12, band: CGFloat = 4.5, step: CGFloat = 12
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        let inner = outer.insetBy(dx: band, dy: band)
        var squares = Path()
        var x = outer.minX, odd = false
        while x < outer.maxX {
            let w = min(step, outer.maxX - x)
            if odd {
                squares.addRect(CGRect(x: x, y: outer.minY, width: w, height: band))
                squares.addRect(CGRect(x: x, y: inner.maxY, width: w, height: band))
            }
            x += step; odd.toggle()
        }
        var y = outer.minY; odd = false
        while y < outer.maxY {
            let h = min(step, outer.maxY - y)
            if odd {
                squares.addRect(CGRect(x: outer.minX, y: y, width: band, height: h))
                squares.addRect(CGRect(x: inner.maxX, y: y, width: band, height: h))
            }
            y += step; odd.toggle()
        }
        context.fill(squares, with: .color(Self.ink.opacity(0.82)))
        context.stroke(Path(outer), with: .color(Self.ink.opacity(0.82)), lineWidth: 0.6)
        context.stroke(Path(inner), with: .color(Self.ink.opacity(0.82)), lineWidth: 0.6)
    }

    // MARK: Under the sheet

    @ViewBuilder private var detail: some View {
        let played = regions.filter { $0.games > 0 }.count
        if let region = selected {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: region.name).font(Theme.display(30)).foregroundStyle(Theme.tin).lineLimit(2).minimumScaleFactor(0.7)
                if region.games == 0 {
                    Text("Aquí encara no hi has estat.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                } else {
                    Text("\(region.games) partides. Guanyades: \(region.wins). Taules: \(region.draws). Perdudes: \(region.losses).").font(Theme.text(16)).foregroundStyle(Theme.tin.opacity(0.9))
                    if region.isDragon { Text("Aquí hi ha dracs.").font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold) }
                }
            }
        } else if played == 0 && chart != nil {
            Text("Quan tinguis partides amb aquest color, sortiran aquí.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
        } else if chart != nil {
            HStack(spacing: 16) {
                legend(Color(red: 0.13, green: 0.40, blue: 0.33), "Et va bé")
                legend(Color(red: 0.72, green: 0.53, blue: 0.22), "A mitges")
                legend(Color(red: 0.68, green: 0.20, blue: 0.12), "Et costa")
                legend(Self.skin, "Per explorar")
            }
        }
    }

    private func legend(_ colour: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(colour).frame(width: 11, height: 11)
            Text(title).font(Theme.text(14)).foregroundStyle(Theme.quiet).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
