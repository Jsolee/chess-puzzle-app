import SwiftUI

/// The ten rules a novice can lean on, as a page to read, each group with the lesson that practises it.
struct GoldenRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var open: LessonMeta?

    private struct Rule { let rule: LocalizedStringKey; let why: LocalizedStringKey }
    private static let groups: [(lesson: String, title: LocalizedStringKey, rules: [Rule])] = [
        ("R01", "L'obertura", [
            Rule(rule: "Lluita pel centre.", why: "Peons i peces al mig del tauler controlen més caselles i arriben abans a tot arreu."),
            Rule(rule: "Treu cavalls i alfils abans que la dama.", why: "Les peces menors volen sortir aviat. Si la dama surt massa d'hora, la persegueixen i perds temps. I no moguis dues vegades la mateixa peça sense motiu."),
            Rule(rule: "Enroca aviat.", why: "Amb l'enroc, el rei queda a recer i la torre entra en joc. Un rei al centre amb columnes obertes és un blanc fàcil."),
        ]),
        ("R02", "Abans de moure", [
            Rule(rule: "Mira què vol el rival.", why: "Escacs, captures i amenaces: primer les seves, després les teves. És la regla que més partides salva."),
            Rule(rule: "No deixis res penjat.", why: "Compta qui ataca i qui defensa cada peça. Si l'ataquen més peces de les que la defensen, és en perill."),
            Rule(rule: "Canvia només quan hi guanyes.", why: "Peó 1, cavall 3, alfil 3, torre 5, dama 9. Una torre per un cavall és un mal negoci, encara que sembli un canvi."),
        ]),
        ("R03", "El pla i el final", [
            Rule(rule: "Torres a les columnes obertes.", why: "Darrere dels teus peons, una torre no fa res. En una columna sense peons arriba fins a la setena fila."),
            Rule(rule: "Si vas guanyant, canvia peces.", why: "Com menys peces queden, més pesa el material de més. Si vas perdent, conserva-les i complica la partida."),
            Rule(rule: "Al final, porta el rei al centre.", why: "Quan les dames ja no hi són, el rei no corre perill i és una peça forta. Fes-lo caminar."),
            Rule(rule: "Empeny els peons passats.", why: "Un peó sense peons contraris al davant vol arribar a dama. Cada pas que fa obliga el rival a vigilar-lo."),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Deu idees que serveixen a tota la partida. Si només te n'has d'endur una, que sigui la quarta.")
                    .font(Theme.text(17)).foregroundStyle(Theme.quiet).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                ForEach(Array(Self.groups.enumerated()), id: \.offset) { g, group in
                    let first = Self.groups[..<g].reduce(0) { $0 + $1.rules.count }
                    SectionTitle(group.title).padding(.top, 34).padding(.bottom, 4)
                    ForEach(Array(group.rules.enumerated()), id: \.offset) { i, rule in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(verbatim: Roman.numeral(first + i + 1)).font(Theme.text(24, .semibold)).foregroundStyle(Theme.gold)
                                .frame(width: 44, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.rule).font(Theme.text(19, .semibold)).foregroundStyle(Theme.tin)
                                Text(rule.why).font(Theme.text(16)).foregroundStyle(Theme.quiet).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                        .accessibilityElement(children: .combine)
                    }
                    if let meta = LessonLibrary.shared.metas.first(where: { $0.id == group.lesson }) {
                        Button { open = meta } label: {
                            Text("Practica-ho").font(Theme.text(17, .semibold)).foregroundStyle(Theme.gold).frame(minHeight: 44)
                        }
                        .padding(.leading, 58)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .fieldBackground()
        .topBar(Text("Les regles d'or")) { BarButton(systemImage: "xmark", label: "Tanca") { dismiss() } } trailing: { EmptyView() }
        .fullScreenCover(item: $open) { LessonRunnerView(meta: $0) }
    }
}
