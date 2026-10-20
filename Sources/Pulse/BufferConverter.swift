import AVFoundation

/// Converte AVAudioPCMBuffer para o formato esperado pelo engine de transcricao.
/// Reusa um unico AVAudioConverter (a tap callback roda em thread real-time).
final class BufferConverter {
    enum Error: Swift.Error { case failedToCreateConverter, failedToCreateConversionBuffer, conversionFailed(NSError?) }
    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw Error.failedToCreateConverter }
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let cap = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: cap) else {
            throw Error.failedToCreateConversionBuffer
        }
        var nsError: NSError?
        var processed = false
        let status = converter.convert(to: out, error: &nsError) { _, statusPtr in
            defer { processed = true }
            statusPtr.pointee = processed ? .noDataNow : .haveData
            return processed ? nil : buffer
        }
        guard status != .error else { throw Error.conversionFailed(nsError) }
        return out
    }
}
