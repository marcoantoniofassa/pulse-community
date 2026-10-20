import AppKit
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.marcofassa.pulse", category: "paste")

private func debugLog(_ msg: String) {
    let line = "[\(Date())] [PASTE] \(msg)\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: "/tmp/pulse-paste.log") {
            if let fh = FileHandle(forWritingAtPath: "/tmp/pulse-paste.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/pulse-paste.log"))
        }
    }
}

final class PasteManager {
    static let shared = PasteManager()
    private init() {}

    /// Check + prompt for Accessibility permission (needed for CGEvent posting)
    func ensureAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        debugLog("ensureAccessibility — trusted: \(trusted)")
    }

    func paste(text: String, toApp appName: String) {
        debugLog("paste() called")

        // Check accessibility first
        let trusted = AXIsProcessTrusted()
        debugLog("AXIsProcessTrusted: \(trusted)")

        // 1. Copy to clipboard
        NSPasteboard.general.clearContents()
        let ok = NSPasteboard.general.setString(text, forType: .string)
        debugLog("Clipboard set: \(ok)")

        // 2. Reactivate original app
        var activated = false
        if !appName.isEmpty {
            let apps = NSWorkspace.shared.runningApplications
            if let app = apps.first(where: { $0.localizedName == appName }) {
                activated = app.activate()
                debugLog("Target activated: \(activated)")
            } else {
                // Try bundleIdentifier match
                debugLog("Target app unavailable")
            }
        } else {
            debugLog("appName is empty — skipping activation")
        }

        // 3. Cmd+V via CGEvent
        let delay: Double = 0.2  // generous delay for app activation
        debugLog("Scheduling Cmd+V in \(delay)s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.sendCmdV()
        }
    }

    private func sendCmdV() {
        guard AXIsProcessTrusted() else {
            debugLog("FAIL: NOT trusted for Accessibility — Cmd+V blocked")
            ensureAccessibility()
            return
        }

        guard let src = CGEventSource(stateID: .hidSystemState) else {
            debugLog("FAIL: CGEventSource creation failed")
            return
        }

        // V = keycode 9
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else {
            debugLog("FAIL: CGEvent creation failed")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        debugLog("Cmd+V posted OK via cgAnnotatedSessionEventTap")
    }
}
