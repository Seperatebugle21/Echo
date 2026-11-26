import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    private enum Sheet: String, Identifiable {
        case rules, stats, settings, archive
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?
    @State private var appeared = false

    var body: some View {
        let strings = model.strings
        let _ = model.saveRevision
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        LogoView(size: 38)
                        Text(strings.tagline)
                            .font(Theme.roundedFont(16, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                    dailyCard
                        .modifier(Appear(shown: appeared, delay: 0.15))
                    endlessCard
                        .modifier(Appear(shown: appeared, delay: 0.25))
                    archiveCard
                        .modifier(Appear(shown: appeared, delay: 0.35))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { sheet = .rules } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel(strings.howToPlay)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { sheet = .stats } label: { Image(systemName: "chart.bar.fill") }
                        .accessibilityLabel(strings.statistics)
                    Button { sheet = .settings } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel(strings.settings)
                }
            }
            .tint(Theme.ink)
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .rules: HowToPlayView()
                case .stats: StatsView()
                case .settings: SettingsView()
                case .archive: ArchiveView { day in
                    self.sheet = nil
                    // Let the sheet close before the game opens.
                    after(0.35) { model.startArchive(day: day) }
                }
                }
            }
            .environment(model)
            .preferredColorScheme(model.appearance.colorScheme)
        }
        .onAppear {
            appeared = true
            if !model.hasSeenRules {
                model.hasSeenRules = true
                after(0.8) { sheet = .rules }
            }
        }
    }

    // MARK: Cards

    private var dailyCard: some View {
        let strings = model.strings
        let saved = model.savedDay(model.today)
        let finished = saved?.status == .finished
        let streak = model.currentStats.currentStreak(today: model.today)

        return Button {
            Haptics.soft()
            model.startDaily()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label(strings.daily, systemImage: "calendar")
                        .font(Theme.roundedFont(22, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(strings.puzzleNumber(model.today + 1))
                        .font(Theme.roundedFont(14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.accentSoft, in: Capsule())
                }
                Text(strings.dailySubtitle)
                    .font(Theme.roundedFont(15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)

                if let saved, finished {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(strings.scoreToday(saved.score))
                                .font(Theme.roundedFont(17, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text(saved.resultSquares).font(.system(size: 18))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(strings.nextPuzzleIn)
                                .font(Theme.roundedFont(12, weight: .medium))
                                .foregroundStyle(Theme.inkSoft)
                            CountdownText()
                                .font(Theme.roundedFont(17, weight: .bold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                } else {
                    HStack {
                        if let saved {
                            RoundDots(rounds: saved.rounds, current: saved.currentRound)
                        }
                        Spacer()
                        Text(saved == nil ? strings.play : strings.resume)
                            .font(Theme.roundedFont(17, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 11)
                            .background(Theme.accent, in: Capsule())
                    }
                }

                if streak > 0 {
                    Label(strings.streakDays(streak), systemImage: "flame.fill")
                        .font(Theme.roundedFont(14, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private var endlessCard: some View {
        let strings = model.strings
        let saved = model.savedEndless
        return Button {
            Haptics.soft()
            model.startEndless()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "infinity")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.endless)
                        .font(Theme.roundedFont(20, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(strings.endlessSubtitle)
                        .font(Theme.roundedFont(14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                    if model.currentStats.bestEndlessRun > 0 {
                        Text(strings.bestRun(model.currentStats.bestEndlessRun))
                            .font(Theme.roundedFont(13, weight: .bold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                Spacer(minLength: 0)
                Text(saved == nil ? strings.play : strings.resume)
                    .font(Theme.roundedFont(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
            .padding(18)
            .card()
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private var archiveCard: some View {
        let strings = model.strings
        return Button {
            sheet = .archive
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.correct, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.archive)
                        .font(Theme.roundedFont(20, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(strings.archiveSubtitle)
                        .font(Theme.roundedFont(14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(18)
            .card()
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

/// Slides a card up into place the first time the screen shows.
private struct Appear: ViewModifier {
    var shown: Bool
    var delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 24)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay), value: shown)
    }
}
