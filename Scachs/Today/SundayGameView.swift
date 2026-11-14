import SwiftUI

/// A historic game told in a few moments, where you guess the move before reading why. Resources/SundayGames.json.
struct SundayGame: Codable, Identifiable {
    struct Text3: Codable {
        var ca: String
        var es: String
        var en: String
        var current: String {
            switch Locale.preferredLanguages.first?.prefix(2) { case "es": es; case "en": en; default: ca }
        }
    }
    struct Moment: Codable {
        var move: Int
        var side: String
        var san: String
        var text: Text3
        var ply: Int { (move - 1) * 2 + (side == "b" ? 1 : 0) }
    }
    var id: String
    var title: Text3
    var players: String
    var place: String
    var side: String
    var moves: String
    var intro: Text3
    var outro: Text3
    var moments: [Moment]

    var solver: Side { side == "b" ? .black : .white }
}

enum SundayGames {
    static let all: [SundayGame] = Bundle.main.url(forResource: "SundayGames", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([SundayGame].self, from: $0) } ?? []

    /// One a week, changing on Sunday. The list repeats when it runs out.
    static func current(date: Date = Date(), games: [SundayGame] = all) -> SundayGame {
        let day = PuzzleStore.dayNumber(date)
        // Day 1 of the era is a Monday, so day 7 is a Sunday.
        let week = day / 7
        return games[week % max(games.count, 1)]
    }
}

@MainActor @Observable final class SundayModel {
    enum Phase { case intro, watching, guessing, told, done }

    let game: SundayGame
    let board = BoardModel()
    private(set) var phase: Phase = .intro
    private(set) var found = 0
    private(set) var moment: SundayGame.Moment?
    private(set) var gotIt = false
    @ObservationIgnored private var replay: GameReplay?
    @ObservationIgnored private var ply = 0
    @ObservationIgnored private var misses = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(game: SundayGame) {
        self.game = game
        replay = PGN.parse(game.moves).first.flatMap { try? GameReplay($0) }
        board.orientation = game.solver
        board.interactive = false
        if let start = replay?.positions.first { board.set(start, animated: false) }
    }

    func begin() { walk() }
    func stop() { task?.cancel() }
    func next() { walk() }

    private func walk() {
        guard let replay else { return }
        task?.cancel()
        phase = .watching
        moment = nil
        let target = game.moments.first { $0.ply >= ply }
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                if let target, self.ply == target.ply { self.ask(target); return }
                guard self.ply < replay.moves.count else { self.phase = .done; return }
                self.board.play(replay.moves[self.ply])
                self.ply += 1
                try? await Task.sleep(for: .milliseconds(620))
            }
        }
    }

    private func ask(_ m: SundayGame.Moment) {
        moment = m
        misses = 0
        gotIt = false
        phase = .guessing
        board.interactive = true
        board.onMove = { [weak self] move in self?.attempt(move) }
    }

    private func attempt(_ m: Move) {
        guard let replay else { return }
        if m == replay.moves[ply] {
            gotIt = true
            found += 1
            board.reflex(from: m.to)
            finish()
        } else {
            board.flashWrong(m.to)
            misses += 1
            if misses >= 2 { finish() }
        }
    }

    func giveUp() { finish() }

    private func finish() {
        guard let replay else { return }
        board.interactive = false
        board.play(replay.moves[ply])
        ply += 1
        phase = .told
    }
}

struct SundayGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = SundayModel(game: SundayGames.current())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Tanca").padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: model.game.title.current).font(Theme.display(40)).foregroundStyle(Theme.tin).lineLimit(2).minimumScaleFactor(0.7)
                    Text(verbatim: "\(model.game.players) · \(model.game.place)").font(Theme.text(15)).foregroundStyle(Theme.quiet)
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
                BoardView(model.board)
                panel.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .fieldBackground()
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var panel: some View {
        switch model.phase {
        case .intro:
            VStack(alignment: .leading, spacing: 16) {
                body(model.game.intro.current)
                wide("Comença") { model.begin() }
            }
        case .watching:
            Text("Mira.").font(Theme.text(17)).foregroundStyle(Theme.quiet)
        case .guessing:
            VStack(alignment: .leading, spacing: 10) {
                Text(model.game.solver == .white ? "Què jugaries amb blanques?" : "Què jugaries amb negres?").font(Theme.text(20, .medium)).foregroundStyle(Theme.gold)
                Button("No la veig") { model.giveUp() }.font(Theme.text(16, .semibold)).foregroundStyle(Theme.tin).frame(minHeight: 44)
            }
        case .told:
            VStack(alignment: .leading, spacing: 14) {
                Text(model.gotIt ? "Ben vist." : "Es va jugar això.").font(Theme.text(18, .medium)).foregroundStyle(model.gotIt ? Theme.gold : Theme.tin)
                if let text = model.moment?.text.current { body(text) }
                wide("Continua") { model.next() }
            }
        case .done:
            VStack(alignment: .leading, spacing: 14) {
                Text("\(model.found) de \(model.game.moments.count)").font(Theme.display(40)).foregroundStyle(Theme.tin)
                body(model.game.outro.current)
                wide("Fet") { dismiss() }
            }
        }
    }

    private func body(_ text: String) -> some View {
        SANText.prose(text, size: 17).font(Theme.text(17)).foregroundStyle(Theme.tin.opacity(0.92)).fixedSize(horizontal: false, vertical: true).accessibilityLabel(text)
    }

    private func wide(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(.cartouche)
    }
}
