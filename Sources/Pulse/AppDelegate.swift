import AppKit
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.marcofassa.pulse", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayPanel: OverlayPanel!
    private var statusIndicator: StatusIndicator!
    private var hotkeyManager: HotkeyManager!
    private var audioEngine: AudioEngine!
    private var settingsWindow: SettingsWindow?
    private var helpWindow: HelpWindow?
    private let state = StateManager.shared

    // Streaming state
    private var streamingAudio: AudioEngine?
    private var streamingText: String = ""
    // Digitacao ao vivo do engine nativo (volatil incremental com correcao).
    // Serial + fora do MainActor: os Thread.sleep do KeystrokeInjector nao travam a UI.
    private let typingQueue = DispatchQueue(label: "pulse.typing", qos: .userInitiated)
    private var liveTyped = ""
    private let streamQueue = DispatchQueue(label: "pulse.stream", qos: .userInitiated)
    private let nativeEngine = SpeechAnalyzerEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.warning("applicationDidFinishLaunching START")
        UserDefaults.standard.register(defaults: ["PulseShowHelpOnLaunch": true])

        // Write to file as backup
        let logMsg = "[\(Date())] Pulse launched\n"
        try? logMsg.write(toFile: "/tmp/pulse.log", atomically: true, encoding: .utf8)

        setupMenuBar()
        setupOverlay()
        setupHotkey()

        // Cria o vocabulario.txt ja no launch: arquivo que so nasce depois do
        // primeiro ditado e um arquivo que o usuario nunca descobre.
        _ = Vocabulario.carregar()

        // Uma janela por vez no launch. Abrir Ajustes e "Como usar" juntas empilha
        // duas janelas na cara de quem esta abrindo o app pela primeira vez.
        let vaiMostrarAjuda = UserDefaults.standard.bool(forKey: "PulseShowHelpOnLaunch")
        if vaiMostrarAjuda {
            DispatchQueue.main.async { [weak self] in self?.openHelp() }
        } else {
            openSettings()
        }

        // Permissoes DEPOIS da janela aparecer. No primeiro launch os tres pedidos
        // (microfone, fala, acessibilidade) abrem dialogo do sistema; disparados
        // antes, eles empilham por cima da tela que explica pra que servem.
        let atraso: DispatchTimeInterval = vaiMostrarAjuda ? .milliseconds(600) : .milliseconds(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + atraso) { [weak self] in
            guard let self else { return }
            // Microfone e pedido de proposito no launch: sem isso o app so aparece na
            // lista dos Ajustes na primeira gravacao, que exige o atalho, que exige
            // Monitoramento de Entrada. Deadlock.
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("[Pulse] Microphone: \(granted ? "granted" : "denied")")
            }
            PasteManager.shared.ensureAccessibility()
            Task { await self.nativeEngine.warmup() }
        }

        logger.warning("Pulse READY")
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let icon = loadStatusBarIcon() {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true  // macOS auto-adapts to light/dark
                button.image = icon
            }
            button.toolTip = "Pulse · Option 2x"
            button.action = #selector(statusBarClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    private func loadStatusBarIcon() -> NSImage? {
        // Try StatusBarIcon@2x first, then StatusBarIcon, then StatusIcon
        for name in ["StatusBarIcon@2x", "StatusBarIcon", "StatusIcon"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png") {
                return NSImage(contentsOf: url)
            }
            let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            let iconURL = execURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/\(name).png")
            if FileManager.default.fileExists(atPath: iconURL.path) {
                return NSImage(contentsOf: iconURL)
            }
        }
        return nil
    }

    private func loadAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let iconURL = execURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icns")
        if FileManager.default.fileExists(atPath: iconURL.path) {
            return NSImage(contentsOf: iconURL)
        }
        return nil
    }

    @objc private func statusBarClicked() {
        guard let event = NSApp.currentEvent else {
            logger.warning("statusBarClicked: no current event, showing menu")
            showMenu()
            return
        }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            toggleRecordingFromMenuBar()
        }
    }

    /// Menu bar click: starts recording when idle, stops whatever is running
    private func toggleRecordingFromMenuBar() {
        switch state.state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .streaming:
            stopStreaming()
        case .transcribing:
            // Transcription in progress, ignore click
            logger.info("Menu bar click ignored: transcription in progress")
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        // Recording actions (context-aware)
        switch state.state {
        case .idle:
            menu.addItem(NSMenuItem(title: "Iniciar gravação", action: #selector(menuStartRecording), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Iniciar tempo real", action: #selector(menuStartStreaming), keyEquivalent: ""))
        case .recording:
            menu.addItem(NSMenuItem(title: "Parar gravação", action: #selector(menuStopRecording), keyEquivalent: ""))
        case .streaming:
            menu.addItem(NSMenuItem(title: "Parar tempo real", action: #selector(menuStopStreaming), keyEquivalent: ""))
        case .transcribing:
            let item = NSMenuItem(title: "Transcrevendo...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Header
        let versao = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let headerItem = NSMenuItem(title: "Pulse v\(versao)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Engine info
        let engineItem = NSMenuItem(title: "Engine: Apple SpeechAnalyzer", action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)

        // Stats
        let statsItem = NSMenuItem(title: "\(state.history.count) ditados", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        menu.addItem(NSMenuItem(title: "Abrir Pulse", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Como usar", action: #selector(openHelp), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear menu so left click works again next time
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }

    // MARK: - Menu Actions

    @objc private func menuStartRecording() {
        startRecording()
    }

    @objc private func menuStopRecording() {
        stopRecording()
    }

    @objc private func menuStartStreaming() {
        startStreaming()
    }

    @objc private func menuStopStreaming() {
        stopStreaming()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.refresh()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHelp() {
        if helpWindow == nil {
            helpWindow = HelpWindow()
        }
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateMenuBarIcon(state: AppState) {
        guard let button = statusItem?.button else { return }

        switch state {
        case .idle:
            // Status bar icon (template — auto light/dark)
            if let icon = loadStatusBarIcon() {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            }
        case .recording:
            // Red dot indicator
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
                .applying(.init(paletteColors: [.systemRed]))
            if let img = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                img.isTemplate = false
                button.image = img
            }
        case .transcribing:
            // Purple spinner
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                .applying(.init(paletteColors: [NSColor(red: 0.60, green: 0.35, blue: 0.95, alpha: 1)]))
            if let img = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                img.isTemplate = false
                button.image = img
            }
        case .streaming:
            // Blue waveform icon
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                .applying(.init(paletteColors: [NSColor(red: 0.20, green: 0.55, blue: 0.90, alpha: 1)]))
            if let img = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                img.isTemplate = false
                button.image = img
            }
        }
    }

    // MARK: - Overlay

    private func setupOverlay() {
        overlayPanel = OverlayPanel()
        statusIndicator = StatusIndicator()
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()

        hotkeyManager.onToggle = { [weak self] in
            guard let self = self else { return }
            if self.state.state == .idle {
                self.startRecording()
            } else if self.state.state == .recording {
                self.stopRecording()
            }
        }

        hotkeyManager.onCancel = { [weak self] in
            guard let self = self else { return }
            if self.state.state == .recording {
                self.cancelRecording()
            } else if self.state.state == .streaming {
                self.cancelStreaming()
            }
        }

        hotkeyManager.onStreamToggle = { [weak self] in
            guard let self = self else { return }
            if self.state.state == .idle {
                self.startStreaming()
            } else if self.state.state == .streaming {
                self.stopStreaming()
            }
        }

        hotkeyManager.start()
    }

    // MARK: - Recording Flow

    private func startRecording() {
        guard state.state == .idle else { return }

        // Save frontmost app BEFORE we do anything
        state.frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        state.state = .recording
        state.recordingStartTime = Date()
        state.resetLevels()

        // Update UI
        updateMenuBarIcon(state: .recording)

        // Configure waveform
        overlayPanel.waveformView.mode = .recording
        // Primeiro uso numa maquina nova: o modelo pt-BR ainda esta baixando. Dizer
        // isso e melhor do que gravar em silencio e o usuario descobrir depois.
        overlayPanel.waveformView.statusText = nativeEngine.preferredFormat == nil ? "Preparando o motor de voz..." : ""
        overlayPanel.waveformView.resetSmooth()

        // Show overlay + status
        overlayPanel.fadeIn()
        statusIndicator.show(mode: .recording)

        // Start audio
        audioEngine = AudioEngine()

        SoundManager.shared.play("Start1")
        Task { [weak self] in
            guard let self = self else { return }
            await self.nativeEngine.startStreaming { _ in }
            await MainActor.run {
                self.audioEngine.onLiveBuffer = { [weak self] buf in self?.nativeEngine.feed(buf) }
                self.audioEngine.startRecording()
            }
        }
        print("[REC] Recording (Apple SpeechAnalyzer)...")
    }

    private func cancelRecording() {
        guard state.state == .recording else { return }

        audioEngine.onLiveBuffer = nil
        Task { [weak self] in _ = await self?.nativeEngine.stopStreaming() }

        // Stop audio and discard
        let wavURL = audioEngine.stopRecording()
        if let path = wavURL?.path {
            try? FileManager.default.removeItem(atPath: path)
        }

        // Cancel UI
        overlayPanel.waveformView.statusText = "Cancelado"
        overlayPanel.waveformView.mode = .idle
        SoundManager.shared.play("noResult1")
        print("[X] Recording cancelled")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.statusIndicator.hide()
            self?.overlayPanel.fadeOut()
            self?.finishRecording()
        }
    }

    private func stopRecording() {
        guard state.state == .recording else { return }
        state.state = .transcribing

        updateMenuBarIcon(state: .transcribing)
        overlayPanel.waveformView.mode = .transcribing
        overlayPanel.waveformView.controlText = ""
        statusIndicator.show(mode: .transcribing)

        audioEngine.onLiveBuffer = nil
        _ = audioEngine.stopRecording()
        Task { [weak self] in
            guard let self = self else { return }
            let text = await self.nativeEngine.stopStreaming()
            await MainActor.run {
                self.handleTranscriptionResult(text: text.isEmpty ? nil : text)
            }
        }
    }

    private func handleTranscriptionResult(text: String?) {
        let frontApp = state.frontmostApp

        if let text = text, !text.isEmpty {
            // Success — save to history
            state.transcribedText = text
            state.addEntry(text: text, app: frontApp)

            let preview = text.count > 35 ? String(text.prefix(35)) + "\u{2026}" : text
            overlayPanel.waveformView.statusText = preview
            overlayPanel.waveformView.mode = .idle

            SoundManager.shared.play("Stop1")
            print("Ditado concluído")

            // Brief show of result, then fade out and paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusIndicator.hide()
                self?.overlayPanel.fadeOut {
                    PasteManager.shared.paste(text: text, toApp: frontApp)
                }
                self?.finishRecording()
                // Refresh settings window if open
                self?.settingsWindow?.refresh()
            }
        } else {
            // No result
            overlayPanel.waveformView.statusText = "Sem áudio"
            overlayPanel.waveformView.mode = .idle

            SoundManager.shared.play("noResult1")
            print("[--] No speech detected")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.statusIndicator.hide()
                self?.overlayPanel.fadeOut()
                self?.finishRecording()
            }
        }
    }

    private func finishRecording() {
        state.state = .idle
        updateMenuBarIcon(state: .idle)
    }

    // MARK: - Streaming Mode

    private func startStreaming() {
        guard state.state == .idle else { return }

        state.frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        state.state = .streaming
        state.recordingStartTime = Date()
        state.resetLevels()
        streamingText = ""

        updateMenuBarIcon(state: .recording)
        overlayPanel.waveformView.mode = .streaming
        overlayPanel.waveformView.statusText = nativeEngine.preferredFormat == nil ? "Preparando o motor de voz..." : "Tempo real..."
        overlayPanel.waveformView.resetSmooth()
        overlayPanel.fadeIn()
        statusIndicator.show(mode: .streaming)

        streamingAudio = AudioEngine()

        SoundManager.shared.play("Start1")
        typingQueue.async { [weak self] in self?.liveTyped = "" }
        Task { [weak self] in
            guard let self = self else { return }
            await self.nativeEngine.startStreaming { [weak self] result in
                guard let self = self else { return }
                // Acumula os trechos ja finalizados. O cutover tinha deixado
                // streamingText sem nenhuma escrita, entao o fallback do stopStreaming
                // lia string sempre vazia: quando o resultado final vinha vazio, o
                // texto nao entrava no historico nem no clipboard, calado.
                if result.isFinal { self.streamingText += result.text }
                self.typingQueue.async { self.applyLive(text: result.text, isFinal: result.isFinal) }
            }
            await MainActor.run {
                self.streamingAudio?.onLiveBuffer = { [weak self] buf in self?.nativeEngine.feed(buf) }
                self.streamingAudio?.startRecording(keepSessionFile: false)
            }
        }
        print("[STREAM] Started (Apple SpeechAnalyzer)")
    }

    private func stopStreaming() {
        guard state.state == .streaming else { return }

        state.state = .transcribing
        let frontApp = state.frontmostApp
        streamingAudio?.onLiveBuffer = nil
        _ = streamingAudio?.stopRecording()
        streamingAudio = nil
        overlayPanel.waveformView.mode = .transcribing
        statusIndicator.show(mode: .transcribing)
        Task { [weak self] in
            guard let self = self else { return }
            let finalText = await self.nativeEngine.stopStreaming()
            await MainActor.run {
                self.handleStreamingResult(fullText: finalText.isEmpty ? self.streamingText : finalText, toApp: frontApp)
            }
        }
    }

    private func cancelStreaming() {
        guard state.state == .streaming else { return }

        streamingAudio?.onLiveBuffer = nil
        Task { [weak self] in _ = await self?.nativeEngine.stopStreaming() }
        _ = streamingAudio?.stopRecording()
        streamingAudio = nil
        streamingText = ""

        overlayPanel.waveformView.statusText = "Cancelado"
        overlayPanel.waveformView.mode = .idle
        SoundManager.shared.play("noResult1")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.statusIndicator.hide()
            self?.overlayPanel.fadeOut()
            self?.finishStreaming()
        }
    }

    private func handleStreamingResult(fullText: String, toApp: String) {
        SoundManager.shared.play("Stop1")
        overlayPanel.waveformView.mode = .idle

        if !fullText.isEmpty {
            state.transcribedText = fullText
            state.addEntry(text: fullText, app: toApp)
            overlayPanel.waveformView.statusText = fullText.count > 35 ? String(fullText.prefix(35)) + "\u{2026}" : fullText
            print("Ditado concluído")

            // Copy best version to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fullText, forType: .string)
            print("[STREAM] Copied to clipboard (\(fullText.count) chars)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.statusIndicator.hide()
                self?.overlayPanel.fadeOut {
                }
                self?.finishStreaming()
                self?.settingsWindow?.refresh()
            }
        } else {
            overlayPanel.waveformView.statusText = "Sem áudio"
            SoundManager.shared.play("noResult1")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.statusIndicator.hide()
                self?.overlayPanel.fadeOut()
                self?.finishStreaming()
            }
        }
    }

    private func finishStreaming() {
        state.state = .idle
        streamingText = ""
        updateMenuBarIcon(state: .idle)
    }

    /// Digita ao vivo o texto do segmento atual, corrigindo o que o reconhecedor revisa.
    /// Roda na typingQueue (serial). `liveTyped` rastreia o que ja esta na tela do segmento.
    /// Quando isFinal, fecha o segmento com um espaco e zera o tracking pro proximo.
    private func applyLive(text: String, isFinal: Bool) {
        let oldArr = Array(liveTyped), newArr = Array(text)
        var p = 0
        while p < oldArr.count && p < newArr.count && oldArr[p] == newArr[p] { p += 1 }
        let toDelete = String(oldArr[p...])
        let toAdd = String(newArr[p...])
        if !toDelete.isEmpty {
            KeystrokeInjector.shared.correct(oldSuffix: toDelete, newSuffix: toAdd)
        } else if !toAdd.isEmpty {
            KeystrokeInjector.shared.type(text: toAdd)
        }
        if isFinal {
            KeystrokeInjector.shared.type(text: " ")
            liveTyped = ""
        } else {
            liveTyped = text
        }
    }

    // MARK: - Actions

    @objc private func quit() {
        hotkeyManager.stop()
        NSApplication.shared.terminate(nil)
    }
}
