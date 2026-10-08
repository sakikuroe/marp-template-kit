# Marp テンプレートキット

Marp を使ったスライド作成のためのテンプレートです。

## 前提条件

- [Podman](https://podman.io/) がインストールされていること。
- プレビュー用: VS Code + [Marp for VS Code](https://marketplace.visualstudio.com/items?itemName=marp-team.marp-vscode) 拡張機能。

## ディレクトリ構成

```
.
├── scripts/              # ビルド・プレビュー・描画処理
│   ├── build.sh          # ビルドスクリプト
│   ├── serve.sh          # プレビューサーバー
│   ├── render-mermaid.sh # Mermaid単体ファイルのSVG・PNG変換
│   ├── render-drawio.sh  # draw.io単体ファイルのSVG・PNG変換
│   ├── container.sh      # 共通の引数・イメージ管理
│   └── engine.mjs        # Marpのカスタムエンジン
├── config/               # Mermaidの描画・ブラウザ設定
├── samples/              # 各種サンプルスライド
│   ├── components.md     # 使用できるコンポーネント一覧
│   ├── release-process.mmd # 架空の段階的リリース手順
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

### draw.io拡張のフォント

VS Codeのdraw.io拡張で源暎エムゴを表示するには、ホストOSにもフォントのインストールが必要です。
Podman内のフォントやMarp用の`.cache/fonts/fonts.css`は、この拡張には自動で適用されません。
`.drawio`にフォント名を書くだけでは、未インストールの環境で別のフォントへ置き換わります。

Linuxでは、[公式配布の源暎エムゴv2](https://okoneya.jp/font/genei-m-gothic.html)を展開し、
`GenEiMGothic2-Regular.ttf`・`GenEiMGothic2-Medium.ttf`・`GenEiMGothic2-Bold.ttf`を
`~/.local/share/fonts/genei-m-gothic/`へコピーして、`fc-cache -f`を実行してください。
インストール後はVS Codeをすべて終了して起動し直します。

この準備はエディター表示用です。変換スクリプトはPodman内のフォントを使うため、ホストへのインストールは不要です。
フォントを埋め込んだSVGと生成したPNGも、閲覧側のインストールは不要です。

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

### Mermaid単体ファイルを変換する

```bash
./scripts/render-mermaid.sh samples/release-process.mmd out/diagrams/release-process.svg
./scripts/render-mermaid.sh samples/release-process.mmd out/diagrams/release-process.png
```

出力形式は拡張子で選び、背景は透明にします。スライドと同じMermaid設定・源暎エムゴを使い、単体出力では通常文字をRegular（400）、グループ見出しと太字をMedium（500）にします。
SVGにはフォントを埋め込み、PNGは2倍の解像度で描画します。既存イメージの再利用とイメージ操作のオプションもビルドスクリプトと共通です。

### draw.io単体ファイルを変換する

```bash
./scripts/render-drawio.sh --page 1 diagram.drawio out/diagrams/diagram.svg
./scripts/render-drawio.sh --page 1 diagram.drawio out/diagrams/diagram.png
```

公式draw.io DesktopをPodman内で実行し、透明背景で出力します。PNGは2倍の解像度で描画します。
フォントや配置は入力ファイルの設定を使います。SVGには源暎エムゴのRegular/Medium/Boldを埋め込みます。
複数ページのファイルは標準で最初のページを出力し、`--page`で選択できます。外部URLの画像やフォントは取得しないため、画像は図に埋め込み、フォントはコンテナにあるものを指定してください。
既存イメージの再利用とイメージ操作のオプションはビルドスクリプトと共通です。

### 図の画質・サイズ・共有方法を指定する

PNGは可逆圧縮のためJPEGのような品質値は設けず、描画倍率で精細さを調整します。
標準は2倍です。`--scale 3`なら、同じ配置のまま縦横の画素数を約3倍にします。
SVGはベクター形式なので倍率を指定せず、表示側で拡大できます。

| オプション | 用途 |
| --- | --- |
| `--scale N` | PNGの描画倍率。正の数。標準は2 |
| `--background transparent\|white` | スライドに重ねる透明背景、または図を単体共有する白背景 |
| `--no-embed-fonts` | 軽量なSVGを出力。閲覧側に使用フォントのインストールが必要 |
| `--force` | 既存の成果物を上書き。指定しない場合は上書きしない |
| `--width PX` / `--height PX` | Mermaidはブラウザの描画領域、draw.ioは縦横比を保つ出力サイズ |
| `--page N` | draw.ioのページ選択。1から数える |
| `--border PX` | draw.ioの周囲の余白。標準は16 |

Mermaidの幅・高さは折り返しや配置に影響し、出力画像自体は図の範囲へ切り出します。
draw.ioは幅・高さの同時指定や、サイズ指定と倍率の併用を受け付けません。
フォントを埋め込むSVGは大きくなるため、相手に同じフォントがある場合は埋め込みを省略できます。

```bash
# 通常の2倍出力より精細な、白背景のPNG。既存の画像を更新する。
./scripts/render-mermaid.sh --scale 3 --background white --force samples/release-process.mmd out/diagrams/release-process.png

# draw.ioの2ページ目を幅1600pxのPNGへ。縦横比は維持する。
./scripts/render-drawio.sh --page 2 --width 1600 diagram.drawio out/diagrams/page-2.png

# 同じフォントがある環境へ共有する、フォントを埋め込まないSVG。
./scripts/render-drawio.sh --page 1 --no-embed-fonts --force diagram.drawio out/diagrams/diagram.svg
```

すべてのオプションは各スクリプトの`--help`で確認できます。
入力ディレクトリは読み取り専用でマウントし、変換に成功した場合だけ成果物を出力します。

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

draw.io DesktopもMITの対象には含まれず、[GPL v3](https://github.com/jgraph/drawio-desktop/blob/v32.3.0/LICENSE)です。公式パッケージをビルド時に取得し、独立したコマンドとして実行します。自作の図や本リポジトリのスクリプトに、利用しただけでGPLが適用されることはありません。
Desktopを含むコンテナイメージを再配布する場合は、GPLに従ってライセンスと対応するソースコードを提供してください。固定バージョンのソースは[公式リポジトリ](https://github.com/jgraph/drawio-desktop/tree/v32.3.0)にあります。

- [源暎エムゴ](https://okoneya.jp/font/genei-m-gothic.html)、[Rounded Noto Code](https://github.com/sakikuroe/rounded-noto-sans-cjk/tree/v0.2.0)、Noto Sans JP / Noto CJK、IBM Plex Sans JP: SIL Open Font License 1.1。
- 源暎エムゴと Rounded Noto Code は、著作権表示・OFL 1.1 の宣言・ライセンスURLをフォント内に保持しています。VS Code用のコピーとHTMLへの埋め込みでは元のフォントをそのまま使い、この情報を維持します。
- OFL フォントを使用して作成した PDF やスライド自体に、OFL を適用する必要はありません。詳細は [OFL の公式 FAQ](https://openfontlicense.org/ofl-faq/) を参照してください。
