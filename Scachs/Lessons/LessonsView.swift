import SwiftUI

struct LessonsView: View {
    private var progress: Progress { .shared }
    @State private var open: LessonMeta?
    @State private var review: LessonReviews.Due?
    @State private var showRules = false
    @State private var mode = Mode.path
    private enum Mode: Hashable { case path, openings, exercises }
    @State private var entries: [OpeningEntry] = []
    private var library: LessonLibrary { .shared }

    private var pick: Recommender.Pick? {
        Recommender.next(progress: progress, lessons: library.metas, reviewEvidence: GameLibrary.shared.missedTacticEvidence)
    }
    private var due: LessonReviews.Due? { Recommender.spacedDue().first }

    var body: some View {
        let pick = pick
        let next = pick?.lesson.id ?? library.metas.first { !progress.completedLessons.contains($0.id) }?.id
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 6) {
                            ScreenTitle("Lliçons")
                            SectionPicker(items: [("Camí", Mode.path), ("Obertures", .openings), ("Exercicis", .exercises)], selection: $mode)
                        }
                        switch mode {
                        case .openings:
                            OpeningsView(entries: entries, done: progress.completedLessons) { open = $0 }
                        case .exercises:
                            ExercisesView()
                        case .path:
                            if let p = pick { hero(p) }
                            if let d = due, let m = library.metas.first(where: { $0.id == d.lessonID }) { dueRow(m, d) }
                            ForEach(LessonLibrary.sections.filter { $0.id != "openings" }) { section in unit(section, next: next) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 40)
                }
                .onAppear {
                    #if DEBUG
                    if ScreenshotScene.is("openings") { mode = .openings }
                    if ScreenshotScene.is("exercises") { mode = .exercises }
                    if ScreenshotScene.is("lesson") { open = library.metas.first { $0.id == "L06" } }
                    if ScreenshotScene.is("path") { scroller.scrollTo("R02", anchor: .center); return }
                    #endif
                    if let next, mode == .path { scroller.scrollTo(next, anchor: .center) }
                }
                .task { if entries.isEmpty { entries = OpeningEntry.all } }
            }
            .fieldBackground()
            .fullScreenCover(item: $open) { LessonRunnerView(meta: $0) }
            .fullScreenCover(item: $review) { d in
                if let m = library.metas.first(where: { $0.id == d.lessonID }) { LessonRunnerView(meta: m, reexposure: d) }
            }
            .fullScreenCover(isPresented: $showRules) { GoldenRulesView() }
        }
    }

    private func hero(_ p: Recommender.Pick) -> some View {
        Button { open = p.lesson } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.weak ? "Aquí se t'escapen" : "Següent al teu camí").font(Theme.text(14)).foregroundStyle(Theme.quiet)
                    Text(verbatim: p.lesson.title).font(Theme.text(19, .semibold)).foregroundStyle(Theme.gold).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text("\(p.lesson.minutes) min").font(Theme.text(15)).foregroundStyle(Theme.quiet)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.quiet)
            }
            .frame(minHeight: 58).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func dueRow(_ m: LessonMeta, _ d: LessonReviews.Due) -> some View {
        Button { review = d } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per recordar-ho").font(Theme.text(14)).foregroundStyle(Theme.quiet)
                    Text(verbatim: m.title).font(Theme.text(18, .medium)).foregroundStyle(Theme.tin)
                }
                Spacer()
                Text("2 puzzles").font(Theme.text(15)).foregroundStyle(Theme.gold)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func unit(_ section: LessonLibrary.Section, next: String?) -> some View {
        let metas = section.lessonIDs.compactMap { id in library.metas.first { $0.id == id } }
        let done = metas.filter { progress.completedLessons.contains($0.id) }.count
        let first = LessonLibrary.sections.prefix { $0.id != section.id }.reduce(0) { $0 + $1.lessonIDs.count } + 1
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle(verbatim: section.name.text, detail: Text("\(done) de \(metas.count)"))
            if section.id == "rules" {
                Button { showRules = true } label: {
                    Text("Llegeix-les").font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                }
            }
            Trail(metas: metas, first: first, done: progress.completedLessons, next: next) { open = $0 }
        }
    }
}

/// A unit's lessons as stops on a winding road: sealed in wax once done, gold for the next one, open circles ahead.
private struct Trail: View {
    let metas: [LessonMeta]
    let first: Int
    let done: Set<String>
    let next: String?
    let open: (LessonMeta) -> Void
    private let row: CGFloat = 96
    private let node: CGFloat = 62

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let points = metas.indices.map { i in
                CGPoint(x: w / 2 + CGFloat(sin(Double(first + i) * 1.1)) * min(w * 0.24, 92), y: row * (CGFloat(i) + 0.5))
            }
            ZStack(alignment: .topLeading) {
                // A gold thread as far as you've come, dots beyond it.
                thread(points, walked: true).stroke(Theme.gold, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                thread(points, walked: false).stroke(Theme.tin.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 8]))
                ForEach(metas.indices, id: \.self) { i in
                    let p = points[i], right = p.x <= w / 2
                    let labelWidth = right ? w - p.x - node / 2 - 14 : p.x - node / 2 - 14
                    stop(metas[i], number: first + i)
                        .position(p)
                    label(metas[i], alignment: right ? .leading : .trailing)
                        .frame(width: max(labelWidth, 60), alignment: right ? .leading : .trailing)
                        .position(x: right ? p.x + node / 2 + 14 + labelWidth / 2 : labelWidth / 2, y: p.y)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: row * CGFloat(metas.count))
    }

    private func thread(_ points: [CGPoint], walked: Bool) -> Path {
        Path { p in
            for i in points.indices.dropFirst() {
                let reached = done.contains(metas[i - 1].id) && (done.contains(metas[i].id) || metas[i].id == next)
                guard reached == walked else { continue }
                let a = points[i - 1], b = points[i]
                p.move(to: a)
                p.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + row * 0.5), control2: CGPoint(x: b.x, y: b.y - row * 0.5))
            }
        }
    }

    private func stop(_ m: LessonMeta, number: Int) -> some View {
        let isDone = done.contains(m.id), isNext = m.id == next
        let numeral = Roman.numeral(number)
        return Button { open(m) } label: {
            ZStack {
                if isDone {
                    WaxSeal(numeral: numeral, size: node)
                } else if isNext {
                    Circle().stroke(Theme.gold.opacity(0.3), lineWidth: 1).frame(width: node + 12, height: node + 12)
                    Circle().fill(Theme.fieldDeep.opacity(0.85)).frame(width: node * 0.84, height: node * 0.84)
                    Circle().stroke(Theme.gold, lineWidth: 1.5).frame(width: node * 0.84, height: node * 0.84)
                    Text(verbatim: numeral).font(Theme.text(numeral.count > 3 ? 15 : 19, .semibold)).foregroundStyle(Theme.gold)
                } else {
                    Circle().fill(Theme.fieldDeep.opacity(0.65)).frame(width: node * 0.84, height: node * 0.84)
                    Circle().stroke(Theme.tin.opacity(0.38), lineWidth: 1.1).frame(width: node * 0.84, height: node * 0.84)
                    Text(verbatim: numeral).font(Theme.text(numeral.count > 3 ? 15 : 19, .semibold)).foregroundStyle(Theme.tin.opacity(0.55))
                }
            }
            .frame(width: node + 14, height: node + 14).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .id(m.id)
        .accessibilityLabel(Text(verbatim: m.title))
        .accessibilityValue(isDone ? Text("Feta") : isNext ? Text("Següent") : Text(""))
    }

    private func label(_ m: LessonMeta, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(verbatim: m.title).font(Theme.text(16, m.id == next ? .semibold : .medium))
                .foregroundStyle(m.id == next ? Theme.gold : done.contains(m.id) ? Theme.quiet : Theme.tin)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing).lineLimit(2)
            Text("\(m.minutes) min").font(Theme.text(13)).foregroundStyle(Theme.quiet)
        }
        .accessibilityHidden(true)
    }
}

extension LessonReviews.Due: Identifiable { var id: String { lessonID + "\(exposure)" } }
