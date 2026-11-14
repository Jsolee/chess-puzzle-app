import SwiftUI

/// The chart's beasts, in enamel inside gold wire like the pieces. Each draws itself at time `t`, in map units; they
/// breathe, swim and sway slowly, and stand still at t = 0 when Reduce Motion is on.
enum ChartBeasts {
    struct Beast { let box: CGRect; let draw: (inout GraphicsContext, Double) -> Void }
    static let all: [Beast] = [
        Beast(box: CGRect(x: 548, y: 88, width: 431, height: 257), draw: dragon),
        Beast(box: CGRect(x: 556, y: 1056, width: 423, height: 150), draw: serpent),
        Beast(box: CGRect(x: 752, y: 1456, width: 227, height: 182), draw: kraken),
        Beast(box: CGRect(x: 238, y: 1262, width: 96, height: 110), draw: ship),
    ]

    private static let gold = Theme.gold, ink = Color(red: 0.118, green: 0.078, blue: 0.055)
    private static let red = [Color(hex: 0xE45A3A), Color(hex: 0xB0341F), Color(hex: 0x6A190D)], belly = [Color(hex: 0xF8E0AA), Color(hex: 0xD8A05C)]
    private static let horn = [Color(hex: 0xF7EEDB), Color(hex: 0xC7AB80)], verd = [Color(hex: 0x63B199), Color(hex: 0x2C6F5E), Color(hex: 0x143A31)]
    private static let jade = [Color(hex: 0xE2F2E8), Color(hex: 0x9CCAB4)], fin = [Color(hex: 0xD9583A), Color(hex: 0x8E2416)]
    private static let copper = [Color(hex: 0xEAB274), Color(hex: 0xB5823F), Color(hex: 0x6A401D)], sand = [Color(hex: 0xF6E3C0), Color(hex: 0xD9B07A)]

    // MARK: Craft

    struct S { var x: CGFloat; var y: CGFloat; var u: CGFloat; var nx: CGFloat; var ny: CGFloat; var p: CGPoint { CGPoint(x: x, y: y) } }
    typealias Seg = (CGPoint, CGPoint, CGPoint, CGPoint)

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func bez(_ s: Seg, _ t: CGFloat) -> CGPoint {
        let u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return pt(a * s.0.x + b * s.1.x + c * s.2.x + d * s.3.x, a * s.0.y + b * s.1.y + c * s.2.y + d * s.3.y)
    }
    static func spine(_ segs: [Seg], _ steps: Int = 28) -> [S] {
        var P: [CGPoint] = []
        for (i, s) in segs.enumerated() { for k in (i == 0 ? 0 : 1)...steps { P.append(bez(s, CGFloat(k) / CGFloat(steps))) } }
        var L: [CGFloat] = [0]
        for i in 1..<P.count { L.append(L[i - 1] + hypot(P[i].x - P[i - 1].x, P[i].y - P[i - 1].y)) }
        return P.indices.map { i in
            let a = P[max(0, i - 1)], b = P[min(P.count - 1, i + 1)], dx = b.x - a.x, dy = b.y - a.y, d = max(hypot(dx, dy), 0.0001)
            return S(x: P[i].x, y: P[i].y, u: L[i] / L[L.count - 1], nx: -dy / d, ny: dx / d)
        }
    }
    static func tube(_ s: [S], _ w: (CGFloat) -> CGFloat) -> Path {
        Path(polygon: s.map { pt($0.x + $0.nx * w($0.u), $0.y + $0.ny * w($0.u)) } + s.reversed().map { pt($0.x - $0.nx * w($0.u), $0.y - $0.ny * w($0.u)) })
    }
    private static func lin(_ colors: [Color], _ a: CGPoint, _ b: CGPoint) -> GraphicsContext.Shading { .linearGradient(Gradient(colors: colors), startPoint: a, endPoint: b) }
    private static func lift(_ ctx: inout GraphicsContext, _ p: Path) {
        ctx.drawLayer { l in l.addFilter(.shadow(color: Color(red: 0.2, green: 0.125, blue: 0.047).opacity(0.45), radius: 3.5, x: 0, y: 3.5)); l.fill(p, with: .color(Color(hex: 0x5A3A22))) }
    }
    static func wire(_ ctx: inout GraphicsContext, _ p: Path, _ w: CGFloat = 1.4) {
        ctx.stroke(p, with: .color(ink.opacity(0.92)), style: StrokeStyle(lineWidth: w + 1.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(gold), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(Color(red: 1, green: 0.965, blue: 0.86).opacity(0.6)), style: StrokeStyle(lineWidth: w * 0.35, lineCap: .round, lineJoin: .round))
    }
    private static func gloss(_ ctx: inout GraphicsContext, _ p: Path, _ c: CGPoint, _ r: CGFloat, _ a: Double = 0.4) {
        ctx.drawLayer { l in
            l.clip(to: p)
            l.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.91).opacity(a), .clear]), center: c, startRadius: 0, endRadius: r))
        }
    }
    private static func jewel(_ ctx: inout GraphicsContext, _ p: Path, _ fill: GraphicsContext.Shading, _ w: CGFloat = 1.3) { lift(&ctx, p); ctx.fill(p, with: fill); wire(&ctx, p, w) }
    private static func scales(_ ctx: inout GraphicsContext, _ s: [S], _ w: (CGFloat) -> CGFloat, _ from: CGFloat, _ to: CGFloat, _ color: Color, _ size: CGFloat = 3.1) {
        let part = s.filter { $0.u >= from && $0.u <= to }
        guard part.count > 1 else { return }
        var arcs = Path()
        for (i, p) in part.enumerated() where i % 2 == 0 {
            let ww = w(p.u), a = atan2(-p.nx, p.ny), off: CGFloat = (i / 2) % 2 == 1 ? size : 0
            var o = -ww + off
            while o <= ww {
                let c = pt(p.x + p.nx * o, p.y + p.ny * o)
                arcs.move(to: pt(c.x + cos(a - .pi / 2) * size, c.y + sin(a - .pi / 2) * size))
                arcs.addArc(center: c, radius: size, startAngle: .radians(a - .pi / 2), endAngle: .radians(a + .pi / 2), clockwise: false)
                o += size * 2
            }
        }
        ctx.drawLayer { l in l.clip(to: tube(part, w)); l.stroke(arcs, with: .color(color), lineWidth: 0.7) }
    }
    @discardableResult
    private static func band(_ ctx: inout GraphicsContext, _ s: [S], _ w: @escaping (CGFloat) -> CGFloat, _ from: CGFloat, _ to: CGFloat, side: CGFloat, frac: CGFloat,
                             _ fill: GraphicsContext.Shading, every: Int = 0, line: Color = .clear) -> [(S, CGFloat)] {
        let part = s.filter { $0.u >= from && $0.u <= to }
        guard part.count > 1 else { return [] }
        let fade = { (u: CGFloat) in max(0, min(1, (u - from) * 22, (to - u) * 22)) }
        let off = part.map { p -> S in let d = w(p.u) * (1 - frac / 2) * side * 0.97; return S(x: p.x + p.nx * d, y: p.y + p.ny * d, u: p.u, nx: p.nx, ny: p.ny) }
        let bw = { (u: CGFloat) in w(u) * frac / 2 * fade(u) }
        ctx.fill(tube(off, bw), with: fill)
        if every > 0 {
            var plates = Path()
            for (i, p) in off.enumerated() where i % every == 0 { let b = bw(p.u); plates.move(to: pt(p.x + p.nx * b, p.y + p.ny * b)); plates.addLine(to: pt(p.x - p.nx * b, p.y - p.ny * b)) }
            ctx.stroke(plates, with: .color(line), lineWidth: 0.9)
        }
        return off.map { ($0, bw($0.u)) }
    }
    private static func crestFin(_ ctx: inout GraphicsContext, _ s: [S], _ w: (CGFloat) -> CGFloat, _ from: CGFloat, _ to: CGFloat, _ h: CGFloat, _ t: Double, every: Int = 4) {
        let pts = s.enumerated().filter { $0.element.u >= from && $0.element.u <= to && $0.offset % every == 0 }.map(\.element)
        guard pts.count > 1 else { return }
        let base = pts.map { pt($0.x - $0.nx * w($0.u) * 0.55, $0.y - $0.ny * w($0.u) * 0.55) }
        let tips = pts.enumerated().map { i, p -> CGPoint in
            let k = h * (0.65 + 0.35 * sin(CGFloat(i) / CGFloat(pts.count - 1) * .pi)) + CGFloat(sin(t * 2.2 + Double(i) * 0.9)) * 1.2
            return pt(p.x - p.nx * (w(p.u) + k), p.y - p.ny * (w(p.u) + k))
        }
        var m = Path(); m.move(to: base[0]); m.addLine(to: tips[0])
        for i in 1..<tips.count {
            let a = tips[i - 1], b = tips[i], mid = pt((a.x + b.x) / 2, (a.y + b.y) / 2), bm = pt((base[i - 1].x + base[i].x) / 2, (base[i - 1].y + base[i].y) / 2)
            m.addQuadCurve(to: b, control: pt(mid.x + (bm.x - mid.x) * 0.35, mid.y + (bm.y - mid.y) * 0.35))
        }
        m.addLine(to: base[base.count - 1]); for p in base.reversed().dropFirst() { m.addLine(to: p) }; m.closeSubpath()
        lift(&ctx, m)
        ctx.fill(m, with: lin(fin, pt(0, tips.map(\.y).min() ?? 0), pt(0, base.map(\.y).max() ?? 0))); wire(&ctx, m, 0.9)
        for (i, tp) in tips.enumerated() { var r = Path(); r.move(to: base[i]); r.addLine(to: tp); wire(&ctx, r, 0.7) }
    }
    private static func spikes(_ ctx: inout GraphicsContext, _ s: [S], _ w: (CGFloat) -> CGFloat, every: Int, from: CGFloat, to: CGFloat, len: CGFloat) {
        for (i, p) in s.enumerated() where i % every == 0 && p.u >= from && p.u <= to {
            let ww = w(p.u), tx = p.ny, ty = -p.nx, b = pt(p.x - p.nx * ww * 0.5, p.y - p.ny * ww * 0.5), k = len * (1 - abs(p.u - 0.35))
            let tip = pt(p.x - p.nx * (ww + k) - tx * 5, p.y - p.ny * (ww + k) - ty * 5)
            var sp = Path(); sp.move(to: pt(b.x + tx * 5, b.y + ty * 5)); sp.addQuadCurve(to: tip, control: pt(p.x - p.nx * (ww + k * 0.6), p.y - p.ny * (ww + k * 0.6)))
            sp.addLine(to: pt(b.x - tx * 5, b.y - ty * 5)); sp.closeSubpath()
            ctx.fill(sp, with: lin(horn, b, tip)); ctx.stroke(sp, with: .color(ink.opacity(0.85)), lineWidth: 0.9)
        }
    }
    private static func eye(_ ctx: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ t: Double, _ seed: Double) {
        let open: CGFloat = (t + seed).truncatingRemainder(dividingBy: 5.7) < 0.14 ? 0.12 : 1
        var e = ctx; e.translateBy(x: c.x, y: c.y); e.scaleBy(x: s, y: s * open)
        var almond = Path(); almond.move(to: pt(-6, 0)); almond.addQuadCurve(to: pt(6, 0), control: pt(0, -5.5)); almond.addQuadCurve(to: pt(-6, 0), control: pt(0, 4.5)); almond.closeSubpath()
        e.fill(almond, with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6C8), Color(hex: 0xF2C25E), Color(hex: 0xA8701F)]), center: pt(-1, -1), startRadius: 0, endRadius: 7))
        e.fill(Path(ellipseIn: CGRect(x: -0.35, y: -3.6, width: 1.9, height: 7.2)), with: .color(Color(hex: 0x1C120C)))
        e.fill(Path(ellipseIn: CGRect(x: -3.1, y: -2.5, width: 1.8, height: 1.8)), with: .color(.white.opacity(0.85)))
        e.stroke(almond, with: .color(Color(hex: 0x1C120C)), lineWidth: 0.9)
    }

    // MARK: Heads and fire

    private static func head(_ ctx: inout GraphicsContext, _ t: Double, dragon: Bool) {
        let pal = dragon ? red : verd, sway = CGFloat(sin(t * 1.3))
        if dragon {
            for h in [[pt(-6, -15), pt(6, -27), pt(24, -31), pt(8, -22), pt(1, -12)], [pt(-20, -18), pt(-12, -33), pt(12, -41), pt(-4, -30), pt(-9, -16)]] {
                var p = Path(); p.move(to: h[0]); p.addQuadCurve(to: h[2], control: h[1]); p.addQuadCurve(to: h[4], control: h[3]); p.closeSubpath()
                jewel(&ctx, p, lin(horn, pt(-10, -40), pt(20, -14)), 0.8)
                ctx.drawLayer { l in l.clip(to: p); var rings = Path(); for i in 1..<4 { let c = pt(h[0].x + CGFloat(i) * 6, h[0].y - CGFloat(i) * 5); rings.addEllipse(in: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)) }; l.stroke(rings, with: .color(Color(red: 0.59, green: 0.47, blue: 0.31).opacity(0.55)), lineWidth: 0.6) }
            }
        } else {
            var f = Path(); f.move(to: pt(-14, -16)); f.addLine(to: pt(-2, -36)); f.addQuadCurve(to: pt(10, -34), control: pt(4, -28)); f.addQuadCurve(to: pt(20, -26), control: pt(12, -24))
            f.addQuadCurve(to: pt(6, -10), control: pt(16, -16)); f.closeSubpath()
            jewel(&ctx, f, lin(fin, pt(0, -36), pt(0, -10)), 0.8)
            for tip in [pt(-2, -36), pt(10, -34), pt(20, -26)] { var r = Path(); r.move(to: pt(-6, -13)); r.addLine(to: tip); wire(&ctx, r, 0.6) }
        }
        let fr = [pt(17, -15), pt(21, -3), pt(15, 9)]
        var frill = Path(); frill.move(to: pt(2, -9)); frill.addLine(to: fr[0]); frill.addQuadCurve(to: fr[1], control: pt(10, -6)); frill.addQuadCurve(to: fr[2], control: pt(9, 3)); frill.addLine(to: pt(2, 8)); frill.closeSubpath()
        jewel(&ctx, frill, lin(fin, pt(0, -15), pt(0, 9)), 0.7)
        for q in fr { var r = Path(); r.move(to: pt(3, 0)); r.addLine(to: q); wire(&ctx, r, 0.55) }
        var jaw = Path(); jaw.move(to: pt(-24, 3)); jaw.addLine(to: pt(-40, 8)); jaw.addQuadCurve(to: pt(-58, 17), control: pt(-54, 12)); jaw.addQuadCurve(to: pt(-40, 19), control: pt(-52, 21))
        jaw.addQuadCurve(to: pt(-2, 12), control: pt(-20, 18)); jaw.addLine(to: pt(6, 8)); jaw.closeSubpath()
        ctx.fill(Path(polygon: [pt(-24, 3), pt(-50, 1), pt(-57, 15), pt(-40, 8)]), with: .color(Color(hex: 0x3A0D08)))
        var tongue = Path(); tongue.move(to: pt(-28, 6)); tongue.addQuadCurve(to: pt(-50, 8), control: pt(-42, 10 + sway))
        ctx.stroke(tongue, with: .color(Color(hex: 0xD65A4A)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        var teeth = Path()
        for x in [-52.0, -46, -40, -34] { teeth.addLines([pt(x - 1.6, 1), pt(x, 5.5), pt(x + 1.6, 1.4)]); teeth.closeSubpath() }
        for x in [-52.0, -46, -40] { let y = 12 + (x + 52) * -0.3; teeth.addLines([pt(x - 1.5, y + 2), pt(x, y - 3), pt(x + 1.5, y + 2)]); teeth.closeSubpath() }
        ctx.fill(teeth, with: .color(horn[0])); ctx.stroke(teeth, with: .color(ink.opacity(0.8)), lineWidth: 0.5)
        jewel(&ctx, jaw, lin([pal[1], pal[2]], pt(0, 3), pt(0, 21)), 1)
        var top = Path(); top.move(to: pt(8, -8)); top.addQuadCurve(to: pt(-12, -21), control: pt(4, -19)); top.addQuadCurve(to: pt(-34, -18), control: pt(-24, -26))
        top.addQuadCurve(to: pt(-60, -8), control: pt(-48, -14)); top.addQuadCurve(to: pt(-62, 0), control: pt(-67, -4)); top.addLine(to: pt(-48, 1)); top.addLine(to: pt(-26, 3))
        top.addQuadCurve(to: pt(8, 8), control: pt(-8, 10)); top.closeSubpath()
        jewel(&ctx, top, lin(pal, pt(0, -24), pt(0, 8)), 1.1)
        ctx.drawLayer { l in
            l.clip(to: top)
            var arcs = Path()
            for r in 0..<3 { for x in stride(from: -20.0 + Double(r) * 3, to: 6, by: 6) { let c = pt(x, -10 + CGFloat(r) * 5); arcs.move(to: pt(c.x + 3 * cos(.pi * 0.1), c.y + 3 * sin(.pi * 0.1))); arcs.addArc(center: pt(x, -10 + CGFloat(r) * 5), radius: 3, startAngle: .radians(.pi * 0.1), endAngle: .radians(.pi * 0.9), clockwise: false) } }
            l.stroke(arcs, with: .color(Color(red: 1, green: 0.87, blue: 0.63).opacity(0.38)), lineWidth: 0.7)
        }
        gloss(&ctx, top, pt(-36, -16), 22, 0.38)
        var brow = Path(); brow.move(to: pt(-40, -15)); brow.addQuadCurve(to: pt(-21, -16), control: pt(-31, -21)); wire(&ctx, brow, 1)
        eye(&ctx, pt(-30, -10), 1, t, dragon ? 0 : 2.4)
        var nostril = Path(); nostril.move(to: pt(-60, -6)); nostril.addQuadCurve(to: pt(-55, -5), control: pt(-57, -7.5))
        ctx.stroke(nostril, with: .color(Color(hex: 0x1C120C)), lineWidth: 1)
        if !dragon {
            for (i, b) in [(pt(-58, -2), CGFloat(1)), (pt(-56, 2), -1)].enumerated() {
                var w = Path(); w.move(to: b.0)
                w.addCurve(to: pt(b.0.x + 30 + CGFloat(i) * 6, b.0.y + 18 + sway * 5 * b.1), control1: pt(b.0.x - 4, b.0.y + 12 + sway * 3 * b.1), control2: pt(b.0.x + 14, b.0.y + 20 + sway * 4))
                wire(&ctx, w, 0.8)
            }
        }
    }

    private static func fire(_ ctx: inout GraphicsContext, _ t: Double) {
        var g = ctx; g.translateBy(x: -60, y: 10); g.rotate(by: .radians(0.2))
        let L = 62 + CGFloat(sin(t * 6.3)) * 5 + CGFloat(sin(t * 10.1)) * 3
        for (n, layer) in [(1.0, Color(red: 0.84, green: 0.25, blue: 0.12)), (0.74, Color(red: 0.95, green: 0.59, blue: 0.27)), (0.46, Color(red: 1, green: 0.925, blue: 0.67))].enumerated() {
            let len = L * layer.0, wd = 12 * layer.0 + 2
            var top: [CGPoint] = [pt(0, -wd * 0.4)], bottom: [CGPoint] = []
            for i in 1...7 { let u = CGFloat(i) / 7; top.append(pt(-len * u, -wd * (1 - u) + CGFloat(sin(t * 8.7 + Double(i) * 1.7 + Double(n))) * 2.4 * u)) }
            for i in (1...7).reversed() { let u = CGFloat(i) / 7; bottom.append(pt(-len * u, wd * (1 - u) + CGFloat(sin(t * 7.9 + Double(i) * 2.1 + Double(n))) * 2.4 * u)) }
            g.fill(Path(polygon: top + bottom + [pt(0, wd * 0.4)]), with: .linearGradient(Gradient(colors: [layer.1, layer.1.opacity(0.9), layer.1.opacity(0)]), startPoint: .zero, endPoint: pt(-len, 0)))
        }
        for i in 0..<5 {
            let ph = CGFloat((t * 0.7 + Double(i) / 5).truncatingRemainder(dividingBy: 1)), x = -L * (0.45 + ph * 0.75), y = CGFloat(sin(Double(i) * 2.3 + t * 2.5)) * 9 * ph - ph * 8, r = 1.5 * (1 - ph) + 0.4
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color(red: 1, green: 0.8, blue: 0.47).opacity(Double(1 - ph) * 0.9)))
        }
    }

    // MARK: The dragon

    private static func wing(_ ctx: inout GraphicsContext, shoulder sh: CGPoint, angle: Double, elbow el: CGPoint, wrist wr: CGPoint, tips: [CGPoint], back: CGPoint, far: Bool) {
        var g = ctx; g.translateBy(x: sh.x, y: sh.y); g.rotate(by: .radians(angle)); g.translateBy(x: -sh.x, y: -sh.y)
        func pull(_ p: CGPoint, _ q: CGPoint, _ k: CGFloat) -> CGPoint { let m = pt((p.x + q.x) / 2, (p.y + q.y) / 2); return pt(m.x + (wr.x - m.x) * k, m.y + (wr.y - m.y) * k) }
        var m = Path(); m.move(to: sh); m.addLine(to: el); m.addLine(to: wr); m.addLine(to: tips[0])
        for i in 1..<tips.count { m.addQuadCurve(to: tips[i], control: pull(tips[i - 1], tips[i], 0.3)) }
        m.addQuadCurve(to: back, control: pull(tips[tips.count - 1], back, 0.22)); m.closeSubpath()
        lift(&g, m)
        let stops = far ? [Color(hex: 0x9D3020), Color(hex: 0x6A190D), Color(hex: 0x3A0D07)] : [Color(hex: 0xCF4A2E), Color(hex: 0x8F2516), Color(hex: 0x4C1109)]
        g.fill(m, with: .radialGradient(Gradient(colors: stops), center: wr, startRadius: 8, endRadius: 200))
        g.drawLayer { l in
            l.clip(to: m)
            var veins = Path()
            for i in 1..<tips.count { for k in [0.35, 0.65] as [CGFloat] { let p = tips[i - 1], q = tips[i], x = p.x + (q.x - p.x) * k, y = p.y + (q.y - p.y) * k; veins.move(to: wr); veins.addQuadCurve(to: pt(x, y), control: pt((wr.x + x) / 2 + 6, (wr.y + y) / 2)) } }
            l.stroke(veins, with: .color(Color(red: 1, green: 0.77, blue: 0.59).opacity(0.3)), lineWidth: 0.9)
        }
        wire(&g, m, 0.9)
        var arm = Path(); arm.move(to: sh); arm.addLine(to: el); arm.addLine(to: wr); wire(&g, arm, 2.5)
        for tp in tips { var f = Path(); f.move(to: wr); f.addLine(to: tp); wire(&g, f, 1.4) }
        let side: CGFloat = wr.x > el.x ? 1 : -1
        var claw = Path(); claw.move(to: pt(wr.x - side * 2, wr.y + 1)); claw.addQuadCurve(to: pt(wr.x + side * 9, wr.y - 13), control: pt(wr.x + side * 2, wr.y - 12)); claw.addLine(to: pt(wr.x + side * 3, wr.y - 2)); claw.closeSubpath()
        jewel(&g, claw, .color(horn[0]), 0.6)
    }
    private static func talons(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat) {
        for k: CGFloat in [-5, 0, 5] {
            var c = Path(); c.move(to: pt(x + k - 2, y - 2)); c.addQuadCurve(to: pt(x + k - 8, y + 5), control: pt(x + k - 4, y + 4)); c.addLine(to: pt(x + k + 1, y)); c.closeSubpath()
            ctx.fill(c, with: .color(horn[0])); ctx.stroke(c, with: .color(ink.opacity(0.85)), lineWidth: 0.7)
        }
    }
    private static func leg(_ ctx: inout GraphicsContext, _ seg: Seg, _ w0: CGFloat, _ w1: CGFloat) {
        let s = spine([seg], 16), w = { (u: CGFloat) in w0 + (w1 - w0) * u }, p = tube(s, w)
        jewel(&ctx, p, lin(red, pt(0, seg.0.y), pt(0, seg.3.y)), 1)
        scales(&ctx, s, w, 0.05, 0.95, Color(red: 1, green: 0.84, blue: 0.59).opacity(0.35), 2.4)
    }

    static func dragon(_ ctx: inout GraphicsContext, _ t: Double) {
        var g = ctx; g.translateBy(x: 800, y: 252); g.scaleBy(x: 0.82, y: 0.82)
        let flap = sin(t * 1.5), breath = CGFloat(sin(t * 1.5 + 0.7)), sway = CGFloat(sin(t * 0.95))
        var rock = Path(); rock.move(to: pt(-96, 46)); rock.addQuadCurve(to: pt(-22, 22), control: pt(-64, 12)); rock.addQuadCurve(to: pt(80, 22), control: pt(18, 4))
        rock.addQuadCurve(to: pt(134, 46), control: pt(114, 28)); rock.closeSubpath()
        g.fill(rock, with: ChartPainter.skinFill); g.fill(rock, with: .color(ChartPainter.umber.opacity(0.32))); g.stroke(rock, with: .color(ChartPainter.ink), lineWidth: 1.3)
        var hatch = Path(); for i in 0..<6 { let x = 10 + CGFloat(i) * 14; hatch.move(to: pt(x, 18 + CGFloat(i))); hatch.addLine(to: pt(x + 10, 40)) }
        g.stroke(hatch, with: .color(ChartPainter.ink), lineWidth: 0.7)
        wing(&g, shoulder: pt(-14, -30), angle: flap * 0.07, elbow: pt(26, -104), wrist: pt(70, -156), tips: [pt(158, -132), pt(152, -92), pt(124, -62), pt(90, -44)], back: pt(6, -14), far: true)
        wing(&g, shoulder: pt(-46, -40), angle: -flap * 0.07, elbow: pt(-46, -116), wrist: pt(-86, -166), tips: [pt(-168, -146), pt(-162, -104), pt(-136, -74), pt(-100, -52)], back: pt(-48, -22), far: false)
        let hy = breath * 2.2, tx = sway * 3, ty = sway * 5
        let s = spine([(pt(-78, -108 + hy), pt(-62 + breath, -80 + hy), pt(-72, -44), pt(-34, -20)), (pt(-34, -20), pt(0, breath * 0.8), pt(36, 4), pt(60, -6)),
                       (pt(60, -6), pt(92, -18), pt(122, 18 + sway * 2), pt(158, 2 + sway * 3)), (pt(158, 2 + sway * 3), pt(190, -14 + sway * 4), pt(182 + tx * 0.6, -60 + ty), pt(152 + tx, -58 + ty)),
                       (pt(152 + tx, -58 + ty), pt(132 + tx, -56 + ty), pt(134 + tx, -38 + ty), pt(147 + tx, -40 + ty))], 30)
        let w = { (u: CGFloat) -> CGFloat in u < 0.2 ? 10 + 14 * (u / 0.2) : u < 0.42 ? 24 : 1.3 + 22.7 * pow(1 - (u - 0.42) / 0.58, 1.25) }
        leg(&g, (pt(56, 4), pt(64, 14), pt(64, 22), pt(60, 31)), 7, 4.5); talons(&g, 60, 31)
        spikes(&g, s, w, every: 5, from: 0.03, to: 0.8, len: 11)
        let body = tube(s, w)
        lift(&g, body); g.fill(body, with: lin(red, pt(0, -100), pt(0, 30)))
        scales(&g, s, w, 0.02, 0.93, Color(red: 1, green: 0.84, blue: 0.59).opacity(0.4))
        band(&g, s, w, 0.015, 0.62, side: 1, frac: 0.66, lin(belly, pt(0, -80), pt(0, 30)), every: 3, line: Color(red: 0.59, green: 0.33, blue: 0.125).opacity(0.75))
        gloss(&g, body, pt(-40, -70), 70, 0.28); wire(&g, body, 1.2)
        let tip = s[s.count - 1]
        var tail = g; tail.translateBy(x: tip.x, y: tip.y); tail.rotate(by: .radians(atan2(Double(tip.ny), Double(tip.nx)) + .pi))
        var spade = Path(); spade.move(to: .zero); spade.addQuadCurve(to: pt(16, 0), control: pt(4, -9)); spade.addQuadCurve(to: .zero, control: pt(4, 9)); spade.closeSubpath()
        jewel(&tail, spade, lin([gold, Color(hex: 0xA87A3A)], pt(0, -9), pt(16, 9)), 0.8)
        var thigh = Path(); thigh.move(to: pt(28, -10)); thigh.addQuadCurve(to: pt(62, -8), control: pt(46, -22)); thigh.addQuadCurve(to: pt(52, 10), control: pt(66, 8)); thigh.addQuadCurve(to: pt(28, -10), control: pt(36, 8)); thigh.closeSubpath()
        jewel(&g, thigh, lin(red, pt(0, -20), pt(0, 10)), 1.1); gloss(&g, thigh, pt(44, -12), 14, 0.32)
        leg(&g, (pt(48, 6), pt(56, 16), pt(58, 24), pt(54, 31)), 8.5, 5.2); talons(&g, 54, 31)
        var arm = Path(); arm.move(to: pt(-46, -14)); arm.addQuadCurve(to: pt(-26, -4), control: pt(-30, -18)); arm.addQuadCurve(to: pt(-40, 4), control: pt(-30, 6)); arm.addQuadCurve(to: pt(-46, -14), control: pt(-48, -2)); arm.closeSubpath()
        jewel(&g, arm, lin(red, pt(0, -16), pt(0, 6)), 1)
        leg(&g, (pt(-38, 2), pt(-46, 10), pt(-48, 18), pt(-44, 28)), 7.5, 4.6); talons(&g, -44, 28)
        var h = g; h.translateBy(x: -78, y: -108 + hy); h.rotate(by: .radians(-0.12 + Double(breath) * 0.035)); h.scaleBy(x: 1.32, y: 1.32)
        fire(&h, t); head(&h, t, dragon: true)
    }

    // MARK: The sea

    private static func foam(_ ctx: inout GraphicsContext, _ t: Double, _ list: [(CGFloat, CGFloat)], _ y: CGFloat) {
        for (i, (x, w)) in list.enumerated() {
            for k in 0..<2 {
                let ph = CGFloat((t * 0.32 + Double(k) * 0.5 + Double(i) * 0.21).truncatingRemainder(dividingBy: 1)), r = w + ph * 24
                ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: y + 5 - r * 0.22, width: r * 2, height: r * 0.44)), with: .color(ChartPainter.water.opacity(Double(1 - ph) * 0.55)), lineWidth: 1)
            }
            let bob = CGFloat(sin(t * 1.6 + Double(i))) * 0.8
            for (dx, dir) in [(-w - 3, CGFloat(1)), (w + 3, -1)] {
                let cx = x + dx, cy = y + 2 + bob
                var p = Path(); p.move(to: pt(cx - 7 * dir, cy + 3)); p.addQuadCurve(to: pt(cx + dir, cy - 5), control: pt(cx - 5 * dir, cy - 5)); p.addQuadCurve(to: pt(cx + 4 * dir, cy - 1.5), control: pt(cx + 5 * dir, cy - 5))
                p.addQuadCurve(to: pt(cx, cy), control: pt(cx + dir, cy - 3)); p.addQuadCurve(to: pt(cx + 8 * dir, cy + 3), control: pt(cx + 3 * dir, cy + 3)); p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: 0xF3ECD8))); ctx.stroke(p, with: .color(ChartPainter.ink.opacity(0.75)), lineWidth: 0.8)
            }
        }
    }

    static func serpent(_ ctx: inout GraphicsContext, _ t: Double) {
        let water: CGFloat = 1170
        var g = ctx; g.clip(to: Path(CGRect(x: 0, y: 0, width: SeaChart.size.width, height: water)))
        let ts = CGFloat(sin(t * 1.15))
        let tail = spine([(pt(924, water + 8), pt(926, 1142), pt(944 + ts * 3, 1134), pt(950 + ts * 6, 1116))], 22), wt = { (u: CGFloat) in 8 - u * 5.6 }
        let tp = tail[tail.count - 1]
        var fl = g; fl.translateBy(x: tp.x, y: tp.y); fl.rotate(by: .radians(atan2(Double(tp.ny), Double(tp.nx)) + .pi / 2 + Double(ts) * 0.12))
        var fluke = Path(); fluke.move(to: pt(0, 2)); fluke.addQuadCurve(to: pt(-16, -22), control: pt(-20, -6)); fluke.addQuadCurve(to: pt(0, -8), control: pt(-8, -12))
        fluke.addQuadCurve(to: pt(16, -22), control: pt(8, -12)); fluke.addQuadCurve(to: pt(0, 2), control: pt(20, -6)); fluke.closeSubpath()
        jewel(&fl, fluke, lin(fin, pt(0, -22), pt(0, 2)), 0.9)
        for q in [pt(-14, -19), pt(-6, -12), pt(6, -12), pt(14, -19)] { var r = Path(); r.move(to: .zero); r.addLine(to: q); wire(&fl, r, 0.6) }
        jewel(&g, tube(tail, wt), lin(verd, pt(0, 1110), pt(0, water)), 1)
        scales(&g, tail, wt, 0.02, 0.98, Color(red: 0.9, green: 0.84, blue: 0.59).opacity(0.38), 2.6)
        for (x, i) in [(CGFloat(688), 0), (770, 1), (850, 2)] {
            let a = 46 - CGFloat(i) * 5 + CGFloat(sin(t * 1.35 - Double(i) * 1.15)) * 5
            let s = spine([(pt(x, water + 8), pt(x + 2, water - a), pt(x + 58, water - a), pt(x + 60, water + 8))], 26), w = { (_: CGFloat) in 10.5 - CGFloat(i) }
            crestFin(&g, s, w, 0.14, 0.86, 10 - CGFloat(i), t + Double(i))
            let body = tube(s, w)
            lift(&g, body); g.fill(body, with: lin(verd, pt(0, water - a - 10), pt(0, water)))
            scales(&g, s, w, 0, 1, Color(red: 0.9, green: 0.84, blue: 0.59).opacity(0.4), 2.8)
            band(&g, s, w, 0.02, 0.98, side: 1, frac: 0.55, lin(jade, pt(0, water - a), pt(0, water)), every: 3, line: Color(red: 0.235, green: 0.43, blue: 0.35).opacity(0.6))
            gloss(&g, body, pt(x + 22, water - a - 4), 22, 0.35); wire(&g, body, 1.1)
        }
        let sx = CGFloat(sin(t * 1.25)) * 3, sy = CGFloat(sin(t * 1.25 + 1.1)) * 2.2
        let n = spine([(pt(648, water + 8), pt(644, 1136), pt(626 + sx * 0.5, 1114 + sy), pt(604 + sx, 1108 + sy))], 26), wn = { (u: CGFloat) in 10.5 - u * 2.4 }
        crestFin(&g, n, wn, 0.2, 0.92, 11, t + 3)
        let neck = tube(n, wn)
        lift(&g, neck); g.fill(neck, with: lin(verd, pt(0, 1100), pt(0, water)))
        scales(&g, n, wn, 0, 1, Color(red: 0.9, green: 0.84, blue: 0.59).opacity(0.4), 2.8)
        band(&g, n, wn, 0.02, 0.98, side: 1, frac: 0.55, lin(jade, pt(0, 1100), pt(0, water)), every: 3, line: Color(red: 0.235, green: 0.43, blue: 0.35).opacity(0.6))
        wire(&g, neck, 1.1)
        var h = g; h.translateBy(x: 604 + sx, y: 1108 + sy); h.rotate(by: .radians(sin(t * 1.25 + 0.4) * 0.05)); h.scaleBy(x: 0.68, y: 0.68)
        head(&h, t, dragon: false)
        foam(&ctx, t, [(648, 11), (689, 9), (747, 9), (771, 8), (829, 8), (851, 7), (909, 7), (925, 8)], water)
    }

    private static func tentacle(_ ctx: inout GraphicsContext, _ t: Double, base: CGPoint, c1: CGPoint, c2: CGPoint, tip: CGPoint, curl: [CGPoint]?, phase: Double, width tw: CGFloat, back: Bool, water: CGFloat) {
        let s = CGFloat(sin(t * 1.05 + phase)), c = CGFloat(cos(t * 0.9 + phase))
        let tp = pt(tip.x + s * 8, tip.y + c * 3)
        var segs: [Seg] = [(base, pt(c1.x + s * 3, c1.y), pt(c2.x + s * 6, c2.y + c * 2), tp)]
        if let curl { segs.append((tp, pt(curl[0].x + s * 9, curl[0].y + c * 3), pt(curl[1].x + s * 10, curl[1].y + c * 4), pt(curl[2].x + s * 10, curl[2].y + c * 4))) }
        let sp = spine(segs, 24), w = { (u: CGFloat) in tw * (1 - u * 0.86) + 1 }, p = tube(sp, w)
        lift(&ctx, p)
        ctx.fill(p, with: lin(back ? [Color(hex: 0xC98F55), Color(hex: 0x91602C), Color(hex: 0x523015)] : copper, pt(0, 1490), pt(0, water)))
        ctx.drawLayer { l in
            l.clip(to: p)
            var ridges = Path(), spots = Path()
            for (i, q) in sp.enumerated() {
                let ww = w(q.u)
                if i % 3 == 0 { ridges.move(to: pt(q.x + q.nx * ww * 0.1, q.y + q.ny * ww * 0.1)); ridges.addQuadCurve(to: pt(q.x + q.nx * ww, q.y + q.ny * ww), control: pt(q.x + q.nx * ww * 0.6 + q.ny * 2, q.y + q.ny * ww * 0.6 - q.nx * 2)) }
                if i % 7 == 0 && q.u <= 0.85 { let c = pt(q.x + q.nx * ww * 0.45, q.y + q.ny * ww * 0.45); spots.addEllipse(in: CGRect(x: c.x - ww * 0.22, y: c.y - ww * 0.16, width: ww * 0.44, height: ww * 0.32)) }
            }
            l.stroke(ridges, with: .color(Color(red: 0.35, green: 0.2, blue: 0.086).opacity(0.45)), lineWidth: 0.8)
            l.fill(spots, with: .color(Color(red: 0.376, green: 0.2, blue: 0.078).opacity(0.35)))
        }
        let suck = band(&ctx, sp, w, 0.06, 0.94, side: -1, frac: 0.66, lin(sand, pt(0, 1490), pt(0, water)))
        var rims = Path(), cups = Path()
        for (i, (q, b)) in suck.enumerated() where i % 3 == 0 && b >= 1.4 {
            rims.addEllipse(in: CGRect(x: q.x - b * 0.78, y: q.y - b * 0.78, width: b * 1.56, height: b * 1.56))
            cups.addEllipse(in: CGRect(x: q.x - b * 0.22, y: q.y - b * 0.22, width: b * 0.44, height: b * 0.44))
        }
        ctx.fill(rims, with: .color(Color(hex: 0xFBF3E2))); ctx.stroke(rims, with: .color(Color(hex: 0xA87A3A)), lineWidth: 0.7)
        ctx.fill(cups, with: .color(Color(red: 0.47, green: 0.27, blue: 0.12).opacity(0.6)))
        gloss(&ctx, p, pt(tp.x - 4, tp.y + 10), 18, 0.3); wire(&ctx, p, 1)
    }

    static func kraken(_ ctx: inout GraphicsContext, _ t: Double) {
        let water: CGFloat = 1600, bob = CGFloat(sin(t * 0.85)) * 1.6
        var g = ctx; g.clip(to: Path(CGRect(x: 0, y: 0, width: SeaChart.size.width, height: water)))
        tentacle(&g, t, base: pt(876, water + 8), c1: pt(880, 1574), c2: pt(906, 1560), tip: pt(902, 1536), curl: [pt(900, 1522), pt(886, 1524), pt(890, 1534)], phase: 3.1, width: 10, back: true, water: water)
        let dome = Path(ellipseIn: CGRect(x: 856, y: water + 12 + bob - 32, width: 92, height: 64))
        lift(&g, dome); g.fill(dome, with: lin(copper, pt(0, water - 22), pt(0, water + 10)))
        g.drawLayer { l in
            l.clip(to: dome)
            var spots = Path()
            for (x, dy, r) in [(878.0, -6.0, 5.0), (930, -10, 4), (904, -18, 3.5), (918, -2, 3)] { spots.addEllipse(in: CGRect(x: x - r * 1.4, y: water + dy + bob - r, width: r * 2.8, height: r * 2)) }
            l.fill(spots, with: .color(Color(red: 0.416, green: 0.25, blue: 0.114).opacity(0.35)))
        }
        gloss(&g, dome, pt(890, water - 14 + bob), 26, 0.4); wire(&g, dome, 1.2)
        for (i, (x, k)) in [(CGFloat(884), CGFloat(1)), (920, -1)].enumerated() {
            var b = Path(); b.move(to: pt(x - 9 * k, water - 13 + bob)); b.addQuadCurve(to: pt(x + 8 * k, water - 12 + bob), control: pt(x, water - 19 + bob)); wire(&g, b, 1.1)
            eye(&g, pt(x, water - 7 + bob), 0.95, t, Double(i) * 1.3 + 4)
        }
        tentacle(&g, t, base: pt(850, water + 8), c1: pt(838, 1564), c2: pt(874, 1546), tip: pt(866, 1512), curl: [pt(860, 1490), pt(834, 1492), pt(842, 1508)], phase: 0, width: 12.5, back: false, water: water)
        tentacle(&g, t, base: pt(940, water + 8), c1: pt(958, 1570), c2: pt(978, 1556), tip: pt(964, 1520), curl: [pt(956, 1500), pt(936, 1506), pt(944, 1518)], phase: 1.8, width: 12.5, back: false, water: water)
        tentacle(&g, t, base: pt(818, water + 8), c1: pt(800, 1584), c2: pt(786, 1566), tip: pt(800, 1552), curl: nil, phase: 4.4, width: 8, back: false, water: water)
        foam(&ctx, t, [(850, 11), (876, 9), (902, 40), (940, 11), (818, 8)], water)
    }

    static func ship(_ ctx: inout GraphicsContext, _ t: Double) {
        let x = SeaChart.port.x + 22, y = SeaChart.port.y - 6 + CGFloat(sin(t * 1.2 + 1)) * 1.2
        var g = ctx; g.translateBy(x: x, y: y); g.rotate(by: .radians(sin(t * 1.2) * 0.035)); g.scaleBy(x: 0.62, y: 0.62)
        var hull = Path(); hull.move(to: pt(-32, -2)); hull.addQuadCurve(to: pt(32, -4), control: pt(0, 6)); hull.addLine(to: pt(25, 10)); hull.addQuadCurve(to: pt(-25, 10), control: pt(0, 18)); hull.closeSubpath()
        jewel(&g, hull, lin([Color(hex: 0x8A5A32), Color(hex: 0x4A2C16)], pt(0, -4), pt(0, 16)), 1.2)
        var plank = Path(); plank.move(to: pt(-26, 4)); plank.addQuadCurve(to: pt(27, 2), control: pt(0, 10))
        g.stroke(plank, with: .color(Color(red: 1, green: 0.86, blue: 0.63).opacity(0.5)), lineWidth: 0.8)
        var mast = Path(); mast.move(to: pt(0, 2)); mast.addLine(to: pt(0, -48)); wire(&g, mast, 1.6)
        let billow = CGFloat(sin(t * 1.4)) * 2
        var sail = Path(); sail.move(to: pt(-17, -42)); sail.addQuadCurve(to: pt(17, -42), control: pt(0, -37)); sail.addQuadCurve(to: pt(15, -12), control: pt(21 + billow, -27))
        sail.addQuadCurve(to: pt(-15, -12), control: pt(0, -8)); sail.addQuadCurve(to: pt(-17, -42), control: pt(-21 + billow, -27)); sail.closeSubpath()
        jewel(&g, sail, lin([Color(hex: 0xFBF4E2), Color(hex: 0xD9C9A4)], pt(-17, -42), pt(17, -12)), 0.9)
        g.drawLayer { l in l.clip(to: sail); l.fill(Path(CGRect(x: -6, y: -45, width: 12, height: 36)), with: .color(Theme.tileDark)) }
        wire(&g, sail, 0.9)
        var pennant = Path(); pennant.move(to: pt(0, -48)); pennant.addQuadCurve(to: pt(15, -44), control: pt(8, -47 + CGFloat(sin(t * 3)) * 1.5)); pennant.addLine(to: pt(0, -40)); pennant.closeSubpath()
        jewel(&g, pennant, .color(gold), 0.6)
        foam(&ctx, t, [(x, 14)], SeaChart.port.y + 2)
    }
}
