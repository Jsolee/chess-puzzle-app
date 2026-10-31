import SwiftUI
import QuartzCore

/// First thing on screen: the S traced in gold, filled, set into the wordmark, and one glint of light. A tap skips it.
struct LaunchView: View {
    var done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LaunchLogo(reduceMotion: reduceMotion, done: done)
            .background(Theme.field)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: done)
            .accessibilityHidden(true)
    }
}

private struct LaunchLogo: UIViewRepresentable {
    let reduceMotion: Bool
    let done: () -> Void
    func makeUIView(context: Context) -> LogoLayerView { LogoLayerView(reduceMotion: reduceMotion, done: done) }
    func updateUIView(_ view: LogoLayerView, context: Context) {}
}

/// Core Animation, not SwiftUI: it runs in the render server, so it stays smooth while the first screen blocks the main thread.
private final class LogoLayerView: UIView {
    private let reduceMotion: Bool
    private let done: () -> Void
    private var started = false

    private static let tin = UIColor(Theme.tin).cgColor
    private static let gold = UIColor(Theme.gold).cgColor
    private static let quint = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    private static let penSpeed = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)

    init(reduceMotion: Bool, done: @escaping () -> Void) {
        self.reduceMotion = reduceMotion
        self.done = done
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !started, bounds.width > 0 else { return }
        started = true
        let total = reduceMotion ? stillLogo() : animatedLogo()
        DispatchQueue.main.asyncAfter(deadline: .now() + total, execute: done)
    }

    // MARK: Geometry

    private static func placing(_ box: CGRect, scale: CGFloat, at centre: CGPoint) -> CATransform3D {
        var t = CATransform3DMakeTranslation(-box.midX, -box.midY, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
        return CATransform3DConcat(t, CATransform3DMakeTranslation(centre.x, centre.y, 0))
    }

    private func wordScale(_ word: CGRect) -> CGFloat { min(bounds.width * 0.62, 260) / word.width }

    // MARK: Layers

    /// Returns when to hand over.
    private func stillLogo() -> TimeInterval {
        let shape = CGMutablePath()
        shape.addPath(LogoPath.parse(LogoOutlines.initial))
        shape.addPath(LogoPath.parse(LogoOutlines.rest))
        let word = fill(shape, Self.tin)
        word.transform = Self.placing(shape.boundingBox, scale: wordScale(shape.boundingBox), at: CGPoint(x: bounds.midX, y: bounds.midY))
        layer.addSublayer(word)
        add(word, "opacity", from: 0, to: 1, at: 0, for: 0.3)
        return 0.8
    }

    private func animatedLogo() -> TimeInterval {
        let initial = LogoPath.parse(LogoOutlines.initial), rest = LogoPath.parse(LogoOutlines.rest)
        let word = initial.boundingBox.union(rest.boundingBox)
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let bigScale = min(bounds.height * 0.24, 200) / initial.boundingBox.height
        let big = Self.placing(initial.boundingBox, scale: bigScale, at: centre)
        let placed = Self.placing(word, scale: wordScale(word), at: centre)

        // The S: a gold contour, then the fill rising under it, then both settle into the word.
        let letter = CALayer()
        letter.transform = placed
        let body = fill(initial, Self.tin)
        let contour = CAShapeLayer()
        contour.path = initial
        contour.fillColor = nil
        contour.strokeColor = Self.gold
        contour.lineWidth = 1.5 / bigScale
        contour.lineJoin = .round
        contour.opacity = 0
        letter.addSublayer(body)
        letter.addSublayer(contour)
        layer.addSublayer(letter)

        // The other letters come out of the S as if the ink were still running.
        let others = fill(rest, Self.tin)
        others.transform = placed
        let span = rest.boundingBox
        let wipe = CAGradientLayer()
        wipe.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        wipe.locations = [0, 0.72, 1]
        wipe.startPoint = CGPoint(x: 0, y: 0.5)
        wipe.endPoint = CGPoint(x: 1, y: 0.5)
        wipe.frame = CGRect(x: span.minX, y: word.minY, width: span.width * 1.4, height: word.height)
        others.mask = wipe
        layer.addSublayer(others)

        // One glint over the finished word.
        let glintHost = CALayer()
        glintHost.transform = placed
        let glint = CAGradientLayer()
        glint.colors = [UIColor(Theme.gold).withAlphaComponent(0).cgColor, Self.gold, UIColor(Theme.gold).withAlphaComponent(0).cgColor]
        glint.locations = [1, 1.18, 1.36]
        glint.startPoint = CGPoint(x: 0, y: 0.35)
        glint.endPoint = CGPoint(x: 1, y: 0.65)
        glint.frame = word
        let glintMask = CAShapeLayer()
        let toGlint = CGAffineTransform(translationX: -word.minX, y: -word.minY)
        let wordShape = CGMutablePath()
        wordShape.addPath(initial, transform: toGlint)
        wordShape.addPath(rest, transform: toGlint)
        glintMask.path = wordShape
        glint.mask = glintMask
        glintHost.addSublayer(glint)
        layer.addSublayer(glintHost)

        add(contour, "strokeEnd", from: 0, to: 1, at: 0.05, for: 0.8, curve: Self.penSpeed)
        add(contour, "opacity", from: 1, to: 0, at: 0.85, for: 0.22)
        add(body, "opacity", from: 0, to: 1, at: 0.6, for: 0.42, curve: Self.quint)
        add(letter, "transform", from: NSValue(caTransform3D: big), to: NSValue(caTransform3D: placed), at: 1.02, for: 0.6, curve: Self.quint)
        add(wipe, "position.x", from: wipe.position.x - span.width * 1.4, to: wipe.position.x, at: 1.12, for: 0.6, curve: Self.quint)
        add(glint, "locations", from: [-0.36, -0.18, 0], to: [1, 1.18, 1.36], at: 1.5, for: 0.66, curve: Self.penSpeed)
        return 2.2
    }

    private func fill(_ path: CGPath, _ colour: CGColor) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = colour
        return shape
    }

    /// The layer already holds its final value, so the only thing to keep is the start value during the delay.
    private func add(_ target: CALayer, _ path: String, from: Any, to: Any, at delay: CFTimeInterval, for duration: CFTimeInterval,
                     curve: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut)) {
        let a = CABasicAnimation(keyPath: path)
        a.fromValue = from
        a.toValue = to
        a.beginTime = CACurrentMediaTime() + delay
        a.duration = duration
        a.timingFunction = curve
        a.fillMode = .backwards
        target.add(a, forKey: path)
    }
}

enum LogoPath {
    /// Reads what brand/logo/generate.py writes: absolute M, L, Q, C and Z, space separated.
    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let tokens = d.split(separator: " ")
        var i = 0
        func point() -> CGPoint {
            defer { i += 2 }
            return CGPoint(x: Double(tokens[i]) ?? 0, y: Double(tokens[i + 1]) ?? 0)
        }
        while i < tokens.count {
            let op = tokens[i]
            i += 1
            switch op {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "Q":
                let c = point()
                path.addQuadCurve(to: point(), control: c)
            case "C":
                let a = point(), b = point()
                path.addCurve(to: point(), control1: a, control2: b)
            default: path.closeSubpath()
            }
        }
        return path
    }
}
