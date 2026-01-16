import Cocoa
import Carbon

// 入力ソース情報
struct InputSourceInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

class KeyboardMonitor: ObservableObject {
    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
        }
    }

    @Published var englishInputSourceID: String {
        didSet {
            UserDefaults.standard.set(englishInputSourceID, forKey: "englishInputSourceID")
        }
    }

    @Published var japaneseInputSourceID: String {
        didSet {
            UserDefaults.standard.set(japaneseInputSourceID, forKey: "japaneseInputSourceID")
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastKeyCode: CGKeyCode?

    // Key codes for Command keys
    private let leftCommandKeyCode: CGKeyCode = 55
    private let rightCommandKeyCode: CGKeyCode = 54

    init() {
        // デフォルト値を先に設定（self参照前に必要）
        let defaultEnglish = "com.apple.keylayout.ABC"
        let defaultJapanese = "com.google.inputmethod.Japanese"

        self.englishInputSourceID = UserDefaults.standard.string(forKey: "englishInputSourceID") ?? defaultEnglish
        self.japaneseInputSourceID = UserDefaults.standard.string(forKey: "japaneseInputSourceID") ?? defaultJapanese
        self.isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
    }

    // 選択可能な入力ソース一覧を取得
    func getSelectableInputSources() -> [InputSourceInfo] {
        let conditions = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        var result: [InputSourceInfo] = []
        for source in sources {
            if let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
                let selectable = Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue() == kCFBooleanTrue
                if !selectable { continue }
            }

            if let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               let localizedName = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                let id = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
                let name = Unmanaged<CFString>.fromOpaque(localizedName).takeUnretainedValue() as String
                result.append(InputSourceInfo(id: id, name: name))
            }
        }
        return result
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
                // 非同期で切り替えを実行（イベントタップをブロックしないため）
                let isLeftCommand = keyCode == leftCommandKeyCode
                DispatchQueue.main.async { [weak self] in
                    if isLeftCommand {
                        self?.switchToEnglish()
                    } else {
                        self?.switchToJapanese()
                    }
                }
            }
            lastKeyCode = nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func switchToEnglish() {
        switchToInputSource(englishInputSourceID)
    }

    private func switchToJapanese() {
        switchToInputSource(japaneseInputSourceID)
    }

    private func switchToInputSource(_ targetID: String) {
        let conditions = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for source in sources {
            // 選択可能なソースのみ対象
            if let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
                let selectable = Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue() == kCFBooleanTrue
                if !selectable { continue }
            }

            if let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
                if id.contains(targetID) {
                    TISSelectInputSource(source)

                    // CJKV言語の場合はワークアラウンドを適用（Electronアプリ対策）
                    if isCJKV(targetID) {
                        showTemporaryInputWindow()
                    }
                    return
                }
            }
        }
    }

    // CJKV（中国語・日本語・韓国語・ベトナム語）かどうかを判定
    private func isCJKV(_ sourceID: String) -> Bool {
        return sourceID.contains("Japanese") ||
               sourceID.contains("Chinese") ||
               sourceID.contains("Korean") ||
               sourceID.contains("Vietnamese")
    }

    // MARK: - TISSelectInputSource ワークアラウンド
    //
    // 本来は TISSelectInputSource を呼ぶだけでIMEが切り替わるべきだが、
    // macOSのCarbon API（TISSelectInputSource）には既知のバグがあり、
    // CJKV言語でElectronアプリ（Slack、LINEなど）にフォーカスがある場合、
    // メニューバーのIME表示は変わるが実際の入力は切り替わらない。
    //
    // このワークアラウンドは一時的にウィンドウを表示してフォーカスを奪い、
    // 「別アプリに移動して戻る」を人工的に再現することで問題を回避する。
    //
    // 参考:
    // - macism: https://github.com/laishulu/macism
    // - Karabiner-Elements Issue #1602: https://github.com/pqrs-org/Karabiner-Elements/issues/1602
    // - 詳細: docs/electron-ime-sync-issue.md
    //
    private var tempWindow: NSWindow?

    private func showTemporaryInputWindow(waitTimeMs: Int = 50) {
        // 前回のウィンドウがあれば閉じる
        tempWindow?.orderOut(nil)
        tempWindow = nil

        // 画面外に小さなウィンドウを作成
        let rect = NSRect(x: -100, y: -100, width: 1, height: 1)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false

        tempWindow = window

        // ウィンドウを表示（メニューバーアプリではactivateを呼ばない）
        window.orderFrontRegardless()

        // 指定時間後にウィンドウを非表示
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(waitTimeMs)) { [weak self] in
            self?.tempWindow?.orderOut(nil)
            self?.tempWindow = nil
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
