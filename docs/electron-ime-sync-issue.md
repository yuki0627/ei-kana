# Electronアプリでの日本語入力切り替え問題

## 問題の概要

`TISSelectInputSource` APIでIMEを切り替えても、Electronアプリ（Slack、LINEなど）では実際の入力が日本語に切り替わらない。

**症状**:
- メニューバーのIMEアイコンは日本語に変わる
- しかし実際にタイプすると英語（a）が入力される
- 別のアプリに移動して戻ってくると正常に動作する

## 原因

**macOSのCarbon API（`TISSelectInputSource`）の既知のバグ**

特にCJKV（中国語・日本語・韓国語・ベトナム語）の入力ソースで発生する。

`TISSelectInputSource`を呼ぶとシステムのIME状態は変わるが、**現在フォーカス中のアプリのテキストフィールドにはその変更が通知されない**。フォーカスが別のアプリに移動すると同期される。

## 影響を受けるツール

| ツール | 方式 | 問題発生 |
|--------|------|----------|
| ei-kana (現在) | `TISSelectInputSource` | **発生する** |
| Karabiner-Elements `select_input_source` | `TISSelectInputSource` | **発生する** |
| im-select | `TISSelectInputSource` | **発生する** |
| macism | TIS + 一時ウィンドウ | 回避済み |
| 元祖 英かな (cmd-eikana) | キーコード送信 | 発生しない（※macOS Tahoeで動作しなくなった） |

### 参考リンク

- [Karabiner-Elements Issue #1602](https://github.com/pqrs-org/Karabiner-Elements/issues/1602) - CJKV入力ソース切り替え問題
- [macism](https://github.com/laishulu/macism) - ワークアラウンドを実装したツール
- [Kawa](https://github.com/hatashiro/kawa) - macismの元になったツール

## ワークアラウンド

### 方式1: 一時ウィンドウ方式（macism方式）- 推奨

`TISSelectInputSource`を呼んだ後、一時的に小さなウィンドウを表示してフォーカスを奪い、すぐに閉じる。これにより「別のアプリに移動して戻る」を人工的に再現する。

**macismの実装（WindowUtils.swift）**:

```swift
func showTemporaryInputWindow(waitTimeMs: Int = 50) {
    // 画面外に小さなウィンドウを作成
    let rect = NSRect(x: -100, y: -100, width: 1, height: 1)
    let window = NSWindow(
        contentRect: rect,
        styleMask: [],
        backing: .buffered,
        defer: false
    )

    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    // ウィンドウを表示してフォーカスを取得
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    // 指定時間後にウィンドウを閉じる
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(waitTimeMs)) {
        window.close()
    }
}
```

**使用方法**:

```swift
func switchToInputSourceWithWorkaround(_ targetID: String) {
    // 通常の切り替え
    TISSelectInputSource(source)

    // CJKV言語の場合はワークアラウンドを適用
    if isCJKV(targetID) {
        showTemporaryInputWindow(waitTimeMs: 50)
    }
}
```

**CJKV判定**:

```swift
func isCJKV(_ sourceID: String) -> Bool {
    return sourceID.contains("Japanese") ||
           sourceID.contains("Chinese") ||
           sourceID.contains("Korean") ||
           sourceID.contains("Vietnamese")
}
```

### 方式2: キーボードショートカット送信

`TISSelectInputSource`の代わりに、Control+Spaceなどのキーボードショートカットを送信する。

**メリット**: システム標準の動作なので確実
**デメリット**: ユーザーのキーボード設定に依存する

### 方式3: TISEnableInputSource を先に呼ぶ

一部の報告では、`TISSelectInputSource`の前に`TISEnableInputSource`を呼ぶと改善するとのこと（未検証）。

```swift
TISEnableInputSource(source)
TISSelectInputSource(source)
```

## ei-kanaへの実装案

1. `KeyboardMonitor.swift`の`switchToInputSource`関数を修正
2. 日本語（CJKV）への切り替え時のみワークアラウンドを適用
3. 一時ウィンドウを表示→閉じる処理を追加

**注意点**:
- ウィンドウの表示時間は短く（50ms程度）
- 画面外または透明なウィンドウを使用してユーザーに見えないようにする
- メニューバーアプリなのでNSApplicationの設定に注意
