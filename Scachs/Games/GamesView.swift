import SwiftUI

struct GamesView: View {
    private var library: GameLibrary { .shared }
    @State private var showAdd = false
    @State private var showAccounts = false
    @Environment(\.scenePhase) private var scenePhase
    /// Decided once, not from the live text: otherwise the first typed letter swaps out the field being typed in.
    @State private var started = !GameLibrary.shared.chessComUsername.isEmpty || !GameLibrary.shared.lichessUsername.isEmpty

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty && !started { emptyState } else { list }
            }
            .background(Theme.field.ignoresSafeArea())
            .navigationDestination(for: ImportedGame.self) { ReviewView(game: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAccounts = true } label: { Image(systemName: "person.2") }.accessibilityLabel("Comptes")
                    Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Afegeix una partida")
                }
            }
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
                Text("Partides").font(Theme.display(52)).foregroundStyle(Theme.tin)
                Text("Porta aquí les teves partides de chess.com o de Lichess. Stockfish les analitza al teu iPhone, sense connexió.")
                    .font(Theme.text(18)).foregroundStyle(Theme.tin.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                AccountFields().padding(.top, 10)
                Button { started = true; Task { await library.refresh() } } label: {
                    Text("Porta les partides").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
                }
                .disabled(!library.hasAccounts).opacity(library.hasAccounts ? 1 : 0.4)
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
            Text("Partides").font(Theme.display(52)).foregroundStyle(Theme.tin)
                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(.init(top: 0, leading: 20, bottom: 8, trailing: 20))
            ForEach(Array(library.refreshErrors.keys), id: \.self) { source in
                Text(verbatim: "\(source == .chessCom ? "chess.com" : "Lichess"): \(library.refreshErrors[source]?.errorDescription ?? "")")
                    .font(Theme.text(15)).foregroundStyle(Color(hex: 0xEF7D6C))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(library.games) { game in
                NavigationLink(value: game) { GameRow(game: game) }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.hairline)
                    .swipeActions { Button("Esborra", role: .destructive) { library.delete(game) } }
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

/// One line per game, Flighty style: who, how it ended, how well.
struct GameRow: View {
    let game: ImportedGame
    private var side: Side { game.mySide ?? .white }
    private var opponent: String { side == .white ? game.black : game.white }
    private var opponentRating: Int? { side == .white ? game.blackRating : game.whiteRating }
    private var outcome: (label: LocalizedStringKey, color: Color) {
        switch (game.result, side) {
        case ("1-0", .white), ("0-1", .black): return ("Guanyada", Theme.gold)
        case ("1/2-1/2", _): return ("Taules", Theme.tin.opacity(0.72))
        case ("*", _): return ("Sense acabar", Theme.quiet)
        default: return ("Perduda", Color(hex: 0xEF7D6C))
        }
    }
    private var accuracy: Double? { side == .white ? game.whiteAccuracy : game.blackAccuracy }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: opponent).font(Theme.text(18, .medium)).foregroundStyle(Theme.tin).lineLimit(1)
                    if let r = opponentRating { Text(verbatim: "\(r)").font(Theme.text(15)).foregroundStyle(Theme.quiet) }
                }
                HStack(spacing: 6) {
                    Text(outcome.label).foregroundStyle(outcome.color)
                    Text(verbatim: "·").foregroundStyle(Theme.quiet)
                    Text(game.date, format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.quiet)
                    Text(verbatim: "·").foregroundStyle(Theme.quiet)
                    Text(game.timeClass.displayName).foregroundStyle(Theme.quiet)
                }
                .font(Theme.text(14))
            }
            Spacer()
            if let accuracy {
                Text(verbatim: accuracy.formatted(.number.precision(.fractionLength(1)))).font(Theme.text(17, .medium)).foregroundStyle(Theme.tin)
            }
        }
        .padding(.vertical, 6)
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
            .background(Theme.field.ignoresSafeArea())
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
                    Group { if busy { ProgressView().tint(Theme.ink) } else { Text("Afegeix").font(Theme.text(18, .semibold)) } }
                        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Theme.tin))
                }
                .disabled(text.isEmpty || busy)
                Button("Enganxa del porta-retalls") { text = UIPasteboard.general.string ?? "" }
                    .font(Theme.text(17, .semibold)).frame(minHeight: 44)
                Spacer()
            }
            .padding(20)
            .background(Theme.field.ignoresSafeArea())
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
