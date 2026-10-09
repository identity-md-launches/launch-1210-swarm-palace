// Source checks that need no browser: required meta tags, alt text on every
// image, a label for every input, one h1 and no skipped heading levels,
// every in-page anchor resolving to an id, and the mandated footer line.
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, '..');
let failures = 0;
/** @param {boolean} ok @param {string} msg */
const check = (ok, msg) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${msg}`); if (!ok) failures++; };

for (const page of ['index.html', '404.html']) {
  const html = readFileSync(join(site, page), 'utf8');
  console.log(`\n# ${page}`);
  for (const tag of ['<title>', 'name="description"', 'property="og:title"', 'property="og:description"', 'property="og:image"', 'name="twitter:card" content="summary_large_image"', 'rel="icon"', 'name="viewport"', 'lang="en"']) {
    check(html.includes(tag), `has ${tag}`);
  }
  if (page === 'index.html') check(html.includes('rel="canonical"'), 'has canonical link');
  const imgs = [...html.matchAll(/<img\b[^>]*>/g)].map((m) => m[0]);
  check(imgs.every((i) => /\balt="/.test(i)), `every <img> has alt (${imgs.length} images)`);
  check(!/user-scalable=no|maximum-scale=1/.test(html), 'viewport does not block zoom');
  const inputs = [...html.matchAll(/<input\b[^>]*id="([^"]+)"/g)].map((m) => m[1]);
  check(inputs.every((id) => html.includes(`for="${id}"`)), `every input has a <label for> (${inputs.length} inputs)`);
  const h1s = (html.match(/<h1\b/g) || []).length;
  check(h1s === 1, `exactly one <h1> (${h1s})`);
  const levels = [...html.matchAll(/<h([1-6])\b/g)].map((m) => Number(m[1]));
  let skipped = false;
  for (let i = 1; i < levels.length; i++) if (levels[i] > levels[i - 1] + 1) skipped = true;
  check(!skipped, `no skipped heading levels (${levels.join(' ')})`);
  const ids = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]));
  const anchors = [...html.matchAll(/href="#([^"]+)"/g)].map((m) => m[1]);
  check(anchors.every((a) => ids.has(a)), `every in-page anchor resolves (${anchors.length} anchors)`);
  check(html.includes('Built 100% by the') && html.includes('not financial advice'), 'footer line present');
  check(!/0x[0-9a-fA-F]{40}/.test(html), 'no hardcoded contract address');
  check(html.includes('<main') && html.includes('skip-link'), 'main landmark and skip link present');
  if (page === 'index.html') {
    const sections = (html.match(/<section\b/g) || []).length;
    check(sections >= 7, `at least 7 sections (${sections})`);
    check(html.includes('simd-coin.json') || readFileSync(join(site, 'js/app.js'), 'utf8').includes('/simd-coin.json'), 'live data reads /simd-coin.json');
  }
}
const css = readFileSync(join(site, 'css/style.css'), 'utf8');
console.log('\n# css/style.css');
check(css.includes('prefers-reduced-motion'), 'reduced motion handled');
check(css.includes(':focus-visible'), 'focus-visible styles defined');
check(/--color-bg:|--space-4:|--radius-md:/.test(css), 'design tokens defined');

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
