#!/usr/bin/env swift
// キーコード102（英数）と104（かな）を発行して、入力ソースが切り替わるかテスト
//
// 背景:
//   元祖の英かな (https://github.com/iMasanari/cmd-eikana) は
//   キーコード102/104を発行することで入力ソースを切り替えていた。
//   しかし macOS Tahoe (26) 以降、この方式は動作しなくなった。
//
// 実行方法:
//   swift test_keycode.swift
//
// 期待される結果 (macOS Tahoe以降):
//   キーコードを発行しても入力ソースは切り替わらない。
//   → TISSelectInputSource API を使う必要がある。

import Cocoa
import Carbon

func postKeyEvent(keyCode: CGKeyCode) {
    // キーダウン
    if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
        keyDown.post(tap: .cghidEventTap)
    }
    // キーアップ
    if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
        keyUp.post(tap: .cghidEventTap)
    }
}

func getCurrentInputSource() -> String {
    if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
       let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
    }
    return "unknown"
}

print("現在の入力ソース: \(getCurrentInputSource())")
print()

print("キーコード102（英数キー）を発行...")
postKeyEvent(keyCode: 102)
Thread.sleep(forTimeInterval: 0.5)
print("発行後の入力ソース: \(getCurrentInputSource())")
print()

print("キーコード104（かなキー）を発行...")
postKeyEvent(keyCode: 104)
Thread.sleep(forTimeInterval: 0.5)
print("発行後の入力ソース: \(getCurrentInputSource())")
print()

print("もう一度キーコード102（英数キー）を発行...")
postKeyEvent(keyCode: 102)
Thread.sleep(forTimeInterval: 0.5)
print("発行後の入力ソース: \(getCurrentInputSource())")
