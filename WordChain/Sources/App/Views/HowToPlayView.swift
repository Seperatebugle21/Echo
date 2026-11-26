import SwiftUI

struct HowToPlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strings = model.strings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(strings.rulesIntro)
                        .font(Theme.roundedFont(17, weight: .medium))
                        .foregroundStyle(Theme.ink)

                    example(title: strings.kindTitle(.bridge), text: strings.rulesBridge, icon: "arrow.left.and.right")
                    example(title: strings.kindTitle(.tripleBridge), text: strings.rulesTriple, icon: "triangle")
                    example(title: strings.kindTitle(.longBridge), text: strings.rulesLong, icon: "link")

                    rule(strings.rulesGuess, icon: "target")
                    rule(strings.rulesAlternative, icon: "checkmark.seal.fill")
                    rule(strings.rulesDaily, icon: "calendar")
                    rule(strings.rulesEndless, icon: "infinity")

                    PrimaryButton(title: strings.play, systemImage: "play.fill") { dismiss() }
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(strings.howToPlay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(strings.done) { dismiss() } }
            }
        }
    }

    private func example(title: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(Theme.roundedFont(16, weight: .heavy))
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(Theme.roundedFont(16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func rule(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            Text(text)
                .font(Theme.roundedFont(15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
