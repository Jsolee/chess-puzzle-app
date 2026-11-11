import SwiftUI

/// First run, after the welcome: the real app, one tab at a time, with a note on what each one is for.
struct TourOverlay: View {
    @Binding var tab: Int
    var finish: () -> Void
    @State private var step = 0

    private struct Stop { let tab: Int; let title: LocalizedStringKey; let text: LocalizedStringKey }
    private static let stops: [Stop] = [
        Stop(tab: 0, title: "Avui", text: "Cada dia, un moment de la teva última partida. Primer el busques tu, després te l'expliquem. A sota, el puzzle del dia."),
        Stop(tab: 1, title: "Puzzles", text: "Problemes de partides reals, a la teva mida. Els que se t'escapen tornen més endavant."),
        Stop(tab: 2, title: "Partides", text: "Escriu el teu usuari de chess.com o de Lichess i porta les teves partides. Stockfish les analitza aquí mateix, jugada a jugada."),
        Stop(tab: 3, title: "Lliçons", text: "Un camí de lliçons curtes, les regles d'or per a qui comença, i l'arbre de les obertures."),
        Stop(tab: 4, title: "Tu", text: "El teu escut: quina figura medieval ets segons com jugues. I els ajustos."),
    ]
    /// Where each tab's icon sits across the bar, as a share of the width. The bar floats with margins, so these aren't fifths.
    private static let iconX: [CGFloat] = [0.167, 0.326, 0.485, 0.659, 0.831]
    /// Room left at the bottom for the tab bar, which stays bright and is what the caret points at.
    private static let bar: CGFloat = 60

    var body: some View {
        let stop = Self.stops[step]
        let last = step == Self.stops.count - 1
        GeometryReader { g in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(step + 1) de \(Self.stops.count)").font(Theme.text(14)).foregroundStyle(Theme.quiet)
                            Spacer()
                            if !last {
                                Button("Salta") { finish() }.font(Theme.text(15, .semibold)).foregroundStyle(Theme.quiet).frame(minHeight: 44)
                            }
                        }
                        Text(stop.title).font(Theme.display(38)).foregroundStyle(Theme.tin)
                        Text(stop.text).font(Theme.text(17)).foregroundStyle(Theme.tin.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                        Button { advance() } label: {
                            Text(last ? "Comença" : "Següent").font(Theme.text(18, .semibold)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(last ? Theme.gold : Theme.tin))
                        }
                        .padding(.top, 6)
                    }
                    .id(step)
                    .transition(.opacity)
                    .padding(20)
                    .background(Theme.fieldDeep)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                    .overlay(alignment: .bottomLeading) {
                        Caret().fill(Theme.gold).frame(width: 16, height: 8)
                            .offset(x: g.size.width * Self.iconX[stop.tab] - 8, y: 20)
                    }
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                }
                .background(Theme.ink.opacity(0.45).ignoresSafeArea(edges: .top))
                Color.clear.frame(height: Self.bar).contentShape(Rectangle())
            }
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .animation(.easeOut(duration: 0.22), value: step)
    }

    private func advance() {
        guard step < Self.stops.count - 1 else { finish(); return }
        step += 1
        withAnimation(.easeOut(duration: 0.2)) { tab = Self.stops[step].tab }
        Haptics.step()
    }
}

private struct Caret: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
