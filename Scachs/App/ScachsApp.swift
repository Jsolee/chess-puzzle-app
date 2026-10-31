import SwiftUI

@main
struct ScachsApp: App {
    @AppStorage("welcomed") private var welcomed = false
    @State private var launching = true
    /// Held back until the logo is on screen: building the first screen blocks the main thread, which its animation doesn't need.
    @State private var mounted = false

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
