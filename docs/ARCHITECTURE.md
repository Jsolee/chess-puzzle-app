# Scachs architecture

Native iOS 26+ app. SwiftUI for every screen, one Metal view for the board. Stockfish 19 vendored in-process. GPL-3.0-or-later. No third-party Swift packages. Project is generated: `xcodegen generate` from `project.yml`; sources under `Scachs/` are picked up by folder, so adding a file needs no project edit. Swift 5 language mode.

House rules for code: match the surrounding idiom, comments only for non-obvious logic, no abstractions with one implementation, fewest files. Non-trivial logic leaves one runnable check in `Tests/`. UI copy in Catalan as source strings (`Text("...")`, `String(localized:)`), informal "tu", no exclamation marks, no em dashes.

## Module map and contracts

### Scachs/Chess (rules core, no UIKit)
```swift
enum Side: UInt8, Codable { case white, black; var opposite: Side }
enum PieceKind: UInt8, Codable, CaseIterable { case pawn, knight, bishop, rook, queen, king }
struct Piece: Hashable, Codable { var kind: PieceKind; var side: Side }
typealias Square = Int   // 0 = a1, 7 = h1, 56 = a8, 63 = h8
func squareName(_ s: Square) -> String      // "e4"
func square(named: String) -> Square?
struct Move: Hashable, Codable { var from: Square; var to: Square; var promotion: PieceKind?; var uci: String { get }; init?(uci: String) }
struct Position: Hashable {
    static let start: Position
    init?(fen: String)                       // tolerant: accepts 4-field FEN
    var fen: String { get }
    var epd: String { get }                  // 4 fields; ep square only if an ep capture is legal (python-chess epd() rule)
    var side: Side { get }
    var halfmoveClock: Int { get }; var fullmoveNumber: Int { get }
    func piece(at: Square) -> Piece?
    func legalMoves() -> [Move]
    func legalMoves(from: Square) -> [Move]
    func isLegal(_ m: Move) -> Bool
    func applying(_ m: Move) -> Position     // caller guarantees legality
    var inCheck: Bool { get }; var isCheckmate: Bool { get }; var isStalemate: Bool { get }
    var hasInsufficientMaterial: Bool { get }
    func attackers(of: Square, by: Side) -> [Square]
    func king(of: Side) -> Square?
    func san(_ m: Move) -> String
    func move(san: String) -> Move?          // tolerant: O-O/0-0, e8=Q/e8Q, suffixes !?+#, e.p.
    func move(uci: String) -> Move?          // normalises king-takes-rook castling (e1h1 -> e1g1)
    func perft(_ depth: Int) -> UInt64
}
struct PGNMove { var san: String; var move: Move; var clock: Double?; var evalCp: Int?; var evalMate: Int?; var nags: [Int]; var comment: String? }
struct PGNGame { var tags: [String: String]; var startFEN: String?; var moves: [PGNMove]; var result: String }
enum PGN { static func parse(_ text: String) -> [PGNGame] }  // multi-game, BOM, CRLF, comments, %clk %eval %csl %cal, NAGs, variations skipped, 1-0 0-1 1/2-1/2 *
```

### Scachs/Board (Metal board, written by the design owner)
```swift
@Observable final class BoardModel {
    var position: Position; var orientation: Side; var interactive: Bool
    var lastMove: Move?; var hint: Square?; var arrows: [BoardArrow]; var marks: [BoardMark]
    var onMove: ((Move) -> Void)?
    func play(_ m: Move, animated: Bool = true)    // animates, updates position, sound and haptics
    func set(_ p: Position, animated: Bool = true)
    func flashWrong(_ s: Square)
    func reflex(from: Square)                       // the signature wave across the board on success
}
struct BoardView: View { init(_ model: BoardModel) }   // always square, fills the proposed width
struct BoardArrow { var from: Square; var to: Square; var role: ArrowRole }   // .best .threat .idea .opponent
struct BoardMark { var square: Square; var role: MarkRole }                   // tints; plus a move-class badge option
```

### Scachs/Design
`Theme` (colours and fonts), `Sound`, `Haptics`. Colours: `Theme.field` (#0f3a33 deep copper green), `Theme.tin` (#f6f1e6), `Theme.ink` (#16121c), `Theme.gold` (#e7b96c), `Theme.tileDark` (#2c6f5e). Fonts: `Theme.display(size)` Grenze Gotisch Medium, display only, 28 pt and up, never for notation; `Theme.text(size, weight)` Ysabeau Office for everything else, tabular digits by default.

### Scachs/Engine
```swift
enum Score: Hashable, Codable { case cp(Int), mate(Int) }     // side to move's view; mate in plies per Stockfish convention converted to moves
struct EngineLine: Hashable { var multipv: Int; var depth: Int; var score: Score; var pv: [Move]; var nodes: Int; var wdl: WDL? = nil }
enum EngineError: Error { case netMissing, netCorrupt, lowMemory, invalidPosition(String), illegalSearchMove }
actor Engine {
    static let shared: Engine
    func analyse(startFEN: String, moves: [Move], multiPV: Int, nodes: Int?, movetimeMs: Int?, searchMoves: [Move]?, onUpdate: (@Sendable ([EngineLine]) -> Void)?) async throws -> [EngineLine]   // calls run in order; empty if stopped before depth 2; Task cancellation throws CancellationError
    nonisolated func stop()                       // running search only; a stop before it starts does nothing, so prefer Task cancellation
    nonisolated func shutdown() async             // frees the engine, the next analyse reloads it; also runs on memory warnings
    func clearHash()                              // between games
    static func budget(_ nodes: Int) -> Int       // scales a node budget for thermal state and Low Power Mode
}
```

### Scachs/Review
`MoveClass` (brilliant great best excellent good book inaccuracy mistake miss blunder forced), `Classifier`, `Accuracy`, `Openings`, `ReviewEngine` (two-pass), `Coach` (rule-based text), `GameReview` Codable model, `ReviewView`.

### Scachs/Games
`ChessComClient`, `LichessClient`, `GameLibrary` (Codable, Application Support), `ImportedGame`, `GamesView`.

### Scachs/Puzzles
`PuzzleStore` (mmap of `puzzles.bin`), `Glicko2`, `PuzzleSession`, `Progress` (attempt log, Application Support), `PuzzleView`.

### Scachs/Lessons
`Lesson` model decoded from `Resources/Lessons/*.json`, `LessonRunner`, `Recommender`, `LessonsView`.

### Persistence
Plain Codable JSON files in Application Support, written atomically. No database.

## Licences
App: GPL-3.0-or-later. Stockfish: GPLv3, keep `AUTHORS` and `Copying.txt`. Net: CC0. Puzzles and chess-openings: CC0. Fonts: OFL. Do not port AGPL code (lila, lichess-puzzler, Chesskit); reimplement from formulas. Chess.com icon art and palette are not to be reproduced: same class names and bands, our own glyphs.

## Contract: Scachs/Puzzles (non-UI)
```swift
struct Puzzle: Identifiable, Hashable {
    let id: String; let index: Int             // Lichess id; record index in puzzles.bin
    let start: Position                        // the FEN position, before the opponent's setup move
    let line: [Move]                           // line[0] is the setup move; line[1...] alternate solver, reply, solver...
    let rating: Int; let themes: [String]; let popularity: Int
    var solverSide: Side { get }               // start.side.opposite
}
final class PuzzleStore {
    static let shared: PuzzleStore
    var count: Int { get }
    func puzzle(at index: Int) -> Puzzle
    func find(target: Int, anyOf themes: Set<String>?, excluding played: (Int) -> Bool) -> Puzzle?   // widening window around target
    func daily(for date: Date) -> Puzzle
}
struct PuzzleRun {                             // one attempt at one puzzle
    let puzzle: Puzzle
    var step: Int                              // index in line of the next expected solver move
    enum Outcome: Equatable { case correct(reply: Move?), solved, wrong }
    init(_ puzzle: Puzzle)
    mutating func attempt(_ m: Move, on position: Position) -> Outcome   // any checkmate wins; castling forms normalised
    var expected: Move? { get }
}
enum AttemptContext: String, Codable { case blind, themed, lesson, retry }
struct Attempt: Codable { var puzzleID: String; var index: Int; var date: Date; var solved: Bool; var hinted: Bool; var context: AttemptContext; var puzzleRating: Int; var ratingBefore: Double; var themes: [String] }
@Observable final class Progress {
    static let shared: Progress
    var rating: Double { get }; var deviation: Double { get }; var isProvisional: Bool { get }   // RD >= 110
    var attempts: [Attempt] { get }
    var completedLessons: Set<String>
    var dismissedLessons: [String: Date]
    func setInitialRating(_ r: Double)
    func record(_ p: Puzzle, solved: Bool, hinted: Bool, context: AttemptContext) -> Double    // returns the rating change, 0 if unrated
    func played(_ index: Int) -> Bool
    func save()
}
final class PuzzleSession {                    // ten puzzles: 1 warm-up at p .85, 6 core at p .70-.75, 1 stretch at p .50, up to 2 due retries
    init(progress: Progress, store: PuzzleStore)
    private(set) var results: [Bool?]          // one entry per slot, nil until played
    var current: Int { get }
    func next() -> (Puzzle, AttemptContext)?   // nil when the session is over
    func finish(solved: Bool)
    var harderBias: Int                        // -1 easier, 0, +1 harder
}
enum ThemeNames { static func name(_ tag: String) -> String }     // localised Catalan-source display name for a Lichess theme tag
```

## Contract: Recommender (Scachs/Lessons)
```swift
struct LessonMeta: Identifiable, Hashable { let id: String; let title: String; let level: Int; let section: String; let minutes: Int; let requires: [String]; let tags: [String: Double] }
enum Recommender {
    struct Pick { let lesson: LessonMeta; let weak: Bool }   // weak true only under the z <= -1.5 rule
    static func next(progress: Progress, lessons: [LessonMeta], reviewEvidence: [String: Double]) -> Pick?
}
```
