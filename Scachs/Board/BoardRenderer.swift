import Metal
import MetalKit
import QuartzCore
import UIKit
import CoreMotion
import SwiftUI

struct Uniforms {
    var tilt: SIMD2<Float> = .zero
    var time: Float = 0
    var headroom: Float = 1
    var reflexOrigin: SIMD2<Float> = .zero
    var reflexT: Float = -1
    var warmth: Float = 0
    var tilePixels: Float = 100
    var reduceFlash: Float = 0
    var pad: SIMD2<Float> = .zero
}
struct TileState { var tint: SIMD4<Float>; var dot: Float; var wrong: Float; var pad0: Float; var pad1: Float }
struct PieceInstance { var center: SIMD2<Float>; var scale: Float; var kind: Float; var side: Float; var alpha: Float; var lift: Float; var pad: Float }

/// One shared GPU setup; the atlas and pipelines live once however many boards exist.
final class BoardGPU {
    static let shared = BoardGPU()
    let device: MTLDevice, queue: MTLCommandQueue, atlas: MTLTexture
    let library: MTLLibrary
    private var cache: [MTLPixelFormat: (tile: MTLRenderPipelineState, piece: MTLRenderPipelineState, shadow: MTLRenderPipelineState)] = [:]

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!
        let w = 384 * 6, h = 384
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: true)
        d.usage = [.shaderRead]
        atlas = device.makeTexture(descriptor: d)!
        let url = Bundle.main.url(forResource: "pieces", withExtension: "rgba")!
        let bytes = try! Data(contentsOf: url)
        bytes.withUnsafeBytes { atlas.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: w * 4) }
        let cb = queue.makeCommandBuffer()!, blit = cb.makeBlitCommandEncoder()!
        blit.generateMipmaps(for: atlas); blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    }

    func pipelines(_ format: MTLPixelFormat) -> (tile: MTLRenderPipelineState, piece: MTLRenderPipelineState, shadow: MTLRenderPipelineState) {
        if let c = cache[format] { return c }
        func make(_ v: String, _ f: String, blended: Bool) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: v); d.fragmentFunction = library.makeFunction(name: f)
            let c = d.colorAttachments[0]!
            c.pixelFormat = format
            if blended {
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try! device.makeRenderPipelineState(descriptor: d)
        }
        let s = (make("tileVertex", "tileFragment", blended: false), make("pieceVertex", "pieceFragment", blended: true), make("shadowVertex", "shadowFragment", blended: true))
        cache[format] = s
        return s
    }

    func encode(_ enc: MTLRenderCommandEncoder, frame: BoardModel.Frame, uniforms: Uniforms, format: MTLPixelFormat) {
        let p = pipelines(format)
        var u = uniforms
        enc.setRenderPipelineState(p.tile)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        frame.tiles.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        guard !frame.instances.isEmpty else { return }
        frame.instances.withUnsafeBytes { enc.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentTexture(atlas, index: 0)
        enc.setRenderPipelineState(p.shadow)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: frame.instances.count)
        enc.setRenderPipelineState(p.piece)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: frame.instances.count)
    }
}

/// Gravity gives the light. A shared listener, low-passed, so all boards see the same room.
final class TiltSource {
    static let shared = TiltSource()
    static let moved = Notification.Name("TiltSource.moved")
    private let motion = CMMotionManager()
    private var users = 0
    private(set) var tilt = SIMD2<Float>.zero
    private var target = SIMD2<Float>.zero
    private var rest: SIMD2<Float>?

    func start() {
        users += 1
        #if DEBUG
        // Simulators have no gyroscope: -debugTilt m0.4,0.3 (m for minus, a leading - would read as a new argument)
        if let t = UserDefaults.standard.string(forKey: "debugTilt")?.replacingOccurrences(of: "m", with: "-").split(separator: ",").compactMap({ Float($0) }), t.count == 2 {
            target = SIMD2(t[0], t[1])
        }
        #endif
        guard users == 1, motion.isDeviceMotionAvailable, !UIAccessibility.isReduceMotionEnabled else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let v = SIMD2(Float(g.x), Float(g.y))
            if self.rest == nil { self.rest = v }
            // the way you hold the phone slowly becomes the neutral pose
            self.rest = self.rest! + (v - self.rest!) * 0.002
            self.target = (v - self.rest!) * SIMD2(1.05, -1.05)
            let gap = self.target - self.tilt
            if (gap * gap).sum() > 0.0000002 { NotificationCenter.default.post(name: TiltSource.moved, object: nil) }
        }
    }
    func stop() {
        users -= 1
        if users == 0 { motion.stopDeviceMotionUpdates() }
    }
    /// Advances the low-pass filter; returns how far the light moved.
    func step() -> Float {
        let d = (target - tilt) * 0.16
        tilt += d
        return (d * d).sum().squareRoot()
    }
}

final class BoardMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metal: CAMetalLayer { layer as! CAMetalLayer }
    private var link: CADisplayLink?
    private var needsDraw = true
    private var animating = false
    var model: BoardModel? {
        didSet {
            model?.attach { [weak self] in self?.wake() }
            wake()
        }
    }
    private let hdr: Bool

    override init(frame: CGRect) {
        hdr = UIScreen.main.potentialEDRHeadroom > 1.2
        super.init(frame: frame)
        metal.device = BoardGPU.shared.device
        metal.isOpaque = true
        metal.framebufferOnly = true
        metal.maximumDrawableCount = 3
        if hdr {
            metal.pixelFormat = .rgba16Float
            metal.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            metal.wantsExtendedDynamicRangeContent = true
        } else {
            metal.pixelFormat = .bgra8Unorm_srgb
        }
        contentScaleFactor = UIScreen.main.scale
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        NotificationCenter.default.addObserver(forName: TiltSource.moved, object: nil, queue: .main) { [weak self] _ in
            self?.link?.isPaused = false
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            TiltSource.shared.start()
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            l.add(to: .main, forMode: .common)
            link = l
            wake()
        } else {
            TiltSource.shared.stop()
            link?.invalidate(); link = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = bounds.size, scale = contentScaleFactor
        metal.drawableSize = CGSize(width: s.width * scale, height: s.height * scale)
        wake()
    }

    func wake() { needsDraw = true; link?.isPaused = false }

    @objc private func tick(_ l: CADisplayLink) {
        let moved = TiltSource.shared.step()
        guard let model, needsDraw || animating || moved > 0.00015 else { l.isPaused = true; return }
        let frame = model.frame(now: CACurrentMediaTime())
        needsDraw = false
        if frame.animating != animating {
            l.preferredFrameRateRange = frame.animating
                ? CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
                : CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)   // following the light
        }
        animating = frame.animating
        draw(frame)
    }

    private func draw(_ frame: BoardModel.Frame) {
        guard bounds.width > 0, let drawable = metal.nextDrawable() else { return }
        let gpu = BoardGPU.shared
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = drawable.texture
        d.colorAttachments[0].loadAction = .dontCare
        d.colorAttachments[0].storeAction = .store
        guard let cb = gpu.queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: d) else { return }
        var u = Uniforms()
        u.tilt = TiltSource.shared.tilt
        u.time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))
        u.headroom = hdr ? Float(max(1, min(window?.screen.currentEDRHeadroom ?? 1, 3))) : 1
        u.reflexT = frame.reflexT; u.reflexOrigin = frame.reflexOrigin
        u.warmth = Daylight.warmth
        u.tilePixels = Float(metal.drawableSize.width / 8)
        u.reduceFlash = UIAccessibility.isReduceMotionEnabled ? 1 : 0
        gpu.encode(enc, frame: frame, uniforms: u, format: metal.pixelFormat)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

/// "Pinta·l taulell... y fon lo Temps, partit per nits y dies." The room's light follows the hour.
enum Daylight {
    static var warmth: Float {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 7..<10: return 0.45
        case 10..<17: return 0
        case 17..<20: return 0.6
        default: return 0.85
        }
    }
}

struct BoardMetal: UIViewRepresentable {
    let model: BoardModel
    func makeUIView(context: Context) -> BoardMetalView { let v = BoardMetalView(); v.model = model; return v }
    func updateUIView(_ v: BoardMetalView, context: Context) { if v.model !== model { v.model = model }; v.wake() }
}
