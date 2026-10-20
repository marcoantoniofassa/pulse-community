import AppKit

final class OverlayPanel: NSPanel {
    let waveformView: WaveformView

    init() {
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 110

        waveformView = WaveformView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        self.isFloatingPanel = true
        self.level = .floating
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

        // Glass container with waveform on top
        let container = GlassContainerView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        container.addSubview(waveformView)
        self.contentView = container

        centerOnScreen()
        self.alphaValue = 0
        self.orderOut(nil)
    }

    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let x = (frame.width - self.frame.width) / 2 + frame.origin.x
        let y = (frame.height - self.frame.height) / 2 + frame.origin.y
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func fadeIn() {
        centerOnScreen()  // recalculate position every time — screen config may have changed
        self.alphaValue = 0
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }

    func fadeOut(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.waveformView.stopTimer()
            completion?()
        })
    }
}

// MARK: - Glass Container (NSVisualEffectView — macOS native frosted glass)

private class GlassContainerView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        // macOS native frosted glass — same tech as iPhone
        self.material = .hudWindow           // Dark translucent
        self.blendingMode = .behindWindow    // Blurs desktop behind
        self.state = .active                 // Always active (even unfocused)
        self.wantsLayer = true
        self.layer?.cornerRadius = 16
        self.layer?.masksToBounds = true
        // Subtle purple-tinted border
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = NSColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 0.3).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
}
