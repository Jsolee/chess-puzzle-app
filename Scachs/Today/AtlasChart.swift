import CoreGraphics
import Foundation

/// The chart as a picture, the way a portolan was made: vellum first, then coasts in ink, washes of colour on the land.
/// Everything is worked out per pixel from distance fields, because that's what gives scalloped shores, water lines
/// and pigment pooling at the borders. It takes a moment, so it's painted off the main thread and kept.
struct AtlasChart: @unchecked Sendable {
    struct Place {
        let region: AtlasRegion
        /// The middle of the longest straight run across this territory, which is where its name goes.
        let point: CGPoint
        let angle: Double
        let room: CGFloat
        /// Open water near here, for the sea monster, on the worst of the ground you've lost.
        var dragon: CGPoint?
    }

    let image: CGImage
    let size: CGSize
    let scale: CGFloat
    let places: [Place]
    /// Each land's name sits in the water beside it, where it can be read.
    let titles: [Land: CGPoint]
    private let labels: [Int16]
    private let pixelWidth: Int

    func place(at point: CGPoint) -> Place? {
        let x = Int(point.x * scale), y = Int(point.y * scale)
        let i = y * pixelWidth + x
        guard x >= 0, x < pixelWidth, y >= 0, labels.indices.contains(i), labels[i] >= 0 else { return nil }
        return places[Int(labels[i])]
    }

    /// A wash over one territory, for showing which one is selected.
    func highlight(_ region: AtlasRegion) -> CGImage? {
        guard let index = places.firstIndex(where: { $0.region == region }) else { return nil }
        let height = labels.count / pixelWidth
        var pixels = [UInt8](repeating: 0, count: labels.count * 4)
        for i in labels.indices where labels[i] == Int16(index) {
            pixels[i * 4] = 10; pixels[i * 4 + 1] = 10; pixels[i * 4 + 2] = 12; pixels[i * 4 + 3] = 46
        }
        return AtlasPainter.image(from: &pixels, width: pixelWidth, height: height)
    }

    fileprivate init(image: CGImage, size: CGSize, scale: CGFloat, places: [Place], titles: [Land: CGPoint], labels: [Int16], pixelWidth: Int) {
        self.image = image; self.size = size; self.scale = scale; self.places = places
        self.titles = titles; self.labels = labels; self.pixelWidth = pixelWidth
    }
}

enum AtlasPainter {
    /// Where each landmass sits on the sheet, as fractions of it, and how big a territory is before it has been visited.
    private static let layout: [Land: (x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, size: CGFloat)] = [
        .kingPawn: (0.35, 0.29, 0.235, 0.185, 0.085),
        .queenPawn: (0.67, 0.635, 0.215, 0.195, 0.085),
        .flank: (0.27, 0.815, 0.15, 0.085, 0.055),
    ]
    /// Open sea is kept for it, so no land grows under the rose however much you play.
    static let rose = (x: CGFloat(0.80), y: CGFloat(0.175), radius: CGFloat(0.105))

    private static func hash(_ s: String) -> UInt64 { s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 } }

    // MARK: Noise

    private struct Noise {
        private var table = [Float](repeating: 0, count: 65536)

        init(seed: UInt64) {
            var s = seed
            for i in table.indices {
                s ^= s << 13; s ^= s >> 7; s ^= s << 17
                table[i] = Float(s % 10000) / 10000
            }
        }

        @inline(__always) func value(_ x: Float, _ y: Float) -> Float {
            let fx = x.rounded(.down), fy = y.rounded(.down)
            let tx = x - fx, ty = y - fy
            let ix = Int(fx) & 255, iy = Int(fy) & 255
            let jx = (ix + 1) & 255, jy = (iy + 1) & 255
            let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
            return table.withUnsafeBufferPointer { t in
                let a = t[iy << 8 | ix], b = t[iy << 8 | jx], c = t[jy << 8 | ix], d = t[jy << 8 | jx]
                return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
            }
        }

        @inline(__always) func fbm(_ x: Float, _ y: Float, _ octaves: Int) -> Float {
            var total: Float = 0, amplitude: Float = 0.5, px = x, py = y
            for _ in 0..<octaves {
                total += value(px, py) * amplitude
                amplitude *= 0.5
                px = px * 2 + 17
                py = py * 2 + 31
            }
            return total
        }
    }

    /// Two-pass chamfer: distance in pixels from every pixel to the nearest seed.
    private static func distance(from seeds: [Bool], width: Int, height: Int) -> [Float] {
        var d = seeds.map { $0 ? Float(0) : Float.greatestFiniteMagnitude / 4 }
        let straight: Float = 1, diagonal: Float = 1.414
        d.withUnsafeMutableBufferPointer { d in
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    var v = d[i]
                    if x > 0 { v = min(v, d[i - 1] + straight) }
                    if y > 0 {
                        v = min(v, d[i - width] + straight)
                        if x > 0 { v = min(v, d[i - width - 1] + diagonal) }
                        if x < width - 1 { v = min(v, d[i - width + 1] + diagonal) }
                    }
                    d[i] = v
                }
            }
            for y in stride(from: height - 1, through: 0, by: -1) {
                for x in stride(from: width - 1, through: 0, by: -1) {
                    let i = y * width + x
                    var v = d[i]
                    if x < width - 1 { v = min(v, d[i + 1] + straight) }
                    if y < height - 1 {
                        v = min(v, d[i + width] + straight)
                        if x < width - 1 { v = min(v, d[i + width + 1] + diagonal) }
                        if x > 0 { v = min(v, d[i + width - 1] + diagonal) }
                    }
                    d[i] = v
                }
            }
        }
        return d
    }

    @inline(__always) private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private typealias RGB = SIMD3<Float>

    /// Good ground is the app's own green, bad ground is vermilion from the charts' red ink, even ground is ochre.
    private static func wash(_ region: AtlasRegion) -> (colour: RGB, alpha: Float) {
        guard region.games > 0 else { return (RGB(0, 0, 0), 0) }
        let alpha = min(0.50 + Float(region.games) * 0.04, 0.80)
        if region.score >= 0.55 { return (RGB(0.12, 0.38, 0.31), alpha) }
        if region.score < 0.45 { return (RGB(0.70, 0.17, 0.09), alpha) }
        return (RGB(0.76, 0.54, 0.18), alpha * 0.9)
    }

    // MARK: Painting

    static func paint(regions: [AtlasRegion], size: CGSize, scale: CGFloat) -> AtlasChart? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0 else { return nil }
        let W = Float(size.width), H = Float(size.height), s = Float(scale)
        let roseX = Float(rose.x * size.width), roseY = Float(rose.y * size.height), roseR = Float(rose.radius * size.width)
        let noise = Noise(seed: 0x5CAC_5CAC_1475)

        // Places first: a sunflower spiral spreads them evenly, whatever their number, and hashing keeps them where you left them.
        var sites: [(region: AtlasRegion, x: Float, y: Float, reach: Float, land: Int)] = []
        var centres: [Land: CGPoint] = [:]
        for (landIndex, land) in Land.allCases.enumerated() {
            let spot = layout[land]!
            let centre = CGPoint(x: spot.x * size.width, y: spot.y * size.height)
            centres[land] = centre
            let members = regions.filter { $0.land == land }.sorted { hash($0.name) < hash($1.name) }
            for (i, region) in members.enumerated() {
                let r = 0.96 * (Double(i) + 0.5).squareRoot() / Double(members.count).squareRoot()
                let a = Double(i) * 2.39996 + Double(hash(land.rawValue) % 7)
                let grown = 1 + 0.32 * min(log2(1 + Float(region.games)), 2.6)
                sites.append((region, Float(centre.x + r * spot.rx * size.width * cos(a)), Float(centre.y + r * spot.ry * size.height * sin(a)), Float(spot.size) * W * grown, landIndex))
            }
        }
        guard !sites.isEmpty else { return nil }

        // The land's rough shape: soft blobs around each place, on a coarse grid since it has no fine detail anyway.
        let cell = 4
        let coarseWidth = width / cell + 2, coarseHeight = height / cell + 2
        var field = [Float](repeating: 0, count: coarseWidth * coarseHeight)
        for y in 0..<coarseHeight {
            for x in 0..<coarseWidth {
                let px = Float(x * cell) / s, py = Float(y * cell) / s
                var byLand = SIMD3<Float>.zero
                for site in sites {
                    let dx = px - site.x, dy = py - site.y
                    byLand[site.land] += exp(-(dx * dx + dy * dy) / (site.reach * site.reach))
                }
                // Where two lands would meet, a strait runs between them.
                var v = byLand.sum() - 2.4 * (byLand.sum() - byLand.max() - byLand.min())
                // And nothing grows over the border or under the rose.
                v -= (1 - smooth(20, 46, min(min(px, W - px), min(py, H - py)))) * 1.4
                v -= (1 - smooth(roseR + 8, roseR + 34, hypot(px - roseX, py - roseY))) * 1.6
                field[y * coarseWidth + x] = v
            }
        }

        var labels = [Int16](repeating: -1, count: width * height)
        var isLand = [Bool](repeating: false, count: width * height)
        var borderSeeds = [Bool](repeating: false, count: width * height)
        // Medieval shores are a run of tiny bays and capes: broad noise for the gulfs, fine noise for the scallops.
        for y in 0..<height {
            let py = Float(y) / s
            let gy = Float(y) / Float(cell), iy = Int(gy), ty = gy - Float(iy)
            for x in 0..<width {
                let px = Float(x) / s
                let gx = Float(x) / Float(cell), ix = Int(gx), tx = gx - Float(ix)
                let a = field[iy * coarseWidth + ix], b = field[iy * coarseWidth + ix + 1]
                let c = field[(iy + 1) * coarseWidth + ix], d = field[(iy + 1) * coarseWidth + ix + 1]
                var v = a + (b - a) * tx
                v += ((c + (d - c) * tx) - v) * ty
                v += (noise.fbm(px * 0.028, py * 0.028, 3) - 0.44) * 0.62
                v += (noise.fbm(px * 0.17 + 40, py * 0.17 + 9, 2) - 0.37) * 0.20
                guard v > 0.66 else { continue }
                isLand[y * width + x] = true
                // Wobbling the point before measuring turns ruler-straight frontiers into ones that follow rivers.
                let wx = px + (noise.fbm(px * 0.035 + 7, py * 0.035, 3) - 0.44) * 30
                let wy = py + (noise.fbm(px * 0.035, py * 0.035 + 11, 3) - 0.44) * 30
                var best = Float.greatestFiniteMagnitude, owner = 0
                for (i, site) in sites.enumerated() {
                    let dx = wx - site.x, dy = wy - site.y
                    let m = (dx * dx + dy * dy) / (site.reach * site.reach)
                    if m < best { best = m; owner = i }
                }
                labels[y * width + x] = Int16(owner)
            }
        }
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let i = y * width + x
                let l = labels[i]
                guard l >= 0 else { continue }
                let r = labels[i + 1], d = labels[i + width]
                if (r >= 0 && r != l) || (d >= 0 && d != l) { borderSeeds[i] = true }
            }
        }

        let toLand = distance(from: isLand, width: width, height: height)
        let toSea = distance(from: isLand.map { !$0 }, width: width, height: height)
        let toBorder = distance(from: borderSeeds, width: width, height: height)
        let washes = sites.map { wash($0.region) }

        // Vellum under a lamp: warm, a little uneven, darker where hands have held it.
        let vellum = RGB(0.871, 0.812, 0.690), umber = RGB(0.56, 0.42, 0.26)
        let ink = RGB(0.10, 0.09, 0.11), sea = RGB(0.30, 0.46, 0.41), waterLine = RGB(0.15, 0.24, 0.22), shore = RGB(0.60, 0.44, 0.24)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let py = Float(y) / s
                for x in 0..<width {
                    let i = y * width + x
                    let px = Float(x) / s
                    // The torn top and bottom of the skin.
                    let tear = 2.5 + noise.fbm(px * 0.06 + 3, 5, 3) * 5
                    let tearBottom = 2.5 + noise.fbm(px * 0.06 + 91, 5, 3) * 5
                    let edgeY = min(py, Float(size.height) - py)
                    let cover = smooth(tear - 0.5, tear + 0.5, py) * smooth(tearBottom - 0.5, tearBottom + 0.5, Float(size.height) - py)
                    if cover <= 0 { continue }

                    let grain = noise.fbm(px * 0.012 + 3, py * 0.012, 3) - 0.44
                    let fibre = noise.fbm(px * 0.55, py * 0.22, 2) - 0.37
                    var c = vellum * (1 + grain * 0.13 + fibre * 0.045)
                    let edge = min(min(px, W - px), edgeY) / W
                    c += (umber - c) * (1 - smooth(0, 0.14, edge)) * 0.42
                    let stain = smooth(0.54, 0.7, noise.fbm(px * 0.009 + 21, py * 0.009 + 4, 3))
                    c += (umber - c) * stain * 0.10

                    if labels[i] < 0 {
                        let d = toLand[i] / s
                        c += (sea - c) * (0.07 + 0.26 * exp(-d / 13))
                        for (at, strength) in [(Float(3.6), Float(0.46)), (Float(7.6), Float(0.28)), (Float(12.6), Float(0.15))] {
                            c += (waterLine - c) * strength * (1 - smooth(0.16, 0.62, abs(d - at)))
                        }
                    } else {
                        let d = toSea[i] / s
                        let owner = Int(labels[i])
                        c = c * 1.035
                        c += (shore - c) * 0.30 * exp(-d / 6.5)
                        let (colour, alpha) = washes[owner]
                        if alpha > 0 {
                            // Pigment settles at the edge of a wash and goes patchy in the middle.
                            let frontier = toBorder[i] / s
                            let pool = 0.78 + 0.5 * exp(-min(frontier, d) / 4.5)
                            let mottle = 0.76 + 0.48 * noise.fbm(px * 0.09 + 13, py * 0.09 + 2, 3)
                            c += (colour - c) * min(alpha * pool * mottle, 0.93)
                        }
                        let line = 1 - smooth(0.32, 0.86, toBorder[i] / s)
                        if line > 0 {
                            let dash = 0.62 + 0.38 * sin((px + py) * 1.25)
                            c += (ink - c) * line * 0.52 * dash
                        }
                        let pen = 0.72 + 0.62 * noise.value(px * 0.13, py * 0.13)
                        c += (ink - c) * (1 - smooth(pen * 0.62, pen * 1.25, d)) * 0.95
                    }
                    let a = cover
                    out[i * 4] = UInt8(max(min(c.x * a, 1), 0) * 255)
                    out[i * 4 + 1] = UInt8(max(min(c.y * a, 1), 0) * 255)
                    out[i * 4 + 2] = UInt8(max(min(c.z * a, 1), 0) * 255)
                    out[i * 4 + 3] = UInt8(a * 255)
                }
            }
        }
        guard let image = image(from: &pixels, width: width, height: height) else { return nil }

        func owner(_ p: CGPoint) -> Int16 {
            let x = Int(p.x * scale), y = Int(p.y * scale)
            guard p.x >= 0, p.y >= 0, x < width, y < height else { return -1 }
            return labels[y * width + x]
        }
        func run(through p: CGPoint, angle: Double, in territory: Int16) -> (length: CGFloat, middle: CGPoint) {
            let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
            var ahead: CGFloat = 0, behind: CGFloat = 0
            while owner(CGPoint(x: p.x + (ahead + 2) * dx, y: p.y + (ahead + 2) * dy)) == territory { ahead += 2 }
            while owner(CGPoint(x: p.x - (behind + 2) * dx, y: p.y - (behind + 2) * dy)) == territory { behind += 2 }
            return (ahead + behind, CGPoint(x: p.x + (ahead - behind) / 2 * dx, y: p.y + (ahead - behind) / 2 * dy))
        }

        var sumX = [CGFloat](repeating: 0, count: sites.count), sumY = sumX, area = sumX
        for y in 0..<height {
            for x in 0..<width where labels[y * width + x] >= 0 {
                let l = Int(labels[y * width + x])
                sumX[l] += CGFloat(x); sumY[l] += CGFloat(y); area[l] += 1
            }
        }
        var places: [AtlasChart.Place] = sites.enumerated().map { index, site in
            let territory = Int16(index)
            guard area[index] > 0 else {
                return AtlasChart.Place(region: site.region, point: CGPoint(x: CGFloat(site.x), y: CGFloat(site.y)), angle: 0, room: 60)
            }
            var middle = CGPoint(x: sumX[index] / area[index] / scale, y: sumY[index] / area[index] / scale)
            if owner(middle) != territory {
                // A crescent's middle is outside it.
                var nearest = CGFloat.greatestFiniteMagnitude
                let target = middle
                for y in 0..<height {
                    for x in 0..<width where labels[y * width + x] == territory {
                        let p = CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale)
                        let d = hypot(p.x - target.x, p.y - target.y)
                        if d < nearest { nearest = d; middle = p }
                    }
                }
            }
            var best = (score: -1.0, angle: 0.0, length: CGFloat(0), point: middle)
            for step in -4...4 {
                let angle = Double(step) * 0.175
                let found = run(through: middle, angle: angle, in: territory)
                let score = Double(found.length) * (1 - 0.12 * abs(angle))
                if score > best.score { best = (score, angle, found.length, found.middle) }
            }
            return AtlasChart.Place(region: site.region, point: best.point, angle: best.angle, room: best.length - 6)
        }

        // Titles and monsters go in the nearest open water big enough for them.
        let roseBox = rose.radius * size.width + 14
        var taken = [CGRect(x: rose.x * size.width - roseBox, y: rose.y * size.height - roseBox, width: roseBox * 2, height: roseBox * 2),
                     CGRect(x: size.width - 100, y: size.height - 50, width: 80, height: 30)]
        func openWater(near: CGPoint, halfWidth: CGFloat, halfHeight: CGFloat) -> CGPoint? {
            var found: CGPoint?, nearest = CGFloat.greatestFiniteMagnitude
            for y in stride(from: 24 + halfHeight, through: size.height - 24 - halfHeight, by: 6) {
                for x in stride(from: 24 + halfWidth, through: size.width - 24 - halfWidth, by: 6) {
                    let d = hypot(x - near.x, y - near.y)
                    guard d < nearest else { continue }
                    let box = CGRect(x: x - halfWidth, y: y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)
                    guard !taken.contains(where: box.intersects) else { continue }
                    let steps: [CGFloat] = [-1, -0.5, 0, 0.5, 1]
                    let clear = steps.allSatisfy { i in
                        steps.allSatisfy { j in
                            toLand[Int((y + j * halfHeight) * scale) * width + Int((x + i * halfWidth) * scale)] / s > 4
                        }
                    }
                    if clear { found = CGPoint(x: x, y: y); nearest = d }
                }
            }
            if let found { taken.append(CGRect(x: found.x - halfWidth, y: found.y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)) }
            return found
        }
        var titles: [Land: CGPoint] = [:]
        for (land, halfWidth) in [(Land.kingPawn, CGFloat(70)), (.queenPawn, 76), (.flank, 42)] {
            titles[land] = openWater(near: centres[land]!, halfWidth: halfWidth, halfHeight: 17)
        }
        let dragons = places.indices.filter { places[$0].region.isDragon }.sorted { places[$0].region.losses > places[$1].region.losses }
        for index in dragons.prefix(3) {
            places[index].dragon = openWater(near: places[index].point, halfWidth: 44, halfHeight: 24)
        }
        return AtlasChart(image: image, size: size, scale: scale, places: places, titles: titles, labels: labels, pixelWidth: width)
    }

    fileprivate static func image(from pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        pixels.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}
