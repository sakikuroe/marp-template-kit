#!/usr/bin/env bash
# Podman 経由で marp-cli を実行し, Markdown から HTML と PDF を生成する.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 main.md" >&2
  exit 2
fi

input="$1"

if [ ! -f "$input" ]; then
  echo "not found: $input" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rel_input="$(realpath --relative-to="$script_dir" "$input")"
base="$(basename "${input%.*}")"
input_dir="$(dirname "$rel_input")"

mkdir -p "$script_dir/out/htmls" "$script_dir/out/pdfs" "$script_dir/out/png_pdfs"

image="localhost/marp-template-kit/tools"
theme_path="/themes/modern.css"

if ! podman info > /dev/null 2>&1; then
  echo "error: podman が利用できません. インストールと設定を確認してください." >&2
  exit 1
fi

if [ "${MARP_SKIP_IMAGE_BUILD:-0}" != 1 ]; then
  podman build -q -t "$image" -f "$script_dir/Containerfile" "$script_dir" >&2
elif ! podman image exists "$image"; then
  echo "error: 既存イメージがありません. 最初に podman build を実行してください." >&2
  exit 1
fi

mkdir -p "$script_dir/.cache"

# VS Code 用にフォントを取り出し, 相対パスで参照するCSSとプレビュー用テーマを生成する.
# フォントの取得元はコンテナ内に統一し, 生成物は Git 管理外の .cache に置く.
podman run --rm --userns=keep-id --network=none \
  -v "$script_dir:/app" --entrypoint node "$image" -e '
    const fs = require("node:fs");
    const path = require("node:path");
    const fontDir = "/app/.cache/fonts";
    fs.mkdirSync(fontDir, { recursive: true });
    const sourceLicenses = "/usr/share/doc/marp-template-kit/font-licenses";
    const licenseDir = path.join(fontDir, "licenses");
    fs.mkdirSync(licenseDir, { recursive: true });
    for (const name of fs.readdirSync(sourceLicenses)) {
      fs.copyFileSync(path.join(sourceLicenses, name), path.join(licenseDir, name));
    }
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
  '

# HTML を生成する.
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
  --engine /app/engine.mjs \
  -o "out/htmls/${base}.html" \
  --allow-local-files 2>&1) || { rc=$?; printf '%s\n' "$_out" >&2; exit "$rc"; }
printf '%s\n' "$_out" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md$' >&2 || true

# .pdf を生成する.
# --headless=new: Chrome 112+ 新ヘッドレスモード (印刷品質が旧より高い).
# HTML は自己完結しているため --allow-file-access-from-files は不要.
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
  --print-to-pdf="/app/out/pdfs/${base}.pdf" \
  "file:///app/out/htmls/${base}.html"

# _png.pdf を生成する (PNG 経由).
# backdrop-filter が Chromium の PDF エクスポートパイプラインで描画されないため PNG 経由で変換する
# (Chromium Issue #41477207).
# スライド枚数が減ったとき古い PNG が img2pdf に混入しないよう, 再生成前に削除する.
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
  --engine /app/engine.mjs \
  --images png \
  -o ".cache/${base}.png" \
  --allow-local-files 2>&1) || { rc=$?; printf '%s\n' "$_out" >&2; exit "$rc"; }
printf '%s\n' "$_out" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md$' >&2 || true

# ls -v で数値順にソートし, ホスト側パスをコンテナ内パスに変換して img2pdf に渡す.
# img2pdf はページ順に PNG を結合するため, 順序の保証が必要.
mapfile -t png_args < <(ls -v "$script_dir/.cache/${base}".*.png | sed "s|^$script_dir|/app|")
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
