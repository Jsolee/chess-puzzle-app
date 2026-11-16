import SwiftUI

/// One opening lesson, read for its page: the main line it plays from move one, the side you learn, and its picture.
struct OpeningEntry: Identifiable {
    let meta: LessonMeta
    let line: [String]
    let side: Side
    let fen: String
    let essence: String
    var id: String { meta.id }

    init?(meta: LessonMeta, lesson: Lesson) {
        let starts = lesson.startPositions()
        guard let i = lesson.steps.indices.first(where: { lesson.steps[$0].t == .watch && starts[$0]?.fen == Position.start.fen }),
              let recap = lesson.steps.last(where: { $0.t == .recap }), let fen = recap.fen else { return nil }
        var p = Position.start, sans: [String] = []
        for uci in lesson.steps[i].line ?? [] {
            guard let m = p.move(uci: uci) else { break }
            sans.append(p.san(m)); p = p.applying(m)
        }
        let guided = lesson.steps.indices.first { lesson.steps[$0].t == .guided }
        self.meta = meta
        line = sans
        side = guided.flatMap { starts[$0]?.side } ?? .white
        self.fen = fen
        essence = recap.say?.text ?? ""
    }

    static var all: [OpeningEntry] {
        let library = LessonLibrary.shared
        let ids = LessonLibrary.sections.first { $0.id == "openings" }?.lessonIDs ?? []
        return ids.compactMap { id in
            guard let meta = library.metas.first(where: { $0.id == id }), let lesson = library.lesson(id: id) else { return nil }
            return OpeningEntry(meta: meta, lesson: lesson)
        }
    }
}

/// The openings page inside Lessons: a tree that grows from the first move to each opening, then each one with its board.
struct OpeningsView: View {
    let entries: [OpeningEntry]
    let done: Set<String>
    let open: (LessonMeta) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Vint maneres de començar una partida. Cada branca és una jugada; segueix-la fins al nom i aprèn-la.")
                .font(Theme.text(17)).foregroundStyle(Theme.quiet).fixedSize(horizontal: false, vertical: true)
            OpeningTree(entries: entries, done: done, open: open).padding(.top, 22)
            SectionTitle("Totes").padding(.top, 34).padding(.bottom, 4)
            ForEach(entries) { row($0) }
        }
    }

    private func row(_ e: OpeningEntry) -> some View {
        let isDone = done.contains(e.id)
        return Button { open(e.meta) } label: {
            HStack(alignment: .top, spacing: 16) {
                MiniBoard(fen: e.fen, orientation: e.side).frame(width: 96, height: 96)
                    .overlay(alignment: .bottomTrailing) {
                        if isDone { WaxSeal(numeral: "✓", size: 30).offset(x: 9, y: 9) }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: e.meta.title).font(Theme.title(20)).foregroundStyle(Theme.tin).lineLimit(1).minimumScaleFactor(0.7)
                    Text(verbatim: e.essence).font(Theme.text(15)).foregroundStyle(Theme.tin.opacity(0.85))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        SideMark(side: e.side)
                        Text(e.side == .white ? "Amb blanques" : "Amb negres")
                        Text(verbatim: "·")
                        Text("\(e.meta.minutes) min")
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.quiet).padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? Text("Feta") : Text(""))
    }
}

/// Which colour you learn: a tiny tile in that colour.
struct SideMark: View {
    let side: Side
    var body: some View {
        Rectangle().fill(side == .white ? Theme.tin : Theme.ink).frame(width: 9, height: 9)
            .overlay(Rectangle().stroke(Theme.tin.opacity(0.5), lineWidth: 0.5))
    }
}

/// A board small enough to sit beside a line of text, with the app's own pieces.
struct MiniBoard: View {
    let fen: String
    var orientation: Side = .white

    var body: some View {
        Canvas { context, size in
            let s = size.width / 8
            let position = Position(fen: fen)
            for rank in 0..<8 {
                for file in 0..<8 {
                    let x = orientation == .white ? file : 7 - file, y = orientation == .white ? 7 - rank : rank
                    let rect = CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)
                    context.fill(Path(rect), with: .color((rank + file) % 2 == 0 ? Theme.tileDark : Theme.tileLight))
                    if let piece = position?.piece(at: rank * 8 + file) {
                        let letter = ["p", "n", "b", "r", "q", "k"][Int(piece.kind.rawValue)]
                        context.draw(Image(uiImage: PieceImage.load((piece.side == .white ? "w" : "b") + letter)), in: rect.insetBy(dx: s * 0.04, dy: s * 0.04))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The tree of openings: from the first move on the left, one branch per move, thicker where more openings share it,
/// out to each opening's name on the right. Each opening stops at the move that makes it itself.
private struct OpeningTree: View {
    let entries: [OpeningEntry]
    let done: Set<String>
    let open: (LessonMeta) -> Void
    @State private var grown = false
    private let row: CGFloat = 50

    private struct Node {
        var san: String
        var depth: Int
        var children: [Int] = []
        var entry: Int?
        var leaves = 0
        var y: CGFloat = 0
    }

    /// Each line cut at its shortest prefix no other opening shares, then merged into a trie in lesson order.
    private var nodes: [Node] {
        var nodes = [Node(san: "", depth: 0)]
        for (e, entry) in entries.enumerated() {
            let cut = (1...max(entry.line.count, 1)).first { k in
                !entries.indices.contains { $0 != e && Array(entries[$0].line.prefix(k)) == Array(entry.line.prefix(k)) }
            } ?? entry.line.count
            var at = 0
            for san in entry.line.prefix(cut) {
                if let next = nodes[at].children.first(where: { nodes[$0].san == san }) { at = next; continue }
                nodes.append(Node(san: san, depth: nodes[at].depth + 1))
                nodes[at].children.append(nodes.count - 1)
                at = nodes.count - 1
            }
            nodes[at].entry = e
        }
        var leaf: CGFloat = 0
        func place(_ i: Int) {
            if nodes[i].children.isEmpty {
                nodes[i].y = (leaf + 0.5) * row; leaf += 1; nodes[i].leaves = 1
                return
            }
            for c in nodes[i].children { place(c) }
            nodes[i].y = nodes[i].children.map { nodes[$0].y }.reduce(0, +) / CGFloat(nodes[i].children.count)
            nodes[i].leaves = nodes[i].children.map { nodes[$0].leaves }.reduce(0, +)
        }
        place(0)
        return nodes
    }

    var body: some View {
        let nodes = nodes
        let depth = max(nodes.map(\.depth).max() ?? 1, 1)
        let leaves = nodes.filter { $0.children.isEmpty }.count
        GeometryReader { g in
            let names: CGFloat = min(160, g.size.width * 0.42)
            let column = (g.size.width - names - 26) / CGFloat(depth)
            let x: (Int) -> CGFloat = { 8 + CGFloat($0) * column }
            ZStack(alignment: .topLeading) {
                ForEach(nodes.indices.filter { $0 > 0 }, id: \.self) { i in
                    let parent = nodes.firstIndex { $0.children.contains(i) } ?? 0
                    let a = CGPoint(x: x(nodes[parent].depth), y: nodes[parent].y), b = CGPoint(x: x(nodes[i].depth), y: nodes[i].y)
                    Path { p in
                        p.move(to: a)
                        p.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                    }
                    .trim(from: 0, to: grown ? 1 : 0)
                    .stroke(Theme.gold.opacity(0.7), style: StrokeStyle(lineWidth: 0.8 + CGFloat(nodes[i].leaves) * 0.55, lineCap: .round))
                    .animation(.easeOut(duration: 0.5).delay(Double(nodes[i].depth - 1) * 0.12), value: grown)
                }
                ForEach(nodes.indices.filter { nodes[$0].children.isEmpty }, id: \.self) { i in
                    let y = nodes[i].y
                    Path { p in p.move(to: CGPoint(x: x(nodes[i].depth) + 4, y: y)); p.addLine(to: CGPoint(x: g.size.width - names - 8, y: y)) }
                        .stroke(Theme.tin.opacity(0.22), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.5, 5]))
                        .opacity(grown ? 1 : 0).animation(.easeOut(duration: 0.3).delay(0.7), value: grown)
                }
                Circle().fill(Theme.gold).frame(width: 9, height: 9).position(x: x(0), y: nodes[0].y)
                ForEach(nodes.indices.filter { $0 > 0 }, id: \.self) { i in
                    Text(verbatim: nodes[i].san).font(Theme.text(13, .semibold)).foregroundStyle(Theme.tin)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.fieldDeep).overlay(Capsule().strokeBorder(Theme.gold.opacity(0.4), lineWidth: 0.75)))
                        .position(x: x(nodes[i].depth), y: nodes[i].y)
                        .opacity(grown ? 1 : 0)
                        .animation(.easeOut(duration: 0.25).delay(Double(nodes[i].depth) * 0.12), value: grown)
                }
                ForEach(nodes.indices.filter { nodes[$0].entry != nil }, id: \.self) { i in
                    let e = entries[nodes[i].entry!]
                    Button { open(e.meta) } label: {
                        HStack(spacing: 7) {
                            SideMark(side: e.side)
                            Text(verbatim: e.meta.title).font(Theme.title(20)).foregroundStyle(done.contains(e.id) ? Theme.gold : Theme.tin)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(width: names, height: row, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: g.size.width - names / 2, y: nodes[i].y)
                    .accessibilityLabel(Text(verbatim: e.meta.title))
                    .accessibilityHint(Text(verbatim: e.line.prefix(6).joined(separator: " ")))
                }
            }
        }
        .frame(height: row * CGFloat(leaves))
        .onAppear { grown = true }
    }
}
