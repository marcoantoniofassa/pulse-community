import AppKit
import QuartzCore

/// Waveform — Cyberpunk deep purple + glass aesthetic.
/// Bars are STATIONARY (SuperWhisper style), only height changes.
/// Spring physics for fluid motion. Glass overlay background.
final class WaveformView: NSView {
    private let numBars = 60  // Compact bar count for sleeker overlay
    private var barLayers: [CALayer] = []
    private var renderTimer: Timer?
    private var phase: Float = 0

    // Per-bar random seeds
    private var barSeeds: [Float] = []
    private var lastHeights: [CGFloat]

    // Geometry
    private var waveCY: CGFloat = 0
    private var maxH: CGFloat = 0

    // UI sublayers
    private let sepLayer = CALayer()
    private let statusLabel = CATextLayer()
    private let controlLabel = CATextLayer()
    private let logoLabel = CATextLayer()
    private let modelLabel = CATextLayer()

    // -- Cyberpunk Deep Purple Palette --
    // Background: handled by NSVisualEffectView (glass) in OverlayPanel
    // Bars idle: deep purple dim
    private let barDimColor = CGColor(red: 0.25, green: 0.15, blue: 0.40, alpha: 0.4)
    // Active: electric purple → neon magenta
    // Transcribing: electric purple (matches recording theme)
    private let transcribingColor = NSColor(red: 0.70, green: 0.45, blue: 1.0, alpha: 1)
    // Text
    private let textDimColor = NSColor(red: 0.55, green: 0.45, blue: 0.70, alpha: 1)  // Muted purple
    private let textBrightColor = NSColor(red: 0.85, green: 0.75, blue: 1.0, alpha: 1)  // Light lavender
    // Separator
    private let sepColor = CGColor(red: 0.40, green: 0.25, blue: 0.65, alpha: 0.25)

    var mode: AppState = .idle {
        didSet {
            if mode == .recording || mode == .transcribing || mode == .streaming {
                startTimer()
            }
            if oldValue == .transcribing && mode != .transcribing {
                stopStatusPulse()
            }
            if mode == .transcribing {
                statusLabel.string = "Transcrevendo"
                statusLabel.foregroundColor = transcribingColor.cgColor
                startStatusPulse()
            }
            updateControlText()
        }
    }

    var statusText: String = "" {
        didSet { updateStatusLabel() }
    }

    var controlText: String = "\u{2325}\u{2325} para parar" {
        didSet { updateControlLabel() }
    }

    override init(frame: NSRect) {
        lastHeights = Array(repeating: 3, count: 60)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 16
        // Transparent background — glass effect comes from OverlayPanel's NSVisualEffectView
        layer?.backgroundColor = CGColor.clear

        srand48(42)
        barSeeds = (0..<60).map { _ in Float(drand48()) }

        setupLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        guard let rootLayer = self.layer else { return }
        let W = bounds.width
        let H = bounds.height

        // Separator at bottom section
        let sepY: CGFloat = 30
        sepLayer.frame = CGRect(x: 16, y: sepY, width: W - 32, height: 0.5)
        sepLayer.backgroundColor = sepColor
        rootLayer.addSublayer(sepLayer)

        // Geometry
        waveCY = sepY + (H - sepY) / 2
        maxH = (H - sepY - 24) / 2

        // Bar layers — slightly thicker for cyberpunk feel
        let padX: CGFloat = 18
        let barArea = W - 2 * padX
        let gap = barArea / CGFloat(numBars)
        let bw = max(2.5, gap * 0.5)

        for i in 0..<numBars {
            let bar = CALayer()
            let x = padX + CGFloat(i) * gap + (gap - bw) / 2
            bar.frame = CGRect(x: x, y: waveCY - 1.5, width: bw, height: 3)
            bar.backgroundColor = barDimColor
            bar.cornerRadius = bw / 2

            bar.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "backgroundColor": NSNull(),
            ]

            rootLayer.addSublayer(bar)
            barLayers.append(bar)
        }

        // Logo text "P" (Pulse) — minimal cyberpunk
        logoLabel.frame = CGRect(x: 16, y: 6, width: 24, height: 20)
        logoLabel.string = "P"
        logoLabel.fontSize = 12
        logoLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        logoLabel.foregroundColor = NSColor(red: 0.55, green: 0.35, blue: 0.85, alpha: 0.6).cgColor
        logoLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        logoLabel.actions = ["string": NSNull()]
        rootLayer.addSublayer(logoLabel)

        // Engine label (italic)
        modelLabel.frame = CGRect(x: 38, y: 6, width: 140, height: 20)
        modelLabel.string = "Apple SpeechAnalyzer"
        modelLabel.fontSize = 10
        modelLabel.font = NSFont(name: "HelveticaNeue-LightItalic", size: 10)
            ?? NSFont.systemFont(ofSize: 10, weight: .ultraLight)
        modelLabel.foregroundColor = NSColor(red: 0.50, green: 0.38, blue: 0.70, alpha: 0.55).cgColor
        modelLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        modelLabel.actions = ["string": NSNull()]
        rootLayer.addSublayer(modelLabel)

        // Status label (center)
        statusLabel.frame = CGRect(x: 80, y: 6, width: W - 160, height: 20)
        statusLabel.alignmentMode = .center
        statusLabel.fontSize = 12
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.foregroundColor = textDimColor.cgColor
        statusLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        statusLabel.actions = ["string": NSNull(), "foregroundColor": NSNull()]
        rootLayer.addSublayer(statusLabel)

        // Control label (right)
        controlLabel.frame = CGRect(x: W - 170, y: 6, width: 154, height: 20)
        controlLabel.alignmentMode = .right
        controlLabel.fontSize = 11
        controlLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        controlLabel.foregroundColor = NSColor(red: 0.50, green: 0.40, blue: 0.65, alpha: 0.7).cgColor
        controlLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        controlLabel.actions = ["string": NSNull()]
        rootLayer.addSublayer(controlLabel)
    }

    // MARK: - Timer

    func startTimer() {
        // Use 15fps for transcribing (bars just breathe), 30fps for recording/streaming
        let targetFps: Double = (mode == .transcribing) ? 15.0 : 30.0
        let targetInterval = 1.0 / targetFps
        if let existing = renderTimer, existing.isValid {
            // Already running: only restart if fps changed
            if abs(existing.timeInterval - targetInterval) < 0.001 { return }
            existing.invalidate()
            renderTimer = nil
        }
        renderTimer = Timer(timeInterval: targetInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(renderTimer!, forMode: .common)
    }

    func stopTimer() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    private func tick() {
        phase += 0.08

        if mode == .recording || mode == .streaming {
            tickRecording()
        } else if mode == .transcribing {
            tickTranscribing()
        } else {
            tickIdle()
        }
    }

    private func tickRecording() {
        let level = AudioLevelBuffer.shared.currentLevel()
        let recent = AudioLevelBuffer.shared.recentLevels()

        for i in 0..<numBars {
            let bar = barLayers[i]
            let t = Float(i) / Float(numBars - 1)

            let center: Float = 0.5
            let dist = abs(t - center) / 0.5
            let envelope = 1.0 - dist * dist * 0.6

            let delayIndex = min(Int(dist * Float(recent.count - 1)), recent.count - 1)
            let delayedLevel = recent[delayIndex]
            let blendedLevel = level * 0.6 + delayedLevel * 0.4
            let variation = 0.7 + barSeeds[i] * 0.6
            let val = blendedLevel * envelope * variation
            let h = max(3, CGFloat(val) * maxH)

            applySpringHeight(bar: bar, index: i, h: h)

            // Cyberpunk color: deep purple (dim) → electric purple → neon magenta (loud)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if val < 0.01 {
                bar.backgroundColor = barDimColor
            } else {
                let lv = min(val * 1.3, 1.0)
                // Purple → Magenta gradient based on amplitude
                let r = CGFloat(0.35 + lv * 0.55)   // 0.35 → 0.90 (deep purple → neon pink)
                let g = CGFloat(0.15 + lv * 0.15)   // 0.15 → 0.30
                let b = CGFloat(0.55 + lv * 0.35)   // 0.55 → 0.90 (keeps purple)
                bar.backgroundColor = CGColor(red: r, green: g, blue: b, alpha: 1)
            }
            CATransaction.commit()
        }
    }

    private func tickTranscribing() {
        for i in 0..<numBars {
            let bar = barLayers[i]
            let t = Float(i) / Float(numBars)
            var env: Float = 0.15 + 0.35 * sin(t * .pi)
            env += 0.12 * sin(t * 2.5 * .pi + phase * 2.0)
            env += 0.08 * sin(t * 1.3 * .pi - phase * 1.4)
            let val = max(0.06, env)
            let h = max(3, CGFloat(val) * maxH)

            applySpringHeight(bar: bar, index: i, h: h)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let lv = min(val * 1.5, 1.0)
            // Electric purple breathing — matches recording theme
            bar.backgroundColor = CGColor(
                red: CGFloat(0.40 + lv * 0.35),    // 0.40 → 0.75
                green: CGFloat(0.18 + lv * 0.22),   // 0.18 → 0.40
                blue: CGFloat(0.60 + lv * 0.35),    // 0.60 → 0.95
                alpha: 1
            )
            CATransaction.commit()
        }
        // Status text ("Transcrevendo") set once by mode setter with opacity pulse animation
        // No per-tick string update needed
    }

    private func tickIdle() {
        for i in 0..<numBars {
            let bar = barLayers[i]
            let newBounds = CGRect(x: 0, y: 0, width: bar.bounds.width, height: 3)
            bar.bounds = newBounds
            bar.position = CGPoint(x: bar.position.x, y: waveCY)
            bar.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bar.backgroundColor = barDimColor
            CATransaction.commit()
        }
    }

    private func applySpringHeight(bar: CALayer, index i: Int, h: CGFloat) {
        let oldH = lastHeights[i]
        if abs(h - oldH) > 0.5 {
            let newBounds = CGRect(x: 0, y: 0, width: bar.bounds.width, height: h * 2)

            let spring = CASpringAnimation(keyPath: "bounds")
            spring.fromValue = bar.presentation()?.bounds ?? bar.bounds
            spring.toValue = newBounds
            spring.mass = 1.0
            spring.stiffness = 300
            spring.damping = 22
            spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            spring.fillMode = .forwards
            spring.isRemovedOnCompletion = false

            bar.bounds = newBounds
            bar.position = CGPoint(x: bar.position.x, y: waveCY)
            bar.add(spring, forKey: "springBounds")

            lastHeights[i] = h
        }
    }

    // MARK: - Labels

    private func updateStatusLabel() {
        statusLabel.string = statusText
        if mode == .transcribing {
            statusLabel.foregroundColor = transcribingColor.cgColor
        } else if statusText.contains("Erro") || statusText.contains("Sem") {
            statusLabel.foregroundColor = CGColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
        } else {
            statusLabel.foregroundColor = textBrightColor.cgColor
        }
    }

    private func updateControlLabel() {
        controlLabel.string = controlText
    }

    private func updateControlText() {
        if mode == .recording {
            controlLabel.string = "esc cancela  ·  \u{2325}\u{2325} para"
        } else if mode == .streaming {
            controlLabel.string = "esc cancela  ·  \u{2325}Space para"
        } else {
            controlLabel.string = ""
        }
    }

    func resetSmooth() {
        phase = 0
        lastHeights = Array(repeating: 3, count: numBars)
        for bar in barLayers { bar.removeAllAnimations() }
        AudioLevelBuffer.shared.reset()
    }

    // MARK: - Status Pulse (lightweight opacity animation, no string updates)

    private func startStatusPulse() {
        statusLabel.removeAnimation(forKey: "opacityPulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        statusLabel.add(pulse, forKey: "opacityPulse")
    }

    private func stopStatusPulse() {
        statusLabel.removeAnimation(forKey: "opacityPulse")
        statusLabel.opacity = 1.0
    }
}
