#!/usr/bin/env bash
# スライドの引数と、全コマンドで共有するPodmanイメージ管理。

# スライド用CLIの検証結果をinputとimage_modeに返す。
# イメージ管理には渡された引数だけを使い、呼び出し元の変数には依存しない。
parse_slide_options() {
  image_mode=auto
  input=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skip-image-build|--rebuild-image)
        if [ "$image_mode" != auto ]; then
          echo 'error: イメージのオプションは1つだけ指定してください。' >&2
          return 2
        fi
        image_mode="$1" ;;
      -h|--help)
        printf 'usage: %s [--skip-image-build | --rebuild-image] <Markdown ファイル>\n' "$0"
        printf '%s\n' \
          '  通常: Containerfileが変わった場合、またはイメージがない場合にビルド' \
          '  --skip-image-build: 既存イメージを使用 (変更の確認も省略)' \
          '  --rebuild-image: キャッシュを使わずイメージを再ビルド' \
          '  --: 以降をファイル名として扱う'
        exit 0 ;;
      --)
        shift
        if [ "$#" -ne 1 ] || [ -n "$input" ]; then
          echo 'error: Markdownファイルは1つ指定してください。' >&2
          return 2
        fi
        input="$1"
        break ;;
      -*) echo "error: 不明なオプション: $1" >&2; return 2 ;;
      *)
        if [ -n "$input" ]; then
          echo 'error: Markdownファイルは1つ指定してください。' >&2
          return 2
        fi
        input="$1" ;;
    esac
    shift
  done
  if [ -z "$input" ]; then
    echo "usage: $0 [--skip-image-build | --rebuild-image] <Markdown ファイル>" >&2
    return 2
  fi
}

# Markdownは/appへマウントするリポジトリ内にある必要がある。
# ホストに存在してもコンテナに届かない入力を、ビルド開始前に拒否する。
# markdown_path <リポジトリの絶対パス> <入力パス> → リポジトリからの相対パス
markdown_path() {
  local project_dir="$1" input="$2" relative
  case "$input" in
    *.md|*.markdown) ;;
    *) echo 'error: 入力は.mdまたは.markdownを指定してください。' >&2; return 2 ;;
  esac
  if [ ! -f "$input" ]; then echo "not found: $input" >&2; return 2; fi
  relative="$(realpath --relative-to="$project_dir" -- "$input")" || return
  case "$relative" in
    ..|../*) echo 'error: Markdownはリポジトリ内に置いてください。' >&2; return 2 ;;
  esac
  printf '%s\n' "$relative"
}

# ensure_tools_image <リポジトリの絶対パス> <auto|--skip-image-build|--rebuild-image>
# 使用できるイメージ名を標準出力へ返す。進捗は標準エラーへ出す。
# Containerfileのハッシュが同じならpodman buildを起動しない。
ensure_tools_image() {
  local project_dir="$1" mode="$2" image='localhost/marp-template-kit/tools'
  local container_hash stored_hash
  case "$mode" in
    auto|--skip-image-build|--rebuild-image) ;;
    *) echo "error: 不明なイメージモード: $mode" >&2; return 2 ;;
  esac
  if ! podman info > /dev/null 2>&1; then
    echo 'error: podmanが利用できません。インストールと設定を確認してください。' >&2
    return 1
  fi
  if [ "$mode" = --skip-image-build ]; then
    if ! podman image exists "$image"; then
      echo 'error: 既存イメージがありません。オプションなしで実行してください。' >&2
      return 1
    fi
  else
    container_hash="$(sha256sum "$project_dir/Containerfile")" || return
    container_hash="${container_hash%% *}"
    stored_hash="$(podman image inspect --format '{{index .Config.Labels "jp.marp-template-kit.containerfile-sha256"}}' "$image" 2>/dev/null || true)"
    if [ "$mode" = auto ] && [ "$stored_hash" = "$container_hash" ]; then
      echo 'image: 変更がないため既存イメージを使用します。' >&2
    else
      local build_options=()
      if [ "$mode" = --rebuild-image ]; then build_options+=(--no-cache); fi
      podman build -q "${build_options[@]}" \
        --label "jp.marp-template-kit.containerfile-sha256=$container_hash" \
        -t "$image" -f "$project_dir/Containerfile" "$project_dir" >&2 || return
    fi
  fi
  printf '%s\n' "$image"
}
