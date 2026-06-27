// WebSource/*.js を IIFE バンドルにし、対応する HTML を Mac アプリの
// Resources/web へ書き出す。
//
//   pitch.js → pitch.bundle.js + index.html
//
// 実行: npm run build （単発） / npm run watch （変更監視）
import * as esbuild from 'esbuild';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const watch = process.argv.includes('--watch');

const webSourceDir = resolve(__dirname, 'WebSource');
const outputDir = resolve(__dirname, 'SoccerStrikerMac/Resources/web');

const entries = [
  { js: 'pitch.js', bundle: 'pitch.bundle.js', html: 'index.html' },
];

async function rewriteHtml(htmlName, jsName, bundleName) {
  const src = await readFile(join(webSourceDir, htmlName), 'utf8');
  const moduleRe = new RegExp(
    `<script\\s+type=["']module["']\\s+src=["']\\.?\\/?${jsName.replace('.', '\\.')}["']\\s*><\\/script>`,
    'g'
  );
  const out = src
    .replace(moduleRe, `<script src="./${bundleName}"></script>`)
    .replaceAll(`./${jsName}`, `./${bundleName}`)
    .replaceAll(jsName, bundleName);
  await writeFile(join(outputDir, htmlName), out, 'utf8');
}

const baseOptions = {
  bundle: true,
  format: 'iife',
  target: ['safari17'],
  legalComments: 'none',
  loader: { '.js': 'js', '.mjs': 'js' },
  logLevel: 'info',
};

async function build() {
  await mkdir(outputDir, { recursive: true });
  for (const e of entries) {
    const result = await esbuild.build({
      ...baseOptions,
      entryPoints: [join(webSourceDir, e.js)],
      outfile: join(outputDir, e.bundle),
      minify: !watch,
      sourcemap: watch ? 'inline' : false,
    });
    if (result.errors.length > 0) { process.exit(1); }
    await rewriteHtml(e.html, e.js, e.bundle);
    console.log(`[build] wrote ${e.bundle} + ${e.html}`);
  }
}

if (watch) {
  await mkdir(outputDir, { recursive: true });
  for (const e of entries) {
    const ctx = await esbuild.context({
      ...baseOptions,
      entryPoints: [join(webSourceDir, e.js)],
      outfile: join(outputDir, e.bundle),
      sourcemap: 'inline',
    });
    await rewriteHtml(e.html, e.js, e.bundle);
    await ctx.watch();
  }
  console.log('[build] watching…');
} else {
  await build();
}
