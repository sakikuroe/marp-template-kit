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

# スクリプトの置き場所をプロジェクトルートとして扱う.
# サブディレクトリの Markdown からも共有リソース (icons, assets) への相対パスが解決できるよう,
# 常にプロジェクトルートをコンテナの作業ディレクトリにマウントする.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 入力ファイルのプロジェクトルートからの相対パス・ファイル名・拡張子なしベース名を取得する.
input_abs="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
rel_input="$(realpath --relative-to="$script_dir" "$input_abs")"
file="$(basename "$input")"
base="${file%.*}"
dir="$script_dir"

# 使用するコンテナイメージを設定する.
# MARP_IMAGE 環境変数で marp-cli イメージを上書きできる (例: latest タグへの切り替え).
# img2pdf イメージはこのリポジトリの Containerfile からビルドしたローカルイメージを使用する.
image="${MARP_IMAGE:-docker.io/marpteam/marp-cli:v4.3.1}"
tools_image="localhost/marp-template-kit/tools:v1"

# Podman デーモン (またはサービス) が起動しているかを確認する.
# 起動していない場合はコンテナを実行できないため, ここで早期終了する.
if ! podman info > /dev/null 2>&1; then
  echo "error: podman が利用できません. インストールと設定を確認してください." >&2
  exit 1
fi

# プロジェクトルートとテーマディレクトリをコンテナにマウントして marp-cli を実行する.
run_marp() {
  # --userns=keep-id: rootless Podman でホストの UID をコンテナ内に引き継ぐ.
  # --allow-local-files 使用時に marp-cli が出す WARN をフィルタする.
  # 出力をバッファして podman のエラーコードを正しく伝播する.
  local output rc
  output=$(podman run --rm --init \
    --userns=keep-id \
    --network=host \
    -v "$dir:/home/marp/app" \
    -v "$script_dir/themes:/home/marp/themes:ro" \
    -e "LANG=${LANG:-C.UTF-8}" \
    -e "MARP_USER=$(id -u):$(id -g)" \
    "$image" "$@" 2>&1) || { rc=$?; printf '%s\n' "$output" >&2; return $rc; }
  printf '%s\n' "$output" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md$' >&2 || true
}

# PNG キャッシュディレクトリをプロジェクトルートに作成する.
mkdir -p "$dir/.cache"

# HTML を生成する.
# 出力先を入力 Markdown と同じディレクトリにすることで, assets/ への相対パスが正しく解決される.
output_dir="$(dirname "$rel_input")"
run_marp "$rel_input" --theme-set /home/marp/themes/modern.css \
  -o "${output_dir}/${base}.html" --allow-local-files

# .pdf を生成する (Google Chrome stable でブラウザ印刷を再現).
# --headless=new: Chrome 112 以降の新ヘッドレスモード (印刷品質が旧 --headless より高い).
# --no-pdf-header-footer: URL・日付のヘッダー/フッターを出力しない.
# --allow-file-access-from-files: file:/// URL からローカル assets を読み込めるようにする.
# tools イメージがローカルに存在しない場合は Containerfile からビルドする.
if ! podman image exists "$tools_image"; then
  podman build -t "$tools_image" -f "$script_dir/Containerfile" "$script_dir" >&2
fi
podman run --rm --init \
  --userns=keep-id \
  --network=host \
  -v "$dir:/app" \
  --entrypoint google-chrome \
  "$tools_image" \
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
# marp-cli の PDF 出力では backdrop-filter が Chromium の PDF エクスポートパイプラインで
# 描画されないため, PNG 経由で変換する (Chromium Issue #41477207).
# 1. marp-cli でスライドを PNG に書き出す (スクリーンショット経由で backdrop-filter が正しく描画される).
# 2. img2pdf で PNG を PDF に変換する.
# 前回ビルドの古い PNG を削除してから再生成する.
# 削除しないとスライド枚数が減ったとき古いファイルが残り, img2pdf に混入する.
rm -f "$dir/.cache/${base}".*.png
run_marp "$rel_input" --theme-set /home/marp/themes/modern.css \
  --images png -o ".cache/${base}.png" --allow-local-files
# 生成された PNG ファイルを数値順 (ls -v) にソートして配列に格納する.
# sed でホスト側絶対パスをコンテナ内マウントパス (/app/.cache/...) に変換する.
# img2pdf はページ順に PNG を結合するため, 順序の保証が必要.
mapfile -t png_args < <(ls -v "$dir/.cache/${base}".*.png | sed "s|$dir|/app|")
# プロジェクトルートをコンテナ内 /app にマウントして img2pdf を実行する.
# --userns=keep-id: rootless Podman でホストの UID をコンテナ内に引き継ぎ, 出力ファイルのオーナーをホストユーザーに保つ.
# --network=none: img2pdf はネットワーク不要のため, 外部通信を遮断してセキュリティリスクを下げる.
# -e HOME=/tmp: img2pdf が内部で HOME に書き込もうとするため, 書き込み可能な /tmp を渡す.
# --pagesize 2880ptx1620pt: 4K キャンバス (3840×2160px) の 0.75 倍 (= pt 換算) を指定し,
#   PDF のページサイズを 3x キャンバスに合わせる.
podman run --rm --init \
  --userns=keep-id \
  --network=none \
  -e HOME=/tmp \
  -v "$dir:/app" \
  --entrypoint python3 \
  "$tools_image" \
  -m img2pdf \
  --pagesize 2880ptx1620pt \
  "${png_args[@]}" \
  -o "/app/${output_dir}/${base}_png.pdf"
