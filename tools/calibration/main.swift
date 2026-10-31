// Samples positions from a Lichess PGN stream for evaluate.py and fit.py. Lichess database exports are CC0.
// usage: curl ... | zstd -dc | sample --per-band 4000 > positions.tsv
// Stops reading, which closes the pipe and ends the download, as soon as every band has its quota.
//
// Only rated standard games at blitz or slower, between players within 100 points of each other, so that
// the rating gap doesn't leak into what the evaluation predicts. Abandoned games are dropped.
// At most two positions per game: neighbouring positions of one game say almost the same thing.
import Foundation

let bandWidth = 200
let bands = stride(from: 600, through: 2400, by: bandWidth).map { $0 }   // lower edges; below 600 and above 2600 clamp

var perBand = 4000
if let i = CommandLine.arguments.firstIndex(of: "--per-band"), i + 1 < CommandLine.arguments.count {
    perBand = Int(CommandLine.arguments[i + 1]) ?? perBand
}
var filled = [Int: Int]()
func band(_ rating: Int) -> Int { min(max((rating - 600) / bandWidth, 0), bands.count - 1) }

struct SplitMix { var s: UInt64; mutating func next() -> UInt64 {
    s &+= 0x9E3779B97F4A7C15; var z = s
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
} }

func tag(_ name: String, in header: [Substring]) -> String? {
    let prefix = "[\(name) \""
    guard let line = header.first(where: { $0.hasPrefix(prefix) }), line.hasSuffix("\"]") else { return nil }
    return String(line.dropFirst(prefix.count).dropLast(2))
}

var gamesSeen = 0, gamesUsed = 0

func handle(_ text: String, header: [Substring]) {
    gamesSeen += 1
    guard let event = tag("Event", in: header), event.hasPrefix("Rated"),
          event.contains("Blitz") || event.contains("Rapid") || event.contains("Classical"),
          let w = tag("WhiteElo", in: header).flatMap({ Int($0) }), let b = tag("BlackElo", in: header).flatMap({ Int($0) }),
          abs(w - b) <= 100,
          let term = tag("Termination", in: header), term == "Normal" || term == "Time forfeit",
          let result = tag("Result", in: header), ["1-0", "0-1", "1/2-1/2"].contains(result),
          tag("FEN", in: header) == nil
    else { return }
    if filled[band(w), default: 0] >= perBand && filled[band(b), default: 0] >= perBand { return }
    guard let game = PGN.parse(text).first, game.moves.count >= 24 else { return }
    let speed = event.contains("Blitz") ? "blitz" : event.contains("Rapid") ? "rapid" : "classical"
    var rng = SplitMix(s: UInt64(truncatingIfNeeded: text.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }))
    let first = 12 + Int(rng.next() % UInt64(game.moves.count - 16))
    let second = 12 + Int(rng.next() % UInt64(game.moves.count - 16))
    var picks: Set<Int> = [first]
    if abs(second - first) >= 20 { picks.insert(second) }
    var pos = Position.start
    var used = false
    for (ply, m) in game.moves.enumerated() {
        if picks.contains(ply) {
            // Half the records take the side to move, half the other side: the app asks for both.
            let whiteView = rng.next() & 1 == 0
            let rating = whiteView ? w : b, bandIndex = band(rating)
            if filled[bandIndex, default: 0] < perBand {
                filled[bandIndex, default: 0] += 1
                let score = result == "1/2-1/2" ? "0.5" : ((result == "1-0") == whiteView ? "1" : "0")
                print([pos.fen, whiteView ? "w" : "b", "\(rating)", "\(whiteView ? b : w)", score, "\(gamesUsed)", "\(ply)", speed, term].joined(separator: "\t"))
                used = true
            }
        }
        pos = pos.applying(m.move)
    }
    if used { gamesUsed += 1 }
    if gamesSeen % 20000 == 0 { FileHandle.standardError.write(Data("seen \(gamesSeen) used \(gamesUsed) \(bands.indices.map { filled[$0, default: 0] })\n".utf8)) }
    if bands.indices.allSatisfy({ filled[$0, default: 0] >= perBand }) {
        FileHandle.standardError.write(Data("quotas met after \(gamesSeen) games\n".utf8))
        exit(0)
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
var header: [Substring] = []
var current = ""
var inMoves = false
while let line = readLine(strippingNewline: true) {
    if line.hasPrefix("[") && inMoves {
        handle(current, header: header)
        header = []; current = ""; inMoves = false
    }
    if line.hasPrefix("[") { header.append(Substring(line)) } else if !line.isEmpty { inMoves = true }
    current += line; current += "\n"
}
if inMoves { handle(current, header: header) }
FileHandle.standardError.write(Data("end of input: seen \(gamesSeen) used \(gamesUsed) \(bands.indices.map { filled[$0, default: 0] })\n".utf8))
