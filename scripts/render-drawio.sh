#!/usr/bin/env bash
# draw.io単体ファイルをSVG・PNGへ変換する。
# 図側の配置・フォントを尊重する。標準は透明背景・PNG 2倍・周囲16px・1ページ目。
set -euo pipefail

# 設定とイメージはスライドのビルドと共有し、作業ディレクトリには依存しない。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$script_dir/scripts/container.sh"
parse_diagram_options drawio "$@"
if [ ! -f "$input" ]; then
  echo "not found: $input" >&2
  exit 1
fi
case "$input" in
  *.drawio) ;;
  *) echo 'error: 入力は.drawioを指定してください。' >&2; exit 2 ;;
esac

if ! podman info > /dev/null 2>&1; then
  echo 'error: podmanが利用できません。インストールと設定を確認してください。' >&2
  exit 1
fi
# 描画時はネットワークを遮断する。図に使う画像は入力ファイル側へ埋め込んでおく。
ensure_tools_image
mkdir -p "$(dirname "$output")"
input_dir="$(cd "$(dirname "$input")" && pwd)"
output_dir="$(cd "$(dirname "$output")" && pwd)"

# 出力をホストのユーザー所有にする。Electronの一時設定はコンテナ内だけに置く。
podman run --rm --init --userns=keep-id --user "$(id -u):$(id -g)" --network=none \
  --env XDG_CONFIG_HOME=/tmp/config --env XDG_CACHE_HOME=/tmp/cache \
  -v "$script_dir:/app:ro" \
  -v "$input_dir:/input:ro" \
  -v "$output_dir:/output" \
  --entrypoint node "$image" -e '
    const fs = require("node:fs");
    const path = require("node:path");
    const { execFileSync } = require("node:child_process");
    const [input, output, scale, width, height, background, page, border, embedFonts, force] = process.argv.slice(1);
    const format = path.extname(output).slice(1);
    const exported = `/tmp/diagram.${format}`;
    // Desktopは範囲外ページを成功扱いにするため、先にページ数を検証する。
    // コンテナにあるPythonの標準XMLパーサーを使い、圧縮済みページの外枠だけ読む。
    // XMLを正規表現で数えず、コメントやCDATAに含まれる文字列を誤認しない。
    const pageCount = Number(execFileSync("python3", ["-c", `
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
tag = root.tag.rsplit("}", 1)[-1]
print(sum(child.tag.rsplit("}", 1)[-1] == "diagram" for child in root) if tag == "mxfile" else int(tag == "mxGraphModel"))
    `, input], { encoding: "utf8" }));
    if (Number(page) > pageCount) throw new Error(`ページ${page}はありません（全${pageCount}ページ）。`);
    // Electronには仮想画面が必要。GPUと小容量の/dev/shmへの依存を避け、CIでも動かす。
    const args = ["-a", "drawio", "--no-sandbox", "--disable-update",
      "--disable-gpu", "--disable-dev-shm-usage",
      "--export", "--format", format, "--theme", "light", "--border", border,
      "--page-index", page, "--scale", scale, "--embed-svg-fonts", "false",
      "--output", exported];
    if (background === "transparent") args.push("--transparent");
    if (width) args.push("--width", width);
    if (height) args.push("--height", height);
    args.push(input);
    // 途中で止まった変換を無期限に待たず、失敗時は既存の出力に触れない。
    execFileSync("xvfb-run", args, { stdio: "inherit", timeout: 120000 });
    if (!fs.existsSync(exported) || fs.statSync(exported).size === 0)
      throw new Error("draw.ioの出力が作成されませんでした。");
    let result;
    if (format === "svg" && embedFonts === "true") {
      // スライドの本文フォントを埋め込み、別環境でも日本語の形を保つ。
      const theme = fs.readFileSync("/app/themes/modern.css", "utf8");
      const faces = (theme.match(/@font-face\s*\{[^}]*\}/g) || [])
        .filter(face => /font-family:\s*"GenEi M Gothic v2"/.test(face))
        .map(face => face.replace(/url\("([^"]+)"\)/g, (_, file) =>
          `url("data:font/ttf;base64,${fs.readFileSync(file).toString("base64")}")`));
      if (faces.length !== 2) throw new Error("Regular・Mediumのフォント定義が見つかりません。");
      const bold = execFileSync("fc-match", ["-f", "%{file}", "GenEi M Gothic v2:style=Bold"],
        { encoding: "utf8" }).trim();
      faces.push(`@font-face { font-family: "GenEi M Gothic v2"; font-weight: 700; font-style: normal;
        src: url("data:font/ttf;base64,${fs.readFileSync(bold).toString("base64")}"); }`);
      // draw.ioで指定したMediumの別名を、埋め込み済みの500へ対応させる。
      faces.push(`[font-family*="GenEi M Gothic v2 Medium"],
        [style*="GenEi M Gothic v2 Medium"] {
        font-family: "GenEi M Gothic v2" !important; font-weight: 500 !important; }`);
      const svg = fs.readFileSync(exported, "utf8");
      if (!svg.includes("</svg>")) throw new Error("SVGの出力形式が不正です。");
      const styles = faces.map(face =>
        `<style type="text/css"><![CDATA[${face}]]></style>`).join("");
      // 大きいフォントを1つのCDATAへまとめず、一般的なXMLパーサーでも扱えるよう分ける。
      result = svg.replace("</svg>", `<defs>${styles}</defs></svg>`);
    }
    // 成功した出力だけを差し替える。旧ファイルの所有者が違っても、親ディレクトリに
    // 書き込み権限があれば更新できる。失敗した変換で既存成果物を壊さない。
    const staging = fs.mkdtempSync(path.join(path.dirname(output), ".render-drawio-"));
    try {
      const staged = path.join(staging, "diagram");
      if (result !== undefined) fs.writeFileSync(staged, result);
      else fs.copyFileSync(exported, staged);
      if (force === "true") fs.renameSync(staged, output);
      else fs.linkSync(staged, output); // 変換中に作られた同名ファイルも保護する。
    } finally {
      fs.rmSync(staging, { recursive: true });
    }
  ' "/input/$(basename "$input")" "/output/$(basename "$output")" \
  "$scale" "$width" "$height" "$background" "$page" "$border" "$embed_fonts" "$force"

echo "output: $output"
