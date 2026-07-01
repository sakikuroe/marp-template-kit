import { createRequire } from 'module';
const require = createRequire('/home/marp/.cli/marp-cli.js');
const { Marp } = require('@marp-team/marp-core');
import { execSync } from 'child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { createHash } from 'crypto';
import { join } from 'path';

const CACHE_DIR = '/tmp/marp-mermaid';
mkdirSync(CACHE_DIR, { recursive: true });

function toResponsiveSvg(svg) {
  return svg
    .replace(/ width="\d+(\.\d+)?"/, '')
    .replace(/ height="\d+(\.\d+)?"/, '')
    .replace('<svg', '<svg style="height:1300px;width:auto;max-width:100%;display:block;margin:0 auto"');
}

function renderMermaid(code) {
  const hash = createHash('sha256').update(code).digest('hex').slice(0, 16);
  const mmdPath = join(CACHE_DIR, `${hash}.mmd`);
  const svgPath = join(CACHE_DIR, `${hash}.svg`);

  if (existsSync(svgPath)) return toResponsiveSvg(readFileSync(svgPath, 'utf8'));

  writeFileSync(mmdPath, code);
  try {
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

class MarpWithMermaid extends Marp {
  constructor(opts) {
    super(opts);
    const md = this.markdown;
    const orig = md.renderer.rules.fence?.bind(md.renderer);
    md.renderer.rules.fence = (tokens, idx, options, env, self) => {
      const token = tokens[idx];
      if (token.info.trim().split(/\s/)[0] === 'mermaid') {
        return renderMermaid(token.content.trim());
      }
      return orig ? orig(tokens, idx, options, env, self) : self.renderToken(tokens, idx, options);
    };
  }
}

export default (opts) => new MarpWithMermaid(opts);
