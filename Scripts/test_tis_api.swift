#!/usr/bin/env swift
// TISSelectInputSource API を使って入力ソースを切り替えるテスト
//
// 背景:
//   macOS Tahoe (26) 以降、キーコード102/104による切り替えは動作しなくなった。
//   代わりに TISSelectInputSource API を使用する必要がある。
//
// 実行方法:
//   swift Scripts/test_tis_api.swift
//
// 期待される結果:
//   TISSelectInputSource API で入力ソースが正しく切り替わる。

import Cocoa
import Carbon

func getCurrentInputSource() -> String {
    if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
       let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
    }
    return "unknown"
}

func listSelectableInputSources() -> [(id: String, name: String)] {
    let conditions = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
    guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }

    var result: [(id: String, name: String)] = []
    for source in sources {
        // 選択可能なソースのみ
        if let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
            let selectable = Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue() == kCFBooleanTrue
            if !selectable { continue }
        }

        if let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
           let localizedName = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            let id = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
            let name = Unmanaged<CFString>.fromOpaque(localizedName).takeUnretainedValue() as String
            result.append((id: id, name: name))
        }
    }
    return result
}

func switchToInputSource(_ targetID: String) -> Bool {
    let conditions = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
    guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
        return false
    }

    for source in sources {
        // 選択可能なソースのみ
        if let selectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
            let selectable = Unmanaged<CFBoolean>.fromOpaque(selectablePtr).takeUnretainedValue() == kCFBooleanTrue
            if !selectable { continue }
        }

        if let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
            if id.contains(targetID) {
                let status = TISSelectInputSource(source)
                return status == noErr
            }
        }
    }
    return false
}

// テスト開始
print("=== TISSelectInputSource API テスト ===")
print()

print("選択可能な入力ソース一覧:")
for source in listSelectableInputSources() {
    print("  - \(source.name): \(source.id)")
}
print()

let initialSource = getCurrentInputSource()
print("現在の入力ソース: \(initialSource)")
print()

// 英語に切り替え
print("TISSelectInputSource で英語（ABC）に切り替え...")
if switchToInputSource("ABC") {
    Thread.sleep(forTimeInterval: 0.3)
    print("切り替え後: \(getCurrentInputSource())")
} else {
    print("切り替え失敗（ABCが見つからない可能性）")
}
print()

// 日本語に切り替え
print("TISSelectInputSource で日本語に切り替え...")
if switchToInputSource("Japanese") {
    Thread.sleep(forTimeInterval: 0.3)
    print("切り替え後: \(getCurrentInputSource())")
} else {
    print("切り替え失敗（Japaneseが見つからない可能性）")
}
print()

// 元に戻す
print("元の入力ソースに戻す...")
if switchToInputSource(initialSource) {
    Thread.sleep(forTimeInterval: 0.3)
    print("切り替え後: \(getCurrentInputSource())")
}
print()

print("=== テスト完了 ===")
