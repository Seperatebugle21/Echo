import SwiftUI

struct GameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shake: CGFloat = 0
    @State private var banner: Banner?
    @State private var confetti = 0
    @State private var askToLeave = false
    @FocusState private var keysFocused: Bool

    struct Banner: Equatable {
        var id = UUID()
        var text: String
        var detail: String?
        var tone: Tone

        enum Tone { case good, bad, neutral }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let game = model.session {
                VStack(spacing: 0) {
                    header(game)
                    if game.status == .finished {
                        ResultView(game: game, onConfetti: { confetti += 1 })
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                    removal: .opacity))
                    } else if let round = game.round {
                        playArea(game: game, round: round)
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: game.status)
            }
            ConfettiView(trigger: confetti)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .focusable()
        .focused($keysFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onAppear { keysFocused = true }
        .confirmationDialog(model.strings.quitTitle, isPresented: $askToLeave, titleVisibility: .visible) {
            Button(model.strings.leave) { model.closeGame() }
            if model.session?.mode == .endless {
                Button(model.strings.endRun, role: .destructive) { model.endRun() }
            }
            Button(model.strings.cancel, role: .cancel) {}
        } message: {
            Text(model.strings.quitMessage)
        }
    }

    // MARK: Header

    private func header(_ game: GameSession) -> some View {
        let strings = model.strings
        return ZStack {
            VStack(spacing: 6) {
                Text(title(for: game))
                    .font(Theme.roundedFont(17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                if game.mode == .endless {
                    HStack(spacing: 10) {
                        LivesView(lives: game.livesLeft, total: GameSession.endlessLives)
                        Text("\(strings.run) \(game.correctRounds)")
                            .font(Theme.roundedFont(13, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                            .contentTransition(.numericText(value: Double(game.correctRounds)))
                            .animation(.spring, value: game.correctRounds)
                    }
                } else {
                    RoundDots(rounds: game.rounds, current: game.status == .finished ? -1 : game.currentRound)
                }
            }
            HStack {
                Button {
                    if game.status == .finished { model.closeGame() } else { askToLeave = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 38, height: 38)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.line))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(strings.close)
                Spacer()
                Text("\(game.score)")
                    .font(Theme.roundedFont(17, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText(value: Double(game.score)))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: game.score)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.accentSoft, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func title(for game: GameSession) -> String {
        let strings = model.strings
        switch game.mode {
        case .endless: return strings.endless
        case .daily, .archive:
            if game.status == .finished { return strings.puzzleNumber(game.puzzleNumber ?? 1) }
            return strings.roundOf(game.currentRound + 1, game.rounds.count)
        }
    }

    // MARK: Playing

    private func playArea(game: GameSession, round: Round) -> some View {
        let strings = model.strings
        return VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    RoundBoard(round: round, typed: game.typed, width: min(proxy.size.width - 32, 520),
                               graph: model.graph(for: game.language), strings: strings, shake: shake)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                        .id(round.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            bannerView
                .frame(height: 44)

            controls(game: game, round: round)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            KeyboardView(
                enterTitle: round.isDone ? "→" : "OK",
                enterEnabled: round.isDone || game.remainingLetters == 0,
                onLetter: { letter in
                    guard !round.isDone else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { model.type(letter) }
                },
                onDelete: {
                    withAnimation(.easeOut(duration: 0.12)) { model.deleteLetter() }
                },
                onEnter: enter
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            HStack(spacing: 8) {
                Image(systemName: icon(for: banner.tone))
                Text(banner.text).font(Theme.roundedFont(16, weight: .heavy))
                if let detail = banner.detail {
                    Text(detail).font(Theme.roundedFont(15, weight: .semibold)).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(color(for: banner.tone), in: Capsule())
            .shadow(color: color(for: banner.tone).opacity(0.35), radius: 8, y: 3)
            .id(banner.id)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }

    private func icon(for tone: Banner.Tone) -> String {
        switch tone {
        case .good: return "checkmark.circle.fill"
        case .bad: return "xmark.circle.fill"
        case .neutral: return "info.circle.fill"
        }
    }

    private func color(for tone: Banner.Tone) -> Color {
        switch tone {
        case .good: return Theme.correct
        case .bad: return Theme.wrong
        case .neutral: return Theme.inkSoft
        }
    }

    @ViewBuilder
    private func controls(game: GameSession, round: Round) -> some View {
        let strings = model.strings
        if round.isDone {
            let finishing = game.mode == .endless ? game.livesLeft <= 0 : game.isLastDailyRound
            PrimaryButton(title: finishing ? strings.seeResult : strings.nextRound,
                          systemImage: finishing ? "flag.checkered" : "arrow.right",
                          fill: finishing ? Theme.gold : Theme.accent) {
                advance()
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            let slotIndex = round.activeSlotIndex ?? 0
            let slot = round.slots[slotIndex]
            let full = Round.maxPoints / round.slots.count
            let cost = Int(Double(full) * Round.hintCostShare)
            let canHint = slot.hintLetters < slot.length - 1
            HStack(spacing: 10) {
                Button {
                    if model.useHint() {
                        Haptics.soft()
                        show(Banner(text: "−\(cost)", detail: nil, tone: .neutral))
                    }
                } label: {
                    Label("\(strings.hint)  −\(cost)", systemImage: "lightbulb.fill")
                        .font(Theme.roundedFont(15, weight: .bold))
                        .foregroundStyle(canHint ? Theme.ink : Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                }
                .buttonStyle(PressableStyle())
                .disabled(!canHint)

                Button {
                    Haptics.warning()
                    let answer = slot.answer
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { model.skip() }
                    show(Banner(text: strings.answerWas(answer), detail: nil, tone: .bad))
                } label: {
                    Label(strings.skip, systemImage: "forward.fill")
                        .font(Theme.roundedFont(15, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
                }
                .buttonStyle(PressableStyle())
            }
            .transition(.opacity)
        }
    }

    // MARK: Actions

    private func enter() {
        guard let game = model.session, let round = game.round else { return }
        if round.isDone {
            advance()
        } else {
            submit()
        }
    }

    private func submit() {
        guard let before = model.session, let round = before.round, let slotIndex = round.activeSlotIndex else { return }
        let roundIndex = before.currentRound
        let answer = round.slots[slotIndex].answer
        let outcome = withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { model.submit() }
        let strings = model.strings

        switch outcome {
        case .incomplete:
            Haptics.warning()
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
            show(Banner(text: strings.notInList, detail: nil, tone: .neutral))
        case .correct(let alternative):
            Haptics.success()
            let updated = model.session?.rounds[roundIndex]
            let points = updated?.value(ofSlot: slotIndex) ?? 0
            show(Banner(text: alternative ? strings.alsoCorrect : strings.correct, detail: "+\(points)", tone: .good))
            if updated?.isDone == true, updated?.isPerfect == true, !reduceMotion {
                after(0.35) { confetti += 1 }
            }
        case .wrong:
            Haptics.error()
            withAnimation(.linear(duration: 0.45)) { shake += 1 }
            show(Banner(text: strings.answerWas(answer), detail: nil, tone: .bad))
        case .notPlaying:
            break
        }
    }

    private func advance() {
        Haptics.soft()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            banner = nil
            model.advance()
        }
    }

    private func show(_ new: Banner) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { banner = new }
        let id = new.id
        after(2.2) {
            if banner?.id == id {
                withAnimation(.easeOut(duration: 0.25)) { banner = nil }
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let game = model.session, game.status == .playing, let round = game.round else { return .ignored }
        if press.key == .return {
            enter()
            return .handled
        }
        if press.key == .delete {
            withAnimation(.easeOut(duration: 0.12)) { model.deleteLetter() }
            return .handled
        }
        guard !round.isDone, let character = press.characters.lowercased().first,
              ("a"..."z").contains(character) else { return .ignored }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { model.type(character) }
        return .handled
    }
}

// MARK: - Board

/// The clues and answer tiles of one round.
struct RoundBoard: View {
    var round: Round
    var typed: String
    var width: CGFloat
    var graph: WordGraph
    var strings: L10n
    var shake: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(strings.kindTitle(round.kind).uppercased())
                    .font(Theme.roundedFont(12, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.accentSoft, in: Capsule())
                Text(strings.kindHint(round.kind))
                    .font(Theme.roundedFont(15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 6)

            switch round.kind {
            case .bridge: bridge
            case .tripleBridge: triple
            case .longBridge: long
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bridge: some View {
        let lead = round.leadingClue?.word ?? ""
        let trail = round.trailingClue?.word ?? ""
        let slot = round.slots[0]
        return VStack(spacing: 6) {
            ClueCard(word: lead)
            LinkConnector(lit: slot.result == .correct, failed: slot.result == .wrong,
                          label: graph.compound(lead, slot.answer))
            slotRow(0)
            LinkConnector(lit: slot.result == .correct, failed: slot.result == .wrong,
                          label: graph.compound(slot.answer, trail))
            ClueCard(word: trail)
        }
    }

    private var long: some View {
        let lead = round.leadingClue?.word ?? ""
        let trail = round.trailingClue?.word ?? ""
        let first = round.slots[0]
        let second = round.slots[1]
        return VStack(spacing: 6) {
            ClueCard(word: lead)
            LinkConnector(lit: first.result == .correct, failed: first.result == .wrong,
                          label: graph.compound(lead, first.answer))
            slotRow(0)
            LinkConnector(lit: first.result == .correct && second.result == .correct,
                          failed: second.result == .wrong,
                          label: graph.compound(first.answer, second.answer))
            slotRow(1)
            LinkConnector(lit: second.result == .correct, failed: second.result == .wrong,
                          label: graph.compound(second.answer, trail))
            ClueCard(word: trail)
        }
    }

    private var triple: some View {
        let slot = round.slots[0]
        return VStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { tripleClues }
                VStack(spacing: 8) { tripleClues }
            }
            .frame(maxWidth: width)
            LinkConnector(lit: slot.result == .correct, failed: slot.result == .wrong, label: nil)
            slotRow(0)
            if slot.isDone {
                VStack(spacing: 6) {
                    ForEach(round.clues, id: \.self) { clue in
                        Text(clue.side == .before ? graph.compound(clue.word, slot.answer)
                                                  : graph.compound(slot.answer, clue.word))
                            .font(Theme.roundedFont(13, weight: .semibold))
                            .foregroundStyle(slot.result == .correct ? Theme.correct : Theme.wrong)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(slot.result == .correct ? Theme.correctSoft : Theme.wrongSoft, in: Capsule())
                    }
                }
                .padding(.top, 8)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: slot.isDone)
    }

    @ViewBuilder
    private var tripleClues: some View {
        ForEach(round.clues, id: \.self) { clue in
            HStack(spacing: 6) {
                if clue.side == .after { slotGlyph }
                Text(clue.word.uppercased())
                    .font(Theme.roundedFont(18, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if clue.side == .before { slotGlyph }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .card(fill: Theme.surfaceRaised)
        }
    }

    private var slotGlyph: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            .frame(width: 16, height: 16)
    }

    private func slotRow(_ index: Int) -> some View {
        let slot = round.slots[index]
        let active = round.activeSlotIndex == index
        let locked = !slot.isDone && !active
        let spacing: CGFloat = 6
        let size = min(52, (width - spacing * CGFloat(slot.length - 1)) / CGFloat(slot.length))
        let letters = Array(slot.answer)
        let typedLetters = Array(typed)

        return VStack(spacing: 6) {
            HStack(spacing: spacing) {
                ForEach(0..<slot.length, id: \.self) { i in
                    let tile = tileContent(i, slot: slot, active: active, locked: locked,
                                           letters: letters, typed: typedLetters)
                    LetterTile(letter: tile.0, style: tile.1, size: size, index: i)
                }
            }
            .modifier(ShakeEffect(animatableData: active ? shake : 0))
            if slot.result == .wrong, let guess = slot.guess {
                Text(guess.uppercased())
                    .font(Theme.roundedFont(14, weight: .bold))
                    .strikethrough(true, color: Theme.wrong)
                    .foregroundStyle(Theme.inkSoft)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(slot: slot, active: active))
    }

    private func tileContent(_ i: Int, slot: AnswerSlot, active: Bool, locked: Bool,
                             letters: [Character], typed: [Character]) -> (Character?, TileStyle) {
        if slot.isDone {
            return (letters[i], slot.result == .correct ? .correct : .wrong)
        }
        if locked { return (nil, .locked) }
        if i < slot.hintLetters { return (letters[i], .hint) }
        let typedIndex = i - slot.hintLetters
        if typedIndex < typed.count { return (typed[typedIndex], .typed) }
        return (nil, typedIndex == typed.count && active ? .cursor : .empty)
    }

    private func accessibilityText(slot: AnswerSlot, active: Bool) -> String {
        if slot.isDone { return slot.answer }
        let known = String(slot.answer.prefix(slot.hintLetters)) + (active ? typed : "")
        return "\(slot.length) letters" + (known.isEmpty ? "" : ", \(known)")
    }
}
