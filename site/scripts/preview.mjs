// Local preview server for the static export. Serves ../dist at / and at
// /preview/ (to check relative asset URLs under a subpath), answers
// /simd-coin.json with a sample payload (set COIN_JSON=path to use your own)
// and serves 404.html for unknown paths. Ctrl-C to stop.
import { createServer } from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dist = resolve(here, '..', '..', 'dist');
const port = Number(process.env.PORT) || 4173;

const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };

export const SAMPLE_COIN = {
  name: 'Swarm Palace', symbol: 'SPALACE', token: null, chainName: 'Ethereum',
  coinUrl: 'https://www.si-md.xyz/launchpad', chartUrl: 'https://www.si-md.xyz/launchpad', status: 'launching',
  market: { marketCap: null, priceUsd: null, volume24h: null },
};

/** @param {import('node:http').IncomingMessage} req @param {import('node:http').ServerResponse} res */
export function handle(req, res, coin = SAMPLE_COIN) {
  const url = new URL(req.url || '/', 'http://localhost');
  let path = decodeURIComponent(url.pathname);
  if (path === '/simd-coin.json' || path === '/preview/simd-coin.json') {
    res.writeHead(200, { 'content-type': TYPES['.json'] });
    res.end(JSON.stringify(coin));
    return;
  }
  if (path.startsWith('/preview/')) path = path.slice('/preview'.length);
  if (path.endsWith('/')) path += 'index.html';
  const file = normalize(join(dist, path));
  if (file.startsWith(dist) && existsSync(file) && statSync(file).isFile()) {
    res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'application/octet-stream' });
    res.end(readFileSync(file));
    return;
  }
  res.writeHead(404, { 'content-type': TYPES['.html'] });
  res.end(readFileSync(join(dist, '404.html')));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const coin = process.env.COIN_JSON ? JSON.parse(readFileSync(process.env.COIN_JSON, 'utf8')) : SAMPLE_COIN;
  createServer((req, res) => handle(req, res, coin)).listen(port, () => {
    console.log(`Swarm Palace preview: http://localhost:${port}/ and http://localhost:${port}/preview/ (serving ${dist})`);
  });
}
