# Marp テンプレートキット

Marp を使ったスライド作成のためのテンプレートです.

## 前提条件

- [Podman](https://podman.io/) がインストールされていること.
- プレビュー用: VS Code + [Marp for VS Code](https://marketplace.visualstudio.com/items?itemName=marp-team.marp-vscode) 拡張機能.

## ディレクトリ構成

```
.
├── build.sh              # ビルドスクリプト
├── components.md         # 使用できるコンポーネント一覧
├── samples/              # 各種サンプルスライド
│   └── morning.md        # 朝会報告のサンプル
├── themes/
│   └── modern.css        # カスタムテーマ CSS
├── icons/                # ステータスアイコン (SVG)
└── out/                  # 出力先 (build.sh が自動生成)
```

## VS Code プレビュー

`.vscode/settings.json` にテーマが登録済みです. VS Code でこのフォルダを開き, `components.md` や `samples/morning.md` の Marp プレビュー (`Ctrl+Shift+V`) を起動するとカスタムフォントが適用されます.

新しい Markdown ファイルで同じテーマを使う場合は, フロントマターに以下を追加してください.

```yaml
---
marp: true
theme: modern
---
```

## セクション見出し

`_class: section` のスライドでは, `#` に章番号, `###` にメイン見出しを書きます.

```markdown
<!-- _class: section -->

# 02

### 基本的なコンテンツ<br>テキストと箇条書き
```

見出しと短い横線は, 行数に応じて全体が上下中央に配置されます. 1〜3 行の見出しを想定しています.
長い見出しは自動で折り返されます. 意味の区切りで改行したい場合は, 上の例のように `<br>` を使います.

## ビルド

### 実行

```bash
./build.sh <Markdown ファイル>
```

HTML, 文字を選択できる PDF (`out/pdfs/`), 画像ベースの PDF (`out/png_pdfs/`) が生成されます.
`backdrop-filter` の見た目を含めて確認する場合は, PNG 経由で変換した画像ベースの PDF を使用します.

### 注意

- コンテナイメージの初回構築には, 依存関係とフォントを取得するためネットワーク接続が必要です.
- フォントは生成 HTML に埋め込まれるため, 閲覧時に外部から取得する必要はありません.
- git clone で取得した場合, 実行権限はすでに付与されています. 別の方法で取得した場合は `chmod +x build.sh` を実行してください.
