#!/usr/bin/env bash
# Podman 経由で marp-cli を実行し、Markdown から HTML と PDF を生成する。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$script_dir/scripts/container.sh"
parse_slide_options "$@"

# エンジンがプレビュー用のエラー表示を返しても、ビルドでは失敗として扱う。
report_marp_output() {
  printf '%s\n' "$1" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md$' >&2 || true
  if [[ "$1" =~ (^|$'\n')\[(mermaid|matplotlib)\] ]]; then
    echo 'error: スライド内の図を描画できませんでした。' >&2
    return 1
  fi
}

rel_input="$(markdown_path "$script_dir" "$input")"
base="$(basename -- "${input%.*}")"
input_dir="$(dirname "$rel_input")"

mkdir -p "$script_dir/out/htmls" "$script_dir/out/pdfs" "$script_dir/out/png_pdfs"

theme_path="/themes/modern.css"

image="$(ensure_tools_image "$script_dir" "$image_mode")"

mkdir -p "$script_dir/.cache"

# VS Code 用にフォントを取り出し、相対パスで参照するCSSとプレビュー用テーマを生成する。
# フォントの取得元はコンテナ内に統一し、生成物は Git 管理外の .cache に置く。
html_url=$(podman run --rm --userns=keep-id --network=none \
  -v "$script_dir:/app" --entrypoint node "$image" -e '
    const fs = require("node:fs");
    const path = require("node:path");
    const { pathToFileURL } = require("node:url");
    const fontDir = "/app/.cache/fonts";
    fs.mkdirSync(fontDir, { recursive: true });
    const mime = { ".ttf": "font/ttf", ".otf": "font/otf", ".png": "image/png" };
    const urls = /url\(([\x27\x22]?)([^\x27\x22)]+)\1\)/g;
    const faces = [];
    const theme = fs.readFileSync("/app/themes/modern.css", "utf8").replace(
      /@font-face\s*\{[^}]*\}/g,
      (face) => {
        faces.push(face.replace(urls, (match, quote, src) => {
          const file = path.resolve("/app", src);
          const name = path.basename(file);
          fs.copyFileSync(file, path.join(fontDir, name));
          return `url("${name}")`;
        }));
        return "";
      }
    );
    fs.writeFileSync(path.join(fontDir, "fonts.css"), faces.join("\n\n"));
    const css = theme.replace(
      /url\(([\x27\x22]?)([^\x27\x22)]+)\1\)/g,
      (match, quote, src) => {
        if (/^(https?:|data:)/.test(src)) return match;
        const file = path.resolve("/app", src);
        const type = mime[path.extname(file).toLowerCase()];
        if (!type || !fs.existsSync(file)) throw new Error(`Cannot embed preview asset: ${src}`);
        return `url("data:${type};base64,${fs.readFileSync(file).toString("base64")}")`;
      }
    );
    fs.writeFileSync("/app/.cache/modern-preview.css", css);
    // #や%を含む名前も、ChromeへファイルURLとして正しく渡す。
    process.stdout.write(pathToFileURL(process.argv[1]).href);
  ' "/app/out/htmls/${base}.html")

# HTML を生成する。
_out=$(podman run --rm --init \
  --userns=keep-id \
  --network=host \
  -v "$script_dir:/app" \
  -v "$script_dir/themes:/themes:ro" \
  -e "LANG=${LANG:-C.UTF-8}" \
  -e "NODE_PATH=/home/marp/.cli/node_modules" \
  -e "MARP_INPUT_DIR=/app/${input_dir}" \
  --entrypoint node \
  "$image" /home/marp/.cli/marp-cli.js \
  "$rel_input" \
  --theme-set "$theme_path" \
  --engine /app/scripts/engine.mjs \
  -o "out/htmls/${base}.html" \
  --allow-local-files 2>&1) || { rc=$?; printf '%s\n' "$_out" >&2; exit "$rc"; }
report_marp_output "$_out"

# .pdf を生成する。
# --headless=new: Chrome 112+ 新ヘッドレスモード (印刷品質が旧より高い)。
# HTML は自己完結しているため --allow-file-access-from-files は不要。
# Chromeは読み込み失敗でも成功終了することがあるため、一時PDFの生成を確認する。
pdf_tmp="$(mktemp "$script_dir/out/pdfs/.pdf.XXXXXX")"
trap 'rm -f -- "$pdf_tmp"' EXIT
podman run --rm --init \
  --userns=keep-id \
  --network=host \
  -v "$script_dir:/app" \
  --entrypoint google-chrome \
  "$image" \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --disable-setuid-sandbox \
  --disable-dev-shm-usage \
  --no-pdf-header-footer \
  --print-to-pdf="/app/out/pdfs/$(basename -- "$pdf_tmp")" \
  "$html_url"
if [ ! -s "$pdf_tmp" ]; then
  echo 'error: PDFが生成されませんでした。' >&2
  exit 1
fi
mv -- "$pdf_tmp" "$script_dir/out/pdfs/${base}.pdf"

# _png.pdf を生成する (PNG 経由)。
# backdrop-filter が Chromium の PDF エクスポートパイプラインで描画されないため PNG 経由で変換する
# (Chromium Issue #41477207)。
# スライド枚数が減ったとき古い PNG が img2pdf に混入しないよう、再生成前に削除する。
rm -f "$script_dir/.cache/${base}".*.png
_out=$(podman run --rm --init \
  --userns=keep-id \
  --network=host \
  -v "$script_dir:/app" \
  -v "$script_dir/themes:/themes:ro" \
  -e "LANG=${LANG:-C.UTF-8}" \
  -e "NODE_PATH=/home/marp/.cli/node_modules" \
  -e "MARP_INPUT_DIR=/app/${input_dir}" \
  --entrypoint node \
  "$image" /home/marp/.cli/marp-cli.js \
  "$rel_input" \
  --theme-set "$theme_path" \
  --engine /app/scripts/engine.mjs \
  --images png \
  -o ".cache/${base}.png" \
  --allow-local-files 2>&1) || { rc=$?; printf '%s\n' "$_out" >&2; exit "$rc"; }
report_marp_output "$_out"

# ファイル名を行や正規表現として解釈せず、数値順でimg2pdfへ渡す。
# 空白や角括弧を含む名前でも、パス変換とページ順が壊れないようにする。
shopt -s nullglob
png_paths=( "$script_dir/.cache/${base}".*.png )
if [ "${#png_paths[@]}" -eq 0 ]; then
  echo 'error: スライドのPNGが生成されませんでした。' >&2
  exit 1
fi
mapfile -d '' -t png_paths < <(printf '%s\0' "${png_paths[@]}" | sort -zV)
png_args=()
for png in "${png_paths[@]}"; do png_args+=("/app/.cache/$(basename -- "$png")"); done
podman run --rm --init \
  --userns=keep-id \
  --network=none \
  -e HOME=/tmp \
  -v "$script_dir:/app" \
  --entrypoint python3 \
  "$image" \
  -m img2pdf \
  --pagesize 2880ptx1620pt \
  "${png_args[@]}" \
  -o "/app/out/png_pdfs/${base}.pdf"
