import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

private let field = Color(red: 0.059, green: 0.227, blue: 0.2)
private let tin = Color(red: 0.965, green: 0.945, blue: 0.902)
private let gold = Color(red: 0.906, green: 0.725, blue: 0.424)
private let lightTile = Color(red: 0.925, green: 0.902, blue: 0.839)
private let darkTile = Color(red: 0.173, green: 0.435, blue: 0.369)

private func display(_ size: CGFloat) -> Font { .custom("GrenzeGotisch-Medium", fixedSize: size) }

private func dayNumber(_ date: Date) -> Int { Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: date) ?? 0 }

@main
struct ScachsWidgets: WidgetBundle {
    var body: some Widget {
        MateWidget()
        StreakWidget()
        AnalysisLiveActivity()
    }
}

// MARK: Mate in one, played on the Home Screen

/// What's been tapped today, between the taps. Widgets keep nothing in memory.
struct MateProgress: Codable {
    var day = 0
    var selected: Int?
    var wrong: Int?
    var solved = false

    private static var file: URL? { SharedContainer.url?.appending(path: "widget-progress.json") }
    static func load(day: Int) -> MateProgress {
        let stored = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(MateProgress.self, from: $0) }
        if let stored, stored.day == day { return stored }
        return MateProgress(day: day)
    }
    func save() { if let file = Self.file, let data = try? JSONEncoder().encode(self) { try? data.write(to: file, options: .atomic) } }
}

private func squareName(_ s: Int) -> String { "\(["a", "b", "c", "d", "e", "f", "g", "h"][s % 8])\(s / 8 + 1)" }

private func squares(fromFEN fen: String) -> [String?] {
    var out = [String?](repeating: nil, count: 64)
    let ranks = (fen.split(separator: " ").first ?? "").split(separator: "/")
    for (r, rank) in ranks.enumerated() {
        var file = 0
        for ch in rank {
            if let n = ch.wholeNumberValue { file += n; continue }
            guard file < 8 else { break }
            out[(7 - r) * 8 + file] = (ch.isUppercase ? "w" : "b") + ch.lowercased()
            file += 1
        }
    }
    return out
}

struct TapSquareIntent: AppIntent {
    static let title: LocalizedStringResource = "Toca una casella"
    static let isDiscoverable = false

    @Parameter(title: "Casella") var square: Int

    init() {}
    init(square: Int) { self.square = square }

    func perform() async throws -> some IntentResult {
        let day = dayNumber(Date())
        guard let puzzle = WidgetData.load()?.puzzles.first(where: { $0.day == day }) else { return .result() }
        var progress = MateProgress.load(day: day)
        guard !progress.solved else { return .result() }
        progress.wrong = nil
        let white = puzzle.fen.split(separator: " ").dropFirst().first == "w"
        let isMine = squares(fromFEN: puzzle.fen)[square].map { $0.hasPrefix(white ? "w" : "b") } ?? false
        if let from = progress.selected, !isMine {
            if puzzle.best.hasPrefix(squareName(from) + squareName(square)) {
                progress.solved = true
            } else {
                progress.wrong = square
            }
            progress.selected = nil
        } else {
            progress.selected = isMine ? square : nil
        }
        progress.save()
        return .result()
    }
}

struct MateEntry: TimelineEntry {
    var date: Date
    var puzzle: WidgetData.MatePuzzle?
    var progress: MateProgress
}

struct MateProvider: TimelineProvider {
    func entry(at date: Date) -> MateEntry {
        let day = dayNumber(date)
        return MateEntry(date: date, puzzle: WidgetData.load()?.puzzles.first { $0.day == day }, progress: MateProgress.load(day: day))
    }
    func placeholder(in context: Context) -> MateEntry { MateEntry(date: Date(), progress: MateProgress()) }
    func getSnapshot(in context: Context, completion: @escaping (MateEntry) -> Void) { completion(entry(at: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MateEntry>) -> Void) {
        let midnight = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86400)
        completion(Timeline(entries: [entry(at: Date())], policy: .after(midnight)))
    }
}

struct MateWidgetView: View {
    let entry: MateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.progress.solved ? "Mat. Ben trobat." : entry.progress.wrong != nil ? "Aquesta no." : "Mat en 1")
                .font(.custom("YsabeauOffice-SemiBold", size: 15)).foregroundStyle(entry.progress.solved ? gold : tin)
            if let puzzle = entry.puzzle {
                board(puzzle)
            } else {
                Text("Obre Scachs per veure el mat d'avui.").font(.footnote).foregroundStyle(tin.opacity(0.7))
            }
        }
        .containerBackground(field, for: .widget)
    }

    private func board(_ puzzle: WidgetData.MatePuzzle) -> some View {
        let pieces = squares(fromFEN: puzzle.fen)
        let white = puzzle.fen.split(separator: " ").dropFirst().first == "w"
        return VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        let square = white ? (7 - row) * 8 + column : row * 8 + (7 - column)
                        Button(intent: TapSquareIntent(square: square)) {
                            ZStack {
                                tileColor(square)
                                if let name = pieces[square], let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Pieces"),
                                   let image = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: image).resizable().scaledToFit()
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tileColor(_ square: Int) -> Color {
        if entry.progress.selected == square { return gold.opacity(0.85) }
        if entry.progress.wrong == square { return Color(red: 0.937, green: 0.49, blue: 0.424).opacity(0.8) }
        return (square / 8 + square % 8) % 2 == 0 ? darkTile : lightTile
    }
}

struct MateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "mate", provider: MateProvider()) { MateWidgetView(entry: $0) }
            .configurationDisplayName("Mat en 1")
            .description("Un mat cada dia, per resoldre sense obrir l'app.")
            .supportedFamilies([.systemLarge])
    }
}

// MARK: Streak

struct StreakEntry: TimelineEntry {
    var date: Date
    var data: WidgetData
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry { StreakEntry(date: Date(), data: WidgetData()) }
    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) { completion(StreakEntry(date: Date(), data: WidgetData.load() ?? WidgetData())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let midnight = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86400)
        completion(Timeline(entries: [StreakEntry(date: Date(), data: WidgetData.load() ?? WidgetData())], policy: .after(midnight)))
    }
}

struct StreakWidgetView: View {
    let entry: StreakEntry

    var body: some View {
        let today = dayNumber(entry.date)
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "S").font(display(30)).foregroundStyle(tin)
            Spacer(minLength: 0)
            if entry.data.showStreak {
                Text(verbatim: "\(entry.data.streak)").font(display(48)).foregroundStyle(gold)
                HStack(spacing: 2) {
                    ForEach((today - 6)...today, id: \.self) { day in
                        Rectangle().fill(entry.data.dailyDays.contains(day) ? gold : day == today ? tin.opacity(0.55) : tin.opacity(0.14)).frame(width: 12, height: 12)
                    }
                }
            } else {
                Text("Puzzle del dia").font(.custom("YsabeauOffice-SemiBold", size: 15)).foregroundStyle(gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(field, for: .widget)
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "streak", provider: StreakProvider()) { StreakWidgetView(entry: $0) }
            .configurationDisplayName("Puzzle del dia")
            .description("La teva ratxa i els últims set dies.")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: Live Activity

struct AnalysisLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AnalysisAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Analitzant contra \(context.attributes.opponent)").font(.custom("YsabeauOffice-Medium", size: 16)).foregroundStyle(tin).lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(Int(context.state.progress * 100)) %").font(.custom("YsabeauOffice-Medium", size: 16)).foregroundStyle(gold)
                }
                ProgressView(value: context.state.progress).tint(gold)
            }
            .padding(16)
            .activityBackgroundTint(field)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(verbatim: "S").font(display(30)).foregroundStyle(tin) }
                DynamicIslandExpandedRegion(.trailing) { Text(verbatim: "\(Int(context.state.progress * 100)) %").foregroundStyle(gold) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Analitzant contra \(context.attributes.opponent)").foregroundStyle(tin).lineLimit(1)
                        ProgressView(value: context.state.progress).tint(gold)
                    }
                }
            } compactLeading: {
                Text(verbatim: "S").font(display(20)).foregroundStyle(tin)
            } compactTrailing: {
                Text(verbatim: "\(Int(context.state.progress * 100))%").foregroundStyle(gold)
            } minimal: {
                Text(verbatim: "S").font(display(18)).foregroundStyle(gold)
            }
        }
    }
}
