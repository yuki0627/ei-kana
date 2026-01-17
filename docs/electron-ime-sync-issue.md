# TISSelectInputSource API の入力切り替え問題

## 問題の概要

`TISSelectInputSource` APIでIMEを切り替えても、実際の入力が切り替わらないことがある。

**症状**:
- メニューバーのIMEアイコンは切り替わる
- しかし実際にタイプすると切り替え前の入力モードのまま
- 別のアプリに移動して戻ってくると正常に動作する

## 現在の状況（v0.4.5時点）

v0.4.3 で一時ウィンドウ方式のワークアラウンドを実装したが、**一部のケースで問題が継続している**。

### 問題が発生する条件

| 英語入力（左コマンド） | 日本語入力（右コマンド） | 問題 |
|----------------------|------------------------|------|
| macOS ABC | Google 日本語入力 | **発生する** |
| Google IME 英語 | Google 日本語入力 | 発生しない |

**重要な発見**: 異なるIME間の切り替え（ABC ↔ Google日本語入力）で問題が発生し、同じIME内のモード切り替え（Google IME内）では問題が起きない。

### 具体的な症状

1. 右コマンドで日本語入力に切り替える
2. IMEアイコンは「A」と表示される（期待値は「あ」）
3. タイプすると英語が入力される
4. 左コマンドを1回押しても変化なし（まだ「A」）
5. 左コマンドをもう1回押すとやっと英語モード（ABC）に切り替わる
6. 右コマンドを押すと日本語入力できるようになる

**「1回では切り替わらず、2回押すと切り替わる」** という現象が特徴的。

### 考察

- **同じIME内の切り替え**: 入力ソースが「選択された状態」のまま内部モードだけが切り替わる → 状態の不一致が起きにくい
- **異なるIME間の切り替え**: 完全に違う入力ソースに切り替える → macOSの内部状態と実際の状態がズレやすい

元祖の英かな（cmd-eikana）はキーコード102/104を送信していて、macOSのシステムレベルで処理されるため同期が取れていた。ei-kanaは`TISSelectInputSource`で直接指定するため、この同期がうまくいっていない可能性がある。

### 今後の調査項目

- [ ] `TISSelectInputSource` を複数回呼ぶと改善するか
- [ ] 切り替え前に現在の入力ソースを確認して条件分岐する
- [ ] 異なるIME間の切り替え時に追加のワークアラウンドを入れる
- [ ] 一時ウィンドウの表示時間を調整する

---

## 原因（一般的な説明）

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
