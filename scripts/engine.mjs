// marp-cli の --engine オプションに渡すカスタムエンジン。
// Marp のコアクラスを継承し、mermaid / matplotlib コードブロックを図・グラフに変換して埋め込む。
// marp-cli はデフォルトでこれらを解釈しないため、このファイルで処理を差し込む。

import { createRequire } from 'module';
// marp-cli のコンテナ内パスから Marp コアを require する。
// ESM と CJS が混在するため createRequire を使う。
const require = createRequire('/home/marp/.cli/marp-cli.js');
const { Marp } = require('@marp-team/marp-core');
import { execSync } from 'child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { createHash } from 'crypto';
import { join, resolve, extname } from 'path';

// mmdc が生成した SVG の一時置き場。ビルド中は同じ図を何度も変換しないようキャッシュする。
const CACHE_DIR = '/tmp/marp-mermaid';
mkdirSync(CACHE_DIR, { recursive: true });

// mmdc が出力する SVG は width/height 属性で固定サイズになっている。
// marp のスライド座標系は 3840×2160 px なので、固定サイズのままでは図が極小になる。
// width/height 属性を除去して CSS で高さを指定し、アスペクト比を保ったまま拡大する。
function toResponsiveSvg(svg) {
  return svg
    .replace(/ width="\d+(\.\d+)?"/, '')
    .replace(/ height="\d+(\.\d+)?"/, '')
    .replace('<svg', '<svg style="height:1300px;width:auto;max-width:100%;display:block;margin:0 auto"');
}

// Mermaid コードを受け取り、mmdc で SVG に変換して返す。
// 同じコードは SVG をキャッシュして再利用する。
function renderMermaid(code) {
  const hash = createHash('sha256').update(code).digest('hex').slice(0, 16);
  const mmdPath = join(CACHE_DIR, `${hash}.mmd`);
  const svgPath = join(CACHE_DIR, `${hash}.svg`);

  if (existsSync(svgPath)) return toResponsiveSvg(readFileSync(svgPath, 'utf8'));

  writeFileSync(mmdPath, code);
  try {
    // -w 700: 図の描画幅 (px)。大きすぎると余白が広がるため適度な値にする。
    // -p: Chrome の起動オプション。コンテナ内でサンドボックスを無効化するための設定ファイル。
    // -c: フォント統一の設定。図内テキストをテーマと同じ埋め込みフォントでレイアウト・描画し、
    //     HTML と PDF で解決されるフォントが変わる問題を防ぐ。
    execSync(`mmdc -i "${mmdPath}" -o "${svgPath}" -p /app/config/mermaid-puppeteer.json -c /app/config/mermaid-config.json -w 700`, {
      timeout: 60000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return toResponsiveSvg(readFileSync(svgPath, 'utf8'));
  } catch (e) {
    const msg = e.stderr?.toString() || e.message;
    process.stderr.write(`[mermaid] ${msg}\n`);
    return `<div style="color:red;border:1px solid red;padding:.5em">Mermaid error: see stderr</div>`;
  }
}

// matplotlib コードを受け取り、Python で実行して PNG を生成し base64 で返す。
// _output 変数を自動注入するので、ユーザーは plt.savefig(_output) で保存先を指定する。
function renderMatplotlib(code) {
  const hash = createHash('sha256').update(code).digest('hex').slice(0, 16);
  const pyPath = join(CACHE_DIR, `${hash}.py`);
  const pngPath = join(CACHE_DIR, `${hash}.png`);

  if (!existsSync(pngPath)) {
    // _output: ユーザーが plt.savefig(_output) で参照する出力先パス。
    // matplotlib.use / font の設定はヘッドレス環境向けに自動注入する。
    const script = [
      'import matplotlib',
      'matplotlib.use("Agg")',  // ヘッドレス環境では非対話バックエンドが必要
      'matplotlib.rcParams["font.family"] = ["GenEi M Gothic v2", "Noto Sans CJK JP"]',
      `_output = ${JSON.stringify(pngPath)}`,
      code,
    ].join('\n');
    writeFileSync(pyPath, script);
    try {
      execSync(`python3 "${pyPath}"`, { timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] });
    } catch (e) {
      const msg = e.stderr?.toString() || e.message;
      process.stderr.write(`[matplotlib] ${msg}\n`);
      return `<div style="color:red;border:1px solid red;padding:.5em">matplotlib error: see stderr</div>`;
    }
  }

  const b64 = readFileSync(pngPath).toString('base64');
  // marp の 3840×2160 座標系に合わせて高さを指定する。
  return `<img src="data:image/png;base64,${b64}" style="height:1300px;width:auto;max-width:100%;display:block;margin:0 auto">`;
}

// ローカル画像を base64 data URI に変換する。
// build.sh が MARP_INPUT_DIR に markdown ファイルのディレクトリを渡す。
// http(s):// や data: で始まるパスはそのまま返す。
const INPUT_DIR = process.env.MARP_INPUT_DIR || '/app';
const PROJECT_ROOT = '/app';
const MIME = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff', '.woff2': 'font/woff2',
};

function embedImage(src, baseDir = INPUT_DIR) {
  if (/^(https?:|data:)/.test(src)) return src;
  const abs = resolve(baseDir, src);
  if (!existsSync(abs)) return src;
  const mime = MIME[extname(abs).toLowerCase()] ?? 'application/octet-stream';
  const b64 = readFileSync(abs).toString('base64');
  return `data:${mime};base64,${b64}`;
}

// コードブロックのダウンロードボタンで使うファイル名の拡張子を、フェンスの言語指定から推測する。
const LANG_EXT_MAP = {
  python: 'py', javascript: 'js', typescript: 'ts', bash: 'sh', shell: 'sh', sh: 'sh',
  json: 'json', yaml: 'yml', yml: 'yml', html: 'html', css: 'css', rust: 'rs', cpp: 'cpp',
  c: 'c', go: 'go', java: 'java', ruby: 'rb', php: 'php', sql: 'sql', markdown: 'md', md: 'md',
};

// 通常のコードブロック (mermaid / matplotlib 以外) の描画結果を、
// Copy / Download ボタン付きのツールバーで包む。
// ボタン自体のクリック処理は markdown 本文に <script> を書いても marp-core にエスケープされてしまうため、
// render() 側で HTML 文字列に直接スクリプトを追記する方式にしている (CODE_TOOLBAR_SCRIPT を参照)。
function wrapWithCodeToolbar(renderedHtml, lang) {
  const ext = LANG_EXT_MAP[lang] || 'txt';
  return `<div class="code-block-wrap"><div class="code-toolbar">`
    + `<button type="button" class="code-copy-btn">Copy</button>`
    + `<button type="button" class="code-download-btn" data-ext="${ext}">Download</button>`
    + `</div>${renderedHtml}</div>`;
}

// コードブロックの Copy / Download ボタンを動作させるクライアントスクリプト。
// HTML 出力 (out/htmls) でのみ意味を持つ。PDF 出力では @media print でボタンごと非表示にする。
const CODE_TOOLBAR_SCRIPT = `<script>
(function () {
  // ボタンのラベルを一時的に差し替えて完了を伝える (Copy / Download 共通)。
  function showFeedback(btn, label) {
    var original = btn.textContent;
    btn.textContent = label;
    btn.classList.add('copied');
    setTimeout(function () {
      btn.textContent = original;
      btn.classList.remove('copied');
    }, 500);
  }

  function copyText(text, btn) {
    function onSuccess() {
      showFeedback(btn, 'Copied!');
    }
    function fallbackCopy() {
      var textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      try {
        document.execCommand('copy');
        onSuccess();
      } catch (err) {
        console.error('コピーに失敗しました', err);
      }
      document.body.removeChild(textarea);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(onSuccess, fallbackCopy);
    } else {
      fallbackCopy();
    }
  }

  function downloadText(text, filename, btn) {
    var blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showFeedback(btn, 'Downloaded!');
  }

  document.querySelectorAll('.code-block-wrap').forEach(function (wrap, index) {
    var code = wrap.querySelector('code');
    if (!code) return;
    var text = code.innerText;

    var copyBtn = wrap.querySelector('.code-copy-btn');
    if (copyBtn) {
      copyBtn.addEventListener('click', function () {
        copyText(text, copyBtn);
      });
    }

    var downloadBtn = wrap.querySelector('.code-download-btn');
    if (downloadBtn) {
      downloadBtn.addEventListener('click', function () {
        var ext = downloadBtn.dataset.ext || 'txt';
        downloadText(text, 'snippet-' + (index + 1) + '.' + ext, downloadBtn);
      });
    }
  });
})();
</script>`;

// Marp のコアクラスを継承し、コードブロックのレンダラーを上書きする。
class MarpWithMermaid extends Marp {
  constructor(opts) {
    super(opts);
    const md = this.markdown;

    // ローカル画像を base64 data URI に変換する core rule。
    // marp の画像プラグインは image トークンを renderer より前に処理するため、
    // renderer の上書きでは効かない。core rule でトークンを直接書き換える。
    md.core.ruler.push('embed_local_images', (state) => {
      const replaceSrc = (s) => embedImage(s);
      for (const block of state.tokens) {
        // インライン画像: inline トークンの children に image トークンがある。
        if (block.type === 'inline' && block.children) {
          for (const t of block.children) {
            if (t.type === 'image') {
              const i = t.attrIndex('src');
              if (i >= 0) t.attrs[i][1] = replaceSrc(t.attrs[i][1]);
            }
            // marp が image を html_inline に変換していた場合も対応する。
            if (t.type === 'html_inline') {
              t.content = t.content.replace(/src="([^"]+)"/g, (_, s) => `src="${replaceSrc(s)}"`);
            }
          }
        }
        if (block.type === 'html_block') {
          block.content = block.content.replace(/src="([^"]+)"/g, (_, s) => `src="${replaceSrc(s)}"`);
        }
      }
    });

    const orig = md.renderer.rules.fence?.bind(md.renderer);
    // fence = コードブロック (``` ... ```) のレンダラー。
    md.renderer.rules.fence = (tokens, idx, options, env, self) => {
      const token = tokens[idx];
      // 言語指定に応じて専用レンダラーに委ねる。それ以外は元のレンダラーを使う。
      const lang = token.info.trim().split(/\s/)[0];
      if (lang === 'mermaid') return renderMermaid(token.content.trim());
      if (lang === 'matplotlib') return renderMatplotlib(token.content.trim());
      const rendered = orig ? orig(tokens, idx, options, env, self) : self.renderToken(tokens, idx, options);
      return wrapWithCodeToolbar(rendered, lang);
    };
  }

  // CSS の url() 参照もプロジェクトルート基準で base64 に変換する。
  // modern.css の背景画像など、テーマ CSS が参照するローカルファイルを自己完結 HTML に埋め込む。
  render(markdown, env) {
    const result = super.render(markdown, env);
    result.css = result.css.replace(/url\((['"]?)([^'")]+)\1\)/g, (match, q, path) => {
      const embedded = embedImage(path, PROJECT_ROOT);
      return embedded === path ? match : `url(${q}${embedded}${q})`;
    });
    // 自己完結 HTML に含まれるテーマの MIT License を保持する。
    const projectLicense = readFileSync('/app/LICENSE', 'utf8');
    result.css = `/*! MIT License\n${projectLicense}*/\n${result.css}`;
    // コードブロックのボタン用スクリプトを追記する。
    // markdown 本文に直接 <script> を書くと marp-core にエスケープされて実行されないため、
    // レンダリング後の HTML 文字列に直接追記する (この経路なら実行される)。
    result.html += CODE_TOOLBAR_SCRIPT;
    return result;
  }
}

// marp-cli が --engine で受け取る関数。Marp インスタンスを返す。
export default (opts) => new MarpWithMermaid(opts);
