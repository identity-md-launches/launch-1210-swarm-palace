// Production "build": the site has no build step, so this copies the runtime
// files from site/ into ../dist (the committed static export) and verifies
// that every local file referenced by the pages exists in the export.
import { cpSync, rmSync, mkdirSync, existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, '..');
const dist = resolve(site, '..', 'dist');

const RUNTIME = ['index.html', '404.html', 'css', 'js', 'assets'];

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
for (const entry of RUNTIME) {
  const from = join(site, entry);
  if (!existsSync(from)) throw new Error(`missing ${entry} in site/`);
  cpSync(from, join(dist, entry), { recursive: true });
}

// Resolve every local href/src in the exported HTML against dist/.
let missing = 0;
for (const page of ['index.html', '404.html']) {
  const html = readFileSync(join(dist, page), 'utf8');
  const refs = [...html.matchAll(/(?:href|src)="([^"#?]+)[^"]*"/g)].map((m) => m[1]);
  for (const ref of refs) {
    if (/^(https?:)?\/\//.test(ref) || ref.startsWith('mailto:') || ref.startsWith('data:')) continue;
    const target = ref.startsWith('/') ? join(dist, ref) : join(dist, dirname(page), ref);
    if (!existsSync(target)) { missing++; console.error(`[build] ${page}: missing ${ref}`); }
  }
}
if (missing) process.exit(1);

/** @param {string} dir @returns {string[]} */
function files(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((d) =>
    d.isDirectory() ? files(join(dir, d.name)) : [join(dir, d.name)]);
}
const total = files(dist).reduce((sum, f) => sum + statSync(f).size, 0);
console.log(`[build] exported ${RUNTIME.join(', ')} to ${dist} (${(total / 1024).toFixed(0)} KiB, ${files(dist).length} files)`);
