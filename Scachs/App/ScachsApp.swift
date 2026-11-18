import SwiftUI

@main
struct ScachsApp: App {
    @AppStorage("welcomed") private var welcomed = false
    @State private var launching = true
    /// Held back until the logo is on screen: building the first screen blocks the main thread, which its animation doesn't need.
    @State private var mounted = false

    init() {
        AutoReview.shared.registerBackgroundTask()
        // Sheets keep the system bar; this gives it the same dark bar, engraved title and gold wire as ours.
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(Theme.field)
        bar.shadowColor = UIColor(Theme.hairline)
        bar.titleTextAttributes = [.font: UIFont(name: "MarcellusSC-Regular", size: 15) ?? .systemFont(ofSize: 15), .kern: 2.4, .foregroundColor: UIColor(Theme.tin)]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
    }

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
            .toggleStyle(WireToggleStyle())
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
    @State private var tab = 0
    @State private var barHidden = false
    @AppStorage("toured") private var toured = false
    var body: some View {
        // The system bar is glass on iOS 26 and can't be made flat, so it's hidden and ours sits in its place.
        TabView(selection: $tab) {
            Tab("Avui", image: "tab.today", value: 0) { tabContent(TodayView()) }
            Tab("Puzzles", image: "tab.puzzles", value: 1) { tabContent(PuzzleView()) }
            Tab("Partides", image: "tab.games", value: 2) { tabContent(GamesView()) }
            Tab("Lliçons", image: "tab.lessons", value: 3) { tabContent(LessonsView()) }
            Tab("Tu", image: "tab.you", value: 4) { tabContent(ProfileView()) }
        }
        .overlay(alignment: .bottom) {
            if !barHidden { ScachsTabBar(tab: $tab).transition(.move(edge: .bottom)) }
        }
        .onPreferenceChange(TabBarHidden.self) { hidden in withAnimation(.easeOut(duration: 0.2)) { barHidden = hidden } }
        // The board is a UIKit view, so the overlay alone doesn't keep its touches from it.
        .allowsHitTesting(toured)
        .overlay {
            if !toured {
                TourOverlay(tab: $tab) { withAnimation(.easeOut(duration: 0.25)) { toured = true; tab = 0 } }.transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AutoReview.shared.scheduleOvernight() }
            if phase == .active { InboxReader.drain() }
        }
        .fullScreenCover(item: $share.game) { game in
            NavigationStack { ReviewView(game: game) }
        }
        .fullScreenCover(item: $share.picture) { CaptureView(image: $0.image) }
        .fullScreenCover(item: Binding(get: { share.fen.map(SharedPosition.init) }, set: { share.fen = $0?.fen })) { PositionEditor(pieces: $0.pieces) }
        .alert(item: $share.failure) { Alert(title: Text(verbatim: $0.message)) }
        .task { Sound.start(); InboxReader.drain() }
        #if DEBUG
        .onAppear {
            switch ScreenshotScene.value {
            case "path", "openings", "exercises", "lesson": tab = 3
            case "profile": tab = 4
            case "review": share.game = GameLibrary.shared.games.first(where: \.reviewed)
            default: break
            }
        }
        #endif
    }
}

extension RootView {
    /// Each tab keeps clear of our bar, which floats over the hidden system one.
    func tabContent<V: View>(_ content: V) -> some View {
        content.toolbarVisibility(.hidden, for: .tabBar).safeAreaPadding(.bottom, barHidden ? 0 : ScachsTabBar.height)
    }
}

/// Set by a pushed screen that brings its own tools, like the review, to take the tab bar away while it's open.
struct TabBarHidden: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The five tabs under a hairline: the chosen icon in gold, the names in rubric capitals.
private struct ScachsTabBar: View {
    static let height: CGFloat = 55
    @Binding var tab: Int
    private let items: [(LocalizedStringKey, String)] = [("Avui", "tab.today"), ("Puzzles", "tab.puzzles"), ("Partides", "tab.games"), ("Lliçons", "tab.lessons"), ("Tu", "tab.you")]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let on = tab == i
                Button { tab = i } label: {
                    VStack(spacing: 4) {
                        Image(items[i].1).renderingMode(.template).resizable().scaledToFit().frame(width: 23, height: 23)
                            .foregroundStyle(on ? Theme.gold : Theme.muted)
                        Text(items[i].0).font(Theme.label(9.5)).tracking(1.3).textCase(.uppercase).foregroundStyle(on ? Theme.tin : Theme.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).frame(height: 49).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(items[i].0))
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, 6)
        .background(Theme.field.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

/// Screens that hide the system bar for their own still go back with a swipe from the edge.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { viewControllers.count > 1 }
}
