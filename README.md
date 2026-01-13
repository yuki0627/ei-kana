# ei-kana

macOS用の英数/かな切り替えアプリ。左右のCommandキー単体押しで入力ソースを切り替えます。

- **左Command** → 英数 (ABC)
- **右Command** → かな (日本語)

## 対応OS

- macOS 14.0 (Sonoma) 以降
- macOS 26 (Tahoe) で動作確認済み

## インストール

### ビルド済みアプリ

[Releases](https://github.com/yuki/ei-kana/releases) からダウンロード

### ソースからビルド

```bash
cd ei-kana
swiftc -parse-as-library -emit-executable -o ei-kana \
  ei_kanaApp.swift KeyboardMonitor.swift MenuBarView.swift \
  -framework Cocoa -framework Carbon -target arm64-apple-macosx14.0
```

## 使い方

1. アプリを起動
2. アクセシビリティ権限を許可（システム設定 > プライバシーとセキュリティ > アクセシビリティ）
3. メニューバーに「⌘」アイコンが表示されます
4. 左右のCommandキーで入力ソースが切り替わります

## 技術的な背景

macOS 26 (Tahoe) では、従来のキーコード送信方式（keyCode 102/104）による入力ソース切り替えが動作しなくなりました。このアプリは `TISSelectInputSource` API を使用して直接入力ソースを切り替えます。

## クレジット

このプロジェクトは [cmd-eikana](https://github.com/iMasanari/cmd-eikana) にインスパイアされて作成されました。

## ライセンス

MIT License
