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
│   ├── render-diagram.sh # Mermaid・draw.ioのSVG・PNG変換
│   ├── diagram.mjs      # 図の描画・フォント埋め込み・PNG化
│   ├── container.sh      # 共通のイメージ管理
│   └── engine.mjs        # Marpのカスタムエンジン
├── config/               # Mermaidの描画・ブラウザ設定
├── samples/              # サンプルスライド・図
│   ├── components.md     # 使用できるコンポーネント一覧
│   ├── release-process.mmd # 架空の段階的リリース手順
│   ├── diagram-gallery.drawio # 計画・業務・設計・画面・リリース手順の22ページ
│   └── morning.md        # 朝会報告のサンプル
├── assets/               # サンプルで使用する画像
├── themes/
│   └── modern.css        # カスタムテーマ CSS
├── icons/                # ステータスアイコン (SVG)
└── out/                  # スライドと図の出力先
```

## VS Code プレビュー

初回は`./scripts/build.sh samples/components.md`を実行してください。Podman内のフォントから、VS Code用のフォントとテーマを`.cache/`に生成します。
`.vscode/settings.json`にはこのテーマが登録済みです。生成後、`samples/components.md`や`samples/morning.md`のMarpプレビュー（`Ctrl+Shift+V`）で同じフォントを使用できます。

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

Markdownはリポジトリ内に置いてください。
HTML、文字を選択できる PDF (`out/pdfs/`)、画像ベースの PDF (`out/png_pdfs/`) が生成されます。
`backdrop-filter` の見た目を含めて確認する場合は、PNG 経由で変換した画像ベースの PDF を使用します。

イメージは初回と `Containerfile` の変更時にビルドし、それ以外は既存イメージを再利用します。
`scripts/serve.sh` も同じ判定を使用します。選択できるオプションは `--help` で確認できます。

```bash
./scripts/build.sh --rebuild-image samples/components.md     # キャッシュを使わず再ビルド
./scripts/build.sh --skip-image-build samples/components.md  # 変更の確認を省いて既存イメージを使用
```

従来の独自環境変数 `MARP_SKIP_IMAGE_BUILD` は廃止しました。`--skip-image-build` を使用してください。

### 図をSVG・PNGに変換する

```bash
./scripts/render-diagram.sh samples/release-process.mmd
./scripts/render-diagram.sh --page 21 samples/diagram-gallery.drawio
```

入力の拡張子でMermaid（`.mmd`・`.mermaid`）とdraw.io（`.drawio`）を判別します。
1回の実行でSVGとPNGを生成し、標準の出力先は`out/diagrams/`です。
上の例では`out/diagrams/release-process.svg`・`.png`、`out/diagrams/diagram-gallery-21.svg`・`.png`ができます。
入力形式やページ数によって出力先を変えず、ファイル名で入力とページを区別します。
背景は透明、余白は16px、SVGはフォント埋め込み、PNGは2倍の解像度が標準です。
PNGは完成したSVGから描画するため、両形式で配置とフォントが揃います。

draw.ioは標準で全ページを出力し、`--page`で1ページに限定できます。
複数ページの出力名には`-01`・`-02`のようなページ番号が付きます。選択した場合も元のページ番号を維持します。
既存ファイルは上書きしません。更新するときは`--force`を指定してください。
イメージ操作のオプションはビルドスクリプトと共通です。

Mermaidはスライドと同じ設定・源暎エムゴを使い、通常文字はRegular（400）、グループ見出しと太字はMedium（500）にします。
手書き風などの指定は入力ファイルのfrontmatterに書けます。
draw.ioは図側の配置とフォント設定を使います。サンプルの通常文字はMedium（500）、太字はBold（700）です。
SVGにはMermaidでRegular/Medium、draw.ioでRegular/Medium/Boldを埋め込みます。
描画中はネットワークに接続しません。外部画像は図に埋め込み、フォントはコンテナにあるものを指定してください。

### draw.ioの作例

`samples/diagram-gallery.drawio`には、貸出予約サービスを題材にした20種類の図、受注処理、段階的リリースのフローチャートを合わせた22ページを収録しています。
VS Codeのdraw.io拡張ではページを切り替えて編集できます。
人物・日付・数値は架空の例です。ガントは担当・開始終了日・進捗・先行条件・承認ゲート、WBSは成果物・責任者・完了条件、カンバンは着手条件・WIP上限・経過日数・完了条件を含みます。

| ページ | 図 | 説明する内容 |
| --- | --- | --- |
| 1 | システム構成図 | 利用者・画面・API・DB・通知処理のつながり |
| 2 | シーケンス図 | 予約受付時の呼び出しと応答の順番 |
| 3 | ER図 | 利用者・書誌・資料個体・予約・貸出・通知の関連 |
| 4 | 状態遷移図 | 待ち・準備・受取と、取消・期限切れの状態とイベント |
| 5 | マインドマップ | 利用者・スタッフ・運用・データの検討事項 |
| 6 | 組織図 | チームの責任と担当範囲 |
| 7 | 作業分解図 | 成果物・責任者・完了条件 |
| 8 | スイムレーン図 | 担当者間の引き継ぎと例外処理 |
| 9 | ユースケース図 | 利用者の目的とサービスの境界 |
| 10 | クラス図 | 属性・操作・関連 |
| 11 | データフロー図 | 入力・記録・参照の流れ |
| 12 | ネットワーク図 | 接続とネットワークの分離 |
| 13 | 配置図 | ホストと実行するプロセス |
| 14 | ロードマップ | 公開範囲と目標の段階 |
| 15 | ガントチャート | 作業期間・担当・進捗・依存関係 |
| 16 | カンバンボード | 作業の状態・上限・滞留 |
| 17 | カスタマージャーニー | 行動・感情の理由・改善の優先度・担当と指標 |
| 18 | 判断ツリー | 問い合わせへの対応の選択 |
| 19 | 故障の木解析 | 障害の原因と観測・対策 |
| 20 | ワイヤーフレーム | 画面の情報と操作の配置 |
| 21 | フローチャート | 受注・在庫確認・決済・出荷・通知の流れ |
| 22 | 段階的リリース | 並行検証・承認者の分岐・段階的公開・切り戻し・再申請 |

22ページ目は`release-process.mmd`と同様のリリース手順を、draw.io向けに配置した例です。
主経路を中央、差し戻しと切り戻しを左右に置き、2系統の検証の並行実行と合流を横棒で示しています。

```bash
./scripts/render-diagram.sh --page 22 samples/diagram-gallery.drawio
```

白を基調にした図形、黒い線、控えめな角丸と影、源暎エムゴ500／700を共通にしています。注意が必要な状態には低彩度の色を使い、同じ役割の要素は形と装飾を揃えています。
出力範囲と配置は各図の用途に合わせて決まります。単体で共有しても対象が分かるように、図名・対象範囲は必要に応じて見出し、中心のテーマ、システム境界などに記します。
凡例・基準日・制約・判断条件は残し、関連線、該当作業、画面の外側など、読み手が必要とする場所に置きます。全図に同じ見出し・補足見出し・フッターの配置を当てはめることはしません。
大きい囲み枠とER図のカードは固定の角丸にし、図形が大きくても角丸を大きくしません。
矢印や関連の記号は図の種類に合わせ、シーケンス図の直線やER図の多重度は維持します。
カスタマージャーニーの感情は未調査の仮説として言葉と理由を記し、数値の折れ線にはしていません。
故障の木解析は論理ゲートを文字で表記した簡略図です。原因の網羅性や発生確率は検証対象として明記しています。

```bash
./scripts/render-diagram.sh --page 3 samples/diagram-gallery.drawio
./scripts/render-diagram.sh --page 15 samples/diagram-gallery.drawio
```

記法と内容の参考：[Mermaidのガント](https://mermaid.js.org/syntax/gantt.html)、[PMIのWBS解説](https://www.pmi.org/learning/library/practice-standard-work-breakdown-structures-8063)、[Kanban Guide](https://kanbanguides.org/the-kanban-guide/)、[NN/gのジャーニーマップ解説](https://www.nngroup.com/articles/journey-mapping-101/)、[draw.ioのDFD解説](https://www.drawio.com/docs/diagram-types/data-flow-diagrams/)。作例はこれらの図を複製したものではなく、このリポジトリ用に作成しています。
ER図・シーケンス図・原因分析では、[draw.ioの多重度の記法](https://www.drawio.com/docs/tutorials/crows-foot-notation/)、[シーケンス図の解説](https://www.drawio.com/docs/diagram-types/uml/sequence-diagrams/)、[NASAのFault Tree Handbook（PDF）](https://s3vi.ndc.nasa.gov/ssri-kb/static/resources/Fault%20Tree%20Handbook_NASA.pdf)も参照しています。

### 図の画質・サイズ・共有方法を指定する

PNGは可逆圧縮のためJPEGのような品質値は設けず、描画倍率で精細さを調整します。
標準は2倍です。`--scale 3`なら、同じ配置のままSVGの自然寸法に対して縦横を約3倍の画素数で描画します。
固定の横幅が必要なら`--png-width 1600`のように画素数を指定できます。縦横比は維持します。
倍率と固定幅はどちらか一方を指定します。SVGはベクター形式なので、このPNGの設定には影響されません。

| オプション | 用途 |
| --- | --- |
| `--output DIR` | 出力ディレクトリ |
| `--format both\|svg\|png` | 必要な形式を選択。標準は両方 |
| `--scale N` | PNGの描画倍率。正の数。標準は2 |
| `--png-width PX` | PNGの横幅を画素数で指定。`--scale`とは併用不可 |
| `--background COLOR` | CSSの色指定。`transparent`、`white`、`#f5f5f5`、`rgba(...)`など |
| `--no-embed-fonts` | 軽量なSVGを出力。閲覧側に使用フォントが必要。PNGの見た目は維持 |
| `--force` | 既存の成果物を上書き。指定しない場合は上書きしない |
| `--page N` | draw.ioのページ選択。1から数える。標準は全ページ |
| `--padding PX` | 両形式に共通の余白。標準は16 |

フォントを埋め込むSVGは大きくなるため、相手に同じフォントがある場合は埋め込みを省略できます。

```bash
# 通常の2倍出力より精細な、白背景のPNG。既存の画像を更新する。
./scripts/render-diagram.sh --format png --scale 3 --background white --force samples/release-process.mmd

# 半透明の背景を指定する。SVG・PNGとも透明度を維持する。
./scripts/render-diagram.sh --background 'rgba(240,245,250,0.5)' --output out/previews/diagram-preview samples/release-process.mmd

# draw.ioの2ページ目を幅1600pxのPNGへ。縦横比は維持する。
./scripts/render-diagram.sh --page 2 --png-width 1600 samples/diagram-gallery.drawio

# 同じフォントがある環境へ共有する、フォントを埋め込まないSVG。
./scripts/render-diagram.sh --format svg --page 21 --no-embed-fonts --force samples/diagram-gallery.drawio
```

すべてのオプションは`./scripts/render-diagram.sh --help`で確認できます。
入力ディレクトリは読み取り専用でマウントし、選択した全ページの描画に成功してから成果物を公開します。

### CIでPDFを取得する

PR、`main` へのpush、および手動実行で、コンポーネント一覧とサンプルをビルドします。
GitHubの **Actions → Build slides → 実行結果 → Artifacts → slide-pdfs** からPDFを取得できます。
文字を選択できるPDFを14日間保存します。ダウンロードにはGitHubへのログインとリポジトリの読み取り権限が必要です。
CIの実行環境は毎回新しいため、イメージは各実行の初回にビルドします。同じ実行内のサンプルでは再利用します。

### 注意

- コンテナイメージの初回構築には、依存関係とフォントを取得するためネットワーク接続が必要です。
- フォントは生成 HTML に埋め込まれるため、閲覧時に外部から取得する必要はありません。
- 通常の絵文字は文字として描画し、外部CDNから画像を取得しません。HTMLでの絵文字の字形は閲覧環境によって変わります。
- ベースイメージはdigest、Chrome for Testing・Pythonの直接依存はバージョンを固定しています。Chromeと取得するフォントはチェックサムも検証します。更新時は `Containerfile` の対応する値を変更してください。
- OSパッケージと推移的依存は完全には固定していないため、再ビルドがバイト単位で同一になる保証はありません。
- git clone で取得した場合、実行権限はすでに付与されています。別の方法で取得した場合は `chmod +x scripts/build.sh` を実行してください。

## ライセンス

本リポジトリのコード、テーマ、ドキュメント、サンプル、画像およびアイコンは [MIT License](LICENSE) で公開しています。
取得するフォントには各配布元のライセンスが適用され、本リポジトリの MIT License には含まれません。

draw.io DesktopもMITの対象には含まれず、[GPL v3](https://github.com/jgraph/drawio-desktop/blob/v32.3.0/LICENSE)です。公式パッケージをビルド時に取得し、独立したコマンドとして実行します。自作の図や本リポジトリのスクリプトに、利用しただけでGPLが適用されることはありません。
Desktopを含むコンテナイメージを再配布する場合は、GPLに従ってライセンスと対応するソースコードを提供してください。固定バージョンのソースは[公式リポジトリ](https://github.com/jgraph/drawio-desktop/tree/v32.3.0)にあります。

- [源暎エムゴ](https://okoneya.jp/font/genei-m-gothic.html)、[Rounded Noto Code](https://github.com/sakikuroe/rounded-noto-sans-cjk/tree/v0.2.0)、Noto Sans JP / Noto CJK、IBM Plex Sans JP: SIL Open Font License 1.1。
- 源暎エムゴと Rounded Noto Code は、著作権表示・OFL 1.1 の宣言・ライセンスURLをフォント内に保持しています。VS Code用のコピーとHTML・SVGへの埋め込みでは元のフォントをそのまま使い、この情報を維持します。
- OFL フォントを使用して作成した PDF やスライド自体に、OFL を適用する必要はありません。詳細は [OFL の公式 FAQ](https://openfontlicense.org/ofl-faq/) を参照してください。
