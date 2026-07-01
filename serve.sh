#!/usr/bin/env bash
# marp-cli のサーバーモードで HTML をリアルタイムプレビューする.
# ファイルを変更するたびにブラウザが自動リロードされる.
# Ctrl+C で停止する.
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
input_dir="$(dirname "$rel_input")"

image="localhost/marp-template-kit/tools"

if ! podman info > /dev/null 2>&1; then
  echo "error: podman が利用できません. インストールと設定を確認してください." >&2
  exit 1
fi

podman build -q -t "$image" -f "$script_dir/Containerfile" "$script_dir" >&2

base="$(basename "${input%.*}")"
echo "preview: http://localhost:8080/${base}.md" >&2

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
  --engine /app/engine.mjs \
  --server \
  --allow-local-files
