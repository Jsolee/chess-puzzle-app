import SwiftUI
import Observation

enum ArrowRole { case best, threat, idea, opponent }
struct BoardArrow: Hashable { var from: Square; var to: Square; var role: ArrowRole }
enum MarkRole { case lastMove, selected, check, good, bad, hint, target }
struct BoardMark: Hashable { var square: Square; var role: MarkRole }

/// Everything the board shows. The renderer pulls a frame from here on each display tick.
@MainActor @Observable final class BoardModel {
    var position: Position
    var orientation: Side
    var interactive = true
    var lastMove: Move? { didSet { dirty() } }
    var hint: Square? { didSet { dirty() } }
    var arrows: [BoardArrow] = []
    var marks: [BoardMark] = [] { didSet { dirty() } }
    var badge: (square: Square, cls: MoveClass)?
    var onMove: ((Move) -> Void)?
    /// When set, touches pick squares instead of moving pieces (lessons that train board vision).
    var onTapSquare: ((Square) -> Void)?
    /// Set while the player picks a promotion piece.
    var promotion: (from: Square, to: Square)?
    private(set) var selected: Square? { didSet { dirty() } }

    @ObservationIgnored fileprivate var sprites: [Sprite] = []
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var drag: (id: Int, at: SIMD2<Float>, moved: Bool)?
    @ObservationIgnored private var wrongSquare: (Square, CFTimeInterval)?
    @ObservationIgnored private var reflexStart: CFTimeInterval?
    @ObservationIgnored private var reflexOrigin = SIMD2<Float>(0.5, 0.5)
    @ObservationIgnored private var hoverSquare: Square?
    @ObservationIgnored fileprivate var redraw: () -> Void = {}
    @ObservationIgnored var soundOn = true

    init(position: Position = .start, orientation: Side = .white) {
        self.position = position
        self.orientation = orientation
        rebuildSprites()
    }

    struct Sprite {
        var id: Int; var piece: Piece; var square: Square
        var from: SIMD2<Float>; var start: CFTimeInterval = 0; var duration: CFTimeInterval = 0
        var fadeOutStart: CFTimeInterval?; var fadeInStart: CFTimeInterval?
        var liftStart: CFTimeInterval?
    }

    private func dirty() { redraw() }
    func attach(_ redraw: @escaping () -> Void) { self.redraw = redraw }

    // MARK: Moves

    func set(_ p: Position, animated: Bool = true) {
        let now = CACurrentMediaTime()
        promotion = nil
        cancelSelection()
        for i in sprites.indices { sprites[i].liftStart = nil }
        drag = nil
        var remaining = sprites.filter { $0.fadeOutStart == nil }
        sprites.removeAll { $0.fadeOutStart == nil }
        var next: [Sprite] = []
        var missing: [(Square, Piece)] = []
        for s in 0..<64 {
            guard let piece = p.piece(at: s) else { continue }
            if let i = remaining.firstIndex(where: { $0.square == s && $0.piece == piece }) {
                next.append(remaining.remove(at: i))
            } else { missing.append((s, piece)) }
        }
        for (s, piece) in missing {
            if animated, let i = remaining.enumerated().filter({ $0.element.piece == piece }).min(by: {
                distance(logical($0.element.square), logical(s)) < distance(logical($1.element.square), logical(s))
            })?.offset {
                var sp = remaining.remove(at: i)
                sp.from = logical(sp.square); sp.square = s; sp.start = now; sp.duration = 0.3
                next.append(sp)
            } else {
                nextID += 1
                next.append(Sprite(id: nextID, piece: piece, square: s, from: logical(s), fadeInStart: animated ? now : nil))
            }
        }
        if animated { for var sp in remaining { sp.fadeOutStart = now; sprites.append(sp) } }
        sprites += next
        position = p
        dirty()
    }

    /// Plays a legal move with its sound and haptic. The player's own moves and scripted ones share this.
    func play(_ m: Move, animated: Bool = true, quiet: Bool = false) {
        guard position.isLegal(m) else { return }
        let now = CACurrentMediaTime()
        promotion = nil
        let before = position
        let after = before.applying(m)
        let isCapture = before.piece(at: m.to) != nil || (before.piece(at: m.from)?.kind == .pawn && m.from % 8 != m.to % 8)
        cancelSelection()
        if isCapture {
            var victimSquare = m.to
            if before.piece(at: m.to) == nil { victimSquare = (m.from / 8) * 8 + m.to % 8 }
            if let i = sprites.firstIndex(where: { $0.square == victimSquare && $0.fadeOutStart == nil }) {
                if animated { sprites[i].fadeOutStart = now + 0.09 } else { sprites.remove(at: i) }
            }
        }
        if let i = sprites.firstIndex(where: { $0.square == m.from && $0.fadeOutStart == nil }) {
            let startAt = dragging(i) ? drag!.at : logical(m.from)
            sprites[i].from = startAt; sprites[i].square = m.to; sprites[i].start = now
            sprites[i].duration = animated ? (dragging(i) ? 0.11 : 0.2) : 0
            sprites[i].liftStart = nil
            if let promo = m.promotion { sprites[i].piece.kind = promo }
            drag = nil
        }
        if before.piece(at: m.from)?.kind == .king, abs(m.to % 8 - m.from % 8) == 2 {
            let rank = m.from / 8
            let (rf, rt) = m.to % 8 == 6 ? (rank * 8 + 7, rank * 8 + 5) : (rank * 8, rank * 8 + 3)
            if let i = sprites.firstIndex(where: { $0.square == rf && $0.fadeOutStart == nil }) {
                sprites[i].from = logical(rf); sprites[i].square = rt; sprites[i].start = now; sprites[i].duration = animated ? 0.24 : 0
            }
        }
        position = after
        lastMove = m
        if soundOn && !quiet {
            if isCapture { Sound.capture(); Haptics.capture() } else { Sound.place(); Haptics.place() }
            if after.inCheck { Sound.check() }
        }
        dirty()
    }

    private func dragging(_ spriteIndex: Int) -> Bool { drag?.id == sprites[spriteIndex].id }

    func flashWrong(_ s: Square) {
        wrongSquare = (s, CACurrentMediaTime())
        Sound.wrong(); Haptics.wrong()
        dirty()
    }

    /// The signature: a wave of light from the square of the last move.
    func reflex(from s: Square, step: Int = 0) {
        reflexStart = CACurrentMediaTime()
        let (x, y) = screen(s)
        reflexOrigin = SIMD2((x + 0.5) / 8, (y + 0.5) / 8)
        Sound.reflex(step: step); Haptics.reflex()
        dirty()
    }

    // MARK: Touch

    func touchDown(_ p: CGPoint, in size: CGFloat) {
        if let tap = onTapSquare { if let s = square(at: p, size: size) { tap(s) }; return }
        touchStart = nil
        guard interactive, promotion == nil, let s = square(at: p, size: size) else { return }
        if let sel = selected, sel != s, position.legalMoves(from: sel).contains(where: { $0.to == s }) { return }   // tap-to-move resolves on touch up
        if let piece = position.piece(at: s), piece.side == position.side {
            if selected == s { pendingDeselect = true } else { selected = s; pendingDeselect = false; Haptics.lift() }
            if let i = sprites.firstIndex(where: { $0.square == s && $0.fadeOutStart == nil }) {
                drag = (sprites[i].id, logical(s), false)
                sprites[i].liftStart = CACurrentMediaTime()
            }
            hoverSquare = s
        } else {
            cancelSelection()
        }
        dirty()
    }
    @ObservationIgnored private var pendingDeselect = false
    @ObservationIgnored private var touchStart: SIMD2<Float>?

    func touchMoved(_ p: CGPoint, in size: CGFloat) {
        guard let d = drag else { return }
        let u = CGFloat(8) / size
        var at = SIMD2<Float>(Float(p.x * u), Float(p.y * u) - 0.55)     // above the finger
        if orientation == .black { at = SIMD2(8 - at.x, 8 - at.y) }
        let logicalAt = SIMD2<Float>(at.x - 0.5, 7.5 - at.y)
        // Measured at the finger, not the lifted piece, so a tap with some jitter stays a tap.
        let finger = SIMD2<Float>(Float(p.x * u), Float(p.y * u))
        if touchStart == nil { touchStart = finger }
        let moved = d.moved || distance(finger, touchStart ?? finger) > 0.15
        drag = (d.id, logicalAt, moved)
        if let s = square(at: p, size: size), s != hoverSquare {
            hoverSquare = s
            if let sel = selected, position.legalMoves(from: sel).contains(where: { $0.to == s }) { Haptics.step() }
        }
        dirty()
    }

    func touchUp(_ p: CGPoint, in size: CGFloat) {
        defer {
            if let d = drag, let i = sprites.firstIndex(where: { $0.id == d.id }) {
                sprites[i].liftStart = nil
                if d.moved { sprites[i].from = d.at; sprites[i].start = CACurrentMediaTime(); sprites[i].duration = 0.14 }
            }
            drag = nil; dirty()
        }
        guard interactive, promotion == nil else { return }
        guard let s = square(at: p, size: size), let sel = selected else { return }
        if s == sel {
            if pendingDeselect, drag?.moved != true { cancelSelection() }
            pendingDeselect = false
            return
        }
        let moves = position.legalMoves(from: sel).filter { $0.to == s }
        guard let first = moves.first else {
            if drag?.moved == true { Haptics.tap(0.2, sharpness: 0.2) }
            return
        }
        if moves.count > 1 {
            promotion = (sel, s)
        } else {
            onMove?(first)
            cancelSelection()
        }
    }

    func choosePromotion(_ k: PieceKind?) {
        guard let pr = promotion else { return }
        promotion = nil
        if let k { onMove?(Move(from: pr.from, to: pr.to, promotion: k)) }
        cancelSelection()
    }

    func cancelSelection() { selected = nil; pendingDeselect = false }

    func square(at p: CGPoint, size: CGFloat) -> Square? {
        let t = size / 8
        let cx = Int(floor(p.x / t)), cy = Int(floor(p.y / t))
        guard (0..<8).contains(cx), (0..<8).contains(cy) else { return nil }
        return orientation == .white ? (7 - cy) * 8 + cx : cy * 8 + (7 - cx)
    }

    fileprivate func screen(_ s: Square) -> (Float, Float) {
        let f = Float(s % 8), r = Float(s / 8)
        return orientation == .white ? (f, 7 - r) : (7 - f, r)
    }
    func screenPoint(_ s: Square, size: CGFloat) -> CGPoint {
        let (x, y) = screen(s)
        return CGPoint(x: (CGFloat(x) + 0.5) * size / 8, y: (CGFloat(y) + 0.5) * size / 8)
    }
    /// Stable coordinates (file, rank) as floats, so orientation can flip without touching sprites.
    private func logical(_ s: Square) -> SIMD2<Float> { SIMD2(Float(s % 8), Float(s / 8)) }

    private func rebuildSprites() {
        sprites = (0..<64).compactMap { s in
            guard let p = position.piece(at: s) else { return nil }
            nextID += 1
            return Sprite(id: nextID, piece: p, square: s, from: logical(s))
        }
    }

    // MARK: Frame

    struct Frame {
        var instances: [PieceInstance]; var tiles: [TileState]
        var reflexT: Float; var reflexOrigin: SIMD2<Float>; var animating: Bool
    }

    func frame(now: CFTimeInterval, gold: SIMD3<Float> = SIMD3(0.7991, 0.4851, 0.1500)) -> Frame {
        var animating = false
        sprites.removeAll { sp in
            if let f = sp.fadeOutStart, now - f > 0.16 { return true }
            return false
        }
        var list: [(PieceInstance, Int)] = []
        for sp in sprites {
            var pos = logical(sp.square)
            var scale: Float = 1, alpha: Float = 1, lift: Float = 0
            var order = 0
            if sp.duration > 0, now - sp.start < sp.duration {
                let t = Float(max(0, (now - sp.start) / sp.duration))
                let e = 1 - pow(1 - t, 4)
                pos = sp.from + (pos - sp.from) * e
                let arc = sin(t * .pi)
                scale += arc * 0.06; lift = arc * 0.5
                animating = true
                order = 2
            }
            if let f = sp.fadeOutStart {
                let t = Float(max(0, min(1, (now - f) / 0.16)))
                alpha = 1 - t; scale *= 1 - t * 0.14
                animating = true
                order = -1
            }
            if let f = sp.fadeInStart, now - f < 0.2 {
                alpha = Float((now - f) / 0.2); animating = true
            }
            if let d = drag, d.id == sp.id, d.moved {
                pos = d.at; scale = 1.22; lift = 1; order = 3
            } else if let l = sp.liftStart {
                let t = Float(min(1, (now - l) / 0.09))
                scale += 0.05 * t; lift = max(lift, 0.35 * t)
                if t < 1 { animating = true }
            }
            let (sx, sy): (Float, Float) = orientation == .white ? (pos.x, 7 - pos.y) : (7 - pos.x, pos.y)
            let inst = PieceInstance(center: SIMD2(sx + 0.5, sy + 0.5), scale: scale, kind: Float(sp.piece.kind.rawValue),
                                     side: sp.piece.side == .white ? 0 : 1, alpha: alpha, lift: lift, pad: 0)
            list.append((inst, order))
        }
        list.sort { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.center.y < $1.0.center.y }

        var tiles = [TileState](repeating: TileState(tint: .zero, dot: 0, wrong: 0, pad0: 0, pad1: 0), count: 64)
        func index(_ s: Square) -> Int { let (x, y) = screen(s); return Int(y) * 8 + Int(x) }
        if let m = lastMove {
            tiles[index(m.from)].tint = SIMD4(gold * 0.9, 0.22)
            tiles[index(m.to)].tint = SIMD4(gold * 0.9, 0.34)
        }
        for mark in marks {
            switch mark.role {
            case .lastMove: tiles[index(mark.square)].tint = SIMD4(gold * 0.9, 0.3)
            case .selected: tiles[index(mark.square)].tint = SIMD4(gold, 0.5)
            case .check: tiles[index(mark.square)].tint = SIMD4(0.62, 0.06, 0.03, 0.62)
            case .good: tiles[index(mark.square)].tint = SIMD4(0.12, 0.55, 0.35, 0.55)
            case .bad: tiles[index(mark.square)].tint = SIMD4(0.72, 0.08, 0.04, 0.5)
            case .hint: tiles[index(mark.square)].tint = SIMD4(gold, 0.55)
            case .target: tiles[index(mark.square)].dot = 1
            }
        }
        if position.inCheck, let k = position.king(of: position.side) {
            tiles[index(k)].tint = SIMD4(0.62, 0.06, 0.03, 0.58)
        }
        if let s = hint { tiles[index(s)].tint = SIMD4(gold, 0.55) }
        if let sel = selected {
            tiles[index(sel)].tint = SIMD4(gold, 0.46)
            for m in position.legalMoves(from: sel) {
                tiles[index(m.to)].dot = position.piece(at: m.to) != nil ? 2 : 1
            }
        }
        if let (s, t) = wrongSquare {
            let a = now - t
            if a < 0.5 {
                tiles[index(s)].wrong = Float(1 - a / 0.5)
                animating = true
            } else { wrongSquare = nil }
        }
        var rt: Float = -1
        if let start = reflexStart {
            let a = now - start
            if a < 2.2 { rt = Float(a); animating = true } else { reflexStart = nil }
        }
        return Frame(instances: list.map(\.0), tiles: tiles, reflexT: rt, reflexOrigin: reflexOrigin, animating: animating)
    }
}

private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { ((a - b) * (a - b)).sum().squareRoot() }
