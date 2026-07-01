// marp-cli の --engine オプションに渡すカスタムエンジン.
// Marp のコアクラスを継承し, mermaid コードブロックを SVG 図に変換して埋め込む.
// marp-cli はデフォルトで Mermaid を解釈しないため, このファイルで処理を差し込む.

import { createRequire } from 'module';
// marp-cli のコンテナ内パスから Marp コアを require する.
// ESM と CJS が混在するため createRequire を使う.
const require = createRequire('/home/marp/.cli/marp-cli.js');
const { Marp } = require('@marp-team/marp-core');
import { execSync } from 'child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { createHash } from 'crypto';
import { join } from 'path';

// mmdc が生成した SVG の一時置き場. ビルド中は同じ図を何度も変換しないようキャッシュする.
const CACHE_DIR = '/tmp/marp-mermaid';
mkdirSync(CACHE_DIR, { recursive: true });

// mmdc が出力する SVG は width/height 属性で固定サイズになっている.
// marp のスライド座標系は 3840×2160 px なので, 固定サイズのままでは図が極小になる.
// width/height 属性を除去して CSS で高さを指定し, アスペクト比を保ったまま拡大する.
function toResponsiveSvg(svg) {
  return svg
    .replace(/ width="\d+(\.\d+)?"/, '')
    .replace(/ height="\d+(\.\d+)?"/, '')
    .replace('<svg', '<svg style="height:1300px;width:auto;max-width:100%;display:block;margin:0 auto"');
}

// Mermaid コードを受け取り, mmdc で SVG に変換して返す.
// 同じコードは SVG をキャッシュして再利用する.
function renderMermaid(code) {
  const hash = createHash('sha256').update(code).digest('hex').slice(0, 16);
  const mmdPath = join(CACHE_DIR, `${hash}.mmd`);
  const svgPath = join(CACHE_DIR, `${hash}.svg`);

  if (existsSync(svgPath)) return toResponsiveSvg(readFileSync(svgPath, 'utf8'));

  writeFileSync(mmdPath, code);
  try {
    // -w 700: 図の描画幅 (px). 大きすぎると余白が広がるため適度な値にする.
    // -p: Chrome の起動オプション. コンテナ内でサンドボックスを無効化するための設定ファイル.
    execSync(`mmdc -i "${mmdPath}" -o "${svgPath}" -p /app/mermaid-puppeteer.json -w 700`, {
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

// Marp のコアクラスを継承し, コードブロックのレンダラーを上書きする.
class MarpWithMermaid extends Marp {
  constructor(opts) {
    super(opts);
    const md = this.markdown;
    const orig = md.renderer.rules.fence?.bind(md.renderer);
    // fence = コードブロック (``` ... ```) のレンダラー.
    md.renderer.rules.fence = (tokens, idx, options, env, self) => {
      const token = tokens[idx];
      // 言語指定が "mermaid" のブロックだけ SVG に変換し, それ以外は元のレンダラーに委ねる.
      if (token.info.trim().split(/\s/)[0] === 'mermaid') {
        return renderMermaid(token.content.trim());
      }
      return orig ? orig(tokens, idx, options, env, self) : self.renderToken(tokens, idx, options);
    };
  }
}

// marp-cli が --engine で受け取る関数. Marp インスタンスを返す.
export default (opts) => new MarpWithMermaid(opts);
