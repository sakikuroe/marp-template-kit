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

# 入力ファイルの絶対ディレクトリ・ファイル名・拡張子なしベース名を取得する.
# コンテナへのボリュームマウントや出力ファイル名の生成に使用する.
dir="$(cd "$(dirname "$input")" && pwd)"
file="$(basename "$input")"
base="${file%.*}"

# 使用するコンテナイメージを設定する.
# MARP_IMAGE 環境変数で marp-cli イメージを上書きできる (例: latest タグへの切り替え).
# img2pdf イメージはこのリポジトリの Containerfile からビルドしたローカルイメージを使用する.
image="${MARP_IMAGE:-docker.io/marpteam/marp-cli:v4.3.1}"
img2pdf_image="localhost/marp-template-kit/img2pdf:v1"
# テーマの解決をスクリプトの置き場所基準にするため, スクリプト自身のディレクトリを取得する.
# $0 ではなく ${BASH_SOURCE[0]} を使うことで, source 経由でも正しく動作する.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Podman デーモン (またはサービス) が起動しているかを確認する.
# 起動していない場合はコンテナを実行できないため, ここで早期終了する.
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
    --network=host \
    -v "$dir:/home/marp/app" \
    -v "$script_dir/themes:/home/marp/themes:ro" \
    -e "LANG=${LANG:-C.UTF-8}" \
    -e "MARP_USER=$(id -u):$(id -g)" \
    "$image" "$@" 2>&1) || { rc=$?; printf '%s\n' "$output" >&2; return $rc; }
  printf '%s\n' "$output" | grep -Ev '\[  WARN \] Insecure local file|^ +\S+\.md$' >&2 || true
}

# 出力ディレクトリを事前に作成する.
mkdir -p "$dir/out"

# HTML を生成する.
run_marp "$file" --theme-set /home/marp/themes/modern.css -o "out/${base}.html" --allow-local-files

# PDF を生成する.
# marp-cli の PDF 出力では backdrop-filter が Chromium の PDF エクスポートパイプラインで
# 描画されないため, PNG 経由で変換する (Chromium Issue #41477207).
# 1. marp-cli でスライドを PNG に書き出す (スクリーンショット経由で backdrop-filter が正しく描画される).
# 2. img2pdf で PNG を PDF に変換する.
mkdir -p "$dir/out/.cache"
# 前回ビルドの古い PNG を削除してから再生成する.
# 削除しないとスライド枚数が減ったとき古いファイルが残り, img2pdf に混入する.
rm -f "$dir/out/.cache/${base}".*.png
run_marp "$file" --theme-set /home/marp/themes/modern.css \
  --images png -o "out/.cache/${base}.png" --allow-local-files
# img2pdf イメージがローカルに存在しない場合は Containerfile からビルドする.
if ! podman image exists "$img2pdf_image"; then
  podman build -t "$img2pdf_image" -f "$script_dir/Containerfile" "$script_dir" >&2
fi
# 生成された PNG ファイルを数値順 (ls -v) にソートして配列に格納する.
# sed でホスト側絶対パスをコンテナ内マウントパス (/out/.cache/...) に変換する.
# img2pdf はページ順に PNG を結合するため, 順序の保証が必要.
mapfile -t png_args < <(ls -v "$dir/out/.cache/${base}".*.png | sed 's|.*/|/out/.cache/|')
# ホスト out/ ディレクトリをコンテナ内 /out にマウントして img2pdf を実行する.
# --userns=keep-id: rootless Podman でホストの UID をコンテナ内に引き継ぎ, 出力ファイルのオーナーをホストユーザーに保つ.
# --network=none: img2pdf はネットワーク不要のため, 外部通信を遮断してセキュリティリスクを下げる.
# -e HOME=/tmp: img2pdf が内部で HOME に書き込もうとするため, 書き込み可能な /tmp を渡す.
# --pagesize 2880ptx1620pt: 4K キャンバス (3840×2160px) の 0.75 倍 (= pt 換算) を指定し,
#   PDF のページサイズを 3x キャンバスに合わせる.
podman run --rm --init \
  --userns=keep-id \
  --network=none \
  -e HOME=/tmp \
  -v "$dir/out:/out" \
  "$img2pdf_image" \
  --pagesize 2880ptx1620pt \
  "${png_args[@]}" \
  -o "/out/${base}.pdf"
