import AppKit

final class StatusIndicator: NSPanel {
    private let dotView: NSView
    private let label: NSTextField
    private var pulseTimer: Timer?
    private let pillWidth: CGFloat = 150
    private let pillHeight: CGFloat = 30

    init() {
        dotView = NSView(frame: NSRect(x: 12, y: 10, width: 10, height: 10))
        label = NSTextField(labelWithString: "Gravando")

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 150, height: 30),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        self.isFloatingPanel = true
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden

        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        setupContent()
        centerOnTop()

        self.alphaValue = 0
        self.orderOut(nil)
    }

    private func setupContent() {
        // Glass pill background
        let glass = GlassPillView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))

        // Dot
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor(red: 0.75, green: 0.20, blue: 0.85, alpha: 1).cgColor
        dotView.layer?.cornerRadius = 5
        glass.addSubview(dotView)

        // Label
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(red: 0.78, green: 0.68, blue: 0.92, alpha: 1.0) // Lavender
        label.alignment = .center
        label.frame = NSRect(x: 28, y: 5, width: 110, height: 20)
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        glass.addSubview(label)

        self.contentView = glass
    }

    func centerOnTop() {
        guard let screen = NSScreen.main else { return }
        let x = (screen.frame.width - pillWidth) / 2 + screen.frame.origin.x
        let y = screen.frame.maxY - pillHeight - 6
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show(mode: AppState) {
        switch mode {
        case .recording:
            dotView.layer?.backgroundColor = NSColor(red: 0.75, green: 0.20, blue: 0.85, alpha: 1).cgColor
            label.stringValue = "Gravando"
            startPulse()
        case .streaming:
            dotView.layer?.backgroundColor = NSColor(red: 0.20, green: 0.55, blue: 0.90, alpha: 1).cgColor
            label.stringValue = "Tempo real"
            startPulse()
        case .transcribing:
            dotView.layer?.backgroundColor = NSColor(red: 0.60, green: 0.35, blue: 0.95, alpha: 1).cgColor
            label.stringValue = "Transcrevendo"
            stopPulse()
        case .idle:
            break
        }

        self.alphaValue = 0
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0.95
        }
    }

    func hide() {
        stopPulse()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }

    private func startPulse() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let dot = self?.dotView.layer else { return }
            let t = Date().timeIntervalSince1970
            let p = 0.5 + 0.5 * sin(t * 4)
            // Pulsing purple
            let r = (0.55 + p * 0.25)
            let b = (0.65 + p * 0.25)
            dot.backgroundColor = NSColor(red: CGFloat(r), green: 0.15, blue: CGFloat(b), alpha: 1.0).cgColor
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }
}

// Glass pill using NSVisualEffectView
private class GlassPillView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.material = .hudWindow
        self.blendingMode = .behindWindow
        self.state = .active
        self.wantsLayer = true
        self.layer?.cornerRadius = frame.height / 2
        self.layer?.masksToBounds = true
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = NSColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 0.3).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
}
