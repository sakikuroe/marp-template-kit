#!/usr/bin/env bash
# ビルド・図の変換スクリプトの引数とイメージ管理。
# 呼び出し元で script_dir をリポジトリの絶対パスに設定してからsourceする。

# 図の出力条件は2つの変換スクリプトで共通にする。
# 各描画ツールへの翻訳は呼び出し元に残し、幅・高さの意味の違いを隠さない。
diagram_usage() {
  printf 'usage: %s [オプション] <入力ファイル> <出力.svg|出力.png>\n' "$0"
  cat <<'HELP'
  --scale N              PNGの描画倍率。正の数。標準: 2（SVGには指定不可）
  --background COLOR     transparent または white。標準: transparent
  --no-embed-fonts        SVGのフォント埋め込みを省略し、ファイルを小さくする
                         閲覧側にも使用フォントが必要。PNGには指定不可
  --force                既存の出力ファイルを上書きする
  --skip-image-build      変更確認を省略して既存のPodmanイメージを使う
  --rebuild-image         キャッシュを使わずPodmanイメージをビルドする
  --                     以降をファイル名として扱う
  -h, --help             このヘルプを表示する
HELP
  if [ "$diagram_kind" = mermaid ]; then
    cat <<'HELP'
  --width PX             ブラウザの描画領域の幅。標準: 700
  --height PX            ブラウザの描画領域の高さ。標準: 600
                         折り返し・配置に影響する。出力は図の範囲に切り出す
HELP
  else
    cat <<'HELP'
  --width PX             縦横比を保って図を指定幅に収める
  --height PX            縦横比を保って図を指定高さに収める
                         幅と高さの同時指定、および--scaleとの併用は不可
  --page N               出力するページ。1から数える。標準: 1
  --border PX            図の周囲の余白。0以上の整数。標準: 16
HELP
  fi
}

# 不正な引数はイメージのビルド前に拒否する。evalを使わず配列で保持するため、
# 空白やシェルの特殊文字が入ったファイル名も、コマンドとして解釈されない。
parse_diagram_options() {
  diagram_kind="$1"
  shift
  image_mode=auto
  scale=2
  scale_set=false
  width=
  height=
  background=transparent
  embed_fonts=true
  force=false
  page=1
  border=16
  if [ "$diagram_kind" = mermaid ]; then width=700; height=600; fi
  local files=() option value
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scale|--width|--height|--background|--page|--border)
        option="$1"
        if [ "$#" -lt 2 ]; then
          echo "error: $option の値を指定してください。" >&2
          return 2
        fi
        value="$2"
        case "$option" in
          --scale)
            if [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ ! "$value" =~ [1-9] ]]; then
              echo 'error: --scaleは正の数を指定してください。' >&2; return 2
            fi
            scale="$value"; scale_set=true ;;
          --width|--height|--page)
            if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
              echo "error: $option は正の整数を指定してください。" >&2; return 2
            fi
            case "$option" in
              --width) width="$value" ;;
              --height) height="$value" ;;
              --page)
                if [ "$diagram_kind" != drawio ]; then
                  echo 'error: --pageはdraw.io専用です。' >&2; return 2
                fi
                page="$value" ;;
            esac ;;
          --border)
            if [ "$diagram_kind" != drawio ] || [[ ! "$value" =~ ^(0|[1-9][0-9]*)$ ]]; then
              echo 'error: --borderはdraw.io専用で、0以上の整数を指定してください。' >&2; return 2
            fi
            border="$value" ;;
          --background)
            case "$value" in
              transparent|white) background="$value" ;;
              *) echo 'error: --backgroundはtransparentまたはwhiteを指定してください。' >&2; return 2 ;;
            esac ;;
        esac
        shift ;;
      --no-embed-fonts) embed_fonts=false ;;
      --force) force=true ;;
      --skip-image-build|--rebuild-image)
        if [ "$image_mode" != auto ]; then
          echo 'error: イメージのオプションは1つだけ指定してください。' >&2; return 2
        fi
        image_mode="$1" ;;
      -h|--help) diagram_usage; exit 0 ;;
      --) shift; files+=("$@"); break ;;
      -*) echo "error: 不明なオプション: $1" >&2; return 2 ;;
      *) files+=("$1") ;;
    esac
    shift
  done
  if [ "${#files[@]}" -ne 2 ]; then diagram_usage >&2; return 2; fi
  input="${files[0]}"
  output="${files[1]}"
  case "$output" in
    *.svg)
      if [ "$scale_set" = true ]; then
        echo 'error: --scaleはPNG専用です。SVGは拡大しても画質が落ちません。' >&2; return 2
      fi
      scale=1 ;;
    *.png)
      if [ "$embed_fonts" = false ]; then
        echo 'error: --no-embed-fontsはSVG専用です。' >&2; return 2
      fi ;;
    *) echo 'error: 出力は.svgまたは.pngを指定してください。' >&2; return 2 ;;
  esac
  if [ "$diagram_kind" = drawio ] && [ -n "$width$height" ]; then
    if { [ -n "$width" ] && [ -n "$height" ]; } || [ "$scale_set" = true ]; then
      echo 'error: draw.ioの--width、--height、--scaleは同時に指定できません。' >&2; return 2
    fi
    # 固定サイズ指定時には標準の2倍拡大を適用しない。
    scale=1
  fi
  if [ -e "$output" ] && { [ "$force" = false ] || [ ! -f "$output" ]; }; then
    echo "error: 出力先が存在します。ファイルを上書きするには--forceを指定してください: $output" >&2
    return 2
  fi
}

parse_container_options() {
  image_mode=auto
  input=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skip-image-build|--rebuild-image)
        if [ "$image_mode" != auto ]; then
          echo 'error: イメージのオプションは1つだけ指定してください。' >&2
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
          echo "error: Markdown ファイルは1つ指定してください。" >&2
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
  # 毎回podman buildを呼ばず、Containerfileのハッシュをイメージのラベルと比較する。
  # 同じ環境で連続して図やスライドを生成するときの起動コストを抑える。
  container_hash="$(sha256sum "$script_dir/Containerfile")"
  container_hash="${container_hash%% *}"

  if [ "$image_mode" = --skip-image-build ]; then
    if ! podman image exists "$image"; then
      echo 'error: 既存イメージがありません。オプションなしで実行してください。' >&2
      return 1
    fi
    return 0
  fi

  stored_hash="$(podman image inspect --format '{{index .Config.Labels "jp.marp-template-kit.containerfile-sha256"}}' "$image" 2>/dev/null || true)"
  if [ "$image_mode" = auto ] && [ "$stored_hash" = "$container_hash" ]; then
    echo 'image: 変更がないため既存イメージを使用します。' >&2
    return 0
  fi

  local build_options=()
  if [ "$image_mode" = --rebuild-image ]; then
    # 明示した再ビルドだけキャッシュを無効化する。通常の変更時には既存レイヤーを使う。
    build_options+=(--no-cache)
  fi
  podman build -q "${build_options[@]}" \
    --label "jp.marp-template-kit.containerfile-sha256=$container_hash" \
    -t "$image" -f "$script_dir/Containerfile" "$script_dir" >&2
}
