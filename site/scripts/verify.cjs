// Browser verification of the static export in ../dist with Playwright.
// Starts its own preview server, drives headless Chromium through the primary
// interactions at 1440, 375 and 320 CSS pixels, records console errors, failed
// requests and horizontal overflow, saves screenshots and exits non-zero on any
// failure. Needs playwright-core resolvable (NODE_PATH or a local install) and
// a Chromium it can launch (CHROME_PATH overrides the bundled one).
//   NODE_PATH=/path/to/node_modules node scripts/verify.cjs
'use strict';
const http = require('node:http');
const path = require('node:path');
const fs = require('node:fs');

const SHOTS = process.env.SHOTS_DIR || path.resolve(__dirname, '..', '..', 'test', 'scratch', 'shots');
fs.mkdirSync(SHOTS, { recursive: true });

/** @type {{ name: string, ok: boolean, detail?: string }[]} */
const results = [];
const record = (/** @type {string} */ name, /** @type {boolean} */ ok, /** @type {string=} */ detail) => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ' · ' + detail : ''}`);
};

const LIVE_COIN = {
  name: 'Swarm Palace', symbol: 'SPALACE', token: '0x1111111111111111111111111111111111111111', chainName: 'Ethereum',
  coinUrl: 'https://www.si-md.xyz/launchpad?coin=spalace', chartUrl: 'https://www.si-md.xyz/launchpad?chart=spalace', status: 'live',
  market: { marketCap: 2531.5, priceUsd: 0.0000025315, volume24h: 812.25 },
};

(async () => {
  const { handle, SAMPLE_COIN } = await import('./preview.mjs');
  const { chromium } = require('playwright-core');
  let coin = SAMPLE_COIN;
  const server = http.createServer((req, res) => handle(req, res, coin));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = /** @type {import('node:net').AddressInfo} */ (server.address()).port;
  const base = `http://127.0.0.1:${port}`;
  console.log('preview at', base);

  const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined, headless: true });
  const context = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'], acceptDownloads: true });
  const page = await context.newPage();
  /** @type {string[]} */ const consoleErrors = [];
  /** @type {string[]} */ const failed = [];
  page.on('console', (m) => {
    // the deliberate /nope navigation logs the document's own 404 status; everything else counts
    if (m.type() === 'error' && !(m.location().url || '').endsWith('/nope')) consoleErrors.push(m.text() + ' @ ' + (m.location().url || ''));
  });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + e.message));
  page.on('requestfailed', (r) => failed.push(r.url() + ' ' + (r.failure()?.errorText || '')));
  page.on('response', (r) => { if (r.status() >= 400 && !r.url().endsWith('/nope')) failed.push(r.url() + ' HTTP ' + r.status()); });

  const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  const brokenImages = () => page.evaluate(() => Array.from(document.images).filter((i) => !i.complete || i.naturalWidth === 0).map((i) => i.src));

  // --- Launching state (no token yet), subpath preview, three widths -------
  for (const [w, h] of [[1440, 900], [375, 812], [320, 640]]) {
    await page.setViewportSize({ width: w, height: h });
    await page.goto(base + '/preview/', { waitUntil: 'networkidle' });
    await page.waitForTimeout(400);
    record(`${w}px: no horizontal overflow`, (await overflow()) <= 0, `scrollWidth-clientWidth=${await overflow()}`);
    const broken = await brokenImages();
    record(`${w}px: no broken images`, broken.length === 0, broken.join(', '));
    record(`${w}px: plaques say launching…`, await page.locator('.js-stat').first().innerText() === 'launching…');
    record(`${w}px: copy button disabled before deploy`, await page.locator('.js-copy-contract').isDisabled());
    record(`${w}px: meme wall has 8 pieces`, (await page.locator('.wall__item').count()) === 8);
    // scroll through the page like a reader so every reveal fires, then check the wall
    const total = await page.evaluate(() => document.body.scrollHeight);
    for (let y = 0; y < total; y += Math.round(h * 0.8)) { await page.evaluate((yy) => window.scrollTo(0, yy), y); await page.waitForTimeout(120); }
    await page.waitForTimeout(900);
    const wallOpacity = await page.evaluate(() => Array.from(document.querySelectorAll('.wall__item')).map((el) => Number(getComputedStyle(el).opacity)));
    record(`${w}px: meme wall items revealed on scroll`, wallOpacity.length === 8 && wallOpacity.every((o) => o > 0.95), wallOpacity.map((o) => o.toFixed(2)).join(','));
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(SHOTS, `home-${w}.jpg`), fullPage: true, type: 'jpeg', quality: 55 });
  }

  // --- Mobile menu + anchor navigation at 375 ----------------------------------
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto(base + '/preview/', { waitUntil: 'networkidle' });
  await page.click('.nav__toggle');
  record('375px: menu opens', await page.locator('#nav-menu').isVisible() && (await page.getAttribute('.nav__toggle', 'aria-expanded')) === 'true');
  await page.click('#nav-menu a[href="#treasury"]');
  // smooth scrolling: poll until the scroll position settles
  for (let last = -1, i = 0; i < 20; i++) {
    await page.waitForTimeout(300);
    const y = await page.evaluate(() => window.scrollY);
    if (y === last && y > 0) break;
    last = y;
  }
  const treasuryTop = await page.evaluate(() => document.getElementById('treasury')?.getBoundingClientRect().top ?? 9999);
  record('375px: anchor link scrolls to Treasury and closes menu', treasuryTop >= -2 && treasuryTop < 120 && !(await page.locator('#nav-menu').isVisible()), `top=${Math.round(treasuryTop)}`);
  await page.keyboard.press('Escape');

  // --- Live state: token + market numbers -------------------------------------
  coin = LIVE_COIN;
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(base + '/preview/', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1400);
  const price = await page.locator('[data-stat="priceUsd"]').innerText();
  const cap = await page.locator('[data-stat="marketCap"]').innerText();
  const vol = await page.locator('[data-stat="volume24h"]').innerText();
  record('live: plaques formatted', price.startsWith('$0.0000025') && cap === '$2.5K' && vol === '$812.25', `${price} ${cap} ${vol}`);
  record('live: contract shown', (await page.locator('.js-contract').innerText()) === LIVE_COIN.token);
  record('live: buy/chart links from JSON', (await page.getAttribute('.hero .js-buy', 'href')) === LIVE_COIN.coinUrl && (await page.getAttribute('.hero .js-chart', 'href')) === LIVE_COIN.chartUrl);
  await page.click('.js-copy-contract');
  await page.waitForTimeout(200);
  const clip = await page.evaluate(() => navigator.clipboard.readText());
  record('live: copy address writes clipboard + toast', clip === LIVE_COIN.token && (await page.locator('.toast').innerText()).includes('copied'), clip);

  // Buy button: confetti and a new tab to coinUrl
  const [popup] = await Promise.all([context.waitForEvent('page'), page.click('.hero .js-confetti')]);
  await page.waitForTimeout(100);
  record('buy: confetti burst rendered', (await page.locator('.confetti').count()) > 0);
  record('buy: opens coin page in new tab', popup.url().startsWith('https://www.si-md.xyz/launchpad'), popup.url());
  await popup.close();

  // Share links + copy link
  const share0 = await page.getAttribute('.js-share[data-share="0"]', 'href');
  record('share: X intent prefilled', !!share0 && share0.startsWith('https://x.com/intent/post?text=') && share0.includes('swarmpalace.si-md.xyz'));
  await page.click('.js-copy-link');
  await page.waitForTimeout(200);
  record('share: copy link', (await page.evaluate(() => navigator.clipboard.readText())) === 'https://swarmpalace.si-md.xyz/');

  // Meme wall download
  const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 15000 }), page.click('.wall__item button')]);
  const dlPath = await dl.path();
  record('wall: PNG download', dl.suggestedFilename() === 'spalace-throne.png' && !!dlPath && fs.statSync(dlPath).size > 5000 && fs.readFileSync(dlPath).subarray(1, 4).toString() === 'PNG', `${dl.suggestedFilename()} ${dlPath ? fs.statSync(dlPath).size : 0}B`);

  // Forge: template switch, typing, download
  await page.click('#forge-templates .chip:nth-child(3)');
  await page.fill('#forge-top', 'Hello court');
  await page.fill('#forge-bottom', 'From the swarm');
  const preview = await page.locator('#forge-preview svg').getAttribute('aria-label');
  record('forge: preview updates with text', preview === 'Hello court / From the swarm' && (await page.getAttribute('#forge-templates .chip:nth-child(3)', 'aria-pressed')) === 'true', preview || '');
  const [dl2] = await Promise.all([page.waitForEvent('download', { timeout: 15000 }), page.click('.js-forge-download')]);
  record('forge: PNG download', dl2.suggestedFilename() === 'spalace-decree.png' && (await page.locator('.forge__status').innerText()).includes('Downloaded'));
  await page.screenshot({ path: path.join(SHOTS, 'forge-1440.jpg'), type: 'jpeg', quality: 55, clip: { x: 0, y: (await page.locator('#forge').boundingBox())?.y ?? 0, width: 1440, height: 760 }, fullPage: true });

  // Brick meter
  for (let i = 0; i < 12; i++) await page.click('.js-brick');
  record('bricks: meter and count update', (await page.getAttribute('.meter', 'aria-valuenow')) === '20' && (await page.locator('.js-brick-count').innerText()) === '12' && (await page.locator('#brick-layer rect').count()) === 12);
  await page.reload({ waitUntil: 'networkidle' });
  record('bricks: persisted in localStorage', (await page.locator('.js-brick-count').innerText()) === '12');

  // Draggable sticker: pointer drag + keyboard (scroll back to the hero first)
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(300);
  const box = await page.locator('#logo-sticker').boundingBox();
  if (box) {
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 60, box.y + box.height / 2 + 30, { steps: 5 });
    await page.mouse.up();
  }
  const after = await page.locator('#logo-sticker').boundingBox();
  record('sticker: drags with the pointer', !!box && !!after && Math.round(after.x - box.x) === 60, `dx=${box && after ? Math.round(after.x - box.x) : 'n/a'}`);
  await page.focus('#logo-sticker');
  await page.keyboard.press('ArrowRight');
  const after2 = await page.locator('#logo-sticker').boundingBox();
  record('sticker: moves with arrow keys', !!after && !!after2 && Math.round(after2.x - after.x) === 12);

  // Keyboard walk: skip link first, visible focus ring on buttons
  await page.goto(base + '/preview/', { waitUntil: 'networkidle' });
  await page.keyboard.press('Tab');
  const firstFocus = await page.evaluate(() => document.activeElement?.className || '');
  record('keyboard: skip link is first tab stop', firstFocus.includes('skip-link'));
  for (let i = 0; i < 4; i++) await page.keyboard.press('Tab');
  const ring = await page.evaluate(() => { const el = document.activeElement; if (!el) return ''; const cs = getComputedStyle(el); return `${el.tagName}.${el.className} outline=${cs.outlineStyle} ${cs.outlineWidth} ${cs.outlineColor}`; });
  record('keyboard: focused control has a solid outline', ring.includes('outline=solid 3px rgb(255, 216, 24)'), ring);
  await page.screenshot({ path: path.join(SHOTS, 'focus-1440.jpg'), type: 'jpeg', quality: 55 });

  // Reduced motion: marquee and bounce stop
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.reload({ waitUntil: 'networkidle' });
  const anims = await page.evaluate(() => [getComputedStyle(document.querySelector('.marquee__track')).animationName, getComputedStyle(document.querySelector('.hero__sticker')).animationName]);
  record('reduced motion: marquee and bounce disabled', anims.every((a) => a === 'none'), anims.join(','));
  await page.emulateMedia({ reducedMotion: 'no-preference' });

  // 404 page at an unknown route
  const res404 = await page.goto(base + '/nope', { waitUntil: 'networkidle' });
  record('404: served with status 404 and styled', res404?.status() === 404 && (await page.locator('.notfound__code').innerText()) === '404' && (await brokenImages()).length === 0);
  await page.setViewportSize({ width: 375, height: 812 });
  record('404: no overflow at 375', (await overflow()) <= 0);
  await page.screenshot({ path: path.join(SHOTS, '404-375.jpg'), type: 'jpeg', quality: 55 });

  // Internal links resolve
  await page.goto(base + '/preview/', { waitUntil: 'networkidle' });
  const hrefs = await page.evaluate(() => Array.from(document.querySelectorAll('a[href]')).map((a) => a.getAttribute('href') || ''));
  const ids = await page.evaluate(() => Array.from(document.querySelectorAll('[id]')).map((e) => e.id));
  const badAnchors = hrefs.filter((h) => h.startsWith('#') && !ids.includes(h.slice(1)));
  record('links: every in-page anchor resolves', badAnchors.length === 0, badAnchors.join(','));
  const externals = [...new Set(hrefs.filter((h) => /^https?:/.test(h)))];
  console.log('external links (not fetched here):', externals.join('  '));

  const realFailures = failed.filter((f) => !/fonts\.(googleapis|gstatic)\.com/.test(f));
  record('no failed resource requests (fonts excluded)', realFailures.length === 0, realFailures.join(' | '));
  record('no console errors', consoleErrors.length === 0, consoleErrors.join(' | '));
  if (failed.length !== realFailures.length) console.log('note: Google Fonts requests failed in this environment (offline); fallback fonts rendered.');

  await browser.close();
  server.close();
  const failures = results.filter((r) => !r.ok);
  fs.writeFileSync(path.join(SHOTS, 'results.json'), JSON.stringify(results, null, 2));
  console.log(`\n${results.length - failures.length}/${results.length} browser checks passed; screenshots in ${SHOTS}`);
  process.exit(failures.length ? 1 : 0);
})().catch((err) => { console.error(err); process.exit(1); });
