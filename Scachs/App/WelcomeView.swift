import SwiftUI

/// First run. Not a picture of the app: you play the last move of the earliest recorded game with the modern queen.
struct WelcomeView: View {
    var done: () -> Void
    @State private var board = BoardModel(position: Position(fen: "5k1r/2pQ1ppp/6q1/3R4/5b2/7P/PPP2PP1/4K2R w K - 1 21")!, orientation: .white)
    @State private var solved = false
    @State private var level: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image("Wordmark").renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 236).foregroundStyle(Theme.tin)
                    .padding(.top, 28).accessibilityLabel("Scachs")
                Text(solved ? "Mat de dama a casa de l'altra dama." : "València, c.1475. El registre més antic que es coneix de la dama moderna acaba amb aquesta jugada.")
                    .font(solved ? Theme.display(30) : Theme.text(18))
                    .foregroundStyle(Theme.tin).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16).padding(.bottom, 18)
                    .frame(minHeight: 128, alignment: .topLeading)
                    .animation(.easeOut(duration: 0.25), value: solved)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            BoardView(board)
            VStack(alignment: .leading, spacing: 14) {
                if solved {
                    Text("Quant jugues?").font(Theme.text(17, .medium)).foregroundStyle(Theme.tin).padding(.top, 18)
                    HStack(spacing: 10) {
                        levelButton("Començo", 1000); levelButton("Jugo sovint", 1400); levelButton("Competeixo", 1800)
                    }
                } else {
                    Text("Juguen les blanques. Troba el mat.").font(Theme.text(17, .medium)).foregroundStyle(Theme.gold).padding(.top, 18)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.field.ignoresSafeArea())
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            Sound.start()
            board.onMove = { [board] m in
                if board.position.applying(m).isCheckmate {
                    board.play(m)
                    board.interactive = false
                    board.reflex(from: m.to)
                    solved = true
                } else {
                    board.flashWrong(m.to)
                }
            }
        }
    }

    private func levelButton(_ title: LocalizedStringKey, _ r: Double) -> some View {
        Button {
            Progress.shared.setInitialRating(r)
            done()
        } label: {
            Text(title).font(Theme.text(16, .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 8)
                .padding(.vertical, 13).frame(maxWidth: .infinity)
                .background(Capsule().fill(Theme.tin))
        }
    }
}
