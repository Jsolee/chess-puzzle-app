import SwiftUI

/// One moment of your own game at a time: the board asks first, the answer comes after.
@MainActor @Observable final class TodayModel {
    enum Phase { case asking, wrong, found, shown }

    let board = BoardModel()
    private(set) var card: MistakeCard?
    private(set) var phase: Phase = .asking
    private(set) var idea: String?
    @ObservationIgnored private var hintLevel = 0
    @ObservationIgnored private var missed = false
    @ObservationIgnored private var answered = false

    /// Only fills an empty board: things finishing in the background must not pull an answer away while you read it.
    func load() {
        guard card == nil else { return }
        card = Progress.shared.nextMistake()
        guard let card, let position = Position(fen: card.fen) else { return }
        phase = .asking; idea = nil; hintLevel = 0; missed = false; answered = false
        board.arrows = []; board.hint = nil; board.marks = []
        board.orientation = card.side
        board.set(position, animated: true)
        board.lastMove = card.lastMove.flatMap(Move.init(uci:))
        board.interactive = true
        board.onMove = { [weak self] m in self?.attempt(m) }
    }

    func next() {
        card = nil
        load()
    }

    private func attempt(_ m: Move) {
        guard let card else { return }
        if m.uci == card.bestUCI || board.position.applying(m).isCheckmate {
            board.hint = nil
            board.play(m)
            board.interactive = false
            board.reflex(from: m.to)
            answer(solved: !missed)
            phase = .found
        } else {
            board.flashWrong(m.to)
            missed = true
            phase = .wrong
        }
    }

    private func answer(solved: Bool) {
        guard let card, !answered else { return }
        answered = true
        Progress.shared.answerMistake(card, solved: solved)
    }

    func hint() {
        guard let card, let best = Move(uci: card.bestUCI) else { return }
        hintLevel += 1
        missed = true
        if hintLevel == 1, let motif = card.motif, ThemeNames.idea(of: [motif]) != nil {
            idea = ThemeNames.name(motif)
        } else {
            board.hint = best.from
            Haptics.tap(0.2, sharpness: 0.3)
        }
    }

    func reveal() {
        guard let card, let best = Move(uci: card.bestUCI) else { return }
        board.interactive = false
        board.hint = nil
        board.arrows = [BoardArrow(from: best.from, to: best.to, role: .best)]
        answer(solved: false)
        phase = .shown
    }
}

/// The home screen: what's worth doing today, in the order it helps, and nothing about what wasn't done.
struct TodayView: View {
    @State private var model = TodayModel()
    @State private var dailyBoard = BoardModel()
    @State private var openLesson: LessonMeta?
    @State private var focus: FocusedPuzzles?
    @State private var cover: Cover?
    @Environment(\.scenePhase) private var scenePhase
    private var library: GameLibrary { .shared }
    private var auto: AutoReview { .shared }

    private enum Cover: Int, Identifiable { case daily, blindfold, sunday, atlas; var id: Int { rawValue } }
    private struct FocusedPuzzles: Identifiable { let themes: Set<String>; var id: String { themes.sorted().joined() } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
                    hero
                    rows.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
                }
            }
            .background(Theme.field.ignoresSafeArea())
            .sheet(item: $openLesson) { LessonRunnerView(meta: $0) }
            .fullScreenCover(item: $focus) { PuzzleView(focus: $0.themes) }
            .fullScreenCover(item: $cover) { cover in
                switch cover {
                case .daily: DailyPuzzleView()
                case .blindfold: BlindfoldView()
                case .sunday: SundayGameView()
                case .atlas: AtlasView()
                }
            }
            .onChange(of: cover) { _, now in if now == nil { showDaily() } }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
            .onChange(of: auto.finished) { _, _ in model.load() }
        }
    }

    private func refresh() async {
        library.harvestOldReviews()
        model.load()
        showDaily()
        await library.refreshIfStale()
        auto.kick()
        WidgetSnapshot.write()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Avui").font(Theme.display(52)).foregroundStyle(Theme.tin)
            Spacer()
            Text(Date(), format: .dateTime.day().month(.wide)).font(Theme.text(16)).foregroundStyle(Theme.quiet)
        }
    }

    // MARK: The board

    @ViewBuilder private var hero: some View {
        if let card = model.card {
            moment(card)
        } else {
            dailyHero
        }
    }

    private func moment(_ card: MistakeCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Contra \(card.opponent)").font(Theme.text(16)).foregroundStyle(Theme.quiet).lineLimit(1)
                Text(momentTitle).font(Theme.display(40)).foregroundStyle(Theme.tin).contentTransition(.opacity)
                Text(verbatim: momentSubtitle(card)).font(Theme.text(16))
                    .foregroundStyle(model.phase == .wrong ? Color(hex: 0xEF7D6C) : Theme.quiet).contentTransition(.opacity)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            .animation(.easeOut(duration: 0.2), value: model.phase)
            BoardView(model.board)
            Group {
                switch model.phase {
                case .asking, .wrong:
                    HStack {
                        Button { model.hint() } label: { Text("Pista").font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44) }
                        Spacer()
                        Button { model.reveal() } label: { Text("Solució").font(Theme.text(17, .semibold)).foregroundStyle(Theme.tin).frame(minHeight: 44) }
                    }
                case .found, .shown:
                    VStack(alignment: .leading, spacing: 14) {
                        if let note = card.note, !note.isEmpty {
                            SANText.prose(note, size: 16).font(Theme.text(16)).foregroundStyle(Theme.tin.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true).accessibilityLabel(note)
                        }
                        Button { model.next() } label: {
                            Text("Següent").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 14)
        }
    }

    private var momentTitle: LocalizedStringKey {
        switch model.phase {
        case .asking: "Aquí hi havia més"
        case .wrong: "Aquesta no"
        case .found: "Ben trobat"
        case .shown: "Era aquesta"
        }
    }

    private func momentSubtitle(_ card: MistakeCard) -> String {
        if let idea = model.idea, model.phase == .asking || model.phase == .wrong { return String(localized: "Pensa en això: \(idea).") }
        switch model.phase {
        case .asking: return String(localized: "A la partida vas jugar \(card.playedSAN). Troba'n una de millor.")
        case .wrong: return String(localized: "Torna-hi, o mira la solució.")
        case .found, .shown: return String(localized: "A la partida vas jugar \(card.playedSAN).")
        }
    }

    private var dailyHero: some View {
        let solved = Progress.shared.dailyDays.contains(PuzzleStore.dayNumber(Date()))
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if let game = auto.current {
                    Text("Analitzant la partida contra \(game.mySide == .white ? game.black : game.white). \(Int(auto.progress * 100)) %")
                        .font(Theme.text(16)).foregroundStyle(Theme.quiet).lineLimit(1).contentTransition(.numericText())
                }
                Text("Puzzle del dia").font(Theme.display(40)).foregroundStyle(Theme.tin)
                Text(solved ? "Resolt." : "Toca el tauler per començar.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            BoardView(dailyBoard)
                .contentShape(Rectangle())
                .onTapGesture { cover = .daily }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Puzzle del dia")
            if !library.hasAccounts {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vincula el teu compte i aquí sortiran els moments de les teves partides.").font(Theme.text(16)).foregroundStyle(Theme.tin)
                    AccountFields()
                }
                .padding(.horizontal, 20).padding(.top, 18)
            }
        }
    }

    private func showDaily() {
        let p = PuzzleStore.shared.daily(for: Date())
        dailyBoard.interactive = false
        dailyBoard.orientation = p.solverSide
        let afterSetup = p.start.applying(p.start.move(uci: p.line[0].uci) ?? p.line[0])
        dailyBoard.set(afterSetup, animated: false)
        dailyBoard.lastMove = p.line[0]
    }

    // MARK: What else

    private var rows: some View {
        let pick = Recommender.next(progress: .shared, lessons: LessonLibrary.shared.metas, reviewEvidence: library.missedTacticEvidence)
        return VStack(alignment: .leading, spacing: 0) {
            if model.card != nil { DailyRow { cover = .daily }; hairline }
            if let pick {
                row("Lliçó", detail: pick.lesson.title) { openLesson = pick.lesson }
                hairline
                row("Tres puzzles", detail: pick.lesson.title) { focus = FocusedPuzzles(themes: Set(pick.lesson.tags.keys)) }
                hairline
            }
            row("La partida del diumenge", detail: SundayGames.current().title.current) { cover = .sunday }
            hairline
            row("A cegues, amb auriculars", detail: nil) { cover = .blindfold }
            hairline
            row("L'Atles de les teves obertures", detail: nil) { cover = .atlas }
        }
    }

    private var hairline: some View { Rectangle().fill(Theme.hairline).frame(height: 0.5) }

    private func row(_ title: LocalizedStringKey, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.text(17, .medium)).foregroundStyle(Theme.tin)
                    if let detail { Text(verbatim: detail).font(Theme.text(14)).foregroundStyle(Theme.quiet).lineLimit(1) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.quiet)
            }
            .frame(minHeight: 54).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
