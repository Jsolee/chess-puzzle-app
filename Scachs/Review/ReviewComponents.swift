import SwiftUI

/// A small enamel disc: classes are told apart by glyph first, then colour.
struct MoveClassBadge: View {
    let cls: MoveClass
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            Circle().fill(cls.fill)
            Circle().strokeBorder(Theme.ink.opacity(0.22), lineWidth: max(0.5, size * 0.03))
            glyph
        }
        .frame(width: size, height: size)
        .accessibilityLabel(cls.displayName)
    }

    @ViewBuilder private var glyph: some View {
        switch cls.glyph {
        case "star": icon("star.fill")
        case "thumb": icon("hand.thumbsup.fill")
        case "check": icon("checkmark")
        case "book": icon("book.fill")
        case "x": icon("xmark")
        case "forced": icon("arrow.right")
        default:
            Text(verbatim: cls.glyph).font(.custom(Theme.TextWeight.semibold.rawValue, fixedSize: size * (cls.glyph.count > 1 ? 0.58 : 0.72)))
                .tracking(-0.3).foregroundStyle(cls.on)
        }
    }
    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(cls.on)
    }
}

/// White's share of the game, as a column of tin against ink.
struct EvalBar: View {
    let winPercent: Double
    let label: String
    let flipped: Bool
    var body: some View {
        GeometryReader { g in
            let white = g.size.height * CGFloat(max(3, min(97, winPercent)) / 100)
            ZStack(alignment: flipped ? .top : .bottom) {
                Rectangle().fill(Theme.ink)
                Rectangle().fill(Theme.tin).frame(height: white)
                    .animation(.easeOut(duration: 0.28), value: winPercent)
            }
        }
        .accessibilityLabel("Avaluació \(label)")
    }
}

/// The eval graph, drawn like an instrument. Drag to scrub, with a detent per move.
struct EvalGraph: View {
    let values: [Double?]          // white win percent per position
    var marks: [(ply: Int, cls: MoveClass)] = []
    var current: Int?
    var flipped = false
    var onScrub: ((Int) -> Void)?

    var body: some View {
        GeometryReader { g in
            Canvas { ctx, size in
                guard values.count > 1 else { return }
                let w = size.width, h = size.height, step = w / CGFloat(values.count - 1)
                func y(_ v: Double) -> CGFloat { let t = CGFloat(v / 100); return flipped ? t * h : (1 - t) * h }
                var area = Path(); var line = Path(); var started = false; var lastX: CGFloat = 0
                for (i, v) in values.enumerated() {
                    guard let v else { continue }
                    let p = CGPoint(x: CGFloat(i) * step, y: y(v))
                    if !started { area.move(to: CGPoint(x: p.x, y: flipped ? 0 : h)); area.addLine(to: p); line.move(to: p); started = true }
                    else { area.addLine(to: p); line.addLine(to: p) }
                    lastX = p.x
                }
                area.addLine(to: CGPoint(x: lastX, y: flipped ? 0 : h)); area.closeSubpath()
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink))
                ctx.fill(area, with: .color(Theme.tin))
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: h / 2)); $0.addLine(to: CGPoint(x: w, y: h / 2)) },
                           with: .color(Theme.gold.opacity(0.4)), style: StrokeStyle(lineWidth: 0.75, dash: [2, 3]))
                ctx.stroke(line, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                for m in marks where m.ply < values.count {
                    guard let v = values[m.ply] else { continue }
                    let dot = Path(ellipseIn: CGRect(x: CGFloat(m.ply) * step - 4, y: y(v) - 4, width: 8, height: 8))
                    ctx.fill(dot, with: .color(m.cls.fill))
                    ctx.stroke(dot, with: .color(Theme.ink), lineWidth: 1.2)
                }
                if let c = current, c < values.count {
                    ctx.stroke(Path { $0.move(to: CGPoint(x: CGFloat(c) * step, y: 0)); $0.addLine(to: CGPoint(x: CGFloat(c) * step, y: h)) }, with: .color(Theme.gold), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(onScrub == nil ? nil : DragGesture(minimumDistance: 0).onChanged { v in
                guard values.count > 1 else { return }
                let i = Int((v.location.x / g.size.width * CGFloat(values.count - 1)).rounded())
                onScrub?(max(0, min(values.count - 1, i)))
            })
        }
        .accessibilityElement().accessibilityLabel("Gràfic d'avaluació")
    }
}

extension View {
    /// An instrument's bezel: a gold wire round the face, and a fainter one outside it.
    func wireFrame() -> some View {
        clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.gold, lineWidth: 1))
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.gold.opacity(0.5), lineWidth: 0.75))
    }
}

extension Score {
    /// "+0,74", "-1,20", "M3" with the sign of the side it favours, seen from White.
    func whiteLabel(sideToMove: Side) -> String {
        switch self {
        case .cp(let c):
            let v = Double(sideToMove == .white ? c : -c) / 100
            return (v >= 0 ? "+" : "") + v.formatted(.number.precision(.fractionLength(1)))
        case .mate(let m):
            let mine = sideToMove == .white ? m : -m
            return (mine >= 0 ? "M" : "-M") + "\(abs(m))"
        }
    }
}
