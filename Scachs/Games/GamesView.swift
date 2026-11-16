import SwiftUI

struct GamesView: View {
    private var library: GameLibrary { .shared }
    @State private var showAdd = false
    @State private var showAccounts = false
    @State private var filter = Filter.all
    private enum Filter: Hashable { case all, won, lost }
    @Environment(\.scenePhase) private var scenePhase
    /// Decided once, not from the live text: otherwise the first typed letter swaps out the field being typed in.
    @State private var started = !GameLibrary.shared.chessComUsername.isEmpty || !GameLibrary.shared.lichessUsername.isEmpty

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty && !started { emptyState } else { list }
            }
            .fieldBackground()
            .topBar(Text("Partides")) {
                BarButton(systemImage: "person.2", label: "Comptes") { showAccounts = true }
            } trailing: {
                BarButton(systemImage: "plus", label: "Afegeix una partida") { showAdd = true }
            }
            .navigationDestination(for: ImportedGame.self) { ReviewView(game: $0) }
            .sheet(isPresented: $showAdd) { AddGameSheet() }
            .sheet(isPresented: $showAccounts, onDismiss: { Task { await library.refreshIfStale() } }) { AccountsSheet() }
            .task { await library.refreshIfStale() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await library.refreshIfStale() } }
            }
            .onChange(of: library.games.isEmpty) { _, empty in if !empty { started = true } }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Porta aquí les teves partides de chess.com o de Lichess. Stockfish les analitza al teu iPhone, sense connexió.")
                    .font(Theme.text(18)).foregroundStyle(Theme.tin.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                AccountFields().padding(.top, 10)
                Button { started = true; Task { await library.refresh() } } label: {
                    Text("Porta les partides")
                }
                .buttonStyle(.plaque)
                .disabled(!library.hasAccounts)
                .padding(.top, 6)
                Button { showAdd = true } label: {
                    Text("O enganxa un PGN o un enllaç").font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                }
            }
            .padding(20)
        }
    }

    private var list: some View {
        List {
            SectionPicker(items: [("Totes", Filter.all), ("Guanyades", .won), ("Perdudes", .lost)], selection: $filter)
                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(.init(top: 12, leading: 14, bottom: 4, trailing: 14))
            if !library.refreshErrors.isEmpty {
                // Says which account failed and opens the place to fix it, instead of a loose red line.
                Button { showAccounts = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warn)
                        Text(verbatim: library.refreshErrors.map { "\($0.key == .chessCom ? "chess.com" : "Lichess"): \($0.value.errorDescription ?? "")" }.sorted().joined(separator: " · "))
                            .foregroundStyle(Theme.tin).lineLimit(2)
                        Spacer(minLength: 8)
                        Text("Revisa-ho").foregroundStyle(Theme.gold)
                    }
                    .font(Theme.text(15)).frame(minHeight: 44).contentShape(Rectangle())
                    .panel(Theme.warn.opacity(0.14), padding: 10)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(.init(top: 4, leading: 14, bottom: 4, trailing: 14))
            }
            ForEach(library.games.filter { filter == .all || GameRow.won($0) == (filter == .won) }) { game in
                NavigationLink(value: game) { GameRow(game: game) }
                    .listRowBackground(RoundedRectangle(cornerRadius: 6).fill(Theme.panel).padding(.vertical, 4).padding(.horizontal, 14))
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 4, leading: 24, bottom: 4, trailing: 24))
                    .swipeActions { Button("Esborra", role: .destructive) { library.delete(game) } }
            }
            if library.hasAccounts && !library.games.isEmpty && !library.reachedOldest {
                Button { Task { await library.loadOlder() } } label: {
                    Text("Carrega'n més").font(Theme.text(16, .semibold)).foregroundStyle(Theme.gold).frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(library.isRefreshing)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await library.refresh() }
        .overlay {
            if library.isRefreshing && library.games.isEmpty { ProgressView().tint(Theme.gold) }
            else if library.games.isEmpty && library.refreshErrors.isEmpty {
                Text("Encara no hi ha partides. Afegeix-ne amb el botó de dalt.").font(Theme.text(16)).foregroundStyle(Theme.quiet).multilineTextAlignment(.center).padding(32)
            }
        }
    }
}

/// What a row shows of a game besides its headers: where it ended and what was opened. Read once, off the main thread.
@MainActor private enum Glance {
    struct Value { let fen: String; let opening: String? }
    static var cache: [String: Value] = [:]

    static func read(_ game: ImportedGame) async -> Value {
        if let hit = cache[game.id] { return hit }
        let pgn = game.pgn
        let value = await Task.detached(priority: .utility) { () -> Value in
            guard let g = PGN.parse(pgn).first else { return Value(fen: Position.start.fen, opening: nil) }
            let start = g.startFEN.flatMap(Position.init(fen:)) ?? .start
            let end = g.moves.reduce(start) { $0.applying($1.move) }
            let name = Openings.shared.name(start: start, moves: g.moves.map(\.move))?.name
            return Value(fen: end.fen, opening: name.map { OpeningNames.local(Atlas.family($0)) })
        }.value
        cache[game.id] = value
        return value
    }
}

/// One line per game: where it ended, who, how it ended and how well.
struct GameRow: View {
    let game: ImportedGame
    private var side: Side { game.mySide ?? .white }
    private var opponent: String { side == .white ? game.black : game.white }
    private var opponentRating: Int? { side == .white ? game.blackRating : game.whiteRating }
    private var outcome: (label: LocalizedStringKey, color: Color) {
        switch (game.result, side) {
        case ("1-0", .white), ("0-1", .black): return ("Guanyada", Theme.good)
        case ("1/2-1/2", _): return ("Taules", Theme.muted)
        case ("*", _): return ("Sense acabar", Theme.muted)
        default: return ("Perduda", Theme.warn)
        }
    }
    /// Won, lost, or neither (a draw or unfinished game is in neither filter).
    static func won(_ game: ImportedGame) -> Bool? {
        switch (game.result, game.mySide ?? .white) {
        case ("1-0", .white), ("0-1", .black): return true
        case ("1-0", .black), ("0-1", .white): return false
        default: return nil
        }
    }
    private var siteAccuracy: Double? { side == .white ? game.whiteAccuracy : game.blackAccuracy }
    @State private var glance: Glance.Value?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let glance { MiniBoard(fen: glance.fen, orientation: side) } else { Theme.fieldDeep }
            }
            .frame(width: 50, height: 50)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(verbatim: opponent).font(Theme.text(17, .semibold)).foregroundStyle(Theme.tin).lineLimit(1)
                    if let r = opponentRating { Text(verbatim: "\(r)").font(Theme.text(14)).foregroundStyle(Theme.muted) }
                }
                HStack(spacing: 7) {
                    Text(outcome.label).font(Theme.text(13, .semibold)).foregroundStyle(outcome.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(outcome.color.opacity(0.2)))
                    Group {
                        if let opening = glance?.opening { Text(verbatim: opening) } else { Text(game.timeClass.displayName) }
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.muted)
                }
                .lineLimit(1)
            }
            Spacer()
            // Bright once this app has read the game; the site's own figure, if any, stays quiet until then.
            VStack(alignment: .trailing, spacing: 3) {
                if let accuracy = game.myAccuracy ?? siteAccuracy {
                    Text(verbatim: accuracy.formatted(.number.precision(.fractionLength(1)))).font(Theme.text(18, .semibold))
                        .foregroundStyle(game.reviewed ? Theme.tin : Theme.muted)
                        .accessibilityLabel(game.reviewed ? "Analitzada. Precisió \(accuracy.formatted(.number.precision(.fractionLength(1))))" : "Precisió \(accuracy.formatted(.number.precision(.fractionLength(1))))")
                }
                Text(game.date, format: .dateTime.day().month(.abbreviated)).font(Theme.text(13)).foregroundStyle(Theme.muted)
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
        .task(id: game.id) { glance = await Glance.read(game) }
    }
}

struct AccountFields: View {
    @Bindable private var library = GameLibrary.shared
    var body: some View {
        VStack(spacing: 0) {
            field("Usuari de chess.com", text: $library.chessComUsername, source: .chessCom)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            field("Usuari de Lichess", text: $library.lichessUsername, source: .lichess)
        }
    }
    private func field(_ title: LocalizedStringKey, text: Binding<String>, source: GameSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(title, text: text, prompt: Text(title).foregroundStyle(Theme.quiet))
                    .font(Theme.text(18)).foregroundStyle(Theme.tin)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done).padding(.vertical, 14)
                if library.isLinked(source) {
                    Image(systemName: "checkmark").foregroundStyle(Theme.gold).accessibilityLabel("Vinculat")
                }
            }
            if let error = library.refreshErrors[source]?.errorDescription {
                Text(verbatim: error).font(Theme.text(15)).foregroundStyle(Color(hex: 0xEF7D6C)).padding(.bottom, 12)
            }
        }
    }
}

struct AccountsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Només el nom d'usuari, sense contrasenya. Scachs demana a cada servei les teves partides públiques.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                    AccountFields()
                }.padding(20)
            }
            .fieldBackground()
            .navigationTitle("Comptes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if checking { ProgressView().tint(Theme.gold) } else { Button("Fet") { confirm() } }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Stays open on a name the site doesn't know, so it can be fixed here. Any other failure can wait for the next refresh.
    private func confirm() {
        checking = true
        Task {
            await GameLibrary.shared.refresh()
            checking = false
            if !GameLibrary.shared.refreshErrors.values.contains(.userNotFound) { dismiss() }
        }
    }
}

struct AddGameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enganxa un PGN o l'enllaç d'una partida.").font(Theme.text(17)).foregroundStyle(Theme.tin)
                TextEditor(text: $text)
                    .font(Theme.text(16)).foregroundStyle(Theme.tin).scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10).background(Theme.fieldDeep).frame(minHeight: 180)
                if let error { Text(verbatim: error).font(Theme.text(15)).foregroundStyle(Color(hex: 0xEF7D6C)) }
                Button { add() } label: {
                    if busy { ProgressView().tint(Theme.ink) } else { Text("Afegeix") }
                }
                .buttonStyle(.plaque)
                .disabled(text.isEmpty || busy)
                Button("Enganxa del porta-retalls") { text = UIPasteboard.general.string ?? "" }
                    .font(Theme.text(17, .semibold)).frame(minHeight: 44)
                CapturePicker()
                Spacer()
            }
            .padding(20)
            .fieldBackground()
            .navigationTitle("Afegeix una partida").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel·la") { dismiss() } } }
        }
    }

    private func add() {
        busy = true; error = nil
        Task {
            do { _ = try await GameLibrary.shared.add(pasted: text); dismiss() }
            catch let e as ImportError { error = e.errorDescription }
            catch { self.error = String(localized: "No s'ha pogut llegir.") }
            busy = false
        }
    }
}

extension TimeClass {
    var displayName: LocalizedStringKey {
        switch self {
        case .ultraBullet: "ultrabala"
        case .bullet: "bala"
        case .blitz: "blitz"
        case .rapid: "ràpida"
        case .classical: "clàssica"
        case .daily: "per correspondència"
        case .unknown: "partida"
        }
    }
}
