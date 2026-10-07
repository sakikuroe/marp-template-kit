#!/usr/bin/env bash
# build.sh と serve.sh の引数・イメージ管理。呼び出し元で script_dir を設定する。

parse_container_options() {
  image_mode=auto
  input=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skip-image-build|--rebuild-image)
        if [ "$image_mode" != auto ]; then
          echo 'error: イメージのオプションは1つだけ指定してください.' >&2
          return 2
        fi
        image_mode="$1"
        ;;
      -h|--help)
        printf 'usage: %s [--skip-image-build | --rebuild-image] <Markdown ファイル>\n' "$0"
        printf '%s\n' \
          '  通常: Containerfileが変わった場合、またはイメージがない場合にビルド' \
          '  --skip-image-build: 既存イメージを使用 (変更の確認も省略)' \
          '  --rebuild-image: キャッシュを使わずイメージを再ビルド' \
          '  --: 以降をファイル名として扱う'
        exit 0
        ;;
      --)
        shift
        if [ "$#" -ne 1 ] || [ -n "$input" ]; then
          echo "usage: $0 [--skip-image-build | --rebuild-image] <Markdown ファイル>" >&2
          return 2
        fi
        input="$1"
        break
        ;;
      -*)
        echo "error: 不明なオプション: $1" >&2
        return 2
        ;;
      *)
        if [ -n "$input" ]; then
          echo "error: Markdown ファイルは1つ指定してください." >&2
          return 2
        fi
        input="$1"
        ;;
    esac
    shift
  done
  if [ -z "$input" ]; then
    echo "usage: $0 [--skip-image-build | --rebuild-image] <Markdown ファイル>" >&2
    return 2
  fi
}

ensure_tools_image() {
  image="localhost/marp-template-kit/tools"
  local container_hash stored_hash
  container_hash="$(sha256sum "$script_dir/Containerfile")"
  container_hash="${container_hash%% *}"

  if [ "$image_mode" = --skip-image-build ]; then
    if ! podman image exists "$image"; then
      echo 'error: 既存イメージがありません. オプションなしで実行してください.' >&2
      return 1
    fi
    return 0
  fi

  stored_hash="$(podman image inspect --format '{{index .Config.Labels "jp.marp-template-kit.containerfile-sha256"}}' "$image" 2>/dev/null || true)"
  if [ "$image_mode" = auto ] && [ "$stored_hash" = "$container_hash" ]; then
    echo 'image: 変更がないため既存イメージを使用します.' >&2
    return 0
  fi

  local build_options=()
  if [ "$image_mode" = --rebuild-image ]; then
    build_options+=(--no-cache)
  fi
  podman build -q "${build_options[@]}" \
    --label "jp.marp-template-kit.containerfile-sha256=$container_hash" \
    -t "$image" -f "$script_dir/Containerfile" "$script_dir" >&2
}
