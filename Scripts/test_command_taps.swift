// Run from the repo root:
// swiftc ei-kana/KeyboardMonitor.swift Scripts/test_command_taps.swift -o /tmp/ei-kana-tap-tests
// /tmp/ei-kana-tap-tests
// Pure state tests: never opens a keyboard, requests permission, or changes input source.
import Foundation

@main
struct CommandTapTests {
    static func main() {
        typealias Key = CommandTapTracker.Key
        let left = Key(device: 1, page: 7, usage: 0xe3)
        let right = Key(device: 1, page: 7, usage: 0xe7)
        let letter = Key(device: 1, page: 7, usage: 0x06)
        let shift = Key(device: 1, page: 7, usage: 0xe1)
        let internalLetter = Key(device: 2, page: 7, usage: 0x06)
        let internalCommand = Key(device: 2, page: 7, usage: 0xe3)
        let volume = Key(device: 3, page: 0x0c, usage: 0xe9)
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            passed += 1
        }
        for key in [left, right] {
            var state = CommandTapTracker()
            check(state.update(key, pressed: true, eligible: true) == nil, "no switch on press")
            check(state.update(key, pressed: false, eligible: true) == key.usage, "switch on lone release")
        }
        for other in [letter, shift, right, internalLetter, internalCommand, volume] {
            for releaseCommandFirst in [false, true] {
                var state = CommandTapTracker()
                _ = state.update(left, pressed: true, eligible: true)
                _ = state.update(other, pressed: true, eligible: other.page == 7)
                let first = releaseCommandFirst ? left : other
                let second = releaseCommandFirst ? other : left
                check(state.update(first, pressed: false, eligible: true) == nil, "chord first release")
                check(state.update(second, pressed: false, eligible: true) == nil, "chord final release")
            }
            var state = CommandTapTracker()
            _ = state.update(other, pressed: true, eligible: other.page == 7)
            _ = state.update(left, pressed: true, eligible: true)
            check(state.update(left, pressed: false, eligible: true) == nil, "key held before Command")
        }
        var state = CommandTapTracker()
        _ = state.update(internalCommand, pressed: true, eligible: true)
        check(state.update(internalCommand, pressed: false, eligible: true) == internalCommand.usage, "internal Command tap switches")
        _ = state.update(left, pressed: true, eligible: false)
        check(state.update(left, pressed: false, eligible: true) == nil, "disabled press ignored")
        _ = state.update(left, pressed: true, eligible: true)
        _ = state.update(left, pressed: true, eligible: true)
        check(state.update(left, pressed: false, eligible: true) == left.usage, "duplicate press does not add a tap")
        check(state.update(left, pressed: false, eligible: true) == nil, "duplicate release ignored")
        _ = state.update(left, pressed: true, eligible: true)
        state.removeDevice(1)
        check(state.update(left, pressed: false, eligible: true) == nil, "disconnect cancels tap")
        _ = state.update(left, pressed: true, eligible: true)
        state.cancel()
        check(state.update(left, pressed: false, eligible: true) == nil, "cancel prevents tap")
        _ = state.update(left, pressed: true, eligible: true)
        state.reset()
        check(state.update(left, pressed: false, eligible: true) == nil, "reset prevents tap")
        state.seedHeld(internalLetter)
        _ = state.update(left, pressed: true, eligible: true)
        check(state.update(left, pressed: false, eligible: true) == nil, "startup held key blocks tap")
        _ = state.update(internalLetter, pressed: false, eligible: false)
        _ = state.update(right, pressed: true, eligible: true)
        check(state.update(right, pressed: false, eligible: true) == right.usage, "recovers after chord/startup state")
        print("Passed \(passed) Command-tap regression assertions")
    }
}
