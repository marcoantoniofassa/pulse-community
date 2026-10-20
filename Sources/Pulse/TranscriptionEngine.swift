import AVFoundation

/// Resultado incremental emitido por um engine de streaming.
struct TranscriptResult {
    let text: String    // texto deste segmento (volatil ou final)
    let isFinal: Bool   // true = estavel; false = volatil (ainda muda)
}

/// Abstracao do motor de transcricao nativo Apple SpeechAnalyzer.
protocol TranscriptionEngine: AnyObject {
    /// Prepara o engine (carrega modelo / garante asset on-device). Idempotente.
    func warmup() async

    /// Inicia uma sessao de streaming ao vivo. Os AVAudioPCMBuffer empurrados
    /// via `feed(_:)` sao transcritos incrementalmente. Os resultados chegam
    /// pelo `onResult`, ja no MainActor (pronto pra tocar a UI / digitar).
    func startStreaming(onResult: @escaping @MainActor (TranscriptResult) -> Void) async

    /// Empurra um buffer de audio ao vivo. Seguro chamar da thread de audio.
    func feed(_ buffer: AVAudioPCMBuffer)

    /// Finaliza a sessao, drena os ultimos resultados e retorna o texto final completo.
    func stopStreaming() async -> String

    /// Formato de audio que o engine espera. Nil ate o warmup terminar.
    var preferredFormat: AVAudioFormat? { get }
}
