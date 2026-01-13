import Cocoa
import Carbon

class KeyboardMonitor: ObservableObject {
    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastKeyCode: CGKeyCode?

    // Key codes for Command keys
    private let leftCommandKeyCode: CGKeyCode = 55
    private let rightCommandKeyCode: CGKeyCode = 54

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
    }

    func start() {
        checkAccessibilityPermission()
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary

        if AXIsProcessTrustedWithOptions(options) {
            startEventTap()
        } else {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.startEventTap()
                }
            }
        }
    }

    private func startEventTap() {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.keyDown.rawValue)

        let observer = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        )

        guard let eventTap = eventTap else {
            print("Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("Event tap started")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event: event)
        case .keyDown:
            lastKeyCode = nil
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard keyCode == leftCommandKeyCode || keyCode == rightCommandKeyCode else {
            lastKeyCode = nil
            return Unmanaged.passUnretained(event)
        }

        let isCommandPressed = flags.contains(.maskCommand)

        if isCommandPressed {
            lastKeyCode = keyCode
        } else {
            if lastKeyCode == keyCode {
                if keyCode == leftCommandKeyCode {
                    switchToEnglish()
                } else {
                    switchToJapanese()
                }
            }
            lastKeyCode = nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func switchToEnglish() {
        switchToInputSource("ABC")
    }

    private func switchToJapanese() {
        switchToInputSource("Kotoeri.RomajiTyping.Japanese")
    }

    private func switchToInputSource(_ targetID: String) {
        let conditions = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for source in sources {
            if let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
                if id.contains(targetID) {
                    TISSelectInputSource(source)
                    return
                }
            }
        }
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        stop()
    }
}
