import SwiftUI

struct LessonsView: View {
    private var progress: Progress { .shared }
    @State private var open: LessonMeta?
    @State private var review: LessonReviews.Due?
    @State private var showRules = false
    @State private var mode = Mode.path
    private enum Mode { case path, openings, exercises }
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lliçons").font(Theme.display(52)).foregroundStyle(Theme.tin)
                            HStack(spacing: 22) {
                                modeButton("Camí", .path)
                                modeButton("Obertures", .openings)
                                modeButton("Exercicis", .exercises)
                            }
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
            .background(Theme.field.ignoresSafeArea())
            .fullScreenCover(item: $open) { LessonRunnerView(meta: $0) }
            .fullScreenCover(item: $review) { d in
                if let m = library.metas.first(where: { $0.id == d.lessonID }) { LessonRunnerView(meta: m, reexposure: d) }
            }
            .fullScreenCover(isPresented: $showRules) { GoldenRulesView() }
        }
    }

    private func modeButton(_ title: LocalizedStringKey, _ value: Mode) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { mode = value } } label: {
            Text(title).font(Theme.text(16, .semibold)).foregroundStyle(mode == value ? Theme.gold : Theme.quiet).frame(minHeight: 44)
        }
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }

    private func hero(_ p: Recommender.Pick) -> some View {
        Button { open = p.lesson } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(p.weak ? "Aquí se t'escapen" : "Següent al teu camí").font(Theme.text(15)).foregroundStyle(Theme.quiet)
                Text(verbatim: p.lesson.title).font(Theme.display(42)).foregroundStyle(Theme.gold).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text("\(p.lesson.minutes) minuts").font(Theme.text(16)).foregroundStyle(Theme.quiet)
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: section.name.text).font(Theme.display(30)).foregroundStyle(Theme.tin)
                Spacer()
                Text("\(done) de \(metas.count)").font(Theme.text(15)).foregroundStyle(Theme.quiet)
            }
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
                Path { p in
                    guard let start = points.first else { return }
                    p.move(to: start)
                    for (a, b) in zip(points, points.dropFirst()) {
                        p.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + row * 0.5), control2: CGPoint(x: b.x, y: b.y - row * 0.5))
                    }
                }
                .stroke(Theme.tin.opacity(0.24), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 8]))
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

    private func stop(_ m: LessonMeta, number: Int) -> some View {
        let isDone = done.contains(m.id), isNext = m.id == next
        let numeral = Roman.numeral(number)
        return Button { open(m) } label: {
            ZStack {
                if isDone {
                    WaxSeal(numeral: numeral, size: node)
                } else if isNext {
                    Circle().stroke(Theme.gold.opacity(0.35), lineWidth: 1.5).frame(width: node + 14, height: node + 14)
                    Circle().fill(Theme.gold).frame(width: node, height: node)
                    Text(verbatim: numeral).font(Theme.text(numeral.count > 3 ? 15 : 19, .semibold)).foregroundStyle(Theme.ink)
                } else {
                    Circle().fill(Theme.fieldDeep).frame(width: node, height: node)
                    Circle().stroke(Theme.tin.opacity(0.3), lineWidth: 1.5).frame(width: node, height: node)
                    Text(verbatim: numeral).font(Theme.text(numeral.count > 3 ? 15 : 19, .semibold)).foregroundStyle(Theme.tin.opacity(0.75))
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
            Text(verbatim: m.title).font(Theme.text(16, .medium)).foregroundStyle(done.contains(m.id) ? Theme.quiet : Theme.tin)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing).lineLimit(2)
            Text("\(m.minutes) min").font(Theme.text(13)).foregroundStyle(Theme.quiet)
        }
        .accessibilityHidden(true)
    }
}

extension LessonReviews.Due: Identifiable { var id: String { lessonID + "\(exposure)" } }
