import SwiftUI

struct LeatherJournalBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [JournalPalette.leatherTop, JournalPalette.leatherBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if !reduceTransparency {
                Image("LeatherGrain")
                    .resizable()
                    .scaledToFill()
                    .blendMode(.softLight)
                    .opacity(0.16)
            }

            LinearGradient(
                colors: [.white.opacity(reduceTransparency ? 0 : 0.035), .clear, .black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct JournalCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency ? JournalPalette.cardOpaque : JournalPalette.card.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(JournalPalette.paperRule.opacity(0.72), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.18), radius: 10, y: 5)
    }
}

struct JournalIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .foregroundStyle(configuration.isPressed ? JournalPalette.paperInk.opacity(0.6) : JournalPalette.paperInk)
    }
}

extension View {
    func journalCard() -> some View { modifier(JournalCardModifier()) }
}
