import SwiftUI

@main
struct ScachsApp: App {
    @AppStorage("welcomed") private var welcomed = false
    @State private var launching = true
    /// Held back until the logo is on screen: building the first screen blocks the main thread, which its animation doesn't need.
    @State private var mounted = false

    init() { AutoReview.shared.registerBackgroundTask() }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if mounted {
                    if welcomed { RootView() } else { WelcomeView { withAnimation(.easeOut(duration: 0.35)) { welcomed = true } } }
                }
                if launching {
                    LaunchView { withAnimation(.easeOut(duration: 0.4)) { launching = false } }
                        .transition(.opacity).zIndex(1)
                }
            }
            .background(Theme.field)
            .preferredColorScheme(.dark)
            .tint(Theme.gold)
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                mounted = true
            }
        }
    }
}

private struct SharedPosition: Identifiable {
    let fen: String
    var id: String { fen }
    var pieces: [Piece?] {
        guard let position = Position(fen: fen) else { return Array(repeating: nil, count: 64) }
        return (0..<64).map { position.piece(at: $0) }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var share = ShareCenter.shared
    var body: some View {
        TabView {
            Tab("Avui", systemImage: "sun.horizon") { TodayView() }
            Tab("Puzzles", systemImage: "square.grid.3x3.middle.filled") { PuzzleView() }
            Tab("Partides", systemImage: "list.bullet.rectangle") { GamesView() }
            Tab("Lliçons", systemImage: "book.closed") { LessonsView() }
            Tab("Tu", systemImage: "person.crop.circle") { ProfileView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AutoReview.shared.scheduleOvernight() }
            if phase == .active { InboxReader.drain() }
        }
        .fullScreenCover(item: $share.game) { game in
            NavigationStack {
                ReviewView(game: game).toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Tanca") { share.game = nil } }
                }
            }
        }
        .fullScreenCover(item: $share.picture) { CaptureView(image: $0.image) }
        .fullScreenCover(item: Binding(get: { share.fen.map(SharedPosition.init) }, set: { share.fen = $0?.fen })) { PositionEditor(pieces: $0.pieces) }
        .alert(item: $share.failure) { Alert(title: Text(verbatim: $0.message)) }
        .task { Sound.start(); InboxReader.drain() }
    }
}
