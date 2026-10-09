#!/usr/bin/env bash
# 入力形式の判別・フォント・描画環境は内部で処理し、SVGとPNGをまとめて生成する。
# ホストにNode.jsは不要。不正なCLI引数はPodman起動前に拒否する。
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/scripts/container.sh"

usage() {
  printf 'usage: %s [オプション] <図.mmd|図.mermaid|図.drawio>\n' "$0"
  cat <<'HELP'
  標準: SVGとPNG、透明背景、周囲16px、PNG 2倍、SVGにフォント埋め込み
        draw.ioは全ページ。出力先はリポジトリ内のout/diagrams/<入力名>/
  --output DIR           出力ディレクトリ
  --format both|svg|png  出力形式。標準: both
  --page N               draw.ioの指定ページだけ出力。1から数える
  --scale N              PNGの描画倍率。正の数。標準: 2
  --png-width PX         PNGの横幅を指定し、縦横比を維持（--scaleとは併用不可）
  --padding PX           図の周囲の余白。0以上の数。標準: 16
  --background COLOR     CSSの色指定。標準: transparent
                         例: white、#f5f5f5、'rgba(255,255,255,0.5)'
  --no-embed-fonts        SVGのフォント埋め込みを省略（PNGの見た目は維持）
  --force                既存の成果物を上書きする
  --skip-image-build      既存のPodmanイメージを使い、変更確認を省く
  --rebuild-image         キャッシュを使わずPodmanイメージをビルドする
  --                     以降を入力ファイル名として扱う
  -h, --help             このヘルプを表示する
  出力名: <入力名>.svg/.png。複数ページは<入力名>-01.svg/.png、-02、…
HELP
}

fail() { echo "error: $*" >&2; exit 2; }
input= output= format=both page= scale=2 png_width= padding=16 background=transparent
image_mode=auto
scale_set=false
render_options=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output|--format|--page|--scale|--png-width|--padding|--background)
      [ "$#" -ge 2 ] && [[ "$2" != --* ]] || fail "$1 の値を指定してください。"
      option="$1" value="$2"
      case "$option" in
        --output) [ -n "$value" ] || fail '出力先を指定してください。'; output="$value" ;;
        --format) case "$value" in both|svg|png) format="$value";; *) fail '形式はboth、svg、pngです。';; esac ;;
        --page|--png-width)
          [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "$option は正の整数を指定してください。"
          if [ "$option" = --page ]; then page="$value"; else png_width="$value"; fi ;;
        --scale)
          [[ "$value" =~ ^([0-9]+(\.[0-9]*)?|\.[0-9]+)$ && "$value" =~ [1-9] ]] || fail '--scaleは正の数を指定してください。'
          scale="$value"; scale_set=true ;;
        --padding)
          [[ "$value" =~ ^([0-9]+(\.[0-9]*)?|\.[0-9]+)$ ]] || fail '--paddingは0以上の数を指定してください。'
          padding="$value" ;;
        --background)
          [ -n "$value" ] || fail '背景色を指定してください。'
          background="$value" ;;
      esac
      shift ;;
    --no-embed-fonts|--force) render_options+=("$1") ;;
    --skip-image-build|--rebuild-image)
      [ "$image_mode" = auto ] || fail 'イメージのオプションは1つだけ指定してください。'
      image_mode="$1" ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      [ "$#" -eq 1 ] && [ -z "$input" ] || fail '入力ファイルは1つ指定してください。'
      input="$1"; break ;;
    -*) fail "不明なオプション: $1" ;;
    *) [ -z "$input" ] || fail '入力ファイルは1つ指定してください。'; input="$1" ;;
  esac
  shift
done
[ -n "$input" ] || { usage >&2; exit 2; }
case "$input" in
  *.drawio) ;;
  *.mmd|*.mermaid) [ -z "$page" ] || fail '--pageはdraw.io専用です。' ;;
  *) fail '入力は.mmd、.mermaid、.drawioを指定してください。' ;;
esac
[ -f "$input" ] || fail "入力ファイルがありません: $input"
if [ -n "$png_width" ] && [ "$scale_set" = true ]; then fail '--png-widthと--scaleは併用できません。'; fi
if [ "$format" = svg ] && { [ -n "$png_width" ] || [ "$scale_set" = true ]; }; then fail 'PNGのサイズ指定にはPNG出力が必要です。'; fi
stem="$(basename -- "${input%.*}")"
output="${output:-$project_dir/out/diagrams/$stem}"
[ ! -e "$output" ] || [ -d "$output" ] || fail "出力先はディレクトリを指定してください: $output"

image="$(ensure_tools_image "$project_dir" "$image_mode")"
mkdir -p -- "$output"
input_dir="$(cd -- "$(dirname -- "$input")" && pwd)"
output_dir="$(cd -- "$output" && pwd)"
# 位置引数の長いリストではなく名前付きの設定を渡し、引数順への依存を避ける。
render_options+=(--format "$format" --scale "$scale" --padding "$padding" --background "$background")
if [ -n "$page" ]; then render_options+=(--page "$page"); fi
if [ -n "$png_width" ]; then render_options+=(--png-width "$png_width"); fi
# 入力・実装は読み取り専用。外部画像は入力に埋め込み、描画中は通信しない。
podman run --rm --init --userns=keep-id --user "$(id -u):$(id -g)" --network=none \
  --env XDG_CONFIG_HOME=/tmp/config --env XDG_CACHE_HOME=/tmp/cache \
  -v "$project_dir:/app:ro" -v "$input_dir:/input:ro" -v "$output_dir:/output" \
  --entrypoint node "$image" /app/scripts/diagram.mjs \
  --input "/input/$(basename -- "$input")" --output /output "${render_options[@]}"
echo "output: $output_dir"
