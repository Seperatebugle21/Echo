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
    private let window: [Float]
    private let coefficients: SIMD32<Float>

    init(sampleRate: Double = 48_000) {
        window = (0..<1024).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / 1023)) }
        var values = SIMD32<Float>(repeating: 0)
        for band in 0..<32 {
            let frequency = 70 * pow(min(14_000, sampleRate * 0.45) / 70, Double(band) / 31)
            values[band] = Float(2 * cos(2 * .pi * frequency / sampleRate))
        }
        coefficients = values
    }

    func ingest(_ samples: UnsafePointer<Float>, otherChannel: UnsafePointer<Float>? = nil, count: Int, time: Double) {
        guard count >= 32 else { return }
        // Log-spaced Goertzel bands respond to bass, vocals and treble separately.
        // SIMD evaluates all bands together, without FFT setup or render-thread allocations.
        let length = min(count, 1024), start = count - length
        var left1 = SIMD32<Float>(repeating: 0), left2 = left1
        var right1 = left1, right2 = left1
        for index in 0..<length {
            let weight = window[index * 1024 / length]
            let input = samples[start + index] * weight
            let next = coefficients * left1 - left2 + SIMD32<Float>(repeating: input)
            left2 = left1; left1 = next
            if let otherChannel {
                let other = otherChannel[start + index] * weight
                let nextRight = coefficients * right1 - right2 + SIMD32<Float>(repeating: other)
                right2 = right1; right1 = nextRight
            }
        }
        let leftPower = left1 * left1 + left2 * left2 - coefficients * left1 * left2
        let rightPower = right1 * right1 + right2 * right2 - coefficients * right1 * right2
        var levels = SIMD32<Float>(repeating: 0)
        for band in 0..<32 {
            let magnitude = 2 * sqrt(max(0, max(leftPower[band], rightPower[band]))) / Float(length)
            let decibels = 20 * log10(max(0.00001, magnitude))
            let normalized = min(1, max(0, (decibels + 58) / 52))
            // More headroom than a linear dB meter: ordinary music sits below the
            // top, leaving space for transients instead of a constantly tall wall.
            levels[band] = pow(normalized, 1.7)
        }
        guard lock.try() else { return }
        // Fast attack and softer release keep the waveform responsive without flicker.
        for band in 0..<32 {
            frame.previous[band] = Float(frame.level(at: band, time: time))
            let blend: Float = levels[band] > frame.levels[band] ? 0.95 : 0.6
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
