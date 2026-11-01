import CoreGraphics
import CoreText
import Foundation

/// Reads a chess position out of a screenshot, with no model and no network: finds the checker pattern, then matches
/// each square's silhouette against reference pieces. It will get some wrong, so its result always goes to an editor first.
enum BoardReader {
    struct Reading {
        /// a1 is 0, h8 is 63.
        var pieces: [Piece?]
        var box: CGRect
    }

    private static let cell = 48
    private static let grid = 32

    // MARK: Pixels

    private struct Bitmap {
        let width: Int, height: Int
        var rgb: [UInt8]

        init?(_ image: CGImage, maxSide: Int) {
            let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
            width = max(1, Int(Double(image.width) * scale))
            height = max(1, Int(Double(image.height) * scale))
            rgb = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &rgb, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        @inline(__always) func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(rgb[i]), Int(rgb[i + 1]), Int(rgb[i + 2]))
        }
    }

    /// Summed-area table of brightness, so the box search can afford to ask about thousands of boxes.
    private struct Integral {
        let width: Int
        var sums: [Int]

        init(_ b: Bitmap) {
            width = b.width + 1
            sums = [Int](repeating: 0, count: width * (b.height + 1))
            for y in 0..<b.height {
                var row = 0
                for x in 0..<b.width {
                    let (r, g, bl) = b.pixel(x, y)
                    row += (r * 3 + g * 6 + bl) / 10
                    sums[(y + 1) * width + x + 1] = sums[y * width + x + 1] + row
                }
            }
        }

        @inline(__always) func mean(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Double {
            let a = sums[y * width + x], b = sums[y * width + x + w], c = sums[(y + h) * width + x], d = sums[(y + h) * width + x + w]
            return Double(d - b - c + a) / Double(max(w * h, 1))
        }
    }

    // MARK: Finding the board

    /// How much a box looks like a board: its squares' corners, where pieces rarely reach, should split into two flat colours.
    private static func checkerScore(_ integral: Integral, x: Int, y: Int, size: Int) -> Double {
        let unit = Double(size) / 8
        let patch = max(1, Int(unit * 0.1))
        var even: [Double] = [], odd: [Double] = []
        even.reserveCapacity(32); odd.reserveCapacity(32)
        for row in 0..<8 {
            for column in 0..<8 {
                let left = x + Int(Double(column) * unit + unit * 0.06), top = y + Int(Double(row) * unit + unit * 0.06)
                let far = Int(unit * 0.94) - Int(unit * 0.06) - patch
                let m = (integral.mean(left + far, top, patch, patch) + integral.mean(left, top + far, patch, patch)) / 2
                if (row + column) % 2 == 0 { even.append(m) } else { odd.append(m) }
            }
        }
        even.sort(); odd.sort()
        let a = even[even.count / 2], b = odd[odd.count / 2]
        let spread = (even.reduce(0) { $0 + abs($1 - a) } + odd.reduce(0) { $0 + abs($1 - b) }) / 64
        return abs(a - b) / (6 + spread)
    }

    private static func findBoard(_ bitmap: Bitmap, _ integral: Integral) -> (x: Int, y: Int, size: Int, score: Double)? {
        var best: (x: Int, y: Int, size: Int, score: Double)?
        let side = min(bitmap.width, bitmap.height)
        var size = side
        while size >= side * 3 / 10 {
            let step = max(1, size / 80)
            var y = 0
            while y + size <= bitmap.height {
                var x = 0
                while x + size <= bitmap.width {
                    let s = checkerScore(integral, x: x, y: y, size: size)
                    if s > (best?.score ?? 0) { best = (x, y, size, s) }
                    x += step
                }
                y += step
            }
            size -= max(1, side / 50)
        }
        return best
    }

    // MARK: Reading a square

    private static func silhouette(of mask: [Bool], size: Int) -> [Bool] {
        // Anything the outside can't reach is part of the piece, which fills in the holes of an outlined drawing.
        var outside = [Bool](repeating: false, count: size * size)
        var stack: [Int] = []
        for i in 0..<size {
            for p in [i, size * size - 1 - i, i * size, i * size + size - 1] where !mask[p] && !outside[p] {
                outside[p] = true
                stack.append(p)
            }
        }
        while let p = stack.popLast() {
            let x = p % size, y = p / size
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < size && ny < size {
                let q = ny * size + nx
                if !mask[q] && !outside[q] { outside[q] = true; stack.append(q) }
            }
        }
        return outside.map { !$0 }
    }

    /// Fitted to a square by height, so a king stays tall and a pawn stays squat next to it only through its own shape.
    private static func normalised(_ shape: [Bool], size: Int) -> [Bool]? {
        var minX = size, maxX = -1, minY = size, maxY = -1
        for y in 0..<size { for x in 0..<size where shape[y * size + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX else { return nil }
        let w = maxX - minX + 1, h = maxY - minY + 1
        let scale = Double(max(w, h)) / Double(grid)
        let offsetX = (Double(grid) - Double(w) / scale) / 2, offsetY = (Double(grid) - Double(h) / scale) / 2
        var out = [Bool](repeating: false, count: grid * grid)
        for gy in 0..<grid { for gx in 0..<grid {
            let sx = Int((Double(gx) - offsetX) * scale) + minX, sy = Int((Double(gy) - offsetY) * scale) + minY
            if sx >= minX, sx <= maxX, sy >= minY, sy <= maxY, shape[sy * size + sx] { out[gy * grid + gx] = true }
        } }
        return out
    }

    private static func overlap(_ a: [Bool], _ b: [Bool]) -> Double {
        var both = 0, either = 0
        for i in a.indices {
            if a[i] && b[i] { both += 1 }
            if a[i] || b[i] { either += 1 }
        }
        return Double(both) / Double(max(either, 1))
    }

    private static func readSquare(_ bitmap: Bitmap, x: Double, y: Double, unit: Double, templates: [(PieceKind, [Bool])]) -> Piece? {
        var pixels = [(Int, Int, Int)](repeating: (0, 0, 0), count: cell * cell)
        for cy in 0..<cell { for cx in 0..<cell {
            let px = min(bitmap.width - 1, Int(x + (Double(cx) + 0.5) / Double(cell) * unit))
            let py = min(bitmap.height - 1, Int(y + (Double(cy) + 0.5) / Double(cell) * unit))
            pixels[cy * cell + cx] = bitmap.pixel(px, py)
        } }
        // The square's own colour, from its corners. Coordinates drawn in a corner only nudge the mean of four.
        var bg = (0, 0, 0)
        let corners = [(3, 3), (cell - 4, 3), (3, cell - 4), (cell - 4, cell - 4)]
        var samples: [[Int]] = [[], [], []]
        for (cx, cy) in corners {
            let p = pixels[cy * cell + cx]
            samples[0].append(p.0); samples[1].append(p.1); samples[2].append(p.2)
        }
        bg = (samples[0].sorted()[1], samples[1].sorted()[1], samples[2].sorted()[1])
        var mask = [Bool](repeating: false, count: cell * cell)
        let margin = cell / 10
        var count = 0
        for cy in margin..<(cell - margin) { for cx in margin..<(cell - margin) {
            let p = pixels[cy * cell + cx]
            if abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) > 70 {
                mask[cy * cell + cx] = true
                count += 1
            }
        } }
        guard Double(count) / Double(cell * cell) > 0.05 else { return nil }
        let shape = silhouette(of: mask, size: cell)
        // White pieces are drawn with heavy dark outlines, so their average can read dark. A good share of bright fill can't.
        var inside = 0, bright = 0
        for i in shape.indices where shape[i] {
            let p = pixels[i]
            inside += 1
            if (p.0 * 3 + p.1 * 6 + p.2) / 10 > 170 { bright += 1 }
        }
        let side: Side = Double(bright) / Double(max(inside, 1)) > 0.28 ? .white : .black
        guard let target = normalised(shape, size: cell) else { return nil }
        var bestKind = PieceKind.pawn, bestScore = -1.0
        for (kind, template) in templates {
            let s = overlap(target, template)
            if s > bestScore { bestScore = s; bestKind = kind }
        }
        return Piece(kind: bestKind, side: side)
    }

    // MARK: Reference shapes

    private static let glyphs: [(PieceKind, String)] = [
        (.king, "\u{2654}"), (.queen, "\u{2655}"), (.rook, "\u{2656}"), (.bishop, "\u{2657}"), (.knight, "\u{2658}"), (.pawn, "\u{2659}"),
        (.king, "\u{265A}\u{FE0E}"), (.queen, "\u{265B}\u{FE0E}"), (.rook, "\u{265C}\u{FE0E}"),
        (.bishop, "\u{265D}\u{FE0E}"), (.knight, "\u{265E}\u{FE0E}"), (.pawn, "\u{265F}\u{FE0E}"),
    ]

    /// The chess signs in the system's fonts, plus any drawn pieces passed in. Different sets draw the same Staunton shapes.
    static func templates(extra: [(PieceKind, CGImage)] = []) -> [(PieceKind, [Bool])] {
        var out: [(PieceKind, [Bool])] = []
        // The two iOS fonts that draw chess pieces well. Measured on real screenshots: 64/64 on Lichess's set, 62/64 on chess.com's.
        for name in ["AppleSymbols", "STIXTwoMath-Regular"] {
            for (kind, glyph) in glyphs {
                if let shape = glyphShape(glyph, fontName: name) { out.append((kind, shape)) }
            }
        }
        for (kind, image) in extra {
            if let shape = imageShape(image) { out.append((kind, shape)) }
        }
        return out
    }

    private static func glyphShape(_ glyph: String, fontName: String) -> [Bool]? {
        let size = 128
        var alpha = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(data: &alpha, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        let font = CTFontCreateWithName(fontName as CFString, 96, nil)
        context.setFillColor(gray: 1, alpha: 1)
        let attributed = NSAttributedString(string: glyph, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 14, y: 24)
        CTLineDraw(line, context)
        return silhouetteGrid(alpha.map { $0 > 128 }, size: size)
    }

    private static func imageShape(_ image: CGImage) -> [Bool]? {
        let size = 128
        var alpha = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(data: &alpha, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return silhouetteGrid(alpha.map { $0 > 128 }, size: size)
    }

    private static func silhouetteGrid(_ mask: [Bool], size: Int) -> [Bool]? {
        guard mask.contains(true) else { return nil }
        return normalised(silhouette(of: mask, size: size), size: size)
    }

    // MARK: All together

    static func read(_ image: CGImage, templates: [(PieceKind, [Bool])] = templates()) -> Reading? {
        guard !templates.isEmpty, let small = Bitmap(image, maxSide: 360) else { return nil }
        let integral = Integral(small)
        guard let found = findBoard(small, integral), found.score > 0.6, let full = Bitmap(image, maxSide: 1600) else { return nil }
        let scale = Double(full.width) / Double(small.width)
        let unit = Double(found.size) * scale / 8
        let originX = Double(found.x) * scale, originY = Double(found.y) * scale
        var pieces = [Piece?](repeating: nil, count: 64)
        for row in 0..<8 {
            for column in 0..<8 {
                let square = (7 - row) * 8 + column
                pieces[square] = readSquare(full, x: originX + Double(column) * unit, y: originY + Double(row) * unit, unit: unit, templates: templates)
            }
        }
        if looksFlipped(pieces) { pieces.reverse() }
        return Reading(pieces: pieces, box: CGRect(x: originX, y: originY, width: unit * 8, height: unit * 8))
    }

    /// White's men usually sit nearer White's edge. Screenshots from Black's side turn the board round.
    static func looksFlipped(_ pieces: [Piece?]) -> Bool {
        func averageRank(_ side: Side) -> Double? {
            let ranks = pieces.indices.compactMap { pieces[$0]?.side == side ? Double($0 / 8) : nil }
            return ranks.isEmpty ? nil : ranks.reduce(0, +) / Double(ranks.count)
        }
        guard let white = averageRank(.white), let black = averageRank(.black) else { return false }
        return white > black
    }

    static func fen(_ pieces: [Piece?], sideToMove: Side) -> String {
        var ranks: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var text = "", empty = 0
            for file in 0..<8 {
                guard let p = pieces[rank * 8 + file] else { empty += 1; continue }
                if empty > 0 { text += "\(empty)"; empty = 0 }
                let letter = ["p", "n", "b", "r", "q", "k"][Int(p.kind.rawValue)]
                text += p.side == .white ? letter.uppercased() : letter
            }
            if empty > 0 { text += "\(empty)" }
            ranks.append(text)
        }
        var castling = ""
        func at(_ s: Int, _ k: PieceKind, _ side: Side) -> Bool { pieces[s]?.kind == k && pieces[s]?.side == side }
        if at(4, .king, .white) {
            if at(7, .rook, .white) { castling += "K" }
            if at(0, .rook, .white) { castling += "Q" }
        }
        if at(60, .king, .black) {
            if at(63, .rook, .black) { castling += "k" }
            if at(56, .rook, .black) { castling += "q" }
        }
        return "\(ranks.joined(separator: "/")) \(sideToMove == .white ? "w" : "b") \(castling.isEmpty ? "-" : castling) - 0 1"
    }
}
