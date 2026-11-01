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

/// Draws the chart once per size: the geometry never changes for the same list of names, so places stay where you left them.
private struct AtlasGeometry {
    struct Cell {
        let region: AtlasRegion
        let polygon: [CGPoint]
        let centre: CGPoint
        let outward: Double
        /// Just off the coast from this territory, where a chart would put its sea monster.
        let offshore: CGPoint
        /// How much of a name fits here without crossing a border, more or less.
        let room: CGFloat
    }

    let cells: [Cell]
    let lands: [[CGPoint]]

    private static func hash(_ s: String) -> UInt64 { s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 } }

    private static let placement: [Land: (x: Double, y: Double, rx: Double, ry: Double)] = [
        .kingPawn: (0.30, 0.27, 0.25, 0.205), .queenPawn: (0.70, 0.62, 0.255, 0.235), .flank: (0.21, 0.84, 0.17, 0.105),
    ]

    private static func blob(_ land: Land, in size: CGSize) -> [CGPoint] {
        let p = placement[land]!
        let seed = Double(hash(land.rawValue) % 1000) / 100
        return (0..<140).map { i in
            let a = Double(i) / 140 * 2 * .pi
            let wobble = 1 + 0.10 * sin(3 * a + seed) + 0.06 * sin(7 * a + seed * 2) + 0.03 * sin(17 * a + seed * 3) + 0.015 * sin(41 * a + seed)
            return CGPoint(x: (p.x + p.rx * wobble * cos(a)) * size.width, y: (p.y + p.ry * wobble * sin(a)) * size.height)
        }
    }

    /// Half-plane clip. The subject isn't convex, but these blobs are close enough that the seams don't show.
    private static func clip(_ polygon: [CGPoint], keepingCloserTo a: CGPoint, than b: CGPoint) -> [CGPoint] {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let nx = b.x - a.x, ny = b.y - a.y
        func side(_ p: CGPoint) -> CGFloat { (p.x - mid.x) * nx + (p.y - mid.y) * ny }
        var out: [CGPoint] = []
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            let sp = side(p), sq = side(q)
            if sp <= 0 { out.append(p) }
            if (sp < 0) != (sq < 0), sp != sq {
                let t = sp / (sp - sq)
                out.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
            }
        }
        return out
    }

    init(regions: [AtlasRegion], size: CGSize) {
        var cells: [Cell] = []
        var lands: [[CGPoint]] = []
        for land in Land.allCases {
            let shape = Self.blob(land, in: size)
            lands.append(shape)
            let members = regions.filter { $0.land == land }.sorted { Self.hash($0.name) < Self.hash($1.name) }
            guard !members.isEmpty else { continue }
            let p = Self.placement[land]!
            let centre = CGPoint(x: p.x * size.width, y: p.y * size.height)
            // A sunflower spiral spreads the sites evenly whatever their number.
            let sites: [CGPoint] = members.indices.map { i in
                let r = 0.82 * (Double(i) + 0.5).squareRoot() / Double(members.count).squareRoot()
                let a = Double(i) * 2.39996 + Double(Self.hash(land.rawValue) % 7)
                return CGPoint(x: centre.x + r * p.rx * size.width * cos(a), y: centre.y + r * p.ry * size.height * sin(a))
            }
            for (i, region) in members.enumerated() {
                var polygon = shape
                for j in members.indices where j != i { polygon = Self.clip(polygon, keepingCloserTo: sites[i], than: sites[j]) }
                guard polygon.count >= 3 else { continue }
                let outward = atan2(sites[i].y - centre.y, sites[i].x - centre.x)
                let land = path(shape)
                var reach: CGFloat = 0
                while reach < size.width, land.contains(CGPoint(x: centre.x + reach * cos(outward), y: centre.y + reach * sin(outward))) { reach += 4 }
                let offshore = CGPoint(x: centre.x + (reach + 20) * cos(outward), y: centre.y + (reach + 20) * sin(outward))
                let nearest: CGFloat = polygon.map { hypot($0.x - sites[i].x, $0.y - sites[i].y) }.min() ?? 25
                let room = nearest * 2.4
                cells.append(Cell(region: region, polygon: polygon, centre: sites[i], outward: outward, offshore: offshore, room: room))
            }
        }
        self.cells = cells
        self.lands = lands
    }
}

private func path(_ points: [CGPoint]) -> Path {
    var p = Path()
    p.addLines(points)
    p.closeSubpath()
    return p
}

struct AtlasView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var side: Side = .white
    @State private var selected: AtlasRegion?
    @State private var regions: [AtlasRegion] = []
    private static let aspect = 1.25

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Tanca").padding(.horizontal, 20)
                HStack(alignment: .firstTextBaseline) {
                    Text("L'Atles").font(Theme.display(52)).foregroundStyle(Theme.tin)
                    Spacer()
                    sideButton("Blanques", .white)
                    sideButton("Negres", .black)
                }
                .padding(.horizontal, 20)
                chart
                detail.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 28)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.field.ignoresSafeArea())
        .task(id: side) {
            let games = GameLibrary.shared.games
            let side = side
            let found = await Task.detached(priority: .userInitiated) { Atlas.regions(games: games, side: side) }.value
            withAnimation(.easeOut(duration: 0.25)) { regions = found; selected = nil }
        }
    }

    private func sideButton(_ title: LocalizedStringKey, _ value: Side) -> some View {
        Button { side = value } label: {
            Text(title).font(Theme.text(16, .semibold)).foregroundStyle(side == value ? Theme.gold : Theme.quiet).frame(minHeight: 44).padding(.leading, 10)
        }
    }

    private var chart: some View {
        GeometryReader { geo in
            let geometry = AtlasGeometry(regions: regions, size: geo.size)
            Canvas { context, size in draw(geometry, in: &context, size: size) }
                .contentShape(Rectangle())
                .onTapGesture { point in
                    selected = geometry.cells.first { path($0.polygon).contains(point) }?.region
                    Haptics.tap(0.2, sharpness: 0.3)
                }
                .accessibilityElement()
                .accessibilityLabel(accessibilitySummary)
        }
        .aspectRatio(1 / Self.aspect, contentMode: .fit)
    }

    private var accessibilitySummary: String {
        let played = regions.filter { $0.games > 0 }.sorted { $0.games > $1.games }
        return played.map { "\($0.name): \($0.games)" }.joined(separator: ", ")
    }

    private func draw(_ geometry: AtlasGeometry, in context: inout GraphicsContext, size: CGSize) {
        drawRhumbs(&context, size)
        // Coast first with a soft second line, the way portolans double their shores.
        for land in geometry.lands {
            context.fill(path(land), with: .color(Theme.fieldDeep))
        }
        for cell in geometry.cells {
            let polygon = path(cell.polygon)
            context.fill(polygon, with: .color(fill(cell.region)))
            if selected == cell.region { context.fill(polygon, with: .color(Theme.tin.opacity(0.16))) }
            context.stroke(polygon, with: .color(Theme.gold.opacity(0.22)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        }
        for land in geometry.lands {
            context.stroke(path(land), with: .color(Theme.gold.opacity(0.28)), lineWidth: 3)
            context.stroke(path(land), with: .color(Theme.gold), lineWidth: 0.9)
        }
        for cell in geometry.cells { drawName(cell, &context) }
        let dragons = geometry.cells.filter(\.region.isDragon)
        for cell in dragons { drawDragon(at: cell.offshore, &context) }
        if let worst = dragons.max(by: { $0.region.losses < $1.region.losses }) {
            context.draw(Text("Aquí hi ha dracs").font(Theme.text(10, .medium)).foregroundColor(Theme.gold), at: CGPoint(x: worst.offshore.x, y: worst.offshore.y - 14))
        }
        drawRose(&context, at: CGPoint(x: size.width * 0.84, y: size.height * 0.16), radius: size.width * 0.085)
    }

    private func fill(_ region: AtlasRegion) -> Color {
        guard region.games > 0 else { return Theme.fieldLift.opacity(0.55) }
        let weight = min(0.42 + Double(region.games) * 0.06, 0.85)
        if region.score >= 0.55 { return Theme.gold.opacity(weight) }
        if region.score < 0.45 { return Color(hex: 0xEF7D6C).opacity(weight) }
        return Theme.tin.opacity(weight * 0.6)
    }

    private func drawRhumbs(_ context: inout GraphicsContext, _ size: CGSize) {
        let centre = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let radius = max(size.width, size.height) * 0.62
        let nodes = (0..<16).map { i -> CGPoint in
            let a = Double(i) / 16 * 2 * .pi
            return CGPoint(x: centre.x + radius * cos(a), y: centre.y + radius * sin(a))
        }
        var lines = Path()
        for origin in nodes + [centre] {
            for i in 0..<16 {
                let a = Double(i) / 16 * 2 * .pi
                lines.move(to: origin)
                lines.addLine(to: CGPoint(x: origin.x + 2 * radius * cos(a), y: origin.y + 2 * radius * sin(a)))
            }
        }
        context.stroke(lines, with: .color(Theme.tin.opacity(0.045)), lineWidth: 0.5)
    }

    /// Names run out from the land towards the sea, as on the real charts.
    private func drawName(_ cell: AtlasGeometry.Cell, _ context: inout GraphicsContext) {
        var angle = cell.outward
        if cos(angle) < 0 { angle += .pi }
        let played = cell.region.games > 0
        var short = cell.region.name.replacingOccurrences(of: " Defense", with: "").replacingOccurrences(of: " Opening", with: "").replacingOccurrences(of: " Game", with: "").replacingOccurrences(of: " Attack", with: "")
        func label(_ text: String) -> GraphicsContext.ResolvedText {
            context.resolve(Text(verbatim: text).font(Theme.text(10, played ? .semibold : .regular)).foregroundColor(played ? Theme.tin : Theme.tin.opacity(0.42)))
        }
        // Too long for its territory: abbreviate the way a chart would, keeping the word that tells places apart.
        if label(short).measure(in: CGSize(width: 400, height: 40)).width > cell.room {
            short = short.replacingOccurrences(of: "Queen's Gambit", with: "QG").replacingOccurrences(of: "Queen's", with: "Q.").replacingOccurrences(of: "King's", with: "K.")
        }
        var copy = context
        copy.translateBy(x: cell.centre.x, y: cell.centre.y)
        copy.rotate(by: .radians(angle))
        copy.draw(label(short), at: .zero)
    }

    /// A small sea serpent, three humps and a head.
    private func drawDragon(at point: CGPoint, _ context: inout GraphicsContext) {
        var snake = Path()
        let y = point.y + 2, x = point.x - 18
        snake.move(to: CGPoint(x: x, y: y))
        for hump in 0..<3 {
            let start = x + CGFloat(hump) * 9
            snake.addQuadCurve(to: CGPoint(x: start + 9, y: y), control: CGPoint(x: start + 4.5, y: y - 9))
        }
        snake.addQuadCurve(to: CGPoint(x: x + 34, y: y - 5), control: CGPoint(x: x + 31, y: y + 3))
        snake.addLine(to: CGPoint(x: x + 38, y: y - 3))
        context.stroke(snake, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        context.stroke(snake, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }

    private func drawRose(_ context: inout GraphicsContext, at centre: CGPoint, radius: CGFloat) {
        for i in 0..<16 {
            let a = Double(i) / 16 * 2 * .pi - .pi / 2
            let major = i % 4 == 0, minor = i % 2 == 0
            let length = major ? radius : minor ? radius * 0.68 : radius * 0.45
            let width = (major ? 0.15 : 0.09) * radius
            let tip = CGPoint(x: centre.x + length * cos(a), y: centre.y + length * sin(a))
            let left = CGPoint(x: centre.x + width * cos(a - .pi / 2), y: centre.y + width * sin(a - .pi / 2))
            let right = CGPoint(x: centre.x + width * cos(a + .pi / 2), y: centre.y + width * sin(a + .pi / 2))
            context.fill(path([centre, left, tip]), with: .color(Theme.gold))
            context.fill(path([centre, right, tip]), with: .color(Theme.tin.opacity(major ? 0.9 : 0.5)))
        }
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius * 0.26, y: centre.y - radius * 0.26, width: radius * 0.52, height: radius * 0.52)), with: .color(Theme.gold.opacity(0.6)), lineWidth: 0.6)
    }

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
        } else if played == 0 {
            Text("Quan tinguis partides amb aquest color, sortiran aquí.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
        } else {
            Text("Daurat on et va bé, vermell on et costa. Toca una terra per veure-la.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
        }
    }
}
