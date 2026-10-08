#!/usr/bin/env bash
# Mermaid単体ファイルをSVG・PNGへ変換する。
# 標準は透明背景・PNG 2倍。SVGには源暎エムゴの実フォントを埋め込む。
# 設定ファイルを入力のfrontmatterで上書きできるため、手書き風などの指定は図側に置く。
set -euo pipefail

# 実行したディレクトリに依存しないよう、スクリプトの場所から設定を探す。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$script_dir/scripts/container.sh"
parse_diagram_options mermaid "$@"
if [ ! -f "$input" ]; then
  echo "not found: $input" >&2
  exit 1
fi
case "$input" in
  *.mmd|*.mermaid) ;;
  *) echo 'error: 入力は.mmdまたは.mermaidを指定してください。' >&2; exit 2 ;;
esac

if ! podman info > /dev/null 2>&1; then
  echo 'error: podmanが利用できません。インストールと設定を確認してください。' >&2
  exit 1
fi
# 入力は読み取り専用。出力ディレクトリだけ書き込み可能にし、描画時の外部通信を止める。
ensure_tools_image
mkdir -p "$(dirname "$output")"
input_dir="$(cd "$(dirname "$input")" && pwd)"
output_dir="$(cd "$(dirname "$output")" && pwd)"

# 実行UIDもホストに合わせ、生成ファイルがnobody所有になるのを防ぐ。
# ブラウザの一時設定はコンテナの/tmpへ置き、ホームディレクトリには書き込まない。
podman run --rm --init --userns=keep-id --user "$(id -u):$(id -g)" --network=none \
  --env XDG_CONFIG_HOME=/tmp/config --env XDG_CACHE_HOME=/tmp/cache \
  -v "$script_dir:/app:ro" \
  -v "$input_dir:/input:ro" \
  -v "$output_dir:/output" \
  --entrypoint node "$image" -e '
    const fs = require("node:fs");
    const path = require("node:path");
    const { execFileSync } = require("node:child_process");
    const [input, output, scale, width, height, background, embedFonts, force] = process.argv.slice(1);
    const exported = `/tmp/diagram${path.extname(output)}`;
    // テーマの本文フォント定義をそのまま使い、SVGにもフォントを埋め込む。
    const theme = fs.readFileSync("/app/themes/modern.css", "utf8");
    const faces = (theme.match(/@font-face\s*\{[^}]*\}/g) || [])
      .filter(face => /font-family:\s*"GenEi M Gothic v2"/.test(face))
      .map(face => face.replace(/url\("([^"]+)"\)/g, (_, file) =>
        `url("data:font/ttf;base64,${fs.readFileSync(file).toString("base64")}")`));
    if (faces.length !== 2) throw new Error("Regular・Mediumのフォント定義が見つかりません。");
    const css = "/tmp/mermaid-fonts.css";
    // PNGの描画には実フォントが必要。軽量SVGの指定時だけ、埋め込みを省く。
    fs.writeFileSync(css, (embedFonts === "true" ? faces.join("\n") : "") + `
      svg { font-synthesis: none; font-weight: 400; }
      svg .label, svg .nodeLabel, svg .edgeLabel { font-weight: 400; }
      svg .cluster-label, svg .cluster-label .nodeLabel,
      svg strong, svg b { font-weight: 500; }
    `);
    execFileSync("mmdc", [
      "-i", input, "-o", exported,
      "-p", "/app/config/mermaid-puppeteer.json",
      "-c", "/app/config/mermaid-config.json",
      "-C", css, "-b", background, "-w", width, "-H", height, "-s", scale
    ], { stdio: "inherit", timeout: 120000 });
    // 失敗した描画で前の成果物を壊さない。正常終了と出力の存在を確認してからコピーする。
    if (!fs.existsSync(exported) || fs.statSync(exported).size === 0)
      throw new Error("Mermaidの出力が作成されませんでした。");
    // 同じ出力ディレクトリで完成させてから差し替え、書き込み途中の画像を残さない。
    const staging = fs.mkdtempSync(path.join(path.dirname(output), ".render-mermaid-"));
    try {
      const staged = path.join(staging, "diagram");
      fs.copyFileSync(exported, staged);
      if (force === "true") fs.renameSync(staged, output);
      else fs.linkSync(staged, output); // 変換中に同名ファイルが作られても上書きしない。
    } finally {
      fs.rmSync(staging, { recursive: true });
    }
  ' "/input/$(basename "$input")" "/output/$(basename "$output")" \
  "$scale" "$width" "$height" "$background" "$embed_fonts" "$force"

echo "output: $output"
