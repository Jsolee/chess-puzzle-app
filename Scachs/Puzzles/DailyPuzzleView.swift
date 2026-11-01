import SwiftUI

/// The run of daily puzzles solved. Worked out from the days themselves, so there is no counter to fall out of step.
struct DailyStreak: Equatable {
    /// One day off doesn't break it: people here don't play every day. Two in a row do, and nothing is said about it.
    static let forgivenDays = 1

    private(set) var current = 0
    private(set) var best = 0

    init(days: Set<Int>, today: Int) {
        var run = 0
        var last: Int?
        for day in days.sorted() where day <= today {
            if let last, day - last <= Self.forgivenDays + 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            last = day
        }
        if let last, today - last <= Self.forgivenDays + 1 { current = run }
    }
}

/// Today's puzzle. Solving it counts for the streak however it went: wrong tries, hints or seeing the solution first.
struct DailyPuzzleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var board = BoardModel()
    @State private var run: PuzzleRun?
    @State private var phase: Phase = .loading
    @State private var logged = false
    @State private var hintLevel = 0
    @State private var hinted = false
    @State private var idea: String?
    @State private var replyTask: Task<Void, Never>?
    @AppStorage("showStreak") private var showStreak = true
    private let day = Date()

    private enum Phase { case loading, yourMove, wrong, solved, revealed }
    private var progress: Progress { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.horizontal, 20).padding(.bottom, 18)
                header.padding(.horizontal, 20).padding(.bottom, 14)
                BoardView(board)
                controls.padding(.horizontal, 20).padding(.top, 16)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.field.ignoresSafeArea())
        .task { if run == nil { start() } }
        .onDisappear { replyTask?.cancel() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.tin).frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityLabel("Tanca")
            Text("Puzzle del dia").font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold)
            Spacer()
            Text(day, format: .dateTime.day().month(.wide)).font(Theme.text(16)).foregroundStyle(Theme.quiet)
        }
    }

    private var title: String {
        guard let side = run?.puzzle.solverSide else { return " " }
        switch phase {
        case .loading: return " "
        case .yourMove: return side == .white ? String(localized: "Juguen les blanques") : String(localized: "Juguen les negres")
        case .wrong: return String(localized: "No és aquesta")
        case .solved, .revealed: return ThemeNames.primary(of: run?.puzzle.themes ?? [])
        }
    }

    private var subtitle: String {
        if let idea, phase == .yourMove || phase == .wrong { return String(localized: "Pensa en això: \(idea).") }
        switch phase {
        case .wrong: return String(localized: "Torna-hi, o mira la solució.")
        case .solved: return String(localized: "Resolt.")
        case .revealed: return String(localized: "Quan el resolguis, compta per a la ratxa.")
        default: return " "
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(Theme.display(46)).foregroundStyle(Theme.tin)
                .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.opacity)
            Text(verbatim: subtitle).font(Theme.text(16)).foregroundStyle(phase == .wrong ? Color(hex: 0xEF7D6C) : Theme.quiet).contentTransition(.opacity)
        }
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    @ViewBuilder private var controls: some View {
        switch phase {
        case .loading:
            Color.clear.frame(height: 44)
        case .yourMove, .wrong:
            HStack {
                Button { hint() } label: { Text("Pista").font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44) }
                Spacer()
                Button { reveal() } label: { Text("Solució").font(Theme.text(17, .semibold)).foregroundStyle(Theme.tin).frame(minHeight: 44) }
            }
        case .revealed:
            wideButton("Torna-hi") { start() }
        case .solved:
            VStack(alignment: .leading, spacing: 18) {
                if showStreak { StreakPanel(days: progress.dailyDays, date: day) }
                wideButton("Fet") { dismiss() }
            }
            .transition(.opacity)
        }
    }

    private func wideButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
        }
    }

    // MARK: Flow

    private func start() {
        replyTask?.cancel()
        let p = PuzzleStore.shared.daily(for: day)
        run = PuzzleRun(p)
        hinted = false; hintLevel = 0; idea = nil
        board.interactive = false; board.arrows = []; board.hint = nil; board.lastMove = nil
        board.orientation = p.solverSide
        if progress.dailyDays.contains(PuzzleStore.dayNumber(day)) {
            let finished = p.line.reduce(p.start) { position, m in position.applying(position.move(uci: m.uci) ?? m) }
            board.set(finished, animated: false)
            phase = .solved
            return
        }
        phase = .loading
        board.set(p.start, animated: true)
        board.onMove = { m in userMove(m) }
        replyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(560))
            guard !Task.isCancelled else { return }
            board.play(p.line[0])
            phase = .yourMove
            board.interactive = true
        }
    }

    private func userMove(_ m: Move) {
        guard var r = run else { return }
        let outcome = r.attempt(m, on: board.position)
        run = r
        switch outcome {
        case .correct(let reply):
            board.hint = nil; board.arrows = []; hintLevel = 0
            board.play(m)
            board.interactive = false
            if phase == .wrong { phase = .yourMove }
            replyTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                if let reply { board.play(reply) }
                board.interactive = true
            }
        case .solved:
            board.hint = nil; board.arrows = []
            board.play(m)
            board.interactive = false
            log(r.puzzle, solved: true)
            progress.recordDaily(on: day)
            WidgetSnapshot.write()
            withAnimation(.easeOut(duration: 0.25)) { phase = .solved }
            board.reflex(from: m.to)
        case .wrong:
            board.flashWrong(m.to)
            log(r.puzzle, solved: false)
            phase = .wrong
        }
    }

    /// Only the first result of a sitting goes to the rating, like any other puzzle.
    private func log(_ p: Puzzle, solved: Bool) {
        guard !logged else { return }
        logged = true
        progress.record(p, solved: solved, hinted: hinted, context: .blind)
    }

    private func hint() {
        guard let r = run, let e = r.expected else { return }
        hintLevel += 1
        hinted = true
        if hintLevel == 1, let name = ThemeNames.idea(of: r.puzzle.themes) { idea = name }
        else { board.hint = e.from; Haptics.tap(0.2, sharpness: 0.3) }
    }

    private func reveal() {
        guard let r = run else { return }
        board.interactive = false; board.hint = nil; board.arrows = []
        log(r.puzzle, solved: false)
        replyTask?.cancel()
        phase = .revealed
        // A correct move's reply may still be pending on the board; the run has already moved past it.
        let pending = board.position.side != r.puzzle.solverSide ? [r.puzzle.line[r.step - 1]] : []
        replyTask = Task { @MainActor in
            for m in pending + r.remaining {
                guard !Task.isCancelled else { return }
                board.play(m)
                try? await Task.sleep(for: .milliseconds(620))
            }
        }
    }
}

/// The streak after a solve: how long, the last week, and that a day off is fine.
private struct StreakPanel: View {
    let days: Set<Int>
    let date: Date

    var body: some View {
        let today = PuzzleStore.dayNumber(date)
        let streak = DailyStreak(days: days, today: today)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "\(streak.current)").font(Theme.display(64)).foregroundStyle(Theme.gold)
                Text(streak.current == 1 ? "dia de ratxa" : "dies de ratxa").font(Theme.text(18, .medium)).foregroundStyle(Theme.tin)
                Spacer()
                WeekTrack(days: days, today: today, size: 13)
            }
            Text("Saltar-te un dia no la trenca.").font(Theme.text(15)).foregroundStyle(Theme.quiet)
            if streak.best > streak.current {
                Text("La teva millor: \(streak.best).").font(Theme.text(15)).foregroundStyle(Theme.quiet)
            }
        }
    }
}

/// The last seven days, today on the right, in the same small tiles as the session track.
struct WeekTrack: View {
    let days: Set<Int>
    let today: Int
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 3) {
            ForEach((today - 6)...today, id: \.self) { day in
                Rectangle()
                    .fill(days.contains(day) ? Theme.gold : day == today ? Theme.tin.opacity(0.55) : Theme.tin.opacity(0.14))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The way in, above the session. It never nags: no badge, no count of what was missed.
struct DailyRow: View {
    var open: () -> Void
    @AppStorage("showStreak") private var showStreak = true

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = PuzzleStore.dayNumber(context.date)
            let days = Progress.shared.dailyDays
            let streak = DailyStreak(days: days, today: today)
            Button(action: open) {
                HStack(spacing: 10) {
                    Text("Puzzle del dia").font(Theme.text(16, .semibold)).foregroundStyle(days.contains(today) ? Theme.quiet : Theme.gold)
                    Spacer()
                    if showStreak {
                        if streak.current > 0 {
                            Text(verbatim: "\(streak.current)").font(Theme.text(16, .medium)).foregroundStyle(Theme.tin)
                        }
                        WeekTrack(days: days, today: today)
                    }
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.quiet)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showStreak && streak.current > 0 ? "Puzzle del dia. Ratxa de \(streak.current)." : "Puzzle del dia")
        }
    }
}
