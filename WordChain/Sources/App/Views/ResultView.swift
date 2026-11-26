import SwiftUI

/// Shown when a day is done or an endless run is over.
struct ResultView: View {
    @Environment(AppModel.self) private var model
    var game: GameSession
    var onConfetti: () -> Void

    @State private var shownScore = 0
    @State private var appeared = false

    var body: some View {
        let strings = model.strings
        let stats = model.stats[game.language] ?? PlayerStats()
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(headline)
                        .font(Theme.roundedFont(30, weight: .black))
                        .foregroundStyle(Theme.ink)
                    Text(game.mode == .endless ? strings.runOver : strings.dayComplete)
                        .font(Theme.roundedFont(15, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 10)

                VStack(spacing: 6) {
                    Text("\(shownScore)")
                        .font(Theme.roundedFont(64, weight: .black))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText(value: Double(shownScore)))
                    Text(game.mode == .endless ? strings.roundsSolved(game.correctRounds) : "/ \(game.maxScore)")
                        .font(Theme.roundedFont(16, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                    Text(game.resultSquares)
                        .font(.system(size: game.rounds.count > 12 ? 18 : 28))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .card()
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

                statsRow(stats)

                VStack(spacing: 10) {
                    ForEach(Array(game.rounds.filter(\.isDone).enumerated()), id: \.offset) { index, round in
                        recapRow(round, number: index + 1)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3 + Double(min(index, 10)) * 0.06),
                                       value: appeared)
                    }
                }

                if game.mode != .endless, game.dayIndex == model.today {
                    VStack(spacing: 4) {
                        Text(strings.nextPuzzleIn)
                            .font(Theme.roundedFont(13, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                        CountdownText()
                            .font(Theme.roundedFont(26, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                }

                VStack(spacing: 10) {
                    ShareLink(item: shareText) {
                        Label(strings.share, systemImage: "square.and.arrow.up")
                            .font(Theme.roundedFont(18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())

                    if game.mode == .endless {
                        PrimaryButton(title: strings.newRun, systemImage: "arrow.clockwise", fill: Theme.gold) {
                            model.startEndless(resume: false)
                        }
                    }
                    Button(strings.backHome) { model.closeGame() }
                        .font(Theme.roundedFont(17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .task(id: game.startedAt) { await countUp() }
    }

    private var headline: String {
        let strings = model.strings
        if game.mode == .endless {
            return game.correctRounds >= 10 ? strings.greatScore : (game.correctRounds >= 3 ? strings.goodScore : strings.lowScore)
        }
        switch game.score {
        case game.maxScore: return strings.perfect
        case 3500...: return strings.greatScore
        case 2000...: return strings.goodScore
        default: return strings.lowScore
        }
    }

    private var shareText: String {
        model.strings.shareText(number: game.puzzleNumber, score: game.score, max: game.maxScore,
                                squares: game.resultSquares, endless: game.mode == .endless, run: game.correctRounds)
    }

    private func statsRow(_ stats: PlayerStats) -> some View {
        let strings = model.strings
        let items: [StatItem]
        if game.mode == .endless {
            items = [StatItem(title: strings.endlessBestRun, value: "\(stats.bestEndlessRun)"),
                     StatItem(title: strings.endlessBestScore, value: "\(stats.bestEndlessScore)"),
                     StatItem(title: strings.endlessRuns, value: "\(stats.endlessRunsPlayed)")]
        } else {
            items = [StatItem(title: strings.played, value: "\(stats.daysPlayed)"),
                     StatItem(title: strings.currentStreak, value: "\(stats.currentStreak(today: model.today))"),
                     StatItem(title: strings.best, value: "\(stats.bestDayScore)")]
        }
        return HStack(spacing: 10) {
            ForEach(items) { item in
                VStack(spacing: 2) {
                    Text(item.value).font(Theme.roundedFont(22, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text(item.title).font(Theme.roundedFont(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .card()
            }
        }
    }

    private func recapRow(_ round: Round, number: Int) -> some View {
        let strings = model.strings
        let clueText = describe(round)
        return HStack(spacing: 12) {
            Text(round.isPerfect ? "🟩" : (round.correctSlots > 0 ? "🟨" : "🟥"))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(strings.round(number)) · \(strings.kindTitle(round.kind))")
                    .font(Theme.roundedFont(12, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                Text(clueText)
                    .font(Theme.roundedFont(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text("\(round.points)")
                .font(Theme.roundedFont(16, weight: .heavy))
                .foregroundStyle(round.points > 0 ? Theme.correct : Theme.wrong)
        }
        .padding(14)
        .card()
    }

    private func describe(_ round: Round) -> String {
        let answers = round.slots.map { $0.answer.uppercased() }
        switch round.kind {
        case .bridge, .longBridge:
            let lead = round.leadingClue?.word.lowercased() ?? ""
            let trail = round.trailingClue?.word.lowercased() ?? ""
            return ([lead] + answers + [trail]).joined(separator: " → ")
        case .tripleBridge:
            let clues = round.clues.map { $0.word.lowercased() }.joined(separator: ", ")
            return "\(clues) → \(answers.joined())"
        }
    }

    private func countUp() async {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        let target = game.score
        let steps = 24
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: 35_000_000)
            withAnimation(.easeOut(duration: 0.1)) { shownScore = target * step / steps }
        }
        let great = game.mode == .endless ? game.correctRounds >= 5 : game.score >= 4000
        if great {
            Haptics.success()
            onConfetti()
        }
    }
}

/// A number with a caption, for the stats rows.
struct StatItem: Identifiable {
    var title: String
    var value: String
    var id: String { title }
}
