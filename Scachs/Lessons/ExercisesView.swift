import SwiftUI

/// Practice by theme: every puzzle tag with enough puzzles, grouped like a chess book's chapters, each shown by one of its
/// own positions. A set follows your rating, so the same page serves someone starting out and someone strong.
struct ExercisesView: View {
    @State private var tiles: [String: Tile] = [:]
    @State private var open: Focus?

    struct Tile { let fen: String; let side: Side; let count: Int }
    private struct Focus: Identifiable { let tag: String; var id: String { tag } }

    private static let minimum = 300
    private static let groups: [(title: LocalizedStringKey, tags: [String])] = [
        ("Finals", ["pawnEndgame", "rookEndgame", "bishopEndgame", "knightEndgame", "queenEndgame", "queenRookEndgame", "zugzwang", "promotion"]),
        ("Mig joc", ["kingsideAttack", "queensideAttack", "exposedKing", "sacrifice", "defensiveMove", "quietMove", "advancedPawn", "attackingF2F7"]),
        ("Tàctica", ["fork", "pin", "skewer", "discoveredAttack", "doubleCheck", "deflection", "attraction", "clearance", "intermezzo",
                     "interference", "xRayAttack", "capturingDefender", "trappedPiece", "hangingPiece"]),
        ("Mats", ["mate", "backRankMate", "smotheredMate", "arabianMate", "hookMate", "anastasiaMate", "bodenMate", "operaMate",
                  "epauletteMate", "pillsburysMate", "doubleBishopMate", "cornerMate"]),
        ("Obertura i partides de mestres", ["opening", "master", "masterVsMaster"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Exercicis per tema, a la teva mida. Tria un capítol i resol-ne tres; si en vols més, continua.")
                .font(Theme.text(17)).foregroundStyle(Theme.quiet).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, group in
                let tags = group.tags.filter { (tiles[$0]?.count ?? 0) >= Self.minimum }
                if !tags.isEmpty {
                    Text(group.title).font(Theme.display(30)).foregroundStyle(Theme.tin).padding(.top, 30).padding(.bottom, 12)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(tags, id: \.self) { tag in tile(tag, tiles[tag]!) }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                    .scrollClipDisabled()
                }
            }
        }
        .fullScreenCover(item: $open) { PuzzleView(focus: [$0.tag]) }
        .task {
            guard tiles.isEmpty else { return }
            let rating = Int(Progress.shared.rating)
            let tags = Self.groups.flatMap(\.tags), minimum = Self.minimum
            tiles = await Task.detached(priority: .userInitiated) {
                let store = PuzzleStore.shared
                let counts = store.tagCounts
                var out: [String: Tile] = [:]
                for tag in tags {
                    let count = counts[tag] ?? 0
                    guard count >= minimum, let p = store.find(target: rating, anyOf: [tag], excluding: { _ in false }) else { continue }
                    out[tag] = Tile(fen: p.start.applying(p.line[0]).fen, side: p.solverSide, count: count)
                }
                return out
            }.value
        }
    }

    private func tile(_ tag: String, _ t: Tile) -> some View {
        Button { open = Focus(tag: tag) } label: {
            VStack(alignment: .leading, spacing: 8) {
                MiniBoard(fen: t.fen, orientation: t.side).frame(width: 148, height: 148)
                    .overlay(Rectangle().stroke(Theme.gold.opacity(0.35), lineWidth: 1))
                Text(verbatim: ThemeNames.name(tag)).font(Theme.text(16, .medium)).foregroundStyle(Theme.tin)
                    .lineLimit(2).multilineTextAlignment(.leading).frame(width: 148, alignment: .leading)
                Text("\(t.count) exercicis").font(Theme.text(13)).foregroundStyle(Theme.quiet)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
