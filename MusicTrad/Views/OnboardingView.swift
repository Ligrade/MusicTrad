import SwiftUI

/// Présentation des fonctions au premier lancement, par-dessus la bulle : une fonction par page,
/// « Suivant » puis « J'ai compris ». Reste affichée tant que ce dernier bouton n'a pas été cliqué.
struct OnboardingView: View {
    let done: () -> Void
    @State private var page = 0
    @State private var forward = true
    @State private var appeared = false

    private struct Page {
        let symbol: String?   // nil = logo de l'app
        let title: String
        let detail: String
    }

    private let pages: [Page] = [
        Page(symbol: nil, title: "Bienvenue", detail: "Les paroles de Musique, traduites en direct."),
        Page(symbol: "text.quote", title: "Paroles en direct", detail: "Clique une ligne : Musique y saute."),
        Page(symbol: "character.bubble", title: "EN → FR", detail: "Clic pour traduire.\nClic droit : traduction auto ∞."),
        Page(symbol: "heart.fill", title: "Le cœur", detail: "Garde une traduction pour toujours."),
        Page(symbol: "internaldrive", title: "Sons traduits", detail: "Relis, réécoute ou supprime tes traductions."),
        Page(symbol: "checkmark.seal", title: "Synchro", detail: "Paroles décalées ? Recale-les en un clic."),
        Page(symbol: "leaf", title: "Mode éco", detail: "En veille, l'app ne consomme rien."),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLast {
                        Button("Passer", action: done)
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 20)
                .padding([.top, .horizontal], 18)

                ZStack {
                    pageView(pages[page])
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipped()

                // Points de page (cliquables).
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? LyricsPalette.original : Color.white.opacity(0.25))
                            .frame(width: i == page ? 18 : 7, height: 7)
                            .onTapGesture { go(to: i) }
                    }
                }
                .animation(.snappy, value: page)

                Button {
                    if isLast { done() } else { go(to: page + 1) }
                } label: {
                    Text(isLast ? "J'ai compris" : "Suivant")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 170)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(LyricsPalette.original))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 22)
                .padding(.bottom, 26)
            }
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.1))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08)))
            )
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { appeared = true } }
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 14) {
            Group {
                if let symbol = p.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(LyricsPalette.original)
                } else {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                }
            }
            .frame(width: 96, height: 96)
            Text(p.title).font(.title.bold())
            Text(p.detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
    }

    private func go(to target: Int) {
        guard target != page else { return }
        forward = target > page
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { page = target }
    }
}
