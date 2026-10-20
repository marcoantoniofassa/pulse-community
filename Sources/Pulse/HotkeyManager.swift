import Cocoa
import Carbon
import os.log

private let logger = Logger(subsystem: "com.marcofassa.pulse", category: "hotkey")

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var streamHotKeyRef: EventHotKeyRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Double-tap Option → recording toggle. A tap counts when Option is RELEASED, and only if
    // nothing else was pressed while it was held: Option+S, Option+Space and ç are chords, not taps.
    private var optionDownTime: TimeInterval = 0     // 0 = Option not held
    private var optionChord = false                  // something else happened while Option was held
    private var lastOptionTapDown: TimeInterval = 0  // when the previous clean tap went down
    // ponytail: 0.4s feels natural; raise if double-taps get missed, lower if it fires too eager.
    private let doubleTapWindow: TimeInterval = 0.4

    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStreamToggle: (() -> Void)?

    func start() {
        // Method 1: Carbon RegisterEventHotKey for ESC + Option+S + Option+Space (no Input Monitoring needed)
        registerCarbonHotkey()

        // Method 2: NSEvent global monitor for Fn+Space + double-tap Option.
        // (Was a CGEvent tap, but the raw tap death-spiraled on .tapDisabledByTimeout
        // after a streaming session under GUI launch — re-enable didn't restore delivery.
        // NSEvent monitors don't disable, and are the standard way to catch global modifiers.)
        registerGlobalMonitor()
    }

    // MARK: - Carbon Hotkey (preferred — no Input Monitoring needed)

    @discardableResult
    private func registerCarbonHotkey() -> Bool {
        // Install handler — dispatches based on hotkey ID
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerRef = UnsafeMutablePointer<EventHandlerRef?>.allocate(capacity: 1)
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(event!, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
                DispatchQueue.main.async {
                    if hotkeyID.id == 1 {
                        NotificationCenter.default.post(name: .hotkeyTriggered, object: nil)
                    } else if hotkeyID.id == 2 {
                        NotificationCenter.default.post(name: .escTriggered, object: nil)
                    } else if hotkeyID.id == 3 {
                        NotificationCenter.default.post(name: .streamToggled, object: nil)
                    }
                }
                return noErr
            },
            1, &eventType, nil, handlerRef
        )

        guard status == noErr else {
            logger.error("InstallEventHandler failed: \(status)")
            return false
        }

        // ESC (id: 2) — cancel recording
        var escKeyID = EventHotKeyID(signature: OSType(0x504C5345), id: 2)
        let escStatus = RegisterEventHotKey(
            UInt32(kVK_Escape), 0,
            escKeyID, GetApplicationEventTarget(), 0, &escHotKeyRef
        )
        if escStatus != noErr {
            logger.warning("RegisterEventHotKey ESC failed: \(escStatus)")
        }

        // Option+Space (id: 3) — streaming mode. Other apps also grab Option+Space
        // (ChatGPT, SuperWhisper), so it lives on the less used mode.
        var streamKeyID = EventHotKeyID(signature: OSType(0x504C5345), id: 3)
        let streamStatus = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(optionKey),
            streamKeyID, GetApplicationEventTarget(), 0, &streamHotKeyRef
        )
        if streamStatus != noErr {
            logger.warning("RegisterEventHotKey Option+Space failed: \(streamStatus) — likely taken by another app")
        }

        // Option+S (id: 1) — toggle recording, fallback for double-tap Option without Input Monitoring
        var recordKeyID = EventHotKeyID(signature: OSType(0x504C5345), id: 1)
        let recordStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_S), UInt32(optionKey),
            recordKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if recordStatus != noErr {
            logger.warning("RegisterEventHotKey Option+S failed: \(recordStatus)")
        }

        NotificationCenter.default.addObserver(forName: .hotkeyTriggered, object: nil, queue: .main) { [weak self] _ in
            self?.onToggle?()
        }
        NotificationCenter.default.addObserver(forName: .escTriggered, object: nil, queue: .main) { [weak self] _ in
            self?.onCancel?()
        }
        NotificationCenter.default.addObserver(forName: .streamToggled, object: nil, queue: .main) { [weak self] _ in
            self?.onStreamToggle?()
        }

        logger.warning("Carbon hotkeys registered: Option+S (record) + ESC + Option+Space (stream)")
        return true
    }

    // MARK: - CGEvent tap fallback

    // MARK: - NSEvent global monitor (Fn+Space + double-tap Option)

    private func registerGlobalMonitor() {
        // Global = fires while OTHER apps are focused (the normal dictation case).
        // Local  = fires while Pulse itself is focused (settings/overlay). Local must
        // return the event so it isn't swallowed.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleNSEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }
        if globalMonitor == nil {
            logger.error("NSEvent global monitor FAILED — need Accessibility/Input Monitoring permission")
        } else {
            logger.warning("NSEvent monitor active: Fn+Space + double-tap Option")
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(keyCode: event.keyCode, flags: event.modifierFlags)
        case .keyDown:
            // Any real key breaks a pending Option-tap chain, so Option+letter never double-fires.
            optionChord = true
            lastOptionTapDown = 0
            // Fn+Space — toggle recording (doesn't conflict with SuperWhisper)
            if event.keyCode == 49 && event.modifierFlags.contains(.function) {
                logger.warning("Fn+Space detected")
                onToggle?()
            }
        default:
            break
        }
    }

    // Double-tap Option (left=58 / right=61) → toggle recording. Modifier-only, so it can't
    // be a Carbon hotkey. NSEvent monitor callbacks already run on the main thread.
    // One clock everywhere (systemUptime): pressedAnything compares against the HID idle time.
    private func handleFlagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let now = ProcessInfo.processInfo.systemUptime
        // Cmd/Shift/Ctrl/Fn change: Option+Cmd is a real shortcut, and it breaks the chain.
        guard keyCode == 58 || keyCode == 61 else {
            optionChord = true
            lastOptionTapDown = 0
            return
        }

        if flags.contains(.option) {
            // A down long after the previous one means its release was lost (Secure Input, menu
            // tracking): start over instead of reading it as the second Option key.
            if optionDownTime == 0 || now - optionDownTime >= doubleTapWindow {
                optionDownTime = now
                optionChord = !flags.intersection([.command, .shift, .control]).isEmpty
            } else {
                optionChord = true  // both Option keys at once: not a tap
            }
            return
        }

        // Every Option key is up.
        let downTime = optionDownTime
        let isTap = downTime != 0 && !optionChord
            && now - downTime < doubleTapWindow
            && !pressedAnything(since: downTime)
        optionDownTime = 0
        optionChord = false
        guard isTap else {
            lastOptionTapDown = 0
            return
        }

        // Window measured down to down, as the 0.4s was tuned.
        if lastOptionTapDown != 0 && downTime - lastOptionTapDown < doubleTapWindow {
            lastOptionTapDown = 0
            logger.warning("Double-tap Option detected → record toggle")
            onToggle?()
        } else {
            lastOptionTapDown = downTime
        }
    }

    /// Key or click since `time`, read from the HID state. Catches what the monitor never sees:
    /// a key swallowed by a Carbon hotkey (our Option+S / Option+Space, or another app's
    /// Option+Space) and mouse clicks (Option+click in an editor is not a tap).
    private func pressedAnything(since time: TimeInterval) -> Bool {
        let elapsed = ProcessInfo.processInfo.systemUptime - time
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        return types.contains { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) < elapsed }
    }

    func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
        }
        if let ref = streamHotKeyRef {
            UnregisterEventHotKey(ref)
            streamHotKeyRef = nil
        }
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }
}

extension Notification.Name {
    static let hotkeyTriggered = Notification.Name("PulseHotkeyTriggered")
    static let escTriggered = Notification.Name("PulseEscTriggered")
    static let streamToggled = Notification.Name("PulseStreamToggled")
}
