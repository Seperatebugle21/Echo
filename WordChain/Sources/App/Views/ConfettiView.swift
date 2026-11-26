import SwiftUI

/// A short burst of confetti each time `trigger` changes.
struct ConfettiView: View {
    var trigger: Int

    @State private var start: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let duration: TimeInterval = 2.8
    private static let pieces = 140

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { context in
            Canvas { canvas, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                guard t < Self.duration else { return }
                let colors: [Color] = [Theme.accent, Theme.gold, Theme.correct, Color(red: 0.42, green: 0.55, blue: 0.98), Color(red: 0.86, green: 0.4, blue: 0.85)]
                for i in 0..<Self.pieces {
                    var rng = SplitMix64(seed: UInt64(i) &* 2_654_435_761 &+ UInt64(trigger))
                    let r = { () -> Double in Double(rng.next() % 10_000) / 10_000 }
                    let originX = size.width * (0.2 + 0.6 * r())
                    let vx = (r() - 0.5) * 520
                    let vy = -(r() * 700 + 350)
                    let gravity = 900.0
                    let x = originX + vx * t
                    let y = size.height * 0.35 + vy * t + 0.5 * gravity * t * t
                    let spin = (r() - 0.5) * 14 * t
                    let w = 6 + r() * 6
                    let h = 9 + r() * 8
                    let fade = max(0, 1 - max(0, t - Self.duration + 0.8) / 0.8)
                    var piece = canvas
                    piece.opacity = fade
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(spin))
                    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h * abs(cos(t * 6 + Double(i))))
                    piece.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[i % colors.count]))
                }
            }
        }
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            let begin = Date()
            start = begin
            after(Self.duration) {
                if start == begin { start = nil }
            }
        }
    }
}
