import SwiftUI

/// How a letter tile looks.
enum TileStyle: Equatable {
    case empty
    /// The next letter will go here.
    case cursor
    case typed
    /// Shown by a hint.
    case hint
    case correct
    /// Shown after a wrong answer.
    case wrong
    /// Waiting for an earlier word.
    case locked

    var fill: Color {
        switch self {
        case .empty, .cursor, .locked: return Theme.surface
        case .typed: return Theme.surface
        case .hint: return Theme.hinted.opacity(0.18)
        case .correct: return Theme.correct
        case .wrong: return Theme.wrong
        }
    }

    var border: Color {
        switch self {
        case .empty, .locked: return Theme.line
        case .cursor: return Theme.accent
        case .typed: return Theme.ink.opacity(0.55)
        case .hint: return Theme.hinted
        case .correct: return Theme.correct
        case .wrong: return Theme.wrong
        }
    }

    var text: Color {
        switch self {
        case .correct, .wrong: return .white
        case .hint: return Theme.ink
        default: return Theme.ink
        }
    }

    var isFinal: Bool { self == .correct || self == .wrong }
}

/// One letter square. Flips over when the word is decided.
struct LetterTile: View {
    var letter: Character?
    var style: TileStyle
    var size: CGFloat
    var index: Int = 0

    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(style.fill)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(style.border, lineWidth: style == .cursor || style == .typed ? 2 : 1.5)
                .opacity(style == .cursor && pulse ? 0.35 : 1)
            if let letter {
                Text(String(letter).uppercased())
                    .font(Theme.roundedFont(size * 0.5, weight: .heavy))
                    .foregroundStyle(style.text)
                    .transition(.scale(scale: 1.35).combined(with: .opacity))
                    .id(letter)
            }
        }
        .frame(width: size, height: size)
        .opacity(style == .locked ? 0.55 : 1)
        .rotation3DEffect(.degrees(style.isFinal ? 360 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(style.isFinal ? Double(index) * 0.07 : 0), value: style)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: letter)
        .onAppear { startPulse() }
        .onChange(of: style) { _, _ in startPulse() }
    }

    private func startPulse() {
        guard style == .cursor else { pulse = false; return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
    }
}

/// A clue word on a card.
struct ClueCard: View {
    var word: String
    var compact = false

    var body: some View {
        Text(word.uppercased())
            .font(Theme.roundedFont(compact ? 17 : 24, weight: .heavy))
            .tracking(compact ? 1 : 2.5)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, compact ? 12 : 22)
            .padding(.vertical, compact ? 10 : 14)
            .frame(minWidth: compact ? 0 : 160)
            .card(fill: Theme.surfaceRaised)
    }
}

/// The short line between two words. Lights up and names the compound once it is found.
struct LinkConnector: View {
    var lit: Bool
    var failed: Bool = false
    var label: String?

    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 4, height: lit || failed ? 12 : 22)
            if (lit || failed), let label {
                Text(label)
                    .font(Theme.roundedFont(12, weight: .semibold))
                    .foregroundStyle(failed ? Theme.wrong : Theme.correct)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background((failed ? Theme.wrongSoft : Theme.correctSoft), in: Capsule())
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: 12)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: lit)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: failed)
    }

    private var color: Color {
        if failed { return Theme.wrong.opacity(0.7) }
        return lit ? Theme.correct : Theme.line
    }
}

/// Little row of hearts for endless mode.
struct LivesView: View {
    var lives: Int
    var total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Image(systemName: index < lives ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(index < lives ? Theme.accent : Theme.inkSoft.opacity(0.5))
                    .scaleEffect(index < lives ? 1 : 0.8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.45), value: lives)
            }
        }
    }
}

/// One dot per daily round, coloured by how it went.
struct RoundDots: View {
    var rounds: [Round]
    var current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(rounds) { round in
                Capsule()
                    .fill(color(for: round))
                    .frame(width: round.id == current ? 22 : 9, height: 9)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
                    .animation(.easeInOut, value: round.isDone)
            }
        }
    }

    private func color(for round: Round) -> Color {
        guard round.isDone else { return round.id == current ? Theme.accent : Theme.line }
        if round.isPerfect { return Theme.correct }
        return round.correctSlots > 0 ? Theme.hinted : Theme.wrong
    }
}

/// The Schakel wordmark: letter tiles that drop in, held together by an arc.
struct LogoView: View {
    var size: CGFloat = 34
    @State private var shown = false

    private let letters = Array("SCHAKEL")

    var body: some View {
        VStack(spacing: 6) {
            ArcShape()
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: size * CGFloat(letters.count) * 0.9, height: size * 0.55)
                .animation(.easeOut(duration: 0.9).delay(0.45), value: shown)
            HStack(spacing: size * 0.12) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .font(Theme.roundedFont(size * 0.55, weight: .black))
                        .foregroundStyle(index == 0 || index == letters.count - 1 ? Color.white : Theme.ink)
                        .frame(width: size, height: size)
                        .background(index == 0 || index == letters.count - 1 ? Theme.accent : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(index == 0 || index == letters.count - 1 ? Color.clear : Theme.line, lineWidth: 1.5))
                        .offset(y: shown ? 0 : -24)
                        .opacity(shown ? 1 : 0)
                        .rotationEffect(.degrees(shown ? 0 : -12))
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(Double(index) * 0.06), value: shown)
                }
            }
        }
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schakel")
    }
}

/// A gentle arch, from the first tile to the last.
struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.03, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.03, y: rect.maxY),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.9))
        return path
    }
}

/// A big full-width button.
struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var fill: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.roundedFont(18, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: fill.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Counts down to the next daily puzzle.
struct CountdownText: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(PuzzleCalendar.nextPuzzleDate(after: context.date).timeIntervalSince(context.date)))
            Text(String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60))
                .monospacedDigit()
        }
    }
}
