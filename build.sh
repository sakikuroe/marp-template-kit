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

dir="$(cd "$(dirname "$input")" && pwd)"
file="$(basename "$input")"
base="${file%.*}"

image="${MARP_IMAGE:-docker.io/marpteam/marp-cli:v4.3.1}"
# テーマの解決をスクリプトの置き場所基準にするため, スクリプト自身のディレクトリを取得する.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! podman info > /dev/null 2>&1; then
  echo "error: podman が利用できません. インストールと設定を確認してください." >&2
  exit 1
fi

# 入力ファイルのディレクトリとテーマディレクトリをコンテナにマウントして marp-cli を実行する.
run_marp() {
  # --userns=keep-id: rootless Podman でホストの UID をコンテナ内に引き継ぐ.
  # --allow-local-files 使用時に marp-cli が出す WARN をフィルタする.
  # 出力をバッファして podman のエラーコードを正しく伝播する.
  local output rc
  output=$(podman run --rm --init \
    --userns=keep-id \
    --network=none \
    -v "$dir:/home/marp/app" \
    -v "$script_dir/themes:/home/marp/themes:ro" \
    -e "LANG=${LANG:-C.UTF-8}" \
    -e "MARP_USER=$(id -u):$(id -g)" \
    "$image" "$@" 2>&1) || { rc=$?; printf '%s\n' "$output" >&2; return $rc; }
  printf '%s\n' "$output" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md\.$' >&2 || true
}

mkdir -p "$dir/out"

# HTML を生成する.
run_marp "$file" --theme-set /home/marp/themes/modern.css -o "out/${base}.html" --allow-local-files

# PDF を生成する.
# marp-cli の PDF 出力では backdrop-filter が Chromium の PDF エクスポートパイプラインで
# 描画されないため, PNG 経由で変換する (Chromium Issue #41477207).
# 1. marp-cli でスライドを PNG に書き出す (スクリーンショット経由で backdrop-filter が正しく描画される).
# 2. img2pdf で PNG を PDF に変換する.
# ページサイズ 2880pt × 1620pt = 4K キャンバス (3840×2160px) を 0.75 倍した PDF 単位.
mkdir -p "$dir/out/.cache"
# 前回ビルドの古い PNG を削除してから再生成する.
# 削除しないとスライド枚数が減ったとき古いファイルが残り, img2pdf に混入する.
rm -f "$dir/out/.cache/${base}".*.png
run_marp "$file" --theme-set /home/marp/themes/modern.css \
  --images png -o "out/.cache/${base}.png" --allow-local-files
# img2pdf をコンテナ内で実行する. ページサイズ 2880pt × 1620pt = 4K キャンバスの 0.75 倍.
podman run --rm --init \
  --userns=keep-id \
  --network=host \
  -e HOME=/tmp \
  -v "$dir/out:/out" \
  docker.io/python:3-slim \
  sh -c "pip install img2pdf --quiet --no-cache-dir --no-warn-script-location && \
         python3 -m img2pdf --pagesize 2880ptx1620pt \
           \$(ls -v /out/.cache/*.png) \
           -o /out/${base}.pdf"
