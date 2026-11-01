#if canImport(VisualIntelligence)
import AppIntents
import VisualIntelligence
import CoreImage

/// Lets Visual Intelligence offer Scachs when the camera or a screenshot shows a board. Tapping it opens the position to check.
struct BoardCaptureEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Posició d'escacs"
    static let defaultQuery = BoardCaptureLookup()

    var id: String
    var fen: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Analitza a Scachs", subtitle: LocalizedStringResource(stringLiteral: String(fen.split(separator: " ").first ?? "")))
    }
}

struct BoardCaptureLookup: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BoardCaptureEntity] {
        identifiers.map { BoardCaptureEntity(id: $0, fen: $0) }
    }
}

@available(iOS 26.0, *)
struct BoardCaptureQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [BoardCaptureEntity] {
        guard let buffer = input.pixelBuffer else { return [] }
        let image: CGImage? = buffer.withUnsafeBuffer { pixels in
            let ci = CIImage(cvPixelBuffer: pixels)
            return CIContext().createCGImage(ci, from: ci.extent)
        }
        guard let image, let reading = BoardReader.read(image) else { return [] }
        let fen = BoardReader.fen(reading.pieces, sideToMove: .white)
        return [BoardCaptureEntity(id: fen, fen: fen)]
    }
}

struct OpenBoardCaptureIntent: OpenIntent {
    static let title: LocalizedStringResource = "Obre la posició"
    @Parameter(title: "Posició") var target: BoardCaptureEntity

    @MainActor func perform() async throws -> some IntentResult {
        ShareCenter.shared.fen = target.fen
        return .result()
    }
}
#endif
