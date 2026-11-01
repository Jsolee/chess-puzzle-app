import Foundation
import ActivityKit

/// What the app, its widgets and its share extension hand each other, through the App Group.
enum SharedContainer {
    static let group = "group.com.jsolee.scachs"
    static var url: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
}

/// Things shared to Scachs from other apps, waiting for the app to open.
enum Inbox {
    enum Item { case text(String), image(Data) }

    private static var folder: URL? { SharedContainer.url?.appending(path: "Inbox", directoryHint: .isDirectory) }

    private static func write(_ data: Data, ext: String) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Named by time so the order needs no file dates, which Apple counts as a reason-required API.
        let stamp = String(format: "%013.0f", Date().timeIntervalSince1970 * 1000)
        try? data.write(to: folder.appending(path: "\(stamp)-\(UUID().uuidString).\(ext)"), options: .atomic)
    }

    static func put(text: String) { write(Data(text.utf8), ext: "txt") }
    static func put(image: Data) { write(image, ext: "img") }

    /// Takes everything out, oldest first.
    static func take() -> [Item] {
        guard let folder, let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        var items: [Item] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file) else { continue }
            try? FileManager.default.removeItem(at: file)
            if file.pathExtension == "txt" { items.append(.text(String(decoding: data, as: UTF8.self))) } else { items.append(.image(data)) }
        }
        return items
    }
}

/// The app writes this; the widgets only read it, since they can't open the puzzle file themselves.
struct WidgetData: Codable, Equatable {
    struct MatePuzzle: Codable, Equatable {
        var day: Int
        var fen: String
        var best: String
        var last: String?
    }
    var puzzles: [MatePuzzle] = []
    var dailyDays: [Int] = []
    var streak = 0
    var showStreak = true

    private static var file: URL? { SharedContainer.url?.appending(path: "widget.json") }
    static func load() -> WidgetData? { file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(WidgetData.self, from: $0) } }
    func save() { if let file = Self.file, let data = try? JSONEncoder().encode(self) { try? data.write(to: file, options: .atomic) } }
}

/// The analysis on the Lock Screen and in the Dynamic Island.
struct AnalysisAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
    }
    var opponent: String
}
