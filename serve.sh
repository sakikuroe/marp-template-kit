#!/usr/bin/env bash
# marp-cli のサーバーモードで HTML をリアルタイムプレビューする.
# ファイルを変更するたびにブラウザが自動リロードされる.
# Ctrl+C で停止する.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/scripts/container.sh"
parse_container_options "$@"

if [ ! -f "$input" ]; then
  echo "not found: $input" >&2
  exit 1
fi

rel_input="$(realpath --relative-to="$script_dir" "$input")"
input_dir="$(dirname "$rel_input")"

if ! podman info > /dev/null 2>&1; then
  echo "error: podman が利用できません. インストールと設定を確認してください." >&2
  exit 1
fi

ensure_tools_image

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
