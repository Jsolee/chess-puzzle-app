import SwiftUI

@main
struct ScachsApp: App {
    @AppStorage("welcomed") private var welcomed = false
    var body: some Scene {
        WindowGroup {
            Group {
                if welcomed { RootView() } else { WelcomeView { withAnimation(.easeOut(duration: 0.35)) { welcomed = true } } }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.gold)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Puzzles", systemImage: "square.grid.3x3.middle.filled") { PuzzleView() }
            Tab("Partides", systemImage: "list.bullet.rectangle") { GamesView() }
            Tab("Lliçons", systemImage: "book.closed") { LessonsView() }
            Tab("Tu", systemImage: "person.crop.circle") { ProfileView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task { Sound.start() }
    }
}
