import SwiftUI

/// The chart of themes: every puzzle theme is a land on a hand-drawn sea chart. A land comes out of the fog once you've
/// tried it and gets a flag once you do better there than your rating expects. The world grows from fixed seeds, so
/// everyone sails the same chart; only the fog and the flags are yours.
enum SeaChart {
    static let size = CGSize(width: 1000, height: 1660)
    static let port = CGPoint(x: 270, y: 1330)

    struct Realm {
        let name: LocalizedStringResource
        let size: CGFloat
        let at: CGPoint
        let shape: (cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, seed: Int, rough: CGFloat)
        let fromPort: Bool
        let terrain: Terrain
        let themes: [(String, Double)]   // theme, how far from the port it lies (0 near, 1 far)
        var atSea = false
        var avoid: [(CGPoint, CGFloat)] = []
    }
    enum Terrain { case mountains, hills, forest, port }

    static let realms: [Realm] = [
        Realm(name: "Serralada dels Mats", size: 30, at: CGPoint(x: 470, y: 300), shape: (520, 300, 400, 182, 11, 0.13), fromPort: false, terrain: .mountains,
              themes: [("mate", 0.18), ("backRankMate", 0.22), ("cornerMate", 0.34), ("smotheredMate", 0.4), ("arabianMate", 0.46), ("hookMate", 0.54), ("operaMate", 0.6),
                       ("doubleBishopMate", 0.66), ("bodenMate", 0.72), ("anastasiaMate", 0.8), ("epauletteMate", 0.86), ("pillsburysMate", 0.94)],
              avoid: [(CGPoint(x: 800, y: 245), 125)]),
        Realm(name: "Regne de la Tàctica", size: 28, at: CGPoint(x: 345, y: 805), shape: (340, 800, 258, 232, 23, 0.12), fromPort: true, terrain: .hills,
              themes: [("hangingPiece", 0.04), ("fork", 0.08), ("pin", 0.12), ("skewer", 0.2), ("discoveredAttack", 0.26), ("doubleCheck", 0.3), ("trappedPiece", 0.34),
                       ("attraction", 0.42), ("deflection", 0.46), ("capturingDefender", 0.5), ("intermezzo", 0.58), ("xRayAttack", 0.64), ("clearance", 0.7), ("interference", 0.78)]),
        Realm(name: "Boscos del Mig Joc", size: 24, at: CGPoint(x: 812, y: 812), shape: (812, 815, 140, 232, 37, 0.12), fromPort: true, terrain: .forest,
              themes: [("attackingF2F7", 0.16), ("exposedKing", 0.24), ("kingsideAttack", 0.32), ("sacrifice", 0.4), ("advancedPawn", 0.48), ("queensideAttack", 0.56),
                       ("defensiveMove", 0.66), ("quietMove", 0.76)]),
        Realm(name: "Port de l'Obertura", size: 19, at: CGPoint(x: 168, y: 1278), shape: (150, 1432, 116, 116, 51, 0.12), fromPort: false, terrain: .port,
              themes: [("opening", 0.02), ("master", 0.3), ("masterVsMaster", 0.5)], atSea: true, avoid: [(CGPoint(x: 196, y: 1362), 46)]),
    ]
    static let archipelago: LocalizedStringResource = "Arxipèlag dels Finals"
    static let archipelagoAt = CGPoint(x: 655, y: 1373)
    static let islands: [(cx: CGFloat, cy: CGFloat, r: CGFloat, seed: Int, theme: String, h: Double)] = [
        (392, 1252, 60, 61, "pawnEndgame", 0.3), (548, 1300, 48, 62, "promotion", 0.26), (705, 1238, 56, 63, "rookEndgame", 0.44), (876, 1296, 56, 64, "queenRookEndgame", 0.62),
        (420, 1448, 54, 65, "bishopEndgame", 0.5), (600, 1460, 56, 66, "knightEndgame", 0.56), (772, 1446, 48, 67, "queenEndgame", 0.68), (318, 1588, 36, 68, "zugzwang", 0.74),
    ]

    static var themes: [String] { realms.flatMap { $0.themes.map(\.0) } + islands.map(\.theme) }

    // MARK: Where you stand

    enum State: Int { case fog, charted, held }

    /// What the chart knows about one land, from your attempts on its theme.
    struct Standing {
        var tried = 0, solved = 0, blind = 0
        var expected = 0.0, got = 0.0
        var edge: Double { blind > 0 ? (got - expected) / Double(blind) : 0 }
        /// Three puzzles chart a land; a dozen blind ones, done better than your rating expects, hold it.
        var state: State { blind >= SeaChart.heldAfter && edge >= 0.05 ? .held : tried >= 3 ? .charted : .fog }
        var towardsHeld: Int { state == .held ? 10 : min(9, blind * 10 / SeaChart.heldAfter) }
    }
    static let heldAfter = 12

    static func standings(_ attempts: [Attempt]) -> [String: Standing] {
        let wanted = Set(themes)
        var out: [String: Standing] = [:]
        for a in attempts {
            let p = 1 / (1 + exp((Double(a.puzzleRating) - a.ratingBefore) / 173.72))
            for t in a.themes where wanted.contains(t) {
                var s = out[t] ?? Standing()
                s.tried += 1
                if a.solved { s.solved += 1 }
                if a.context == .blind && !a.hinted { s.blind += 1; s.expected += p; s.got += a.solved ? 1 : 0 }
                out[t] = s
            }
        }
        return out
    }

    /// A flag stays once it's planted, so a bad week never takes a land back.
    static func states(_ standings: [String: Standing], held: Set<String>) -> [String: State] {
        Dictionary(uniqueKeysWithValues: themes.map { t in (t, held.contains(t) ? .held : standings[t]?.state ?? .fog) })
    }

    static let ranks: [(name: LocalizedStringResource, at: Int)] = [("Grumet", 0), ("Mariner", 3), ("Pilot", 8), ("Patró", 18), ("Mestre de cartes", 36)]
    static func rank(held: Int) -> Int { ranks.lastIndex { held >= $0.at } ?? 0 }
}

// MARK: - The world, grown once

extension SeaChart {
    struct Land {
        let ks: [CGFloat]
        let cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat
        let points: [CGPoint]
        let path: Path
        init(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, seed: Int, rough: CGFloat, n: Int = 720) {
            ks = (0..<n).map { i in
                let t = Double(i) / Double(n) * .pi * 2, c = cos(t), s = sin(t)
                return 1 + rough * (Noise.fbm(c * 1.4 + 7, s * 1.4 + 7, seed, 3) - 0.5) * 5
                    + 0.07 * (Noise.fbm(c * 7 + 3, s * 7 + 3, seed + 5, 2) - 0.5) * 4 + 0.03 * (Noise.fbm(c * 15 + 1, s * 15 + 1, seed + 9, 2) - 0.5) * 4
            }
            (self.cx, self.cy, self.rx, self.ry) = (cx, cy, rx, ry)
            points = Self.ring(ks, cx, cy, rx, ry, 0)
            path = Path(polygon: points)
        }
        func ring(_ d: CGFloat) -> [CGPoint] { Self.ring(ks, cx, cy, rx, ry, d) }
        private static func ring(_ ks: [CGFloat], _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ d: CGFloat) -> [CGPoint] {
            ks.enumerated().map { i, k in
                let t = Double(i) / Double(ks.count) * .pi * 2
                return CGPoint(x: cx + cos(t) * (rx * k + d), y: cy + sin(t) * (ry * k + d))
            }
        }
        func contains(_ p: CGPoint) -> Bool { Geometry.inside(points, p) }
    }

    struct Territory: Identifiable {
        let id: String          // the puzzle theme
        let realm: Int          // index in realms, or realms.count for the archipelago
        let h: Double
        let land: Int
        let seed: CGPoint
        let cell: Path
        let lines: [String]
        let labelRect: CGRect
        var name: String { ThemeNames.name(id) }
        var realmName: LocalizedStringResource { realm < SeaChart.realms.count ? SeaChart.realms[realm].name : SeaChart.archipelago }
    }

    struct Features {
        var mountains: [(p: CGPoint, s: CGFloat, j: CGFloat)] = []
        var hills: [(p: CGPoint, s: CGFloat)] = []
        var trees: [(p: CGPoint, s: CGFloat)] = []
        var rivers: [[CGPoint]] = []
        var curls: [(p: CGPoint, r: CGFloat, dir: CGFloat, tail: CGFloat)] = []
    }

    struct World {
        let lands: [Land]
        let territories: [Territory]
        let borders: [Path]          // dotted lines between lands of one realm, one path per realm
        let features: Features
        func territory(at p: CGPoint) -> Territory? {
            territories.filter { lands[$0.land].contains(p) }.min { hypot($0.seed.x - p.x, $0.seed.y - p.y) < hypot($1.seed.x - p.x, $1.seed.y - p.y) }
        }
    }

    @MainActor static let world = grow()

    static let labelFont = UIFont(name: "YsabeauOffice-SemiBold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)

    /// A theme's name on the chart: one line, or two split near the middle.
    static func lines(_ name: String) -> [String] {
        guard name.count > 13, let cut = name.indices.filter({ name[$0] == " " }).min(by: {
            abs(name.distance(from: name.startIndex, to: $0) - name.count / 2) < abs(name.distance(from: name.startIndex, to: $1) - name.count / 2)
        }) else { return [name] }
        return [String(name[..<cut]), String(name[name.index(after: cut)...])]
    }

    static func nameRect(_ lines: [String], size: CGFloat, at: CGPoint) -> CGRect {
        let font = UIFont(name: "GrenzeGotisch-Medium", size: size) ?? .systemFont(ofSize: size)
        let w = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width + CGFloat($0.count) * 4 }.max() ?? 0
        let h = size * 1.1 * CGFloat(lines.count)
        return CGRect(x: at.x - w / 2, y: at.y - h / 2 - 4, width: w, height: h + 8)
    }

    /// A realm's name as it's lettered: the forest's in two lines, to fit between its trees.
    static func realmLines(_ i: Int) -> [String] {
        let s = String(localized: i < realms.count ? realms[i].name : archipelago)
        return i == 2 ? lines(s) : [s]
    }

    private static func grow() -> World {
        var rects: [CGRect] = []
        var lands: [Land] = [], territories: [Territory] = [], borders: [Path] = []
        for (ri, r) in realms.enumerated() {
            let land = Land(r.shape.cx, r.shape.cy, r.shape.rx, r.shape.ry, seed: r.shape.seed, rough: r.shape.rough)
            let li = lands.count
            lands.append(land)
            let nr = nameRect(realmLines(ri), size: r.size, at: r.at)
            rects.append(nr)
            let inner = land.ring(-34)
            let xs = land.points.map(\.x), ys = land.points.map(\.y)
            let box = CGRect(x: xs.min()! - 60, y: ys.min()! - 60, width: xs.max()! - xs.min()! + 120, height: ys.max()! - ys.min()! + 120)
            var d = sqrt(Geometry.area(land.points) / Double(r.themes.count)) * 0.86
            var rnd = Random(seed: UInt32(r.shape.seed * 977))
            var seeds: [CGPoint] = []
            var tries = 0
            while seeds.count < r.themes.count && tries < 40000 {
                tries += 1
                if tries % 5000 == 4999 { d *= 0.92 }
                let p = CGPoint(x: box.minX + rnd.next() * box.width, y: box.minY + rnd.next() * box.height)
                guard Geometry.inside(inner, p) else { continue }
                if !r.atSea && nr.insetBy(dx: -50, dy: -22).contains(p) { continue }
                if r.avoid.contains(where: { hypot($0.0.x - p.x, $0.0.y - p.y) < $0.1 }) { continue }
                if seeds.contains(where: { hypot($0.x - p.x, $0.y - p.y) < d }) { continue }
                seeds.append(p)
            }
            seeds.sort { r.fromPort ? hypot($0.x - port.x, $0.y - port.y) < hypot($1.x - port.x, $1.y - port.y) : $0.x < $1.x }
            let cells = seeds.indices.map { Geometry.cell($0, seeds, box) }
            var border = Path()
            for (i, poly) in cells.enumerated() {
                for (k, v) in poly.enumerated() where v.edge > i {
                    let w = Geometry.wobble(v.p, poly[(k + 1) % poly.count].p)
                    border.addLines(w)
                }
            }
            borders.append(border)
            for (i, (theme, h)) in r.themes.enumerated() where i < seeds.count {
                let ls = lines(ThemeNames.name(theme))
                territories.append(Territory(id: theme, realm: ri, h: h, land: li, seed: seeds[i], cell: Geometry.cellPath(cells[i]), lines: ls, labelRect: labelRect(ls, seeds[i])))
            }
        }
        for isle in islands {
            let land = Land(isle.cx, isle.cy, isle.r, isle.r * 0.84, seed: isle.seed, rough: 0.16, n: 360)
            let ls = lines(ThemeNames.name(isle.theme)), seed = CGPoint(x: isle.cx, y: isle.cy + 2)
            territories.append(Territory(id: isle.theme, realm: realms.count, h: isle.h, land: lands.count, seed: seed, cell: land.path, lines: ls, labelRect: labelRect(ls, seed)))
            lands.append(land)
            borders.append(Path())
        }
        rects.append(nameRect(realmLines(realms.count), size: 22, at: archipelagoAt))
        rects += territories.map { $0.labelRect.inset(by: UIEdgeInsets(top: -22, left: -14, bottom: 0, right: 0)) }
        return World(lands: lands, territories: territories, borders: borders, features: terrain(lands, rects))
    }

    private static func labelRect(_ lines: [String], _ at: CGPoint) -> CGRect {
        let w = lines.map { ($0 as NSString).size(withAttributes: [.font: labelFont]).width }.max() ?? 0
        let h = 20 + CGFloat(lines.count - 1) * 16
        return CGRect(x: at.x - w / 2 - 6, y: at.y - h / 2, width: w + 12, height: h)
    }

    private static func terrain(_ lands: [Land], _ rects: [CGRect]) -> Features {
        func clear(_ r: CGRect) -> Bool { !rects.contains { $0.intersects(r) } }
        var f = Features()
        for (ri, r) in realms.enumerated() {
            let land = lands[ri], inner = land.ring(-14)
            var rnd = Random(seed: UInt32(r.shape.seed * 131))
            switch r.terrain {
            case .mountains:
                var y: CGFloat = 116
                while y < 520 {
                    var x: CGFloat = 80 + (Int(y / 21) % 2 == 1 ? 15 : 0)
                    while x < 970 {
                        let px = x + (rnd.next() - 0.5) * 14, py = y + (rnd.next() - 0.5) * 9, s = 16 + rnd.next() * 14, j = rnd.next()
                        x += 29
                        guard Geometry.inside(inner, CGPoint(x: px - s, y: py)), Geometry.inside(inner, CGPoint(x: px + s, y: py)), Geometry.inside(inner, CGPoint(x: px, y: py - s)),
                              clear(CGRect(x: px - s, y: py - s * 1.2, width: s * 2, height: s * 1.2 + 2)), hypot(px - 800, py - 262) >= 88 else { continue }
                        f.mountains.append((CGPoint(x: px, y: py), s, j))
                    }
                    y += 21
                }
            case .hills, .port:
                let step: CGFloat = r.terrain == .port ? 42 : 50
                var y: CGFloat = 560
                while y < 1600 {
                    var x: CGFloat = 40
                    while x < 700 {
                        let px = x + (rnd.next() - 0.5) * 26, py = y + (rnd.next() - 0.5) * 26, s = 11 + rnd.next() * 8, skip = rnd.next() < 0.3
                        x += step
                        guard !skip, land.contains(CGPoint(x: px, y: py)), Geometry.inside(inner, CGPoint(x: px - s, y: py)), Geometry.inside(inner, CGPoint(x: px + s, y: py)),
                              clear(CGRect(x: px - s, y: py - s, width: s * 2, height: s + 3)) else { continue }
                        f.hills.append((CGPoint(x: px, y: py), s))
                    }
                    y += step
                }
            case .forest:
                var y: CGFloat = 560
                while y < 1080 {
                    var x: CGFloat = 650 + (Int(y / 13) % 2 == 1 ? 7 : 0)
                    while x < 980 {
                        let px = x + (rnd.next() - 0.5) * 6, py = y + (rnd.next() - 0.5) * 5, s = 6 + rnd.next() * 2.6
                        x += 15
                        guard Noise.fbm(px * 0.018, py * 0.018, 4, 3) >= 0.4, Geometry.inside(inner, CGPoint(x: px, y: py)),
                              clear(CGRect(x: px - s, y: py - s, width: s * 2, height: s * 2.6)) else { continue }
                        f.trees.append((CGPoint(x: px, y: py), s))
                    }
                    y += 13
                }
            }
        }
        for (i, isle) in lands.dropFirst(realms.count).enumerated() {
            var rnd = Random(seed: UInt32(500 + i))
            let inner = isle.ring(-12)
            for _ in 0..<30 {
                let px = isle.cx + (rnd.next() - 0.5) * 110, py = isle.cy + (rnd.next() - 0.5) * 90, s = 9 + rnd.next() * 6
                if Geometry.inside(inner, CGPoint(x: px - s, y: py)), Geometry.inside(inner, CGPoint(x: px + s, y: py)), clear(CGRect(x: px - s, y: py - s, width: s * 2, height: s + 2)),
                   !f.hills.contains(where: { hypot($0.p.x - px, $0.p.y - py) < 22 }) { f.hills.append((CGPoint(x: px, y: py), s)) }
            }
        }
        for (n, start) in [(CGPoint(x: 380, y: 690), 2.1, 330.0), (CGPoint(x: 790, y: 700), 1.75, 300.0)].enumerated() {
            var p = start.0, a = start.1, pts = [p]
            for i in 0..<Int(start.2 / 6) { a += (Noise.fbm(Double(i) * 0.12, Double(n * 9), 88, 2) - 0.5) * 0.7; p = CGPoint(x: p.x + cos(a) * 6, y: p.y + sin(a) * 6); pts.append(p) }
            f.rivers.append(pts)
        }
        var rc = Random(seed: 404)
        var y: CGFloat = 60
        while y < size.height - 40 {
            var x: CGFloat = 40
            while x < size.width - 40 {
                let keep = rc.next() < 0.55, px = x + (rc.next() - 0.5) * 30, py = y + (rc.next() - 0.5) * 20, r = 6 + rc.next() * 7, dir: CGFloat = rc.next() < 0.5 ? 1 : -1, tail = 18 + rc.next() * 26
                if keep { f.curls.append((CGPoint(x: px, y: py), r, dir, tail)) }
                x += 46
            }
            y += 34
        }
        f.mountains.sort { $0.p.y < $1.p.y }
        f.trees.sort { $0.p.y < $1.p.y }
        return f
    }
}

// MARK: - Noise and geometry

extension SeaChart {
/// Value noise and a small seeded generator, the same numbers on every device.
enum Noise {
    static func hash(_ x: Int, _ y: Int, _ s: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x) &* 374_761_393 ^ UInt32(truncatingIfNeeded: y) &* 668_265_263 ^ UInt32(truncatingIfNeeded: s) &* 1_442_695_041
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h) / 4_294_967_296
    }
    static func value(_ x: Double, _ y: Double, _ s: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y)), xf = x - floor(x), yf = y - floor(y)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi, s), b = hash(xi + 1, yi, s), c = hash(xi, yi + 1, s), d = hash(xi + 1, yi + 1, s)
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }
    static func fbm(_ x: Double, _ y: Double, _ s: Int, _ octaves: Int = 4) -> Double {
        var t = 0.0, a = 0.5, f = 1.0, n = 0.0
        for i in 0..<octaves { t += a * value(x * f, y * f, s + i * 17); n += a; a *= 0.5; f *= 2 }
        return t / n
    }
}

struct Random {
    private var a: UInt32
    init(seed: UInt32) { a = seed }
    mutating func next() -> CGFloat {
        a &+= 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return CGFloat(Double(t ^ (t >> 14)) / 4_294_967_296)
    }
}

enum Geometry {
    static func inside(_ pts: [CGPoint], _ p: CGPoint) -> Bool {
        var c = false, j = pts.count - 1
        for i in pts.indices {
            let a = pts[i], b = pts[j]
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }
    static func area(_ pts: [CGPoint]) -> Double {
        var s = 0.0, j = pts.count - 1
        for i in pts.indices { s += (pts[j].x + pts[i].x) * (pts[j].y - pts[i].y); j = i }
        return abs(s / 2)
    }

    struct Vertex { var p: CGPoint; var edge: Int }   // edge: the neighbour the edge from here faces, -1 for the box

    /// A Voronoi cell, clipped from a box one bisector at a time, each edge remembering its neighbour.
    static func cell(_ i: Int, _ seeds: [CGPoint], _ box: CGRect) -> [Vertex] {
        var poly = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)].map { Vertex(p: $0, edge: -1) }
        let a = seeds[i]
        for (j, b) in seeds.enumerated() where j != i {
            let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), n = CGPoint(x: b.x - a.x, y: b.y - a.y)
            func f(_ q: CGPoint) -> CGFloat { (q.x - m.x) * n.x + (q.y - m.y) * n.y }
            var out: [Vertex] = []
            for k in poly.indices {
                let A = poly[k], B = poly[(k + 1) % poly.count], fa = f(A.p), fb = f(B.p)
                if fa <= 0 { out.append(A) }
                if (fa <= 0) != (fb <= 0) {
                    let t = fa / (fa - fb)
                    out.append(Vertex(p: CGPoint(x: A.p.x + (B.p.x - A.p.x) * t, y: A.p.y + (B.p.y - A.p.y) * t), edge: fa <= 0 ? j : A.edge))
                }
            }
            poly = out
        }
        return poly
    }

    /// An edge drawn by hand: split every 9 units and nudged by noise, ends fixed so neighbours meet.
    static func wobble(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        let n = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 9)))
        return (0...n).map { k in
            let t = CGFloat(k) / CGFloat(n), x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, d: CGFloat = k == 0 || k == n ? 0 : 1
            return CGPoint(x: x + d * (Noise.fbm(x * 0.022, y * 0.022, 71, 3) - 0.5) * 22, y: y + d * (Noise.fbm(x * 0.022 + 40, y * 0.022 + 40, 73, 3) - 0.5) * 22)
        }
    }
    static func cellPath(_ poly: [Vertex]) -> Path {
        var pts: [CGPoint] = []
        for (k, v) in poly.enumerated() { pts += wobble(v.p, poly[(k + 1) % poly.count].p).dropLast() }
        return Path(polygon: pts)
    }
}
}

extension Path {
    init(polygon pts: [CGPoint]) {
        self.init()
        guard let first = pts.first else { return }
        move(to: first)
        for p in pts.dropFirst() { addLine(to: p) }
        closeSubpath()
    }
}
