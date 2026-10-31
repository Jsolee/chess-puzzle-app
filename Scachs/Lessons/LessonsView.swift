import SwiftUI

struct LessonsView: View {
    private var progress: Progress { .shared }
    @State private var open: LessonMeta?
    @State private var review: LessonReviews.Due?
    private var library: LessonLibrary { .shared }

    private var pick: Recommender.Pick? {
        Recommender.next(progress: progress, lessons: library.metas, reviewEvidence: GameLibrary.shared.missedTacticEvidence)
    }
    private var due: LessonReviews.Due? { Recommender.spacedDue().first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Lliçons").font(Theme.display(52)).foregroundStyle(Theme.tin)
                    if let p = pick { hero(p) }
                    if let d = due, let m = library.metas.first(where: { $0.id == d.lessonID }) { dueRow(m, d) }
                    ForEach(LessonLibrary.sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: section.name.text).font(Theme.display(30)).foregroundStyle(Theme.tin).padding(.bottom, 6)
                            ForEach(section.lessonIDs, id: \.self) { id in
                                if let m = library.metas.first(where: { $0.id == id }) { row(m) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 40)
            }
            .background(Theme.field.ignoresSafeArea())
            .fullScreenCover(item: $open) { LessonRunnerView(meta: $0) }
            .fullScreenCover(item: $review) { d in
                if let m = library.metas.first(where: { $0.id == d.lessonID }) { LessonRunnerView(meta: m, reexposure: d) }
            }
        }
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

    private func row(_ m: LessonMeta) -> some View {
        let done = progress.completedLessons.contains(m.id)
        return Button { open = m } label: {
            HStack(spacing: 12) {
                Rectangle().fill(done ? Theme.gold : Theme.tin.opacity(0.14)).frame(width: 12, height: 12)
                Text(verbatim: m.title).font(Theme.text(18)).foregroundStyle(done ? Theme.tin.opacity(0.72) : Theme.tin).multilineTextAlignment(.leading)
                Spacer()
                Text("\(m.minutes) min").font(Theme.text(14)).foregroundStyle(Theme.quiet)
            }
            .padding(.vertical, 11).contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityValue(done ? Text("Feta") : Text(""))
    }
}

extension LessonReviews.Due: Identifiable { var id: String { lessonID + "\(exposure)" } }
