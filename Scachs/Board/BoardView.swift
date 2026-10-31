import SwiftUI

/// The board plus everything drawn on top of it: touch, arrows, coordinates, promotion, VoiceOver.
struct BoardView: View {
    @Bindable var model: BoardModel
    var showCoordinates = true
    @State private var touchStart: CGPoint?
    init(_ model: BoardModel, showCoordinates: Bool = true) { self.model = model; self.showCoordinates = showCoordinates }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width
            ZStack(alignment: .topLeading) {
                BoardMetal(model: model)
                if showCoordinates { coordinates(size) }
                if !model.arrows.isEmpty { arrows(size).allowsHitTesting(false) }
                if let b = model.badge {
                    let c = model.screenPoint(b.square, size: size), t = size / 8
                    MoveClassBadge(cls: b.cls, size: t * 0.42).position(x: c.x + t * 0.34, y: c.y - t * 0.34).allowsHitTesting(false)
                        .id(b.square).transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                accessibilityGrid(size)
                if let pr = model.promotion { promotionPicker(pr, size) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    // By start point, not a flag: a gesture the system cancels never reaches onEnded.
                    if touchStart == v.startLocation { model.touchMoved(v.location, in: size) } else { touchStart = v.startLocation; model.touchDown(v.location, in: size) }
                }
                .onEnded { v in touchStart = nil; model.touchUp(v.location, in: size) })
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func coordinates(_ size: CGFloat) -> some View {
        let t = size / 8
        return ZStack(alignment: .topLeading) {
            ForEach(0..<8, id: \.self) { i in
                let rank = model.orientation == .white ? 8 - i : i + 1
                let file = model.orientation == .white ? i : 7 - i
                let darkLeft = i % 2 == 1
                Text("\(rank)").font(Theme.text(max(9, t * 0.2), .medium))
                    .foregroundStyle(darkLeft ? Theme.tileLight : Theme.tileDark)
                    .position(x: t * 0.11, y: CGFloat(i) * t + t * 0.14)
                Text(String(UnicodeScalar(UInt8(97 + file)))).font(Theme.text(max(9, t * 0.2), .medium))
                    .foregroundStyle(i % 2 == 0 ? Theme.tileLight : Theme.tileDark)
                    .position(x: CGFloat(i) * t + t * 0.89, y: size - t * 0.13)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func arrows(_ size: CGFloat) -> some View {
        Canvas { ctx, _ in
            for a in model.arrows {
                let p0 = model.screenPoint(a.from, size: size), p1 = model.screenPoint(a.to, size: size)
                let t = size / 8
                let dx = p1.x - p0.x, dy = p1.y - p0.y, len = max(hypot(dx, dy), 1)
                let ux = dx / len, uy = dy / len
                let start = CGPoint(x: p0.x + ux * t * 0.3, y: p0.y + uy * t * 0.3)
                let tip = CGPoint(x: p1.x - ux * t * 0.08, y: p1.y - uy * t * 0.08)
                let w = t * 0.12, head = t * 0.34
                let neck = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
                let nx = -uy, ny = ux
                var path = Path()
                path.move(to: CGPoint(x: start.x + nx * w / 2, y: start.y + ny * w / 2))
                path.addLine(to: CGPoint(x: neck.x + nx * w / 2, y: neck.y + ny * w / 2))
                path.addLine(to: CGPoint(x: neck.x + nx * head * 0.55, y: neck.y + ny * head * 0.55))
                path.addLine(to: tip)
                path.addLine(to: CGPoint(x: neck.x - nx * head * 0.55, y: neck.y - ny * head * 0.55))
                path.addLine(to: CGPoint(x: neck.x - nx * w / 2, y: neck.y - ny * w / 2))
                path.addLine(to: CGPoint(x: start.x - nx * w / 2, y: start.y - ny * w / 2))
                path.closeSubpath()
                let color: Color
                switch a.role {
                case .best: color = Color(hex: 0x4FB286)
                case .threat: color = Color(hex: 0xD9483B)
                case .idea: color = Theme.gold
                case .opponent: color = Color(hex: 0x6E9FD8)
                }
                ctx.fill(path, with: .color(color.opacity(0.86)))
                ctx.stroke(path, with: .color(Theme.ink.opacity(0.28)), lineWidth: 0.75)
            }
        }
    }

    private func accessibilityGrid(_ size: CGFloat) -> some View {
        let t = size / 8
        return ForEach(0..<64, id: \.self) { s in
            let c = model.screenPoint(s, size: size)
            Color.clear.frame(width: t, height: t).position(c)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(Self.spoken(s, model.position.piece(at: s)))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.touchDown(c, in: size); model.touchUp(c, in: size) }
        }
    }

    static func spoken(_ s: Square, _ p: Piece?) -> String {
        guard let p else { return squareName(s) }
        let names: [PieceKind: String] = [.pawn: String(localized: "peó"), .knight: String(localized: "cavall"), .bishop: String(localized: "alfil"),
                                          .rook: String(localized: "torre"), .queen: String(localized: "dama"), .king: String(localized: "rei")]
        let name = names[p.kind] ?? ""
        return p.side == .white ? String(localized: "\(squareName(s)), \(name) blanc") : String(localized: "\(squareName(s)), \(name) negre")
    }

    private func promotionPicker(_ pr: (from: Square, to: Square), _ size: CGFloat) -> some View {
        let t = size / 8
        let side = model.position.piece(at: pr.from)?.side ?? .white
        let c = model.screenPoint(pr.to, size: size)
        let goingDown = c.y > size / 2
        return ZStack {
            Color.black.opacity(0.42).onTapGesture { model.choosePromotion(nil) }
            VStack(spacing: 0) {
                ForEach([PieceKind.queen, .knight, .rook, .bishop], id: \.self) { k in
                    Button { model.choosePromotion(k) } label: {
                        PieceImage(piece: Piece(kind: k, side: side)).padding(t * 0.04).frame(width: t, height: t)
                    }
                    .accessibilityLabel(Self.spoken(pr.to, Piece(kind: k, side: side)))
                }
            }
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.tileLight))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.copper, lineWidth: 1.5))
            .position(x: c.x, y: goingDown ? c.y - t * 1.5 : c.y + t * 1.5)
        }
    }
}

/// A lit piece for places outside the Metal board.
struct PieceImage: View {
    let piece: Piece
    var body: some View {
        let letter = ["p", "n", "b", "r", "q", "k"][Int(piece.kind.rawValue)]
        Image(uiImage: PieceImage.load((piece.side == .white ? "w" : "b") + letter)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
    }
    private static var cache: [String: UIImage] = [:]
    static func load(_ name: String) -> UIImage {
        if let i = cache[name] { return i }
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Pieces") ?? Bundle.main.url(forResource: name, withExtension: "png")
        let i = url.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage()
        cache[name] = i
        return i
    }
}
