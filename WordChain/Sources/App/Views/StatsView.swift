import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var grow = false

    var body: some View {
        let strings = model.strings
        let stats = model.currentStats
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(strings.daily)
                    grid([
                        StatItem(title: strings.played, value: "\(stats.daysPlayed)"),
                        StatItem(title: strings.average, value: "\(stats.averageDayScore)"),
                        StatItem(title: strings.best, value: "\(stats.bestDayScore)"),
                        StatItem(title: strings.currentStreak, value: "\(stats.currentStreak(today: model.today))"),
                        StatItem(title: strings.longestStreak, value: "\(stats.longestStreak)"),
                        StatItem(title: strings.perfectDays, value: "\(stats.perfectDays)"),
                    ])

                    section(strings.scoreSpread)
                    bands(stats.scoreBands)

                    section(strings.endless)
                    grid([
                        StatItem(title: strings.endlessBestRun, value: "\(stats.bestEndlessRun)"),
                        StatItem(title: strings.endlessBestScore, value: "\(stats.bestEndlessScore)"),
                        StatItem(title: strings.endlessSolved, value: "\(stats.endlessRoundsSolved)"),
                        StatItem(title: strings.endlessRuns, value: "\(stats.endlessRunsPlayed)"),
                    ])

                    Button(role: .destructive) { confirmReset = true } label: {
                        Text(model.language == .dutch ? "Statistieken wissen" : "Reset statistics")
                            .font(Theme.roundedFont(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                }
                .padding(18)
            }
            .background(Theme.background)
            .navigationTitle("\(strings.statistics) \(model.language.flag)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(strings.done) { dismiss() } }
            }
            .confirmationDialog(model.language == .dutch ? "Alle statistieken voor deze taal wissen?" : "Reset all statistics for this language?",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button(model.language == .dutch ? "Wissen" : "Reset", role: .destructive) { model.resetStatistics() }
                Button(strings.cancel, role: .cancel) {}
            }
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15)) { grow = true }
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.roundedFont(13, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(Theme.inkSoft)
    }

    private func grid(_ items: [StatItem]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                  spacing: 10) {
            ForEach(items) { item in
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(Theme.roundedFont(24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(item.title)
                        .font(Theme.roundedFont(12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .padding(.horizontal, 6)
                .card()
            }
        }
    }

    private func bands(_ counts: [Int]) -> some View {
        let maxCount = max(counts.max() ?? 0, 1)
        let labels = ["0", "1000", "2000", "3000", "4000", "5000"]
        return VStack(spacing: 8) {
            if counts.allSatisfy({ $0 == 0 }) {
                Text(model.strings.noGamesYet)
                    .font(Theme.roundedFont(14, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(counts.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text(labels[index] + (index < 5 ? "+" : ""))
                            .font(Theme.roundedFont(12, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(width: 46, alignment: .trailing)
                        GeometryReader { proxy in
                            let fraction = CGFloat(counts[index]) / CGFloat(maxCount)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(index == 5 ? Theme.correct : Theme.accent)
                                .frame(width: max(28, proxy.size.width * (grow ? fraction : 0)))
                                .overlay(alignment: .trailing) {
                                    Text("\(counts[index])")
                                        .font(Theme.roundedFont(12, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .padding(.trailing, 8)
                                }
                        }
                        .frame(height: 24)
                    }
                }
            }
        }
        .padding(14)
        .card()
    }
}
