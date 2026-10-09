// render-diagram.shのコンテナ内実装。描画ツールの起動方法、フォント、SVGの
// 寸法、PNG化、一時ファイルと公開手順をここに閉じ込める。
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { parseArgs } from 'node:util';

const require = createRequire('/usr/local/lib/node_modules/@mermaid-js/mermaid-cli/package.json');
const puppeteer = require('puppeteer');
const browserConfig = JSON.parse(fs.readFileSync('/app/config/mermaid-puppeteer.json', 'utf8'));

// ホスト側で検証済みの名前付き引数。順番を変えても意味が変わらない。
const { values } = parseArgs({ options: {
  input: { type: 'string' }, output: { type: 'string' },
  format: { type: 'string' }, scale: { type: 'string' },
  'png-width': { type: 'string' }, page: { type: 'string' },
  padding: { type: 'string' }, background: { type: 'string' },
  'no-embed-fonts': { type: 'boolean' }, force: { type: 'boolean' },
} });

// フォントはテーマを取得元とし、描画前にもSVGの共有時にも同じ実体を使う。
// draw.ioにはBoldも必要。別名Mediumの指定をCSSの500へ対応させる。
function fontStyles(kind) {
  const theme = fs.readFileSync('/app/themes/modern.css', 'utf8');
  const faces = (theme.match(/@font-face\s*\{[^}]*\}/g) || [])
    .filter(face => /font-family:\s*"GenEi M Gothic v2"/.test(face))
    .map(face => face.replace(/url\("([^"]+)"\)/g, (_, file) =>
      `url("data:font/ttf;base64,${fs.readFileSync(file).toString('base64')}")`));
  if (faces.length !== 2) throw new Error('Regular・Mediumのフォント定義が見つかりません。');
  if (kind === 'drawio') {
    const bold = execFileSync('fc-match', ['-f', '%{file}', 'GenEi M Gothic v2:style=Bold'],
      { encoding: 'utf8' }).trim();
    if (path.basename(bold) !== 'GenEiMGothic2-Bold.ttf')
      throw new Error('源暎エムゴBoldがインストールされていません。');
    faces.push(`@font-face { font-family: "GenEi M Gothic v2"; font-weight: 700;
      src: url("data:font/ttf;base64,${fs.readFileSync(bold).toString('base64')}"); }`);
    faces.push(`[font-family*="GenEi M Gothic v2 Medium"], [style*="GenEi M Gothic v2 Medium"] {
      font-family: "GenEi M Gothic v2" !important; font-weight: 500 !important; }`);
  } else {
    faces.push(`svg { font-synthesis: none; font-weight: 400; }
      svg .label, svg .nodeLabel, svg .edgeLabel { font-weight: 400; }
      svg .cluster-label, svg .cluster-label .nodeLabel, svg strong, svg b { font-weight: 500; }`);
  }
  return faces;
}

function pageCount(input) {
  // Desktopは範囲外ページを成功扱いにするので、XMLの外枠で先に検証する。
  // 圧縮済みページも扱い、コメント・CDATA・名前空間を正規表現で誤認しない。
  const count = Number(execFileSync('python3', ['-c', `
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
tag = root.tag.rsplit('}', 1)[-1]
print(sum(child.tag.rsplit('}', 1)[-1] == 'diagram' for child in root) if tag == 'mxfile' else int(tag == 'mxGraphModel'))
`, input], { encoding: 'utf8', timeout: 10000 }));
  if (!Number.isSafeInteger(count) || count < 1) throw new Error('draw.ioのページがありません。');
  return count;
}

// 両バックエンドとも自然な寸法のSVGだけを作る。PNG用の画面サイズや倍率を
// バックエンドに渡さず、図のレイアウトと成果物の解像度を分離する。
function renderSvg({ input, kind, page, workspace, styles }) {
  const exported = path.join(workspace, 'diagram.svg');
  if (kind === 'mermaid') {
    const css = path.join(workspace, 'fonts.css');
    fs.writeFileSync(css, styles.join('\n'));
    execFileSync('mmdc', ['-i', input, '-o', exported,
      '-p', '/app/config/mermaid-puppeteer.json', '-c', '/app/config/mermaid-config.json',
      '-C', css, '-b', 'transparent', '-w', '700'],
    { stdio: 'pipe', timeout: 120000 });
  } else {
    execFileSync('xvfb-run', ['-a', 'drawio', '--no-sandbox', '--disable-update',
      '--disable-gpu', '--disable-dev-shm-usage', '--export', '--format', 'svg',
      '--theme', 'light', '--border', '0', '--page-index', String(page),
      '--embed-svg-fonts', 'false', '--transparent', '--output', exported, input],
    { stdio: 'pipe', timeout: 120000 });
  }
  const svg = fs.readFileSync(exported, 'utf8');
  if (!svg.includes('</svg>')) throw new Error('SVGが作成されませんでした。');
  // mmdcのCSSにまとまったフォントも分割する。1つのXMLテキストに
  // RegularとMediumを並べると、一般的なパーサーの上限を超えてしまう。
  const withoutFaces = svg.replace(/@font-face\s*\{[^}]*\}/g, '');
  const defs = styles.map(css => `<style type="text/css"><![CDATA[${css}]]></style>`).join('');
  return withoutFaces.replace('</svg>', `<defs>${defs}</defs></svg>`);
}

// SVGのviewBoxを基準に、共通の余白・背景・固定寸法を設定する。
// Mermaidのwidth="100%"やmax-widthを出力サイズとして公開しない。
async function prepareSvg(page, file, { padding, background }) {
  await page.goto(pathToFileURL(file).href, { waitUntil: 'load' });
  return page.evaluate(async ({ padding, background }) => {
    const svg = document.documentElement;
    if (svg.localName !== 'svg') throw new Error('SVGを読み込めませんでした。');
    const box = svg.viewBox.baseVal;
    const width = box.width || svg.width.baseVal.value;
    const height = box.height || svg.height.baseVal.value;
    if (!(width > 0 && height > 0)) throw new Error('SVGの寸法が不正です。');
    const x = box.x - padding, y = box.y - padding;
    svg.setAttribute('viewBox', `${x} ${y} ${width + 2 * padding} ${height + 2 * padding}`);
    svg.setAttribute('width', width + 2 * padding);
    svg.setAttribute('height', height + 2 * padding);
    svg.style.maxWidth = 'none';
    svg.style.removeProperty('background-color');
    // CSSの背景だけではSVGを画像として扱う閲覧ソフトで消える場合がある。
    // viewBoxを覆う図形を最背面に置き、SVGにもPNGにも同じ色と透明度を持たせる。
    const backdrop = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    for (const [name, value] of Object.entries({ x, y,
      width: width + 2 * padding, height: height + 2 * padding }))
      backdrop.setAttribute(name, value);
    backdrop.style.setProperty('fill', background, 'important');
    svg.insertBefore(backdrop, svg.firstChild);
    await document.fonts.ready;
    return { svg: new XMLSerializer().serializeToString(svg),
      width: width + 2 * padding, height: height + 2 * padding };
  }, { padding: Number(padding), background });
}

// 縦長の図もSVGと同じChromeで描画する。Electronの仮想画面の高さによる
// PNG出力失敗や、バックエンドごとの倍率・フォントの違いを利用者に負わせない。
async function renderPng(page, svgFile, output, { width, height, scale, pngWidth }) {
  const density = pngWidth ? Number(pngWidth) / width : Number(scale);
  const pixels = Math.ceil(width * density) * Math.ceil(height * density);
  if (!Number.isFinite(density) || density <= 0 || pixels > 100_000_000)
    throw new Error('PNGが大きすぎます。--scaleまたは--png-widthで小さくしてください。');
  await page.setViewport({ width: Math.ceil(width), height: Math.ceil(height), deviceScaleFactor: density });
  await page.goto(pathToFileURL(svgFile).href, { waitUntil: 'load' });
  await page.evaluate(async () => { await document.fonts.ready; });
  await page.screenshot({ path: output, type: 'png', omitBackground: true,
    clip: { x: 0, y: 0, width, height }, captureBeyondViewport: true });
}

// 全ページを一時ディレクトリで完成させてから公開する。描画の途中失敗では
// 既存成果物に触れない。各ファイルは同じFS内で原子的に差し替える。
async function renderDiagrams(options) {
  const { input, output, format, force } = options;
  if (!Number.isFinite(Number(options.padding)) || !Number.isFinite(Number(options.scale)))
    throw new Error('余白と倍率は有限の数を指定してください。');
  const kind = path.extname(input) === '.drawio' ? 'drawio' : 'mermaid';
  const count = kind === 'drawio' ? pageCount(input) : 1;
  const selected = options.page ? [Number(options.page)] : Array.from({ length: count }, (_, i) => i + 1);
  if (selected.some(n => !Number.isSafeInteger(n) || n < 1 || n > count))
    throw new Error(`ページ${options.page}はありません（全${count}ページ）。`);
  const stem = path.basename(input, path.extname(input));
  const formats = format === 'both' ? ['svg', 'png'] : [format];
  const jobs = selected.map(number => ({ number,
    name: count === 1 ? stem : `${stem}-${String(number).padStart(2, '0')}` }));
  const names = jobs.flatMap(job => formats.map(ext => `${job.name}.${ext}`));
  // --forceでもディレクトリには置き換えない。衝突は描画前にまとめて確認する。
  for (const name of names) {
    const file = path.join(output, name);
    if (fs.existsSync(file) && (!force || !fs.statSync(file).isFile()))
      throw new Error(`出力先が存在します。上書きには--forceが必要です: ${name}`);
  }
  const staging = fs.mkdtempSync(path.join(output, '.render-diagram-'));
  let browser, workspace;
  try {
    workspace = fs.mkdtempSync('/tmp/render-diagram-');
    const styles = fontStyles(kind);
    browser = await puppeteer.launch({ ...browserConfig, headless: true });
    const page = await browser.newPage();
    if (!await page.evaluate(color => CSS.supports('color', color), options.background))
      throw new Error(`有効なCSSの色を指定してください: ${options.background}`);
    for (const job of jobs) {
      console.log(`render: ${job.name}`);
      const source = path.join(workspace, 'source.svg');
      fs.writeFileSync(source, renderSvg({ input, kind, page: job.number, workspace, styles }));
      const prepared = await prepareSvg(page, source, options);
      const svgFile = path.join(workspace, 'prepared.svg');
      fs.writeFileSync(svgFile, prepared.svg);
      if (formats.includes('png')) await renderPng(page, svgFile, path.join(staging, `${job.name}.png`),
        { ...prepared, scale: options.scale, pngWidth: options['png-width'] });
      if (formats.includes('svg')) {
        // 軽量SVGの指定でもPNGの描画には埋め込みフォントを使い続ける。
        const svg = options['no-embed-fonts']
          ? prepared.svg.replace(/@font-face\s*\{[^}]*\}/g, '') : prepared.svg;
        fs.writeFileSync(path.join(staging, `${job.name}.svg`), svg);
      }
    }
    for (const name of names) {
      const staged = path.join(staging, name), destination = path.join(output, name);
      if (force) fs.renameSync(staged, destination);
      else fs.linkSync(staged, destination); // 描画中に作られた同名ファイルも保護する。
      console.log(`created: ${name}`);
    }
  } finally {
    try {
      if (browser) await browser.close();
    } finally {
      if (workspace) fs.rmSync(workspace, { recursive: true, force: true });
      fs.rmSync(staging, { recursive: true, force: true });
    }
  }
}

try {
  await renderDiagrams(values);
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}
