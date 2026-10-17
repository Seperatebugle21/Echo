import Foundation

/// A small, non-observable mailbox between the audio render callback and Canvas.
/// Fixed-size values avoid per-buffer allocations and 120 Hz model notifications.
final class AudioVisualization: @unchecked Sendable {
    struct Frame: Sendable {
        var previous = SIMD32<Float>(repeating: 0)
        var levels = SIMD32<Float>(repeating: 0)
        var timestamp = 0.0

        func level(at index: Int, time: Double) -> Double {
            let elapsed = max(0, time - timestamp)
            let progress = min(1, elapsed / 0.055)
            let blend = progress * progress * (3 - 2 * progress)
            let value = Double(previous[index]) + Double(levels[index] - previous[index]) * blend
            // A stalled engine must settle to silence instead of holding old peaks.
            return value * max(0, 1 - max(0, elapsed - 0.2) / 0.18)
        }
    }
    private let lock = NSLock()
    private var frame = Frame()

    func ingest(_ samples: UnsafePointer<Float>, otherChannel: UnsafePointer<Float>? = nil, count: Int, time: Double) {
        guard count >= 32 else { return }
        var levels = SIMD32<Float>(repeating: 0)
        for band in 0..<32 {
            let start = band * count / 32, end = (band + 1) * count / 32
            var energy: Float = 0
            for index in start..<end {
                let sample = samples[index]
                let other = otherChannel?[index] ?? sample
                energy += max(sample * sample, other * other)
            }
            let rms = sqrt(energy / Float(end - start))
            let decibels = 20 * log10(max(0.0001, rms))
            levels[band] = min(1, max(0, (decibels + 60) / 60))
        }
        guard lock.try() else { return }
        // Fast attack and softer release keep the waveform responsive without flicker.
        for band in 0..<32 {
            frame.previous[band] = Float(frame.level(at: band, time: time))
            let blend: Float = levels[band] > frame.levels[band] ? 0.85 : 0.45
            frame.levels[band] += (levels[band] - frame.levels[band]) * blend
        }
        frame.timestamp = time
        lock.unlock()
    }

    func snapshot() -> Frame {
        lock.lock(); defer { lock.unlock() }
        return frame
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        frame = Frame()
    }
}
