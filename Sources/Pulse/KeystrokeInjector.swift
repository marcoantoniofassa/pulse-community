import AppKit
import CoreGraphics
import Carbon

private let logPath = "/tmp/pulse-keystroke.log"

private func ksLog(_ msg: String) {
    let line = "[\(Date())] [KEYSTROKE] \(msg)\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let fh = FileHandle(forWritingAtPath: logPath) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}

final class KeystrokeInjector {
    static let shared = KeystrokeInjector()
    private init() {}

    /// Delay between keystrokes in seconds
    private let interKeyDelay: TimeInterval = 0.008  // 8ms

    /// Type text at the current cursor position using CGEvent keystroke injection.
    /// Does NOT touch the clipboard.
    func type(text: String) {
        guard AXIsProcessTrusted() else {
            ksLog("FAIL: Accessibility not trusted")
            return
        }

        ksLog("type() called")

        let source = CGEventSource(stateID: .hidSystemState)

        for (i, char) in text.enumerated() {
            if i > 0 {
                Thread.sleep(forTimeInterval: interKeyDelay)
            }
            typeCharacter(char, source: source)
        }

        ksLog("type() done — \(text.count) chars injected")
    }

    /// Apply a correction by backspacing the old suffix and typing the new one.
    /// - Parameters:
    ///   - oldSuffix: the text that was previously typed (to be erased)
    ///   - newSuffix: the replacement text
    /// Safety: never more than 40 backspaces
    func correct(oldSuffix: String, newSuffix: String) {
        guard AXIsProcessTrusted() else {
            ksLog("correct: FAIL Accessibility not trusted")
            return
        }

        let charsToDelete = oldSuffix.count
        guard charsToDelete > 0, charsToDelete <= 40 else {
            ksLog("correct: skip, chars to delete = \(charsToDelete)")
            return
        }

        ksLog("correct: applying backspaces")

        let source = CGEventSource(stateID: .hidSystemState)

        // Send backspaces (keyCode 51 = Delete/Backspace)
        for _ in 0..<charsToDelete {
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                keyDown.post(tap: .cgAnnotatedSessionEventTap)
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
                Thread.sleep(forTimeInterval: interKeyDelay)
            }
        }

        // Pause between delete and retype — needs to be long enough for the text field
        // to process all backspaces before new characters arrive
        Thread.sleep(forTimeInterval: 0.05)

        // Type the new text
        for char in newSuffix {
            typeCharacter(char, source: source)
            Thread.sleep(forTimeInterval: interKeyDelay)
        }

        ksLog("correct: done")
    }

    /// Type a single character via CGEvent.
    /// For characters with a direct keyCode mapping and no modifiers needed,
    /// uses virtualKey events. For everything else (accented, unicode, special),
    /// uses kCGEventKeyboardSetUnicodeString on a dummy key event.
    private func typeCharacter(_ char: Character, source: CGEventSource?) {
        let str = String(char)
        let unichars = Array(str.utf16)

        // Use unicode string injection for all characters.
        // This is the most reliable approach across keyboard layouts and handles
        // accented characters (a, e, c), punctuation, and Unicode natively.
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            ksLog("FAIL: CGEvent creation failed")
            return
        }

        keyDown.keyboardSetUnicodeString(stringLength: unichars.count, unicodeString: unichars)
        keyUp.keyboardSetUnicodeString(stringLength: unichars.count, unicodeString: unichars)

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
