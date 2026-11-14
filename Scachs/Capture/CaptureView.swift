import SwiftUI
import PhotosUI

/// A screenshot of a board, read and put in front of you to correct before anything is analysed.
struct CaptureView: View {
    let image: CGImage
    @Environment(\.dismiss) private var dismiss
    @State private var pieces: [Piece?]?
    @State private var failed = false

    var body: some View {
        Group {
            if let pieces {
                PositionEditor(pieces: pieces)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(failed ? "No hi he trobat cap tauler" : "Llegint el tauler").font(Theme.display(40)).foregroundStyle(Theme.tin)
                    if failed {
                        Text("Prova amb una captura on el tauler es vegi sencer, o col·loca les peces a mà.").font(Theme.text(17)).foregroundStyle(Theme.quiet)
                        Button("Col·loca les peces a mà") { self.pieces = Array(repeating: nil, count: 64) }.font(Theme.text(17, .semibold))
                        Button("Tanca") { dismiss() }.font(Theme.text(17, .semibold))
                    } else {
                        ProgressView().tint(Theme.gold)
                    }
                    Spacer()
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fieldBackground()
        .task {
            let image = image
            let extra = pieceTemplates()
            let reading = await Task.detached(priority: .userInitiated) { BoardReader.read(image, templates: BoardReader.templates(extra: extra)) }.value
            if let reading { pieces = reading.pieces } else { failed = true }
        }
    }

    private func pieceTemplates() -> [(PieceKind, CGImage)] {
        let kinds: [(PieceKind, String)] = [(.pawn, "p"), (.knight, "n"), (.bishop, "b"), (.rook, "r"), (.queen, "q"), (.king, "k")]
        return kinds.compactMap { kind, letter in PieceImage.load("w" + letter).cgImage.map { (kind, $0) } }
    }
}

/// Fix what the reader got wrong, or set a position up from nothing, then look at it with the engine.
struct PositionEditor: View {
    @State var pieces: [Piece?]
    @Environment(\.dismiss) private var dismiss
    @State private var brush: Piece?
    @State private var erasing = false
    @State private var sideToMove: Side = .white
    @State private var analysing: Position?

    private static let kinds: [PieceKind] = [.king, .queen, .rook, .bishop, .knight, .pawn]

    private var position: Position? {
        let whiteKings = pieces.filter { $0?.kind == .king && $0?.side == .white }.count
        let blackKings = pieces.filter { $0?.kind == .king && $0?.side == .black }.count
        guard whiteKings == 1, blackKings == 1 else { return nil }
        return Position(fen: BoardReader.fen(pieces, sideToMove: sideToMove))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Tanca").padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("És aquesta?").font(Theme.display(44)).foregroundStyle(Theme.tin)
                    Text("Comprova-la. Toca una peça de sota i després la casella per corregir-la.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                }
                .padding(.horizontal, 20)
                grid
                palette.padding(.horizontal, 20)
                HStack {
                    Button(sideToMove == .white ? "Juguen les blanques" : "Juguen les negres") { sideToMove = sideToMove == .white ? .black : .white }
                    Spacer()
                    Button("Gira el tauler") { pieces.reverse() }
                }
                .font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold).padding(.horizontal, 20)
                Button { analysing = position } label: {
                    Text(position == nil ? "Falta un rei a cada bàndol" : "Analitza").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin.opacity(position == nil ? 0.4 : 1)))
                }
                .disabled(position == nil).padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .fieldBackground()
        .fullScreenCover(item: Binding(get: { analysing.map(AnalysedPosition.init) }, set: { analysing = $0?.position })) { PositionAnalysisView(position: $0.position) }
    }

    private struct AnalysedPosition: Identifiable { let position: Position; var id: String { position.fen } }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        let square = (7 - row) * 8 + column
                        ZStack {
                            ((row + column) % 2 == 0 ? Theme.tileLight : Theme.tileDark)
                            if let piece = pieces[square] { PieceImage(piece: piece).padding(2) }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .contentShape(Rectangle())
                        .onTapGesture { paint(square) }
                    }
                }
            }
        }
    }

    private func paint(_ square: Int) {
        if erasing { pieces[square] = nil }
        else if let brush { pieces[square] = pieces[square] == brush ? nil : brush }
        else { pieces[square] = nil }
        Haptics.tap(0.2, sharpness: 0.4)
    }

    private var palette: some View {
        VStack(spacing: 4) {
            ForEach([Side.white, Side.black], id: \.self) { side in
                HStack(spacing: 4) {
                    ForEach(Self.kinds, id: \.self) { kind in
                        let piece = Piece(kind: kind, side: side)
                        Button { brush = piece; erasing = false } label: {
                            PieceImage(piece: piece).frame(width: 42, height: 42)
                                .background(RoundedRectangle(cornerRadius: 6).fill(brush == piece && !erasing ? Theme.gold.opacity(0.5) : Theme.fieldLift))
                        }
                        .accessibilityLabel(pieceName(piece))
                    }
                    if side == .white {
                        Button { erasing = true; brush = nil } label: {
                            Image(systemName: "eraser").frame(width: 42, height: 42)
                                .background(RoundedRectangle(cornerRadius: 6).fill(erasing ? Theme.gold.opacity(0.5) : Theme.fieldLift))
                        }
                        .foregroundStyle(Theme.tin).accessibilityLabel("Esborra")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func pieceName(_ piece: Piece) -> String {
        let names: [PieceKind: String] = [.king: String(localized: "rei"), .queen: String(localized: "dama"), .rook: String(localized: "torre"), .bishop: String(localized: "alfil"), .knight: String(localized: "cavall"), .pawn: String(localized: "peó")]
        return "\(names[piece.kind] ?? "") \(piece.side == .white ? String(localized: "blanc") : String(localized: "negre"))"
    }
}

/// The engine on a position that isn't part of any game.
struct PositionAnalysisView: View {
    let position: Position
    @Environment(\.dismiss) private var dismiss
    @State private var board = BoardModel()
    @State private var lines: [EngineLine] = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Tanca").padding(.horizontal, 20)
                BoardView(board)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines, id: \.multipv) { line in
                        Button { play(line) } label: {
                            HStack(spacing: 8) {
                                Text(verbatim: line.score.whiteLabel(sideToMove: board.position.side)).font(Theme.text(15, .semibold)).foregroundStyle(Theme.gold).frame(width: 52, alignment: .leading)
                                Text(verbatim: san(line)).font(Theme.text(15)).foregroundStyle(Theme.tin).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 34).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if lines.isEmpty { Text("El motor pensa").font(Theme.text(15)).foregroundStyle(Theme.quiet) }
                    Button("Torna a la posició") { reset() }.font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
            }
        }
        .fieldBackground()
        .task { reset() }
        .onDisappear { task?.cancel(); AutoReview.shared.release() }
        .onAppear { AutoReview.shared.hold() }
    }

    private func reset() {
        board.orientation = position.side
        board.set(position, animated: true)
        board.lastMove = nil
        board.interactive = true
        board.onMove = { m in board.play(m); analyse() }
        analyse()
    }

    private func play(_ line: EngineLine) {
        guard let m = line.pv.first, board.position.isLegal(m) else { return }
        board.play(m)
        analyse()
    }

    private func analyse() {
        task?.cancel()
        lines = []
        let fen = board.position.fen
        task = Task {
            let result = try? await Engine.shared.analyse(startFEN: fen, moves: [], multiPV: 3, nodes: nil, movetimeMs: 15000, searchMoves: nil) { update in
                Task { @MainActor in if board.position.fen == fen { lines = update } }
            }
            if let result, !Task.isCancelled { lines = result }
        }
    }

    private func san(_ line: EngineLine) -> String {
        var p = board.position
        var out: [String] = []
        for m in line.pv.prefix(7) {
            guard p.isLegal(m) else { break }
            out.append(p.san(m))
            p = p.applying(m)
        }
        return out.joined(separator: " ")
    }
}

/// Picks a screenshot without any permission prompt: the system shows the library in its own process.
struct CapturePicker: View {
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Text("O tria una captura d'un tauler").font(Theme.text(17, .semibold)).frame(minHeight: 44)
        }
        .onChange(of: item) { _, chosen in
            guard let chosen else { return }
            Task {
                if let data = try? await chosen.loadTransferable(type: Data.self), let image = UIImage(data: data)?.cgImage {
                    ShareCenter.shared.picture = .init(image: image)
                }
                item = nil
            }
        }
    }
}
