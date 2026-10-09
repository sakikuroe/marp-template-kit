#!/usr/bin/env bash
# marp-cli のサーバーモードで HTML をリアルタイムプレビューする。
# ファイルを変更するたびにブラウザが自動リロードされる。
# Ctrl+C で停止する。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$script_dir/scripts/container.sh"
parse_slide_options "$@"

rel_input="$(markdown_path "$script_dir" "$input")"
input_dir="$(dirname "$rel_input")"

image="$(ensure_tools_image "$script_dir" "$image_mode")"

filename="$(basename -- "$rel_input")"
echo "preview: http://localhost:8080/$filename" >&2

podman run --rm --init \
  --userns=keep-id \
  --network=host \
  -v "$script_dir:/app" \
  -v "$script_dir/themes:/themes:ro" \
  -e "LANG=${LANG:-C.UTF-8}" \
  -e "NODE_PATH=/home/marp/.cli/node_modules" \
  -e "MARP_INPUT_DIR=/app/${input_dir}" \
  --entrypoint node \
  "$image" /home/marp/.cli/marp-cli.js \
  "/app/${input_dir}" \
  --theme-set /themes/modern.css \
  --engine /app/scripts/engine.mjs \
  --server \
  --allow-local-files
