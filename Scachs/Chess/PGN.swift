struct PGNMove: Sendable {
    var san: String
    var move: Move
    var clock: Double?
    var evalCp: Int?
    var evalMate: Int?
    var nags: [Int]
    var comment: String?
}

struct PGNGame: Sendable {
    var tags: [String: String]
    var startFEN: String?
    var moves: [PGNMove]
    var result: String
}

enum PGN {
    static func parse(_ text: String) -> [PGNGame] {
        var parser = PGNParser(bytes: Array(text.utf8))
        parser.run()
        return parser.games
    }
}

private enum Byte {
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let quote = UInt8(ascii: "\"")
    static let backslash = UInt8(ascii: "\\")
    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let openParen = UInt8(ascii: "(")
    static let closeParen = UInt8(ascii: ")")
    static let semicolon = UInt8(ascii: ";")
    static let dollar = UInt8(ascii: "$")
    static let percent = UInt8(ascii: "%")
    static let dot = UInt8(ascii: ".")
}

private let resultTokens: Set<String> = ["1-0", "0-1", "1/2-1/2", "*"]
// Annotation glyphs that can stand alone in movetext and carry nothing the model stores.
private let ignoredGlyphs: Set<String> = [
    "+", "#", "e.p.", "e.p", "ep", "N", "=", "+-", "-+", "+=", "=+", "+/-", "-/+", "+/=", "=/+", "∞", "±", "∓",
]

private func isWhitespace(_ byte: UInt8) -> Bool {
    byte == Byte.space || byte == Byte.lineFeed || byte == Byte.carriageReturn || byte == Byte.tab
}

private func isLineEnd(_ byte: UInt8) -> Bool {
    byte == Byte.lineFeed || byte == Byte.carriageReturn
}

private func isDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
}

private func isLetter(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
}

private struct PGNParser {
    let bytes: [UInt8]
    var i = 0
    var games: [PGNGame] = []

    // The game being read.
    var tags: [String: String] = [:]
    var moves: [PGNMove] = []
    var position: Position?
    var stopped = false
    var inMovetext = false
    var variationDepth = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func run() {
        while i < bytes.count {
            let byte = bytes[i]
            if isWhitespace(byte) {
                i += 1
            } else if isByteOrderMark(at: i) {
                i += 3
            } else if isNoBreakSpace(at: i) {
                i += 2
            } else if byte == Byte.percent, isAtLineStart(i) {
                skipToLineEnd()
            } else if byte == Byte.semicolon {
                readLineComment()
            } else if byte == Byte.openBracket {
                readTag()
            } else if byte == Byte.openBrace {
                readBraceComment()
            } else if byte == Byte.openParen {
                variationDepth += 1
                i += 1
            } else if byte == Byte.closeParen {
                variationDepth = max(0, variationDepth - 1)
                i += 1
            } else if byte == Byte.dollar {
                readNAG()
            } else if byte == Byte.closeBrace || byte == Byte.closeBracket {
                i += 1
            } else {
                readSymbol()
            }
        }
        finishGame(result: nil)
    }

    // MARK: - Lexical helpers

    private func isByteOrderMark(at index: Int) -> Bool {
        index >= 0 && index + 2 < bytes.count
            && bytes[index] == 0xEF && bytes[index + 1] == 0xBB && bytes[index + 2] == 0xBF
    }

    private func isNoBreakSpace(at index: Int) -> Bool {
        index + 1 < bytes.count && bytes[index] == 0xC2 && bytes[index + 1] == 0xA0
    }

    private func isAtLineStart(_ index: Int) -> Bool {
        index == 0 || isLineEnd(bytes[index - 1]) || isByteOrderMark(at: index - 3)
    }

    private mutating func skipToLineEnd() {
        while i < bytes.count, !isLineEnd(bytes[i]) { i += 1 }
    }

    private func isSymbolEnd(at index: Int) -> Bool {
        let byte = bytes[index]
        return isWhitespace(byte) || byte == Byte.openBrace || byte == Byte.closeBrace || byte == Byte.openParen || byte == Byte.closeParen
            || byte == Byte.semicolon || byte == Byte.dollar || byte == Byte.openBracket || byte == Byte.closeBracket
            || byte == UInt8(ascii: "*") || isNoBreakSpace(at: index)
    }

    // MARK: - Tags

    // `[Name "`: returns the name and the index just past the opening quote.
    private func tagHead(at start: Int) -> (name: Range<Int>, valueStart: Int)? {
        var j = start + 1
        while j < bytes.count, bytes[j] == Byte.space || bytes[j] == Byte.tab { j += 1 }
        let nameStart = j
        while j < bytes.count, isLetter(bytes[j]) || isDigit(bytes[j]) || bytes[j] == UInt8(ascii: "_") { j += 1 }
        let nameEnd = j
        guard nameEnd > nameStart else { return nil }
        while j < bytes.count, bytes[j] == Byte.space || bytes[j] == Byte.tab { j += 1 }
        guard j < bytes.count, bytes[j] == Byte.quote else { return nil }
        return (nameStart..<nameEnd, j + 1)
    }

    // A quote closes the value only if `]` or the end of the line follows, so that
    // exports with bare inner quotes (`[Event "the "big" one"]`) still read correctly.
    private func closesTagValue(quoteAt index: Int) -> Bool {
        var j = index + 1
        while j < bytes.count, bytes[j] == Byte.space || bytes[j] == Byte.tab { j += 1 }
        return j == bytes.count || bytes[j] == Byte.closeBracket || isLineEnd(bytes[j])
    }

    private mutating func readTag() {
        guard let head = tagHead(at: i) else {
            while i < bytes.count, bytes[i] != Byte.closeBracket, !isLineEnd(bytes[i]) { i += 1 }
            if i < bytes.count, bytes[i] == Byte.closeBracket { i += 1 }
            return
        }
        if inMovetext { finishGame(result: nil) }
        variationDepth = 0

        var value: [UInt8] = []
        var j = head.valueStart
        while j < bytes.count, !isLineEnd(bytes[j]) {
            let byte = bytes[j]
            if byte == Byte.backslash, j + 1 < bytes.count, bytes[j + 1] == Byte.quote || bytes[j + 1] == Byte.backslash {
                value.append(bytes[j + 1])
                j += 2
            } else if byte == Byte.quote, closesTagValue(quoteAt: j) {
                j += 1
                break
            } else {
                value.append(byte)
                j += 1
            }
        }
        while j < bytes.count, bytes[j] == Byte.space || bytes[j] == Byte.tab { j += 1 }
        if j < bytes.count, bytes[j] == Byte.closeBracket { j += 1 }
        i = j

        tags[String(decoding: bytes[head.name], as: UTF8.self)] = String(decoding: value, as: UTF8.self)
    }

    // MARK: - Movetext

    private mutating func readNAG() {
        var j = i + 1
        while j < bytes.count, isDigit(bytes[j]) { j += 1 }
        if canAnnotate, let nag = Int(String(decoding: bytes[(i + 1)..<j], as: UTF8.self)) {
            moves[moves.count - 1].nags.append(nag)
        }
        i = j
    }

    private var canAnnotate: Bool {
        variationDepth == 0 && !stopped && !moves.isEmpty
    }

    private mutating func readSymbol() {
        let start = i
        i += 1
        while i < bytes.count, !isSymbolEnd(at: i) { i += 1 }
        let token = String(decoding: bytes[start..<i], as: UTF8.self)
        inMovetext = true

        if resultTokens.contains(token) {
            if variationDepth == 0 { finishGame(result: token) }
            return
        }
        guard variationDepth == 0, !stopped else { return }

        guard let san = strippingMoveNumber(start..<i) else { return }
        if ignoredGlyphs.contains(san) { return }
        if let nag = nag(forGlyphsIn: san), san.utf8.allSatisfy({ $0 == UInt8(ascii: "!") || $0 == UInt8(ascii: "?") }) {
            if canAnnotate { moves[moves.count - 1].nags.append(nag) }
            return
        }
        play(san)
    }

    // "12." and "12..." alone give nil; "12.Nf3" gives "Nf3"; "0-0" stays whole.
    private func strippingMoveNumber(_ range: Range<Int>) -> String? {
        var j = range.lowerBound
        while j < range.upperBound, isDigit(bytes[j]) { j += 1 }
        if j == range.upperBound { return nil }
        if j > range.lowerBound, bytes[j] != Byte.dot { j = range.lowerBound }
        while j < range.upperBound, bytes[j] == Byte.dot { j += 1 }
        if j == range.upperBound { return nil }
        return String(decoding: bytes[j..<range.upperBound], as: UTF8.self)
    }

    private func nag(forGlyphsIn san: String) -> Int? {
        let glyphs = san.utf8.filter { $0 == UInt8(ascii: "!") || $0 == UInt8(ascii: "?") }
        switch String(decoding: glyphs, as: UTF8.self) {
        case "!": return 1
        case "?": return 2
        case "!!": return 3
        case "??": return 4
        case "!?": return 5
        case "?!": return 6
        default: return nil
        }
    }

    private mutating func play(_ san: String) {
        if position == nil {
            guard let start = startPosition() else {
                stopped = true
                return
            }
            position = start
        }
        guard let current = position, let move = current.move(san: san) else {
            stopped = true
            return
        }
        var nags: [Int] = []
        if let nag = nag(forGlyphsIn: san) { nags.append(nag) }
        moves.append(PGNMove(san: current.san(move), move: move, nags: nags))
        position = current.applying(move)
    }

    private var setUpFEN: String? {
        guard tags["SetUp"] != "0" else { return nil }
        return tags["FEN"]
    }

    private func startPosition() -> Position? {
        guard let fen = setUpFEN else { return .start }
        return Position(fen: fen)
    }

    private mutating func finishGame(result: String?) {
        if !tags.isEmpty || !moves.isEmpty {
            // Normalised, because the raw tag can hold stale rights that Stockfish reads differently.
            let startFEN = setUpFEN.flatMap { Position(fen: $0)?.fen }
            let tagResult = tags["Result"].flatMap { resultTokens.contains($0) ? $0 : nil }
            games.append(PGNGame(tags: tags, startFEN: startFEN, moves: moves, result: result ?? tagResult ?? "*"))
        }
        tags = [:]
        moves = []
        position = nil
        stopped = false
        inMovetext = false
        variationDepth = 0
    }

    // MARK: - Comments

    private mutating func readLineComment() {
        let start = i + 1
        skipToLineEnd()
        addComment(start..<i)
    }

    private mutating func readBraceComment() {
        let start = i + 1
        var j = start
        while j < bytes.count, bytes[j] != Byte.closeBrace {
            // A missing `}` must not swallow the games that follow it.
            if bytes[j] == Byte.openBracket, isLineEnd(bytes[j - 1]), tagHead(at: j) != nil { break }
            j += 1
        }
        addComment(start..<j)
        i = j < bytes.count && bytes[j] == Byte.closeBrace ? j + 1 : j
    }

    private mutating func addComment(_ range: Range<Int>) {
        guard canAnnotate else { return }
        let last = moves.count - 1
        var text: [UInt8] = []
        var j = range.lowerBound
        while j < range.upperBound {
            if bytes[j] == Byte.openBracket, let next = applyCommand(at: j, end: range.upperBound) {
                j = next
            } else {
                text.append(bytes[j])
                j += 1
            }
        }
        guard let cleaned = collapsingWhitespace(text) else { return }
        if let existing = moves[last].comment {
            moves[last].comment = existing + " " + cleaned
        } else {
            moves[last].comment = cleaned
        }
    }

    private func collapsingWhitespace(_ text: [UInt8]) -> String? {
        var out: [UInt8] = []
        out.reserveCapacity(text.count)
        for byte in text {
            if isWhitespace(byte) {
                if let last = out.last, last != Byte.space { out.append(Byte.space) }
            } else {
                out.append(byte)
            }
        }
        if out.last == Byte.space { out.removeLast() }
        return out.isEmpty ? nil : String(decoding: out, as: UTF8.self)
    }

    // Reads `[%clk ...]` or `[%eval ...]` into the move and returns the index past it.
    // Anything else, including values that do not parse, returns nil and stays in the comment.
    private mutating func applyCommand(at start: Int, end: Int) -> Int? {
        var j = start + 1
        while j < end, isWhitespace(bytes[j]) { j += 1 }
        guard j < end, bytes[j] == Byte.percent else { return nil }
        j += 1
        let nameStart = j
        while j < end, isLetter(bytes[j]) { j += 1 }
        let name = String(decoding: bytes[nameStart..<j], as: UTF8.self)
        guard name == "clk" || name == "eval" else { return nil }
        let valueStart = j
        while j < end, bytes[j] != Byte.closeBracket { j += 1 }
        guard j < end else { return nil }
        let value = String(decoding: bytes[valueStart..<j].filter { !isWhitespace($0) }, as: UTF8.self)

        if name == "clk" {
            guard let seconds = parseClock(value) else { return nil }
            moves[moves.count - 1].clock = seconds
        } else {
            guard let eval = parseEval(value) else { return nil }
            moves[moves.count - 1].evalCp = eval.cp
            moves[moves.count - 1].evalMate = eval.mate
        }
        return j + 1
    }
}

// Digits with at most one dot. Keeps "inf", "nan" and exponents away from Double and Int conversions.
private func isPlainDecimal<S: StringProtocol>(_ text: S) -> Bool {
    var digits = 0
    var dots = 0
    for byte in text.utf8 {
        if byte == Byte.dot {
            dots += 1
        } else if isDigit(byte) {
            digits += 1
        } else {
            return false
        }
    }
    return digits > 0 && dots <= 1
}

// H:MM:SS(.t) or M:SS(.t), in seconds.
private func parseClock(_ value: String) -> Double? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2 || parts.count == 3 else { return nil }
    var total = 0.0
    for part in parts {
        guard isPlainDecimal(part), let number = Double(part) else { return nil }
        total = total * 60 + number
    }
    return total.isFinite ? total : nil
}

// +-p.pp(,depth) in pawns, or #+-n(,depth) as a mate distance. Both already from White's view.
private func parseEval(_ value: String) -> (cp: Int?, mate: Int?)? {
    var rest = value.prefix { $0 != "," }
    var negative = false
    func takeSign() {
        if rest.hasPrefix("+") {
            rest.removeFirst()
        } else if rest.hasPrefix("-") {
            rest.removeFirst()
            negative.toggle()
        }
    }
    takeSign()
    if rest.hasPrefix("#") {
        rest.removeFirst()
        takeSign()
        guard rest.utf8.allSatisfy(isDigit), let mate = Int(rest) else { return nil }
        return (nil, negative ? -mate : mate)
    }
    guard isPlainDecimal(rest), let pawns = Double(rest), pawns < 1_000_000 else { return nil }
    let cp = Int((pawns * 100).rounded())
    return (negative ? -cp : cp, nil)
}
