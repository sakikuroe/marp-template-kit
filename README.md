# Marp テンプレートキット

Marp を使ったスライド作成のためのテンプレートです.

## 前提条件

- [Podman](https://podman.io/) がインストールされていること.
- プレビュー用: VS Code + [Marp for VS Code](https://marketplace.visualstudio.com/items?itemName=marp-team.marp-vscode) 拡張機能.

## ディレクトリ構成

```
.
├── build.sh          # ビルドスクリプト
├── sample.md         # サンプルスライド (各要素の使い方チートシート)
├── themes/
│   └── modern.css    # カスタムテーマ CSS
└── out/              # 出力先 (build.sh が自動生成)
```

## VS Code プレビュー

`.vscode/settings.json` にテーマが登録済みです. VS Code でこのフォルダを開き, `sample.md` の Marp プレビュー (`Ctrl+Shift+V`) を起動するとカスタムフォントが適用されます.

新しい Markdown ファイルで同じテーマを使う場合は, フロントマターに以下を追加してください.

```yaml
---
marp: true
theme: modern
---
```

## ビルド

### 実行

```bash
./build.sh sample.md
```

`out/` ディレクトリに以下が生成されます.

- `out/sample.html` — HTML
- `out/sample.pdf` — PDF (`backdrop-filter` 対応, PNG 経由で変換)

### 使用イメージの変更

デフォルトは `docker.io/marpteam/marp-cli:v4.3.1` です. `MARP_IMAGE` 環境変数で上書きできます.

```bash
MARP_IMAGE=docker.io/marpteam/marp-cli:latest ./build.sh sample.md
```

### 注意

- PDF: ビルド時にコンテナ内の Chromium が Google Fonts を取得するため, ネットワーク接続が必要です.
- HTML: ビルド時のネットワーク接続は不要です. ブラウザで開く際にフォントが読み込まれます.
- git clone で取得した場合, 実行権限はすでに付与されています. 別の方法で取得した場合は `chmod +x build.sh` を実行してください.
