import SwiftUI

/// Continues the static launch screen (same icon, title and background, in the same
/// place) the moment SwiftUI draws its first frame: the note sends out a few soft
/// "echo" rings while the library loads, then the icon lifts and the whole splash
/// opens up into the app. It never holds the app back for long: it leaves as soon as
/// the library is ready and a single ring has played, and after 2.5 s at most.
struct EchoLaunchSplash: View {
    let isReady: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var leaving = false
    @State private var minimumShown = false

    private let iconSize: CGFloat = 112

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            // Soft colour behind the icon, so the white launch screen warms up.
            Circle()
                .fill(Color(red: 0.86, green: 0.22, blue: 0.18))
                .frame(width: iconSize * 2.4, height: iconSize * 2.4)
                .blur(radius: 60)
                .opacity(appeared ? (leaving ? 0 : 0.22) : 0)
                .scaleEffect(leaving ? 2.2 : 1)

            if !reduceMotion {
                EchoLaunchRings(size: iconSize)
                    .opacity(leaving ? 0 : 1)
            }

            Image("LaunchIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .shadow(color: Color(red: 0.8, green: 0.15, blue: 0.1).opacity(appeared ? 0.35 : 0), radius: 18, y: 8)
                .scaleEffect(leaving ? (reduceMotion ? 1 : 1.25) : 1)
                .phaseAnimator(reduceMotion || leaving ? [1.0] : [1.0, 1.045]) { icon, scale in
                    icon.scaleEffect(scale)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }

            Text(verbatim: "Echo")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(uiColor: .label))
                .offset(y: iconSize / 2 + 18 + 17)
                .opacity(leaving ? 0 : 1)
                .offset(y: leaving ? 12 : 0)
        }
        .opacity(leaving ? 0 : 1)
        .allowsHitTesting(!leaving)
        .task {
            appeared = false
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 750))
            minimumShown = true
            if isReady { leave() }
            // Never wait on a slow library for more than a moment.
            try? await Task.sleep(for: .milliseconds(1750))
            leave()
        }
        .onChange(of: isReady) { _, ready in
            if ready && minimumShown { leave() }
        }
        .accessibilityHidden(true)
    }

    private func leave() {
        guard !leaving else { return }
        withAnimation(.smooth(duration: 0.55)) {
            leaving = true
        } completion: {
            onFinished()
        }
    }
}

/// Rings that ripple out of the icon, like sound leaving a speaker.
private struct EchoLaunchRings: View {
    let size: CGFloat
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    // Rings start one after another from the icon's edge, never mid-way.
                    let local = elapsed - 0.15 - Double(index) * 0.6
                    let progress = local < 0 ? 0 : (local / 1.8).truncatingRemainder(dividingBy: 1)
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Color(red: 0.86, green: 0.22, blue: 0.18), lineWidth: 2.5 * (1 - progress) + 0.5)
                        .frame(width: size, height: size)
                        .scaleEffect(1 + progress * 1.1)
                        .opacity(local < 0 ? 0 : (1 - progress) * 0.45)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
