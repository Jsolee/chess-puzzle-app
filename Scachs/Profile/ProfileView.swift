import SwiftUI
import Charts

struct ProfileView: View {
    private var progress: Progress { .shared }
    @AppStorage("showStreak") private var showStreak = true
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    TemperamentBlock()
                    ratingBlock
                    if ratingHistory.count > 3 { chart }
                    skills
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 40)
            }
            .fieldBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ajustos")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var ratingBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if progress.isProvisional {
                SectionTitle("Encara et conec poc").padding(.bottom, 6)
            } else {
                Text(verbatim: "\(Int(progress.rating.rounded()))").font(Theme.display(72)).foregroundStyle(Theme.tin)
                GoldRule(section: true).padding(.bottom, 6)
            }
            Text(progress.isProvisional ? "La puntuació surt després d'uns quants puzzles." : "Puntuació de puzzles. No és la teva puntuació en partides.")
                .font(Theme.text(16)).foregroundStyle(Theme.quiet)
            Text("Puzzles resolts: \(solvedCount) · Lliçons: \(progress.completedLessons.count)")
                .font(Theme.text(16)).foregroundStyle(Theme.quiet).padding(.top, 2)
            let streak = DailyStreak(days: progress.dailyDays, today: PuzzleStore.dayNumber(Date()))
            if showStreak && streak.best > 0 {
                Text("Ratxa del puzzle del dia: \(streak.current). La millor: \(streak.best).")
                    .font(Theme.text(16)).foregroundStyle(Theme.quiet)
            }
        }
    }

    private var solvedCount: Int { progress.attempts.filter(\.solved).count }

    private var ratingHistory: [(Int, Double)] {
        progress.attempts.filter { $0.context != .retry && !$0.hinted }.suffix(120).enumerated().map { ($0.offset, $0.element.ratingBefore) }
    }

    private var chart: some View {
        Chart(ratingHistory, id: \.0) { p in
            LineMark(x: .value("Puzzle", p.0), y: .value("Puntuació", p.1))
                .foregroundStyle(Theme.gold).interpolationMethod(.monotone).lineStyle(.init(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
            AxisGridLine().foregroundStyle(Theme.hairline)
            AxisValueLabel().font(Theme.text(12)).foregroundStyle(Theme.quiet)
        } }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 130)
        .accessibilityLabel("Evolució de la puntuació")
    }

    /// Per-motif performance from blind attempts: how you do against expectation, without pretending precision.
    private var skillRows: [(String, Double, Int)] {
        var counts: [String: (expected: Double, got: Double, n: Int)] = [:]
        for a in progress.attempts where a.context == .blind && !a.hinted {
            let p = 1 / (1 + exp((Double(a.puzzleRating) - a.ratingBefore) / 173.72))
            for t in a.themes where ThemeNames.isMotif(t) {
                var c = counts[t] ?? (0, 0, 0)
                c.expected += p; c.got += a.solved ? 1 : 0; c.n += 1
                counts[t] = c
            }
        }
        return counts.filter { $0.value.n >= 8 }
            .map { (ThemeNames.name($0.key), ($0.value.got - $0.value.expected) / Double($0.value.n), $0.value.n) }
            .sorted { $0.1 > $1.1 }
    }

    @ViewBuilder private var skills: some View {
        let rows = skillRows
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Temes")
            if rows.isEmpty {
                Text("Quan hagis resolt més puzzles, aquí veuràs on et va millor i on se t'escapen.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
            } else {
                ForEach(rows.prefix(12), id: \.0) { r in
                    HStack {
                        Text(verbatim: r.0).font(Theme.text(16)).foregroundStyle(Theme.tin)
                        Spacer()
                        Text(r.1 > 0.05 ? "millor del previst" : r.1 < -0.05 ? "se t'escapa" : "al teu nivell")
                            .font(Theme.text(14)).foregroundStyle(r.1 > 0.05 ? Theme.gold : r.1 < -0.05 ? Color(hex: 0xEF7D6C) : Theme.quiet)
                    }
                    .padding(.vertical, 6)
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                }
            }
        }
    }

}

/// Sound, touch, the streak and difficulty: out of the profile, which is about you, and into a sheet of their own.
struct SettingsView: View {
    @AppStorage("sound") private var sound = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("difficulty") private var difficulty = 0
    @AppStorage("showStreak") private var showStreak = true
    @State private var showAbout = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle("Ajustos").padding(.bottom, 12)
                    settings
                }
                .padding(.horizontal, 20).padding(.top, 4)
            }
            .fieldBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fet") { dismiss() } } }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
        .toggleStyle(WireToggleStyle())
        .tint(Theme.gold)
        .presentationDetents([.medium, .large])
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("So", isOn: $sound).font(Theme.text(17)).padding(.vertical, 4)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Toggle("Vibració", isOn: $haptics).font(Theme.text(17)).padding(.vertical, 4)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Toggle("Mostra la ratxa", isOn: $showStreak).font(Theme.text(17)).padding(.vertical, 4)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            HStack {
                Text("Dificultat dels puzzles").font(Theme.text(17))
                Spacer()
                Picker("Dificultat dels puzzles", selection: $difficulty) {
                    Text("Més fàcil").tag(-1); Text("Normal").tag(0); Text("Més difícil").tag(1)
                }.labelsHidden().tint(Theme.gold)
            }.padding(.vertical, 6)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Button { showAbout = true } label: {
                HStack { Text("Sobre Scachs").font(Theme.text(17)); Spacer(); Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.quiet) }
                    .padding(.vertical, 12).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .foregroundStyle(Theme.tin).tint(Theme.gold)
    }
}

/// GPLv3 §5(d): appropriate legal notices, how to view the licence, where the source is.
struct AboutView: View {
    static let sourceURL = URL(string: "https://github.com/Jsolee/chess-puzzle-app")!
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image("Wordmark").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).frame(width: 150).foregroundStyle(Theme.tin)
                    Text("«Scachs» és la paraula del poema *Scachs d'amor* (València, c.1475), el registre més antic que es coneix de la dama i l'alfil moderns. Es pronuncia «skaks». El manuscrit conegut era una còpia, i avui se'n desconeix el parador.")
                        .font(Theme.text(17)).foregroundStyle(Theme.tin)
                    Text("Per Dama pres Bellea.").font(Theme.display(30)).foregroundStyle(Theme.gold)
                    Divider().overlay(Theme.hairline)
                    Text("Programari lliure").font(Theme.text(17, .semibold)).foregroundStyle(Theme.tin)
                    Text("Scachs es distribueix sota la llicència GNU GPL versió 3 o posterior, sense cap garantia. Pots veure'n el text aquí i obtenir el codi font complet d'aquesta versió.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                    Link("Codi font", destination: Self.sourceURL).font(Theme.text(17, .semibold))
                    NavigationLink("Llegeix la llicència") { LicenceView() }.font(Theme.text(17, .semibold))
                    Divider().overlay(Theme.hairline)
                    Text("Crèdits").font(Theme.text(17, .semibold)).foregroundStyle(Theme.tin)
                    Text("Motor: Stockfish 19 i els seus autors (GPLv3), xarxa nn-1a298aa575a0 (CC0). Puzzles i noms d'obertures: Lichess (CC0). Lletres: Grenze Gotisch i Ysabeau Office (SIL OFL). Peces, tauler, logotip i lliçons: Scachs.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                    Text("Scachs no està afiliada a chess.com ni a Lichess. Les etiquetes de les jugades les calcula aquesta app amb un model propi i poden no coincidir amb les d'altres serveis.").font(Theme.text(16)).foregroundStyle(Theme.quiet)
                }
                .padding(20)
            }
            .fieldBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fet") { dismiss() } } }
        }
    }
}

struct LicenceView: View {
    var body: some View {
        ScrollView {
            Text(verbatim: (Bundle.main.url(forResource: "LICENSE", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "GNU GPL v3: https://www.gnu.org/licenses/gpl-3.0.html")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.tin).padding(16)
        }
        .fieldBackground()
    }
}
