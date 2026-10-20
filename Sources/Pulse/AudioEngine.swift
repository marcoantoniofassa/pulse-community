import AVFoundation
import Accelerate
import Foundation

final class AudioEngine {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let writeQueue = DispatchQueue(label: "pulse.audiowrite", qos: .utility)
    private let tempDir = FileManager.default.temporaryDirectory
    private let wavSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    var recordedFileURL: URL?

    /// Quando setado (modo streaming nativo), cada buffer do tap e entregue aqui
    /// ao vivo em vez de gravar WAV de chunk. Chamado na thread de audio.
    var onLiveBuffer: ((AVAudioPCMBuffer) -> Void)?

    // FASE 4: Session-level WAV that captures ALL audio continuously
    // (used for final pass re-transcription after streaming ends)
    private var sessionFile: AVAudioFile?
    private var sessionFileURL: URL?

    /// Start recording. When `keepSessionFile` is true (streaming mode),
    /// a second WAV file captures the full session audio for final pass re-transcription.
    func startRecording(keepSessionFile: Bool = false) {
        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Create temp WAV file (chunk file for streaming, or main file for recording)
        let wavURL = tempDir.appendingPathComponent("pulse_\(Int(Date().timeIntervalSince1970)).wav")
        recordedFileURL = wavURL

        do {
            audioFile = try AVAudioFile(forWriting: wavURL, settings: wavSettings)
        } catch {
            print("[AudioEngine] Failed to create WAV: \(error)")
            return
        }

        // FASE 4: Open session-level WAV for full audio capture
        if keepSessionFile {
            let sessionURL = tempDir.appendingPathComponent("pulse_session_\(Int(Date().timeIntervalSince1970)).wav")
            sessionFileURL = sessionURL
            do {
                sessionFile = try AVAudioFile(forWriting: sessionURL, settings: wavSettings)
                print("[AudioEngine] Session file: \(sessionURL.lastPathComponent)")
            } catch {
                print("[AudioEngine] Failed to create session WAV: \(error)")
                sessionFile = nil
                sessionFileURL = nil
            }
        }

        // Pre-create converter (reuse across callbacks)
        let tgtFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        self.targetFormat = tgtFmt
        self.converter = AVAudioConverter(from: hwFormat, to: tgtFmt)

        // Reset level buffer
        AudioLevelBuffer.shared.reset()

        // Install tap — smallest possible buffer for ultra-responsive levels
        // SuperWhisper uses AudioUnit directly; AVAudioEngine with 256 is close enough
        inputNode.installTap(onBus: 0, bufferSize: 256, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // 1. RMS — compute immediately on audio thread, write to shared buffer
            self.computeAndPushRMS(buffer: buffer)

            // 2a. Engine nativo (streaming): entrega o buffer ao vivo. Sem WAV de chunk.
            if let onLive = self.onLiveBuffer {
                onLive(buffer)
                return
            }

            // 2b. Legacy: file write — offload to background queue (don't block audio thread)
            self.writeQueue.async {
                self.convertAndWrite(buffer: buffer)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            print("[AudioEngine] Recording started (\(hwFormat.sampleRate)Hz)")
        } catch {
            print("[AudioEngine] Failed to start: \(error)")
        }
    }

    /// Compute RMS in small chunks and push RAW values to shared buffer.
    /// The AudioLevelBuffer's WaveFormNormalizer handles adaptive gain.
    /// Runs on audio thread — no DispatchQueue.main.async.
    private func computeAndPushRMS(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let totalFrames = Int(buffer.frameLength)
        guard totalFrames > 0 else { return }

        // ~5ms chunks for maximum granularity (matches SuperWhisper responsiveness)
        let sampleRate = Int(engine?.inputNode.outputFormat(forBus: 0).sampleRate ?? 48000)
        let chunkSize = max(64, sampleRate / 200)  // 200Hz = 5ms
        var offset = 0

        while offset < totalFrames {
            let count = min(chunkSize, totalFrames - offset)
            var rms: Float = 0
            vDSP_rmsqv(channelData[0].advanced(by: offset), 1, &rms, vDSP_Length(count))
            // Push RAW RMS — AudioLevelBuffer's normalizer handles adaptive gain
            AudioLevelBuffer.shared.push(rms)
            offset += count
        }
    }

    /// Convert format and write to file. Runs on background write queue.
    private func convertAndWrite(buffer: AVAudioPCMBuffer) {
        guard let converter = self.converter, let targetFormat = self.targetFormat else { return }

        let ratio = targetFormat.sampleRate / converter.inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount)
        else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return }

        do {
            try audioFile?.write(from: outputBuffer)
        } catch {}

        // FASE 4: Also write to session file (full audio capture)
        if let sf = sessionFile {
            do {
                try sf.write(from: outputBuffer)
            } catch {}
        }
    }

    /// Rotate chunk: close current WAV (finalizes header), open new one.
    /// Returns the closed file URL ready for transcription.
    /// Thread-safe via writeQueue.
    func rotateChunk() -> URL? {
        var closedURL: URL?
        writeQueue.sync {
            closedURL = recordedFileURL
            audioFile = nil  // Closing AVAudioFile finalizes the WAV header

            let newURL = tempDir.appendingPathComponent("pulse_chunk_\(Int(Date().timeIntervalSince1970)).wav")
            recordedFileURL = newURL
            do {
                audioFile = try AVAudioFile(forWriting: newURL, settings: wavSettings)
            } catch {
                print("[AudioEngine] rotateChunk error: \(error)")
            }
        }
        return closedURL
    }

    func stopRecording() -> URL? {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        writeQueue.sync {
            audioFile = nil
            // Finalize session file (closing AVAudioFile writes WAV header)
            sessionFile = nil
        }
        converter = nil
        engine = nil
        print("[AudioEngine] Stopped")
        return recordedFileURL
    }

    /// Remove session WAV file without returning it (used on cancel).
    func discardSessionFile() {
        writeQueue.sync {
            sessionFile = nil
        }
        if let url = sessionFileURL {
            try? FileManager.default.removeItem(at: url)
            print("[AudioEngine] Discarded session file")
        }
        sessionFileURL = nil
    }

    /// Returns the session-level WAV URL (full audio from start to stop).
    /// Only available when `startRecording(keepSessionFile: true)` was used.
    func getSessionFileURL() -> URL? {
        // Finalize by closing the file handle so WAV header is written
        writeQueue.sync {
            sessionFile = nil
        }
        return sessionFileURL
    }
}
