import Speech
import AVFoundation
import Foundation

/// Engine de transcricao nativo (Apple SpeechAnalyzer/SpeechTranscriber, macOS 26+).
/// Streaming incremental real, on-device, pt-BR e sem dependencias externas.
///
/// LICAO DO SPIKE (nao remover): o drain de `results` roda FORA do MainActor
/// (Task.detached); o hop pro MainActor acontece so no `onResult` (digitar).
/// Sem isso, sob Approachable Concurrency, feed+drain serializam no main actor
/// e a latencia vai a ~11s com resultados em blocos (Apple Forums 795924).
///
/// LICAO DO SMOKE (nao remover): NAO reutilizar SpeechTranscriber/SpeechAnalyzer
/// entre sessoes. O framework trapa em setWorkers(reusingFrom:) na 2a sessao
/// (EXC_BREAKPOINT). Cria-se um par novo a cada startStreaming; o warmup so
/// garante o asset on-device e descobre o formato de audio.
final class SpeechAnalyzerEngine: TranscriptionEngine {
    private let locale = Locale(identifier: "pt-BR")
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private let converter = BufferConverter()
    private(set) var preferredFormat: AVAudioFormat?
    private var ready = false

    // Instrumentacao de latencia (debug): mede setup, 1o feed, dropados, 1o result.
    private var sessionT0 = Date()
    private var firstResultLogged = false
    private var firstFeedLogged = false
    private var droppedBeforeReady = 0

    // finalizedText e escrito pelo drain (background) e lido por stopStreaming.
    private let textLock = NSLock()
    private var _finalizedText = ""
    private func appendFinalized(_ s: String) { textLock.lock(); _finalizedText += s; textLock.unlock() }
    private func snapshotFinalized() -> String { textLock.lock(); defer { textLock.unlock() }; return _finalizedText }
    private func resetFinalized() { textLock.lock(); _finalizedText = ""; textLock.unlock() }

    private static let logFile = "/tmp/pulse-transcriber.log"
    private static func log(_ m: String) {
        let line = "[\(Date())] [SpeechAnalyzerEngine] \(m)\n"
        print(line, terminator: "")
        if let d = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile), let fh = FileHandle(forWritingAtPath: logFile) {
                fh.seekToEndOfFile(); fh.write(d); fh.closeFile()
            } else { try? d.write(to: URL(fileURLWithPath: logFile)) }
        }
    }

    /// Cria um SpeechTranscriber pt-BR novo (nunca reusar entre sessoes).
    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    func warmup() async {
        // Autorizacao de speech recognition (dispara o dialogo do sistema na 1a vez).
        // Necessaria mesmo on-device; e por-bundle-id, entao o app pede a sua propria.
        let auth = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        Self.log("speech auth = \(auth.rawValue) (3 = authorized)")

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.map({ $0.identifier(.bcp47) }).contains("pt-BR") else {
            Self.log("pt-BR nao suportado neste build"); return
        }

        // Transcriber temporario so pra garantir o asset e descobrir o formato.
        // NAO e guardado: cada sessao cria o seu (ver LICAO DO SMOKE).
        let t = makeTranscriber()
        do {
            if let dl = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                Self.log("baixando modelo pt-BR...")
                try await dl.downloadAndInstall()
            }
        } catch { Self.log("erro garantindo modelo: \(error)") }
        self.preferredFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
        self.ready = (preferredFormat != nil)
        Self.log("warmup ok, ready=\(ready), format=\(String(describing: preferredFormat))")
    }

    func startStreaming(onResult: @escaping @MainActor (TranscriptResult) -> Void) async {
        // Rearme: no primeiro launch de uma maquina nova o modelo pt-BR ainda esta
        // baixando (minutos) e o warmup inicial termina com ready=false. Sem tentar
        // de novo aqui, o app fica mudo pra sempre ate o usuario reabrir, que e
        // exatamente o que acontece na maquina de todo mundo do beta.
        if !ready { await warmup() }
        guard ready, preferredFormat != nil else { Self.log("startStreaming: warmup nao concluiu"); return }
        resetFinalized()
        sessionT0 = Date(); firstResultLogged = false; firstFeedLogged = false; droppedBeforeReady = 0

        // Par NOVO a cada sessao (ver LICAO DO SMOKE: nao reutilizar).
        let t = makeTranscriber()
        self.transcriber = t
        let (seq, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = builder
        let a = SpeechAnalyzer(modules: [t])
        self.analyzer = a

        // Vocabulario contextual: faz o motor ESPERAR os termos em ingles que o
        // usuario fala no meio do portugues (deploy, pull request, endpoint).
        // Nao e um segundo idioma: o locale continua pt-BR, o que muda e a
        // probabilidade de cada termo. Sem isso o motor devolve aproximacao
        // fonetica pra tudo que nao e palavra portuguesa.
        let termos = Vocabulario.carregar()
        if !termos.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings = [.general: termos]
            do {
                try await a.setContext(ctx)
                Self.log("vocabulario contextual: \(termos.count) termos")
            } catch {
                // Falhar aqui degrada a qualidade, nao quebra o ditado: segue sem.
                Self.log("setContext falhou (segue sem vocabulario): \(error)")
            }
        }

        // CRITICO (licao do spike): drain FORA do MainActor; hop pro MainActor so no onResult.
        resultsTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                for try await result in t.results {
                    if !self.firstResultLogged {
                        self.firstResultLogged = true
                        Self.log(String(format: "1o result em %.2fs apos start (dropados antes do ready: %d)", Date().timeIntervalSince(self.sessionT0), self.droppedBeforeReady))
                    }
                    let chunk = String(result.text.characters)
                    if result.isFinal { self.appendFinalized(chunk) }
                    let r = TranscriptResult(text: chunk, isFinal: result.isFinal)
                    await MainActor.run { onResult(r) }
                }
            } catch { Self.log("erro no stream de results: \(error)") }
        }

        do {
            try await a.start(inputSequence: seq)
            Self.log(String(format: "streaming iniciado (setup %.0fms)", Date().timeIntervalSince(sessionT0) * 1000))
        } catch { Self.log("erro start: \(error)") }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let fmt = preferredFormat, let builder = inputBuilder else { droppedBeforeReady += 1; return }
        if !firstFeedLogged {
            firstFeedLogged = true
            Self.log(String(format: "1o feed aceito em %.2fs apos start", Date().timeIntervalSince(sessionT0)))
        }
        if let conv = try? converter.convertBuffer(buffer, to: fmt) {
            builder.yield(AnalyzerInput(buffer: conv))
        }
    }

    func stopStreaming() async -> String {
        inputBuilder?.finish()
        do { try await analyzer?.finalizeAndFinishThroughEndOfInput() }
        catch { Self.log("erro finalize: \(error)") }
        resultsTask?.cancel()
        let final = snapshotFinalized().trimmingCharacters(in: .whitespacesAndNewlines)
        Self.log("streaming finalizado")
        // Libera o par desta sessao (evita "max recognizers reached" e reuso indevido).
        analyzer = nil
        transcriber = nil
        inputBuilder = nil
        resultsTask = nil
        return final
    }
}
