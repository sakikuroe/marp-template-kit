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

# サブディレクトリの Markdown からも共有リソース (icons, assets) への相対パスが解決できるよう,
# 常にプロジェクトルートをコンテナにマウントする.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rel_input="$(realpath --relative-to="$script_dir" "$input")"
base="$(basename "${input%.*}")"
output_dir="$(dirname "$rel_input")"

# MARP_IMAGE 環境変数でイメージを上書きできる.
image="${MARP_IMAGE:-localhost/marp-template-kit/tools:v2}"

if ! podman info > /dev/null 2>&1; then
  echo "error: podman が利用できません. インストールと設定を確認してください." >&2
  exit 1
fi

if ! podman image exists "$image"; then
  podman build -t "$image" -f "$script_dir/Containerfile" "$script_dir" >&2
fi

mkdir -p "$script_dir/.cache"

# HTML を生成する.
_out=$(podman run --rm --init \
  --userns=keep-id \
  --network=host \
  -v "$script_dir:/app" \
  -v "$script_dir/themes:/themes:ro" \
  -e "LANG=${LANG:-C.UTF-8}" \
  --entrypoint node \
  "$image" /home/marp/.cli/marp-cli.js \
  "$rel_input" \
  --theme-set /themes/modern.css \
  -o "${output_dir}/${base}.html" \
  --allow-local-files 2>&1) || { rc=$?; printf '%s\n' "$_out" >&2; exit "$rc"; }
printf '%s\n' "$_out" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md$' >&2 || true

# .pdf を生成する.
# --headless=new: Chrome 112+ 新ヘッドレスモード (印刷品質が旧より高い).
# --allow-file-access-from-files: file:/// URL からローカル assets を読み込む.
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
  --allow-file-access-from-files \
  --no-pdf-header-footer \
  --print-to-pdf="/app/${output_dir}/${base}.pdf" \
  "file:///app/${output_dir}/${base}.html"

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
  --entrypoint node \
  "$image" /home/marp/.cli/marp-cli.js \
  "$rel_input" \
  --theme-set /themes/modern.css \
  --images png \
  -o ".cache/${base}.png" \
  --allow-local-files 2>&1) || { rc=$?; printf '%s\n' "$_out" >&2; exit "$rc"; }
printf '%s\n' "$_out" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md$' >&2 || true

# ls -v で数値順にソートし, ホスト側パスをコンテナ内パスに変換して img2pdf に渡す.
# img2pdf はページ順に PNG を結合するため, 順序の保証が必要.
mapfile -t png_args < <(ls -v "$script_dir/.cache/${base}".*.png | sed "s|$script_dir|/app|")
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
  -o "/app/${output_dir}/${base}_png.pdf"
