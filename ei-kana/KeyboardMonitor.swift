import Cocoa
import Carbon
import IOKit.hid

// This local build observes keys without intercepting or recording typed input.
// Any physical keyboard may initiate a Command tap, regardless of model or connection.
struct CommandTapTracker {
    struct Key: Hashable {
        let device: UInt64
        let page: UInt32
        let usage: UInt32

        var isCommand: Bool { page == 0x07 && (usage == 0xe3 || usage == 0xe7) }
    }

    private var held: Set<Key> = []
    private var candidate: Key?

    mutating func update(_ key: Key, pressed: Bool, eligible: Bool) -> UInt32? {
        if pressed {
            guard !held.contains(key) else { return nil } // Ignore duplicate / repeat reports.
            candidate = eligible && key.isCommand && held.isEmpty ? key : nil
            held.insert(key)
        } else {
            guard held.remove(key) != nil else {
                candidate = nil // A release without an observed press cannot be a tap.
                return nil
            }
            let completed = candidate == key && held.isEmpty ? key.usage : nil
            candidate = nil
            return completed
        }
        return nil
    }

    mutating func seedHeld(_ key: Key) {
        held.insert(key)
        candidate = nil
    }

    mutating func cancel() { candidate = nil }

    mutating func removeDevice(_ device: UInt64) {
        held = held.filter { $0.device != device }
        candidate = nil
    }

    mutating func reset() {
        held.removeAll()
        candidate = nil
    }
}

// 入力ソース情報
struct InputSourceInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

class KeyboardMonitor: ObservableObject {
    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            tapTracker.cancel()
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

    @Published private(set) var hasInputMonitoringAccess = false
    @Published private(set) var monitoringStatus = "Starting keyboard monitor…"

    private var hidManager: IOHIDManager?
    private var permissionTimer: Timer?
    private var targetDevices: Set<UInt64> = []
    private var knownDevices: [IOHIDDevice: UInt64] = [:]
    private var tapTracker = CommandTapTracker()
    private var wakeObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []

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
        guard permissionTimer == nil else { return }
        // Listening needs Input Monitoring, not Accessibility or event-posting access.
        requestInputMonitoringPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshInputMonitoring()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Do not carry a partial tap or held-key state across sleep.
            self?.stopHIDManager()
            self?.refreshInputMonitoring()
        }
    }

    func requestInputMonitoringPermission() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        refreshInputMonitoring()
    }

    private func refreshInputMonitoring() {
        hasInputMonitoringAccess = CGPreflightListenEventAccess()
        guard hasInputMonitoringAccess else {
            stopHIDManager()
            monitoringStatus = "Input Monitoring permission required"
            return
        }
        if hidManager == nil { startHIDManager() }
    }

    private func startHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Watch all keyboards: keys on any keyboard must cancel a Command chord.
        // Consumer controls are also observed so volume/media chords do not switch IME.
        let matches: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x06],
            [kIOHIDDeviceUsagePageKey: 0x0c, kIOHIDDeviceUsageKey: 0x01]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard result == kIOReturnSuccess, let context = context else { return }
            Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue().deviceAdded(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context = context else { return }
            Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard let context = context else { return }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else {
                monitor.tapTracker.cancel()
                return
            }
            monitor.handleValue(value)
        }, context)
        hidManager = manager
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // Never use kIOHIDOptionsTypeSeizeDevice: normal key delivery stays with macOS.
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            stopHIDManager()
            monitoringStatus = "Keyboard monitor unavailable (\(result)); retrying…"
            return
        }
        let mouseDowns: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let observer = NSEvent.addGlobalMonitorForEvents(matching: mouseDowns, handler: { [weak self] _ in
            self?.tapTracker.cancel()
        }) { mouseMonitors.append(observer) }
        if let observer = NSEvent.addLocalMonitorForEvents(matching: mouseDowns, handler: { [weak self] event in
            self?.tapTracker.cancel()
            return event
        }) { mouseMonitors.append(observer) }
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices { deviceAdded(device) }
        }
        updateMonitoringStatus()
    }

    private func deviceID(_ device: IOHIDDevice) -> UInt64? {
        if let identifier = knownDevices[device] { return identifier }
        var identifier: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &identifier) == KERN_SUCCESS else {
            return nil // Unknown origin must never initiate a switch.
        }
        return identifier
    }

    private func isTargetDevice(_ device: IOHIDDevice) -> Bool {
        return IOHIDDeviceConformsTo(device, 0x01, 0x06)
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        guard knownDevices[device] == nil else { return }
        guard let identifier = deviceID(device) else { return }
        knownDevices[device] = identifier
        tapTracker.cancel()
        if isTargetDevice(device) { targetDevices.insert(identifier) }
        // Seed cached physical state, including keys already down when the app starts.
        if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            for element in elements {
                guard (1...4).contains(IOHIDElementGetType(element).rawValue) else { continue }
                let page = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)
                guard isTrackedKey(page: page, usage: usage) else { continue }
                withUnsafeTemporaryAllocation(of: Unmanaged<IOHIDValue>.self, capacity: 1) { buffer in
                    guard let pointer = buffer.baseAddress,
                          IOHIDDeviceGetValue(device, element, pointer) == kIOReturnSuccess else { return }
                    let value = pointer.pointee.takeUnretainedValue()
                    if IOHIDValueGetLength(value) <= MemoryLayout<CFIndex>.size,
                       IOHIDValueGetIntegerValue(value) != 0 {
                        tapTracker.seedHeld(.init(device: identifier, page: page, usage: usage))
                    }
                }
            }
        }
        updateMonitoringStatus()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        if let identifier = deviceID(device) {
            targetDevices.remove(identifier)
            tapTracker.removeDevice(identifier)
            knownDevices.removeValue(forKey: device)
        } else {
            tapTracker.cancel()
        }
        updateMonitoringStatus()
    }

    private func updateMonitoringStatus() {
        monitoringStatus = targetDevices.isEmpty ? "Waiting for a keyboard" : "Ready"
    }

    private func isTrackedKey(page: UInt32, usage: UInt32) -> Bool {
        (page == 0x07 && (0x04...0xe7).contains(usage)) || (page == 0x0c && usage != 0)
    }

    private func handleValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let identifier = deviceID(device) else {
            tapTracker.cancel()
            return
        }
        guard IOHIDValueGetLength(value) <= MemoryLayout<CFIndex>.size else {
            tapTracker.cancel()
            return
        }
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        guard isTrackedKey(page: page, usage: usage) else {
            // Vendor-defined Fn / other controls may not have a standard keyboard usage.
            if pressed { tapTracker.cancel() }
            return
        }
        let key = CommandTapTracker.Key(device: identifier, page: page, usage: usage)
        // Also reject Fn / modifiers already held before monitoring began. Command
        // itself is excluded because this event's own physical press sets that flag.
        let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
        let noOtherModifiers = CGEventSource.flagsState(.combinedSessionState).intersection(otherModifiers).isEmpty
        let eligible = isEnabled && targetDevices.contains(identifier) && noOtherModifiers && NSEvent.pressedMouseButtons == 0
        guard let command = tapTracker.update(key, pressed: pressed, eligible: eligible), eligible else { return }
        // Keep the HID callback short; queued work must still be enabled and connected.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isEnabled, self.targetDevices.contains(identifier) else { return }
            if command == 0xe3 { self.switchToEnglish() } else { self.switchToJapanese() }
        }
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

        let selectableSources: [(String, TISInputSource)] = sources.compactMap { source in
            guard let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  Unmanaged<CFBoolean>.fromOpaque(selectable).takeUnretainedValue() == kCFBooleanTrue,
                  let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return (Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String, source)
        }
        // Exact IDs distinguish Google Hiragana (.base) from Alphanumeric (.Roman).
        // Retain only the old Google parent-ID fallback, with an explicit mode order.
        let fallbackIDs = targetID == "com.google.inputmethod.Japanese" ? [
            "com.google.inputmethod.Japanese.base", "com.google.inputmethod.Japanese.Roman"
        ] : []
        for identifier in [targetID] + fallbackIDs {
            if let (_, source) = selectableSources.first(where: { $0.0 == identifier }) {
                let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
                if inputSourceString(current, kTISPropertyInputSourceID) == identifier { return }
                let currentProvider = inputSourceString(current, kTISPropertyBundleID)
                let targetProvider = inputSourceString(source, kTISPropertyBundleID)
                let sameIME = currentProvider != nil && currentProvider == targetProvider
                if TISSelectInputSource(source) == noErr && isCJKV(identifier) && !sameIME {
                    showTemporaryInputWindow()
                }
                return
            }
        }
    }

    private func inputSourceString(_ source: TISInputSource, _ property: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
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

    private func stopHIDManager() {
        for observer in mouseMonitors { NSEvent.removeMonitor(observer) }
        mouseMonitors.removeAll()
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidManager = nil
        targetDevices.removeAll()
        knownDevices.removeAll()
        tapTracker.reset()
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        stopHIDManager()
        tempWindow?.orderOut(nil)
        tempWindow = nil
    }

    deinit {
        stop()
    }
}
