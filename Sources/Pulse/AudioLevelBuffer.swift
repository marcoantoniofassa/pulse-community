import Foundation
import os

/// Audio level buffer — SuperWhisper style: provides CURRENT level, not scrolling history.
///
/// The WaveFormNormalizer computes a single normalized level from raw RMS.
/// WaveformView distributes this level across bars spatially (standing wave, no scrolling).
final class AudioLevelBuffer {
    static let shared = AudioLevelBuffer()

    private let lock = OSAllocatedUnfairLock()

    // -- Current level (what WaveformView reads) --
    private var _currentLevel: Float = 0
    private var _recentLevels: [Float] = Array(repeating: 0, count: 8) // Short history for wave propagation
    private var _writeIndex: Int = 0

    // -- Adaptive gain (AGC) --
    private var adaptiveGain: Float = 8.0
    private var recentPeaks: [Float] = []
    private let peakHistorySize: Int = 50
    private let minGain: Float = 3.0
    private let maxGain: Float = 30.0
    private let noiseFloor: Float = 0.003

    private init() {}

    /// Called from audio thread — pushes one raw RMS value
    func push(_ rawRMS: Float) {
        lock.withLock {
            let val = applyGain(rawRMS)
            _currentLevel = val
            _recentLevels[_writeIndex % _recentLevels.count] = val
            _writeIndex += 1
        }
    }

    /// Called from audio thread — pushes batch of raw values
    func pushBatch(_ rawLevels: [Float]) {
        lock.withLock {
            for raw in rawLevels {
                let val = applyGain(raw)
                _currentLevel = val
                _recentLevels[_writeIndex % _recentLevels.count] = val
                _writeIndex += 1
            }
        }
    }

    /// Adaptive gain — keeps bars visually responsive regardless of mic volume
    private func applyGain(_ rawRMS: Float) -> Float {
        guard rawRMS > noiseFloor else { return 0 }

        recentPeaks.append(rawRMS)
        if recentPeaks.count > peakHistorySize {
            recentPeaks.removeFirst()
        }

        if recentPeaks.count >= 5 {
            let sorted = recentPeaks.sorted()
            let refPeak = sorted[Int(Float(sorted.count) * 0.85)]
            if refPeak > noiseFloor {
                let target = 0.65 / refPeak
                adaptiveGain += (target - adaptiveGain) * 0.03
                adaptiveGain = max(minGain, min(maxGain, adaptiveGain))
            }
        }

        return min(rawRMS * adaptiveGain, 1.0)
    }

    /// Get current audio level (0..1) — called from main thread
    func currentLevel() -> Float {
        lock.withLock { _currentLevel }
    }

    /// Get recent levels for wave propagation delay effect (newest first)
    func recentLevels() -> [Float] {
        lock.withLock {
            var result = [Float](repeating: 0, count: _recentLevels.count)
            for i in 0..<_recentLevels.count {
                // Newest first
                let idx = (_writeIndex - 1 - i + _recentLevels.count * 100) % _recentLevels.count
                result[i] = _recentLevels[idx]
            }
            return result
        }
    }

    func reset() {
        lock.withLock {
            _currentLevel = 0
            _recentLevels = Array(repeating: 0, count: 8)
            _writeIndex = 0
            adaptiveGain = 8.0
            recentPeaks.removeAll()
        }
    }
}
