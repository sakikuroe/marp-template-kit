# Marp テンプレートキット

Marp を使ったスライド作成のためのテンプレートです。

## 前提条件

- [Podman](https://podman.io/) がインストールされていること。
- プレビュー用: VS Code + [Marp for VS Code](https://marketplace.visualstudio.com/items?itemName=marp-team.marp-vscode) 拡張機能。

## ディレクトリ構成

```
.
├── scripts/              # ビルド・プレビュー処理
│   ├── build.sh          # ビルドスクリプト
│   ├── serve.sh          # プレビューサーバー
│   ├── container.sh      # 共通の引数・イメージ管理
│   └── engine.mjs        # Marpのカスタムエンジン
├── config/               # Mermaidの描画・ブラウザ設定
├── samples/              # 各種サンプルスライド
│   ├── components.md     # 使用できるコンポーネント一覧
│   └── morning.md        # 朝会報告のサンプル
├── assets/               # サンプルで使用する画像
├── themes/
│   └── modern.css        # カスタムテーマ CSS
├── icons/                # ステータスアイコン (SVG)
└── out/                  # 出力先 (scripts/build.sh が自動生成)
```

## VS Code プレビュー

`.vscode/settings.json` にテーマが登録済みです。VS Code でこのフォルダを開き、`samples/components.md` や `samples/morning.md` の Marp プレビュー (`Ctrl+Shift+V`) を起動するとカスタムフォントが適用されます。

新しい Markdown ファイルで同じテーマを使う場合は、フロントマターに以下を追加してください。

```yaml
---
marp: true
theme: modern
---
```

## セクション見出し

`_class: section` のスライドでは、`#` に章番号、`###` にメイン見出しを書きます。

```markdown
<!-- _class: section -->

# 02

### 基本的なコンテンツ<br>テキストと箇条書き
```

見出しと短い横線は、行数に応じて全体が上下中央に配置されます。1〜3 行の見出しを想定しています。
長い見出しは自動で折り返されます。意味の区切りで改行したい場合は、上の例のように `<br>` を使います。

## ビルド

### 実行

```bash
./scripts/build.sh <Markdown ファイル>
```

HTML、文字を選択できる PDF (`out/pdfs/`)、画像ベースの PDF (`out/png_pdfs/`) が生成されます。
`backdrop-filter` の見た目を含めて確認する場合は、PNG 経由で変換した画像ベースの PDF を使用します。

イメージは初回と `Containerfile` の変更時にビルドし、それ以外は既存イメージを再利用します。
`scripts/serve.sh` も同じ判定を使用します。選択できるオプションは `--help` で確認できます。

```bash
./scripts/build.sh --rebuild-image samples/components.md     # キャッシュを使わず再ビルド
./scripts/build.sh --skip-image-build samples/components.md  # 変更の確認を省いて既存イメージを使用
```

従来の独自環境変数 `MARP_SKIP_IMAGE_BUILD` は廃止しました。`--skip-image-build` を使用してください。

### CIでPDFを取得する

PR、`main` へのpush、および手動実行で、コンポーネント一覧とサンプルをビルドします。
GitHubの **Actions → Build slides → 実行結果 → Artifacts → slide-pdfs** からPDFを取得できます。
文字を選択できるPDFを14日間保存します。ダウンロードにはGitHubへのログインとリポジトリの読み取り権限が必要です。
CIの実行環境は毎回新しいため、イメージは各実行の初回にビルドします。同じ実行内のサンプルでは再利用します。

### 注意

- コンテナイメージの初回構築には、依存関係とフォントを取得するためネットワーク接続が必要です。
- フォントは生成 HTML に埋め込まれるため、閲覧時に外部から取得する必要はありません。
- ベースイメージはdigest、Chrome for Testing・Pythonの直接依存はバージョンを固定しています。Chromeと取得するフォントはチェックサムも検証します。更新時は `Containerfile` の対応する値を変更してください。
- OSパッケージと推移的依存は完全には固定していないため、再ビルドがバイト単位で同一になる保証はありません。
- git clone で取得した場合、実行権限はすでに付与されています。別の方法で取得した場合は `chmod +x scripts/build.sh` を実行してください。

## ライセンス

本リポジトリのコード、テーマ、ドキュメント、サンプル、画像およびアイコンは [MIT License](LICENSE) で公開しています。
取得するフォントには各配布元のライセンスが適用され、本リポジトリの MIT License には含まれません。

- [源暎エムゴ](https://okoneya.jp/font/genei-m-gothic.html)、[Rounded Noto Code](https://github.com/sakikuroe/rounded-noto-sans-cjk/tree/v0.2.0)、Noto Sans JP / Noto CJK、IBM Plex Sans JP: SIL Open Font License 1.1。
- 源暎エムゴと Rounded Noto Code は、著作権表示・OFL 1.1 の宣言・ライセンスURLをフォント内に保持しています。VS Code用のコピーとHTMLへの埋め込みでは元のフォントをそのまま使い、この情報を維持します。
- OFL フォントを使用して作成した PDF やスライド自体に、OFL を適用する必要はありません。詳細は [OFL の公式 FAQ](https://openfontlicense.org/ofl-faq/) を参照してください。
