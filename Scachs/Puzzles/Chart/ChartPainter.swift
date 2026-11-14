import SwiftUI

/// Paints the chart in map units (1000 × 1660). The still part, which only changes with the language, is rendered once
/// to an image; the fog, the flags and the names are drawn over it live, since they change with your play.
enum ChartPainter {
    static let vellum = Color(hex: 0xDECFB0), ink = Color(hex: 0x1F1A1C), water = Color(hex: 0x263D38)
    static let umber = Color(hex: 0x8F6B42), nameInk = Color(hex: 0x5C4128), red = Color(hex: 0xA42C1C)
    static let redDeep = Color(hex: 0x6B1A10), verd = Color(hex: 0x2C6F5E), ivory = Color(hex: 0xEBE3CF), goldDeep = Color(hex: 0xA87A3A)

    // MARK: The skin

    /// Stains and a darker rim, at half a pixel per unit: smooth, so it can be stretched.
    static let skin: CGImage? = {
        let w = 500, h = 830
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let stain = max(0, SeaChart.Noise.fbm(Double(x) * 0.0126, Double(y) * 0.0126, 5, 4) - 0.46) * 1.0
                let dx = Double(x) / Double(w) - 0.5, dy = Double(y) / Double(h) - 0.5, rim = max(0, (sqrt(dx * dx + dy * dy) - 0.3) / 0.35) * 0.3
                let k = 1 - min(0.5, stain + rim)
                px[i] = UInt8(222 * k + 143 * (1 - k)); px[i + 1] = UInt8(207 * k + 107 * (1 - k)); px[i + 2] = UInt8(176 * k + 66 * (1 - k)); px[i + 3] = 255
            }
        }
        return image(px, w, h)
    }()
    static let grain: CGImage? = {
        var r = SeaChart.Random(seed: 7)
        var px = [UInt8](repeating: 0, count: 160 * 160 * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            let v = r.next(), a = v > 0.5 ? UInt8((v - 0.5) * 70) : 0
            px[i] = UInt8(90 * Int(a) / 255); px[i + 1] = UInt8(66 * Int(a) / 255); px[i + 2] = UInt8(40 * Int(a) / 255); px[i + 3] = a
        }
        return image(px, 160, 160)
    }()
    private static func image(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        var px = px
        return px.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
    static var skinFill: GraphicsContext.Shading {
        guard let skin else { return .color(vellum) }
        return .tiledImage(Image(decorative: skin, scale: 1), origin: .zero, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 2)
    }

    // MARK: The still chart

    @MainActor static func base(_ world: SeaChart.World, unit: CGFloat, scale: CGFloat) -> Image? {
        let size = CGSize(width: SeaChart.size.width * unit, height: SeaChart.size.height * unit)
        let r = ImageRenderer(content: Canvas { ctx, _ in ctx.scaleBy(x: unit, y: unit); drawBase(&ctx, world) }.frame(width: size.width, height: size.height))
        r.scale = scale
        return r.cgImage.map { Image(decorative: $0, scale: scale) }
    }

    static func drawBase(_ ctx: inout GraphicsContext, _ w: SeaChart.World) {
        let all = CGRect(origin: .zero, size: SeaChart.size)
        ctx.fill(Path(all), with: skinFill)
        var sea = Path(all)
        w.lands.forEach { sea.addPath($0.path) }
        ctx.fill(sea, with: .color(Color(red: 0.302, green: 0.459, blue: 0.412).opacity(0.24)), style: FillStyle(eoFill: true))
        ctx.drawLayer { l in
            l.clip(to: sea, style: FillStyle(eoFill: true))
            for land in w.lands { for (d, a) in [(5.0, 0.55), (11, 0.38), (19, 0.24), (29, 0.13)] { l.stroke(Path(polygon: land.ring(d)), with: .color(water.opacity(a)), lineWidth: 0.9) } }
        }
        for land in w.lands { ctx.drawLayer { l in l.clip(to: land.path); l.stroke(land.path, with: .color(Color(red: 0.6, green: 0.44, blue: 0.22).opacity(0.32)), lineWidth: 16) } }
        let f = w.features
        ctx.drawLayer { l in
            var lands = Path(); w.lands.forEach { lands.addPath($0.path) }
            l.clip(to: lands)
            for river in f.rivers { var p = Path(); p.addLines(river); l.stroke(p, with: .color(water), style: StrokeStyle(lineWidth: 1.8, lineCap: .round)) }
        }
        f.hills.forEach { hill(&ctx, $0.p, $0.s) }
        f.trees.forEach { tree(&ctx, $0.p, $0.s) }
        f.mountains.forEach { mountain(&ctx, $0.p, $0.s, $0.j) }
        town(&ctx)
        for (i, border) in w.borders.enumerated() where !border.isEmpty {
            ctx.drawLayer { l in l.clip(to: w.lands[i].path); l.stroke(border, with: .color(ink.opacity(0.62)), style: StrokeStyle(lineWidth: 1.15, dash: [2.4, 3.8])) }
        }
        w.lands.forEach { ctx.stroke($0.path, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)) }
        if let grain { ctx.fill(Path(all), with: .tiledImage(Image(decorative: grain, scale: 1), scale: 0.6)) }
    }

    private static func mountain(_ ctx: inout GraphicsContext, _ at: CGPoint, _ s: CGFloat, _ j: CGFloat) {
        let x = at.x, y = at.y, px = x + (j - 0.5) * s * 0.3, py = y - s * (0.95 + j * 0.25)
        let L = CGPoint(x: x - s * 0.95, y: y), R = CGPoint(x: x + s * 0.9, y: y), M = CGPoint(x: x + s * 0.1, y: y)
        var slopes = Path(); slopes.move(to: L); slopes.addQuadCurve(to: CGPoint(x: px, y: py), control: CGPoint(x: px - s * 0.42, y: py + s * 0.35))
        slopes.addQuadCurve(to: R, control: CGPoint(x: px + s * 0.42, y: py + s * 0.45))
        var body = slopes; body.closeSubpath()
        ctx.fill(body, with: skinFill)
        var shade = Path(); shade.move(to: CGPoint(x: px, y: py)); shade.addQuadCurve(to: R, control: CGPoint(x: px + s * 0.42, y: py + s * 0.45)); shade.addLine(to: M)
        shade.addQuadCurve(to: CGPoint(x: px, y: py), control: CGPoint(x: px + s * 0.05, y: py + s * 0.55))
        ctx.fill(shade, with: .color(umber.opacity(0.3)))
        for i in 1...3 {
            let t = CGFloat(i) / 4, sx = px + (M.x - px) * t + s * 0.1, sy = py + (M.y - py) * t
            var h = Path(); h.move(to: CGPoint(x: sx, y: sy)); h.addLine(to: CGPoint(x: px + (M.x - px) * t + s * (0.32 + 0.1 * CGFloat(i)), y: sy + s * 0.2))
            ctx.stroke(h, with: .color(ink), lineWidth: 0.7)
        }
        ctx.stroke(slopes, with: .color(ink), lineWidth: 1.1)
        var ridge = Path(); ridge.move(to: CGPoint(x: px, y: py)); ridge.addQuadCurve(to: M, control: CGPoint(x: px + s * 0.05, y: py + s * 0.55))
        ctx.stroke(ridge, with: .color(ink), lineWidth: 0.8)
    }
    private static func hill(_ ctx: inout GraphicsContext, _ at: CGPoint, _ s: CGFloat) {
        var p = Path(); p.move(to: CGPoint(x: at.x - s, y: at.y)); p.addQuadCurve(to: CGPoint(x: at.x + s, y: at.y), control: CGPoint(x: at.x, y: at.y - s * 1.15))
        ctx.fill(p, with: skinFill); ctx.stroke(p, with: .color(ink), lineWidth: 1)
        for i in 0..<2 {
            var h = Path(); let k = CGFloat(i)
            h.move(to: CGPoint(x: at.x + s * (0.2 + k * 0.25), y: at.y - s * (0.45 - k * 0.12))); h.addLine(to: CGPoint(x: at.x + s * (0.32 + k * 0.25), y: at.y - s * (0.1 - k * 0.05)))
            ctx.stroke(h, with: .color(ink), lineWidth: 0.7)
        }
    }
    private static func tree(_ ctx: inout GraphicsContext, _ at: CGPoint, _ s: CGFloat) {
        var trunk = Path(); trunk.move(to: CGPoint(x: at.x, y: at.y + s * 0.5)); trunk.addLine(to: CGPoint(x: at.x, y: at.y + s * 1.5))
        ctx.stroke(trunk, with: .color(ink), lineWidth: 0.8)
        let crown = Path(polygon: (0..<8).map { i in let a = Double(i) / 7 * .pi * 2, r = s * (i % 2 == 1 ? 0.92 : 1.04); return CGPoint(x: at.x + cos(a) * r, y: at.y + sin(a) * r) })
        ctx.fill(crown, with: skinFill)
        var shade = Path(); shade.addArc(center: CGPoint(x: at.x + s * 0.25, y: at.y + s * 0.2), radius: s * 0.62, startAngle: .radians(-0.4), endAngle: .radians(2.2), clockwise: false)
        ctx.fill(shade, with: .color(umber.opacity(0.2)))
        ctx.stroke(crown, with: .color(ink), lineWidth: 0.85)
    }
    private static func town(_ ctx: inout GraphicsContext) {
        for (a, b) in [(CGPoint(x: 236, y: 1338), CGPoint(x: 262, y: 1322)), (CGPoint(x: 244, y: 1350), CGPoint(x: 272, y: 1340))] {
            var p = Path(); p.move(to: a); p.addLine(to: b); ctx.stroke(p, with: .color(ink), lineWidth: 1.4)
        }
        for c in [CGPoint(x: 176, y: 1362), CGPoint(x: 194, y: 1356), CGPoint(x: 184, y: 1378), CGPoint(x: 204, y: 1372), CGPoint(x: 166, y: 1384)] {
            let house = Path(polygon: [CGPoint(x: c.x - 7, y: c.y), CGPoint(x: c.x - 7, y: c.y - 8), CGPoint(x: c.x, y: c.y - 15), CGPoint(x: c.x + 7, y: c.y - 8), CGPoint(x: c.x + 7, y: c.y)])
            ctx.fill(house, with: skinFill)
            ctx.fill(Path(polygon: [CGPoint(x: c.x - 7, y: c.y - 8), CGPoint(x: c.x, y: c.y - 15), CGPoint(x: c.x + 7, y: c.y - 8)]), with: .color(red.opacity(0.55)))
            ctx.stroke(house, with: .color(ink), lineWidth: 0.9)
        }
        let tower = Path(CGRect(x: 212, y: 1330, width: 12, height: 30))
        ctx.fill(tower, with: skinFill); ctx.stroke(tower, with: .color(ink), lineWidth: 1)
        var merlons = Path(); for x in stride(from: 212.0, to: 224, by: 4) { merlons.addRect(CGRect(x: x, y: 1326, width: 2.5, height: 4)) }
        ctx.stroke(merlons, with: .color(ink), lineWidth: 1)
        var pole = Path(); pole.move(to: CGPoint(x: 218, y: 1326)); pole.addLine(to: CGPoint(x: 218, y: 1310)); ctx.stroke(pole, with: .color(ink), lineWidth: 1)
        let flag = Path(polygon: [CGPoint(x: 218, y: 1310), CGPoint(x: 230, y: 1314), CGPoint(x: 218, y: 1318)])
        ctx.fill(flag, with: .color(red)); ctx.stroke(flag, with: .color(ink), lineWidth: 1)
    }

    // MARK: What changes with your play

    static func drawState(_ ctx: inout GraphicsContext, _ w: SeaChart.World, states: [String: SeaChart.State], selected: String?, target: SeaChart.Territory?) {
        var wash = Path(), fog = Path()
        for t in w.territories {
            switch states[t.id] ?? .fog {
            case .held: wash.addPath(t.cell)
            case .fog: fog.addPath(t.cell)
            case .charted: break
            }
        }
        for land in w.lands {
            ctx.drawLayer { l in
                l.clip(to: land.path)
                l.blendMode = .multiply
                l.fill(wash, with: .color(Color(red: 0.306, green: 0.541, blue: 0.431).opacity(0.42)))
            }
            ctx.drawLayer { l in
                l.clip(to: land.path)
                l.drawLayer { f in f.addFilter(.blur(radius: 9)); f.fill(fog, with: .color(Color(red: 0.925, green: 0.894, blue: 0.812).opacity(0.88))) }
                l.clip(to: fog)
                var curls = Path()
                for c in w.features.curls where land.contains(c.p) {
                    let start = c.dir > 0 ? 0 : Double.pi
                    curls.move(to: CGPoint(x: c.p.x + c.r * cos(start), y: c.p.y + c.r * sin(start)))
                    curls.addArc(center: c.p, radius: c.r, startAngle: .radians(start), endAngle: .radians(c.dir > 0 ? .pi * 1.7 : .pi * 2.7), clockwise: false)
                    curls.move(to: CGPoint(x: c.p.x + c.r * c.dir, y: c.p.y))
                    curls.addQuadCurve(to: CGPoint(x: c.p.x + (c.r + c.tail) * c.dir, y: c.p.y - 2), control: CGPoint(x: c.p.x + c.r * c.dir + c.tail * 0.5 * c.dir, y: c.p.y + 4))
                }
                l.stroke(curls, with: .color(umber.opacity(0.22)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
        if let s = w.territories.first(where: { $0.id == selected }) {
            ctx.drawLayer { l in
                l.clip(to: w.lands[s.land].path)
                l.addFilter(.shadow(color: Theme.gold.opacity(0.9), radius: 6))
                l.stroke(s.cell, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 3.4, lineJoin: .round))
            }
        }
        if let t = target {
            let from = CGPoint(x: SeaChart.port.x + 30, y: SeaChart.port.y - 22)
            var route = Path(); route.move(to: from)
            route.addQuadCurve(to: CGPoint(x: t.seed.x + 4, y: t.seed.y + 18), control: CGPoint(x: (from.x + t.seed.x) / 2 + 110, y: (from.y + t.seed.y) / 2 + 40))
            ctx.stroke(route, with: .color(red), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [7, 6]))
            ctx.stroke(Path(ellipseIn: CGRect(x: t.seed.x - 26, y: t.seed.y - 26, width: 52, height: 52)), with: .color(red), lineWidth: 1.6)
        }
        for t in w.territories {
            let state = states[t.id] ?? .fog
            for (i, line) in t.lines.enumerated() {
                let y = t.seed.y + (CGFloat(i) - CGFloat(t.lines.count - 1) / 2) * 16
                let font: Font = state == .fog ? .custom("YsabeauOffice-Regular", fixedSize: 15) : .custom("YsabeauOffice-SemiBold", fixedSize: 15)
                let text = Text(verbatim: line).font(font).foregroundColor(state == .fog ? Color(red: 0.43, green: 0.33, blue: 0.2).opacity(0.75) : ink)
                halo(&ctx, text, CGPoint(x: t.seed.x, y: y), state == .fog ? Color(red: 0.94, green: 0.91, blue: 0.83) : vellum, radius: 2)
            }
            if state == .held {
                let width = t.lines.map { ($0 as NSString).size(withAttributes: [.font: SeaChart.labelFont]).width }.max() ?? 0
                let x = t.seed.x - width / 2 - 8, y = t.seed.y - CGFloat(t.lines.count - 1) * 8 - 2
                var pole = Path(); pole.move(to: CGPoint(x: x, y: y + 8)); pole.addLine(to: CGPoint(x: x, y: y - 20))
                ctx.stroke(pole, with: .color(ink), lineWidth: 1.4)
                let flag = Path(polygon: [CGPoint(x: x, y: y - 20), CGPoint(x: x + 15, y: y - 15.5), CGPoint(x: x, y: y - 11)])
                ctx.fill(flag, with: .color(Theme.gold)); ctx.stroke(flag, with: .color(ink), lineWidth: 0.9)
            }
        }
        drawNames(&ctx)
        rose(&ctx, CGPoint(x: 98, y: 1152), 50)
        frame(&ctx)
    }

    private static func halo(_ ctx: inout GraphicsContext, _ text: Text, _ at: CGPoint, _ color: Color, radius: CGFloat) {
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: color, radius: radius))
            l.addFilter(.shadow(color: color, radius: radius))
            l.addFilter(.shadow(color: color.opacity(0.9), radius: radius * 0.6))
            l.draw(text, at: at, anchor: .center)
        }
    }

    private static func drawNames(_ ctx: inout GraphicsContext) {
        let places: [(Int, CGPoint, CGFloat)] = SeaChart.realms.enumerated().map { ($0.offset, $0.element.at, $0.element.size) } + [(SeaChart.realms.count, SeaChart.archipelagoAt, 22)]
        for (i, at, size) in places {
            let lines = SeaChart.realmLines(i)
            for (n, line) in lines.enumerated() {
                let y = at.y + (CGFloat(n) - CGFloat(lines.count - 1) / 2) * size * 1.1
                let text = Text(verbatim: line).font(.custom("GrenzeGotisch-Medium", fixedSize: size)).tracking(4).foregroundColor(nameInk.opacity(0.92))
                halo(&ctx, text, CGPoint(x: at.x, y: y), i == 3 || i == SeaChart.realms.count ? Color(red: 0.81, green: 0.81, blue: 0.71) : vellum, radius: 3)
            }
        }
        ctx.draw(Text(verbatim: "MARE SCACHORUM").font(.custom("YsabeauOffice-Regular", fixedSize: 21)).tracking(9).foregroundColor(water.opacity(0.82)), at: CGPoint(x: 392, y: 1126), anchor: .center)
        halo(&ctx, Text("Aquí hi ha dracs").font(.custom("YsabeauOffice-Regular", fixedSize: 16)).foregroundColor(red), CGPoint(x: 800, y: 312), vellum, radius: 2)
    }

    private static func rose(_ ctx: inout GraphicsContext, _ c: CGPoint, _ R: CGFloat) {
        let ring = Path(ellipseIn: CGRect(x: c.x - R * 0.74, y: c.y - R * 0.74, width: R * 1.48, height: R * 1.48))
        ctx.fill(ring, with: .color(vellum.opacity(0.55))); ctx.stroke(ring, with: .color(ink), lineWidth: 1.2)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R * 0.66, y: c.y - R * 0.66, width: R * 1.32, height: R * 1.32)), with: .color(ink), lineWidth: 0.6)
        var ticks = Path()
        for i in 0..<32 { let a = Double(i) / 32 * .pi * 2; ticks.move(to: CGPoint(x: c.x + cos(a) * R * 0.66, y: c.y + sin(a) * R * 0.66)); ticks.addLine(to: CGPoint(x: c.x + cos(a) * R * 0.74, y: c.y + sin(a) * R * 0.74)) }
        ctx.stroke(ticks, with: .color(ink), lineWidth: 0.6)
        func kite(_ a: Double, _ len: CGFloat, _ wid: CGFloat, _ left: Color, _ right: Color) {
            let tip = CGPoint(x: c.x + len * cos(a), y: c.y + len * sin(a))
            let l = CGPoint(x: c.x + wid * cos(a - .pi / 2), y: c.y + wid * sin(a - .pi / 2)), r = CGPoint(x: c.x + wid * cos(a + .pi / 2), y: c.y + wid * sin(a + .pi / 2))
            for (side, fill) in [(l, left), (r, right)] { let p = Path(polygon: [c, side, tip]); ctx.fill(p, with: .color(fill)); ctx.stroke(p, with: .color(ink), lineWidth: 0.8) }
        }
        for i in stride(from: 1, to: 16, by: 2) { kite(Double(i) / 16 * .pi * 2 - .pi / 2, R * 0.6, R * 0.05, red, redDeep) }
        for i in stride(from: 1, to: 8, by: 2) { kite(Double(i) / 8 * .pi * 2 - .pi / 2, R * 0.8, R * 0.09, verd, ivory) }
        for i in stride(from: 0, to: 8, by: 2) { kite(Double(i) / 8 * .pi * 2 - .pi / 2, R, R * 0.12, Theme.gold, goldDeep) }
        let hub = Path(ellipseIn: CGRect(x: c.x - R * 0.07, y: c.y - R * 0.07, width: R * 0.14, height: R * 0.14))
        ctx.fill(hub, with: .color(red)); ctx.stroke(hub, with: .color(ink), lineWidth: 0.8)
        ctx.draw(Text(verbatim: "T").font(.custom("GrenzeGotisch-Medium", fixedSize: R * 0.34)).foregroundColor(red), at: CGPoint(x: c.x, y: c.y - R * 1.12), anchor: .center)
    }

    private static func frame(_ ctx: inout GraphicsContext) {
        let o: CGFloat = 9, b: CGFloat = 12, st: CGFloat = 14, W = SeaChart.size.width, H = SeaChart.size.height
        var margin = Path(CGRect(x: 0, y: 0, width: W, height: H)); margin.addRect(CGRect(x: o, y: o, width: W - 2 * o, height: H - 2 * o))
        ctx.fill(margin, with: .color(Color(hex: 0xC9B48C)), style: FillStyle(eoFill: true))
        var checks = Path()
        for x in stride(from: o, to: W - o, by: st * 2) { checks.addRect(CGRect(x: x, y: o, width: min(st, W - o - x), height: b)); checks.addRect(CGRect(x: x, y: H - o - b, width: min(st, W - o - x), height: b)) }
        for y in stride(from: o, to: H - o, by: st * 2) { checks.addRect(CGRect(x: o, y: y, width: b, height: min(st, H - o - y))); checks.addRect(CGRect(x: W - o - b, y: y, width: b, height: min(st, H - o - y))) }
        ctx.fill(checks, with: .color(ink))
        ctx.stroke(Path(CGRect(x: o, y: o, width: W - 2 * o, height: H - 2 * o)), with: .color(ink), lineWidth: 1.6)
        ctx.stroke(Path(CGRect(x: o + b, y: o + b, width: W - 2 * (o + b), height: H - 2 * (o + b))), with: .color(ink), lineWidth: 1)
    }
}
