// Swarm Palace · site script. Plain ES2020, no build step, no dependencies.
// Typechecked with `tsc --checkJs` through JSDoc annotations (see tsconfig.json).
(function () {
  'use strict';

  /** @typedef {{ marketCap?: number|string|null, priceUsd?: number|string|null, volume24h?: number|string|null }} Market */
  /** @typedef {{ name?: string, symbol?: string, token?: string|null, chainName?: string, coinUrl?: string, chartUrl?: string, status?: string, logo?: string, market?: Market }} CoinData */

  const SITE_URL = 'https://swarmpalace.si-md.xyz/';
  const LAUNCHPAD_URL = 'https://www.si-md.xyz/launchpad';
  const COIN_JSON = '/simd-coin.json';
  const REFRESH_MS = 30000;
  const DEFAULT_LOGO = './assets/logo-512.png';
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  /** @param {string} sel @param {ParentNode=} root @returns {HTMLElement[]} */
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  /** @param {string} sel @returns {HTMLElement|null} */
  const $ = (sel) => document.querySelector(sel);

  // ---------------------------------------------------------------------------
  // Toast
  // ---------------------------------------------------------------------------
  const toastEl = $('.toast');
  /** @type {number|undefined} */
  let toastTimer;
  /** @param {string} msg */
  function toast(msg) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.add('is-on');
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toastEl.classList.remove('is-on'), 2600);
  }

  /** @param {string} text @returns {Promise<boolean>} */
  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (_err) {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      let ok = false;
      try { ok = document.execCommand('copy'); } catch (_e) { ok = false; }
      ta.remove();
      return ok;
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------
  const navToggle = $('.nav__toggle');
  const navMenu = $('#nav-menu');
  if (navToggle && navMenu) {
    const setOpen = (/** @type {boolean} */ open) => {
      navToggle.setAttribute('aria-expanded', String(open));
      navMenu.classList.toggle('is-open', open);
    };
    navToggle.addEventListener('click', () => setOpen(navToggle.getAttribute('aria-expanded') !== 'true'));
    navMenu.addEventListener('click', (e) => {
      if (e.target instanceof HTMLElement && e.target.closest('a')) setOpen(false);
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && navToggle.getAttribute('aria-expanded') === 'true') {
        setOpen(false);
        navToggle.focus();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Number formatting + tweening
  // ---------------------------------------------------------------------------
  /** @param {unknown} v @returns {number|null} */
  function toNumber(v) {
    if (v === null || v === undefined || v === '') return null;
    const n = typeof v === 'number' ? v : Number(v);
    return Number.isFinite(n) ? n : null;
  }

  /** @param {number} n @param {'price'|'usd'|'int'|'pct'} kind @returns {string} */
  function formatNumber(n, kind) {
    if (kind === 'int') return Math.round(n).toLocaleString('en-US');
    if (kind === 'pct') return Math.round(n) + '%';
    if (kind === 'price') {
      if (n === 0) return '$0';
      if (n >= 1) return '$' + n.toLocaleString('en-US', { maximumFractionDigits: 2, minimumFractionDigits: 2 });
      if (n >= 0.01) return '$' + n.toLocaleString('en-US', { maximumFractionDigits: 4, minimumFractionDigits: 4 });
      // very small prices: keep 4 significant digits
      const digits = Math.min(12, Math.max(6, Math.ceil(-Math.log10(n)) + 3));
      return '$' + n.toFixed(digits).replace(/0+$/, '');
    }
    // usd compact
    const abs = Math.abs(n);
    if (abs >= 1e9) return '$' + (n / 1e9).toLocaleString('en-US', { maximumFractionDigits: 2 }) + 'B';
    if (abs >= 1e6) return '$' + (n / 1e6).toLocaleString('en-US', { maximumFractionDigits: 2 }) + 'M';
    if (abs >= 1e3) return '$' + (n / 1e3).toLocaleString('en-US', { maximumFractionDigits: 1 }) + 'K';
    return '$' + n.toLocaleString('en-US', { maximumFractionDigits: 2 });
  }

  /** @type {WeakMap<Element, number>} */
  const tweenFrames = new WeakMap();
  /**
   * Animate an element's text from its last value to `to`.
   * @param {HTMLElement} el @param {number} to @param {'price'|'usd'|'int'|'pct'} kind @param {number=} duration
   */
  function tweenNumber(el, to, kind, duration) {
    const from = toNumber(el.dataset.value) ?? 0;
    const dur = reduceMotion.matches ? 0 : (duration ?? 900);
    el.dataset.value = String(to);
    const prev = tweenFrames.get(el);
    if (prev) cancelAnimationFrame(prev);
    if (dur === 0 || from === to) { el.textContent = formatNumber(to, kind); return; }
    const start = performance.now();
    const step = (/** @type {number} */ now) => {
      const t = Math.min(1, (now - start) / dur);
      const eased = 1 - Math.pow(1 - t, 3);
      el.textContent = formatNumber(from + (to - from) * eased, kind);
      if (t < 1) tweenFrames.set(el, requestAnimationFrame(step));
    };
    tweenFrames.set(el, requestAnimationFrame(step));
  }

  // ---------------------------------------------------------------------------
  // Live coin data
  // ---------------------------------------------------------------------------
  /** @type {CoinData} */
  let coin = {};
  /** @type {string} */
  let logoSrc = DEFAULT_LOGO;

  /** @param {CoinData} data */
  function applyCoin(data) {
    coin = data || {};
    const buyUrl = coin.coinUrl || LAUNCHPAD_URL;
    const chartUrl = coin.chartUrl || coin.coinUrl || LAUNCHPAD_URL;
    $$('.js-buy').forEach((a) => a.setAttribute('href', buyUrl));
    $$('.js-chart').forEach((a) => a.setAttribute('href', chartUrl));
    $$('.js-chain').forEach((el) => { el.textContent = coin.chainName || 'Ethereum'; });

    const token = typeof coin.token === 'string' && /^0x[0-9a-fA-F]{40}$/.test(coin.token) ? coin.token : null;
    const addrEl = $('.js-contract');
    const copyBtn = $('.js-copy-contract');
    const hint = $('.js-contract-hint');
    if (addrEl && copyBtn instanceof HTMLButtonElement) {
      if (token) {
        addrEl.textContent = token;
        copyBtn.disabled = false;
        copyBtn.dataset.token = token;
        if (hint) {
          hint.textContent = '';
          const a = document.createElement('a');
          a.href = 'https://etherscan.io/token/' + token;
          a.target = '_blank';
          a.rel = 'noopener';
          a.textContent = 'View the token on Etherscan';
          hint.append('Deployed on ' + (coin.chainName || 'Ethereum') + '. ', a, '.');
        }
      } else {
        addrEl.textContent = 'launching…';
        copyBtn.disabled = true;
        delete copyBtn.dataset.token;
      }
    }

    const status = $('.js-status');
    const statusWrap = $('.hero__status');
    if (status) {
      const live = token !== null;
      const label = coin.status ? coin.status : (live ? 'live' : 'launching…');
      status.textContent = 'Status: ' + label;
      statusWrap?.classList.toggle('is-live', live);
    }

    const market = coin.market || {};
    let any = false;
    $$('.js-stat').forEach((el) => {
      const key = /** @type {keyof Market} */ (el.dataset.stat || '');
      const kind = /** @type {'price'|'usd'} */ (el.dataset.kind === 'price' ? 'price' : 'usd');
      const n = toNumber(market[key]);
      if (n === null || !token) {
        el.textContent = 'launching…';
        delete el.dataset.value;
      } else {
        any = true;
        tweenNumber(el, n, kind);
      }
    });
    const updated = $('.js-updated');
    if (updated) {
      updated.textContent = any
        ? 'Palace report updated at ' + new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) + '. Refreshes every 30 seconds.'
        : 'The throne is not live yet. Plaques fill in once the token is deployed.';
    }

    const nextLogo = typeof coin.logo === 'string' && coin.logo.trim() !== '' ? coin.logo : DEFAULT_LOGO;
    if (nextLogo !== logoSrc) {
      logoSrc = nextLogo;
      $$('img.js-logo').forEach((img) => { img.setAttribute('src', logoSrc); });
      $$('image.js-logo-svg').forEach((im) => { im.setAttribute('href', logoSrc); });
      logoDataUrl = null;
    }
  }

  async function loadCoin() {
    try {
      const res = await fetch(COIN_JSON, { cache: 'no-store' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = /** @type {CoinData} */ (await res.json());
      applyCoin(data);
    } catch (_err) {
      applyCoin({});
    }
  }
  loadCoin();
  window.setInterval(loadCoin, REFRESH_MS);

  // Copy contract
  $$('.js-copy-contract').forEach((btn) => btn.addEventListener('click', async () => {
    const token = btn.dataset.token;
    if (!token) { toast('The address appears once the token is deployed.'); return; }
    toast((await copyText(token)) ? 'Contract address copied.' : 'Unable to copy. Select the address and copy it by hand.');
  }));

  // ---------------------------------------------------------------------------
  // Share
  // ---------------------------------------------------------------------------
  const SHARE_TEXTS = [
    'The swarm built this palace. $SPALACE is a meme kingdom raised by a thousand frog bots in one night. Fixed supply, no owner, no tax.',
    'One night, one palace, one crowned frog who did none of the work. $SPALACE on Ethereum, built 100% by an AI swarm.',
    'No owner. No tax. No mint. Just a frog on a golden throne. $SPALACE, the Swarm Palace.',
  ];
  $$('.js-share').forEach((a) => {
    const i = Number(a.dataset.share) || 0;
    const url = 'https://x.com/intent/post?text=' + encodeURIComponent(SHARE_TEXTS[i] || SHARE_TEXTS[0]) + '&url=' + encodeURIComponent(SITE_URL);
    a.setAttribute('href', url);
  });
  $$('.js-copy-link').forEach((btn) => btn.addEventListener('click', async () => {
    const ok = await copyText(SITE_URL);
    const status = $('.share__status');
    if (status) status.textContent = ok ? 'Link copied: ' + SITE_URL : 'Unable to copy. The link is ' + SITE_URL;
    toast(ok ? 'Site link copied.' : 'Unable to copy the link.');
  }));

  // ---------------------------------------------------------------------------
  // Scroll reveals, counters, stagger
  // ---------------------------------------------------------------------------
  const reveals = $$('.reveal');
  reveals.forEach((el, i) => {
    const siblings = el.parentElement ? Array.from(el.parentElement.children).filter((c) => c.classList.contains('reveal')) : [];
    const idx = Math.max(0, siblings.indexOf(el));
    el.style.setProperty('--stagger', Math.min(idx, 6) * 100 + 'ms');
    if (i === 0) el.classList.add('is-visible');
  });

  /** @param {HTMLElement} el */
  function runCounter(el) {
    const target = toNumber(el.dataset.count) ?? 0;
    const suffix = el.dataset.suffix || '';
    if (el.dataset.done) return;
    el.dataset.done = '1';
    const kind = suffix === '%' ? 'pct' : 'int';
    el.dataset.value = '0';
    tweenNumber(el, target, kind, 1600);
    if (suffix && kind !== 'pct') el.textContent += suffix;
  }

  /** @type {IntersectionObserver|null} */
  let io = null;
  /** Observe a reveal element added after initial setup. @param {HTMLElement} el */
  function observeReveal(el) {
    if (io) io.observe(el); else el.classList.add('is-visible');
  }
  if ('IntersectionObserver' in window) {
    io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        $$('.js-count', entry.target).forEach((c) => runCounter(/** @type {HTMLElement} */ (c)));
        if (entry.target.classList.contains('js-count')) runCounter(/** @type {HTMLElement} */ (entry.target));
        io?.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.15 });
    reveals.forEach((el) => io?.observe(el));
    $$('.js-count').forEach((el) => io?.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add('is-visible'));
    $$('.js-count').forEach((el) => runCounter(el));
  }

  // ---------------------------------------------------------------------------
  // Magnetic buttons (pointer only, motion opt-in)
  // ---------------------------------------------------------------------------
  if (!reduceMotion.matches && window.matchMedia('(hover: hover) and (pointer: fine)').matches) {
    $$('.js-magnet').forEach((btn) => {
      btn.addEventListener('pointermove', (e) => {
        const r = btn.getBoundingClientRect();
        const dx = (e.clientX - (r.left + r.width / 2)) / r.width;
        const dy = (e.clientY - (r.top + r.height / 2)) / r.height;
        btn.style.translate = `${dx * 8 - 2}px ${dy * 8 - 2}px`;
      });
      btn.addEventListener('pointerleave', () => { btn.style.translate = ''; });
    });
  }

  // ---------------------------------------------------------------------------
  // Confetti
  // ---------------------------------------------------------------------------
  const confettiLayer = $('.confetti-layer');
  const CONFETTI_COLORS = ['#a8f030', '#ffd818', '#7800ff', '#ffffff', '#b57bff'];
  /** @param {number} x @param {number} y @param {number=} count */
  function burst(x, y, count) {
    if (!confettiLayer || reduceMotion.matches) return;
    const n = count ?? 40;
    const frag = document.createDocumentFragment();
    for (let i = 0; i < n; i++) {
      const p = document.createElement('span');
      p.className = 'confetti';
      const angle = Math.random() * Math.PI * 2;
      const dist = 80 + Math.random() * 220;
      p.style.left = x + 'px';
      p.style.top = y + 'px';
      p.style.background = CONFETTI_COLORS[i % CONFETTI_COLORS.length];
      p.style.setProperty('--dx', Math.cos(angle) * dist + 'px');
      p.style.setProperty('--dy', Math.sin(angle) * dist + 160 + 'px');
      p.style.setProperty('--rot', Math.round(Math.random() * 720 - 360) + 'deg');
      p.style.borderRadius = i % 3 === 0 ? '50%' : '2px';
      frag.appendChild(p);
    }
    confettiLayer.appendChild(frag);
    window.setTimeout(() => { $$('.confetti', confettiLayer).slice(0, n).forEach((c) => c.remove()); }, 1500);
  }
  $$('.js-confetti').forEach((el) => el.addEventListener('click', (e) => {
    const r = el.getBoundingClientRect();
    burst(e.clientX || r.left + r.width / 2, e.clientY || r.top + r.height / 2);
  }));

  // ---------------------------------------------------------------------------
  // Draggable logo sticker (pointer + keyboard)
  // ---------------------------------------------------------------------------
  const sticker = $('#logo-sticker');
  if (sticker) {
    let x = 0, y = 0;
    let startX = 0, startY = 0, baseX = 0, baseY = 0;
    const apply = () => { sticker.style.translate = `${x}px ${y}px`; };
    sticker.addEventListener('pointerdown', (e) => {
      sticker.setPointerCapture(e.pointerId);
      sticker.classList.add('is-dragging');
      startX = e.clientX; startY = e.clientY; baseX = x; baseY = y;
    });
    sticker.addEventListener('pointermove', (e) => {
      if (!sticker.classList.contains('is-dragging')) return;
      x = baseX + (e.clientX - startX);
      y = baseY + (e.clientY - startY);
      apply();
    });
    const end = () => sticker.classList.remove('is-dragging');
    sticker.addEventListener('pointerup', end);
    sticker.addEventListener('pointercancel', end);
    sticker.addEventListener('keydown', (e) => {
      const step = e.shiftKey ? 40 : 12;
      const map = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
      const d = /** @type {Record<string, number[]>} */ (map)[e.key];
      if (d) { x += d[0]; y += d[1]; apply(); e.preventDefault(); }
      if (e.key === 'Home') { x = 0; y = 0; apply(); e.preventDefault(); }
    });
    sticker.addEventListener('dblclick', () => { x = 0; y = 0; apply(); });
  }

  // ---------------------------------------------------------------------------
  // SVG meme compositions (shared by the wall and the forge)
  // ---------------------------------------------------------------------------
  const SVG_NS = 'http://www.w3.org/2000/svg';
  const C = { violet: '#7800ff', violetDeep: '#2a0a4f', ink: '#180030', lime: '#a8f030', gold: '#ffd818', goldDeep: '#f0a800', cream: '#f5efff', white: '#ffffff' };
  const MEME_FONT = "'Bangers', Impact, 'Arial Black', sans-serif";

  /** @param {string} s @returns {string} */
  const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] || c);

  /**
   * Outlined meme text line.
   * @param {string} text @param {number} y @param {number=} size @param {string=} fill
   */
  function memeText(text, y, size, fill) {
    const s = size ?? 46;
    const t = esc(text.toUpperCase());
    return `<text x="250" y="${y}" text-anchor="middle" font-family="${MEME_FONT}" font-size="${s}" letter-spacing="2" fill="${fill || C.white}" stroke="${C.ink}" stroke-width="${Math.round(s / 6)}" paint-order="stroke" stroke-linejoin="round">${t}</text>`;
  }

  /** @param {number} x @param {number} y @param {number} w @param {number=} rot */
  function logoImg(x, y, w, rot) {
    const r = rot ?? 0;
    return `<g transform="rotate(${r} ${x + w / 2} ${y + w / 2})"><rect x="${x - 6}" y="${y - 6}" width="${w + 12}" height="${w + 12}" rx="${w * 0.22}" fill="${C.white}" stroke="${C.ink}" stroke-width="6"/><clipPath id="clip-${Math.round(x)}-${Math.round(y)}-${Math.round(w)}"><rect x="${x}" y="${y}" width="${w}" height="${w}" rx="${w * 0.2}"/></clipPath><image class="js-logo-svg" href="${logoSrc}" x="${x}" y="${y}" width="${w}" height="${w}" clip-path="url(#clip-${Math.round(x)}-${Math.round(y)}-${Math.round(w)})" preserveAspectRatio="xMidYMid slice"/></g>`;
  }

  const halftone = `<pattern id="ht" width="12" height="12" patternUnits="userSpaceOnUse"><circle cx="6" cy="6" r="2" fill="${C.ink}" opacity="0.35"/></pattern>`;
  const burstBg = (/** @type {string} */ a, /** @type {string} */ b) => {
    let rays = '';
    for (let i = 0; i < 16; i++) {
      const ang = (i / 16) * Math.PI * 2;
      const ang2 = ((i + 0.5) / 16) * Math.PI * 2;
      rays += `<polygon points="250,250 ${250 + Math.cos(ang) * 420},${250 + Math.sin(ang) * 420} ${250 + Math.cos(ang2) * 420},${250 + Math.sin(ang2) * 420}" fill="${b}"/>`;
    }
    return `<rect width="500" height="500" fill="${a}"/>${rays}`;
  };
  const crown = (/** @type {number} */ x, /** @type {number} */ y, /** @type {number} */ s) =>
    `<polygon points="${x - s},${y} ${x - s * 0.6},${y - s} ${x - s * 0.2},${y - s * 0.45} ${x},${y - s * 1.2} ${x + s * 0.2},${y - s * 0.45} ${x + s * 0.6},${y - s} ${x + s},${y}" fill="${C.gold}" stroke="${C.ink}" stroke-width="5" stroke-linejoin="round"/>`;

  /** @typedef {{ id: string, title: string, top: string, bottom: string, build: (top: string, bottom: string) => string }} Template */
  /** @type {Template[]} */
  const TEMPLATES = [
    {
      id: 'throne', title: 'The king approves', top: 'The swarm built this', bottom: 'I just sit here',
      build: (t, b) => `${burstBg(C.violet, '#6a00e0')}<rect width="500" height="500" fill="url(#ht)"/>
        <path d="M130 470 L130 200 Q130 140 190 140 L310 140 Q370 140 370 200 L370 470 Z" fill="${C.gold}" stroke="${C.ink}" stroke-width="8"/>
        <rect x="110" y="420" width="280" height="30" rx="8" fill="${C.goldDeep}" stroke="${C.ink}" stroke-width="6"/>
        ${logoImg(165, 200, 170, -3)}${memeText(t, 78)}${memeText(b, 480, 40)}`,
    },
    {
      id: 'swarm', title: 'Send the swarm', top: 'One prompt', bottom: 'One thousand frogs',
      build: (t, b) => {
        let frogs = '';
        for (let i = 0; i < 14; i++) {
          const x = 40 + ((i * 97) % 420), y = 110 + ((i * 61) % 300), s = 34 + (i % 4) * 10;
          frogs += logoImg(x, y, s, (i % 2 ? 1 : -1) * ((i * 13) % 25));
        }
        return `<rect width="500" height="500" fill="${C.violetDeep}"/><rect width="500" height="500" fill="url(#ht)"/>${frogs}${logoImg(170, 170, 160, 4)}${memeText(t, 78)}${memeText(b, 480, 40)}`;
      },
    },
    {
      id: 'ticker', title: 'Giant ticker', top: '$SPALACE', bottom: 'Not financial advice',
      build: (t, b) => `${burstBg(C.lime, '#8ad020')}<rect width="500" height="500" fill="url(#ht)"/>${logoImg(130, 120, 240, 6)}${crown(250, 100, 60)}${memeText(t, 100, 80, C.gold)}${memeText(b, 470, 36)}`,
    },
    {
      id: 'wojak', title: 'Palace at 3am', top: 'Still building', bottom: 'Sun comes up anyway',
      build: (t, b) => `<rect width="500" height="500" fill="#0d0418"/><circle cx="400" cy="100" r="46" fill="${C.gold}" stroke="${C.ink}" stroke-width="6"/>
        <g fill="${C.violet}" stroke="${C.ink}" stroke-width="6"><rect x="40" y="300" width="420" height="180"/><rect x="150" y="220" width="200" height="80"/><polygon points="140,220 250,150 360,220"/><rect x="20" y="340" width="60" height="140"/><rect x="420" y="340" width="60" height="140"/></g>
        <g fill="${C.lime}"><rect x="70" y="330" width="40" height="18" rx="3"/><rect x="130" y="330" width="40" height="18" rx="3"/><rect x="330" y="330" width="40" height="18" rx="3"/><rect x="100" y="360" width="40" height="18" rx="3"/><rect x="360" y="360" width="40" height="18" rx="3"/><rect x="200" y="390" width="40" height="18" rx="3"/></g>
        ${logoImg(200, 330, 100, -6)}${memeText(t, 78)}${memeText(b, 480, 40)}`,
    },
    {
      id: 'stonks', title: 'Royal decree', top: 'By royal decree', bottom: 'No tax. No mint. No owner.',
      build: (t, b) => `<rect width="500" height="500" fill="${C.gold}"/><rect width="500" height="500" fill="url(#ht)"/>
        <rect x="50" y="110" width="400" height="300" rx="20" fill="${C.cream}" stroke="${C.ink}" stroke-width="8"/>
        <g stroke="${C.ink}" stroke-width="6" stroke-linecap="round"><line x1="90" y1="300" x2="300" y2="300"/><line x1="90" y1="335" x2="260" y2="335"/><line x1="90" y1="370" x2="320" y2="370"/></g>
        <circle cx="390" cy="350" r="40" fill="${C.violet}" stroke="${C.ink}" stroke-width="6"/>
        ${logoImg(90, 140, 130, -5)}${memeText(t, 78, 46, C.white)}${memeText(b, 470, 34)}`,
    },
    {
      id: 'coin', title: 'Fresh mint', top: '1,000,000,000', bottom: 'Minted once. Never again.',
      build: (t, b) => `${burstBg('#2a0a4f', '#3a1266')}<circle cx="250" cy="260" r="170" fill="${C.goldDeep}" stroke="${C.ink}" stroke-width="8"/><circle cx="250" cy="260" r="140" fill="${C.gold}" stroke="${C.ink}" stroke-width="6" stroke-dasharray="10 8"/>
        ${logoImg(170, 180, 160, 0)}${memeText(t, 78, 50, C.lime)}${memeText(b, 480, 36)}`,
    },
    {
      id: 'wall', title: 'Brick by brick', top: 'Brick by brick', bottom: 'The swarm never sleeps',
      build: (t, b) => {
        let bricks = '';
        for (let r = 0; r < 9; r++) for (let c = 0; c < 6; c++) {
          const x = c * 90 - (r % 2 ? 45 : 0), y = 90 + r * 44;
          bricks += `<rect x="${x}" y="${y}" width="84" height="38" rx="4" fill="${(r + c) % 5 === 0 ? C.lime : C.violet}" stroke="${C.ink}" stroke-width="4"/>`;
        }
        return `<rect width="500" height="500" fill="${C.violetDeep}"/>${bricks}${logoImg(150, 150, 200, 5)}${memeText(t, 78)}${memeText(b, 480, 40)}`;
      },
    },
    {
      id: 'crowd', title: 'Royal portrait', top: 'His Majesty', bottom: 'Did none of the work',
      build: (t, b) => `<rect width="500" height="500" fill="${C.ink}"/><rect x="40" y="40" width="420" height="420" rx="18" fill="${C.violet}" stroke="${C.gold}" stroke-width="14"/><rect x="60" y="60" width="380" height="380" rx="10" fill="none" stroke="${C.ink}" stroke-width="6"/>
        <rect width="500" height="500" fill="url(#ht)"/>${logoImg(130, 130, 240, 0)}${crown(250, 118, 54)}${memeText(t, 78, 50, C.gold)}${memeText(b, 480, 40)}`,
    },
  ];

  /** @param {Template} tpl @param {string} top @param {string} bottom @returns {string} */
  function renderSvg(tpl, top, bottom) {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 500 500" width="500" height="500" role="img" aria-label="${esc(top)} / ${esc(bottom)}"><defs>${halftone}</defs>${tpl.build(top, bottom)}</svg>`;
  }

  /** @type {string|null} */
  let logoDataUrl = null;
  /** @returns {Promise<string>} */
  async function getLogoDataUrl() {
    if (logoDataUrl) return logoDataUrl;
    const res = await fetch(logoSrc);
    const blob = await res.blob();
    const url = await new Promise((resolve, reject) => {
      const fr = new FileReader();
      fr.onload = () => resolve(String(fr.result));
      fr.onerror = () => reject(fr.error);
      fr.readAsDataURL(blob);
    });
    logoDataUrl = /** @type {string} */ (url);
    return logoDataUrl;
  }

  /**
   * Rasterise an SVG string to a PNG download (canvas is used only for export).
   * @param {string} svgMarkup @param {string} filename
   */
  async function downloadPng(svgMarkup, filename) {
    const data = await getLogoDataUrl();
    const markup = svgMarkup.split(`href="${logoSrc}"`).join(`href="${data}"`);
    const blob = new Blob([markup], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    try {
      const img = new Image();
      img.decoding = 'async';
      await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = () => reject(new Error('svg load failed')); img.src = url; });
      const size = 1000;
      const canvas = document.createElement('canvas');
      canvas.width = size; canvas.height = size;
      const ctx = canvas.getContext('2d');
      if (!ctx) throw new Error('no canvas');
      ctx.drawImage(img, 0, 0, size, size);
      const png = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
      if (!png) throw new Error('no png');
      const a = document.createElement('a');
      a.href = URL.createObjectURL(png);
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    } finally {
      URL.revokeObjectURL(url);
    }
  }

  // Meme wall
  const wall = $('#wall');
  if (wall) {
    TEMPLATES.forEach((tpl, i) => {
      const li = document.createElement('li');
      li.className = 'wall__item card reveal';
      li.style.setProperty('--stagger', (i % 4) * 100 + 'ms');
      li.innerHTML = `<div class="wall__art">${renderSvg(tpl, tpl.top, tpl.bottom)}</div><p class="wall__title">${esc(tpl.title)}</p><button class="btn btn--primary btn--sm" type="button" data-wall="${tpl.id}">Download PNG</button>`;
      const btn = li.querySelector('button');
      btn?.addEventListener('click', async () => {
        btn.textContent = 'Preparing…';
        try {
          await downloadPng(renderSvg(tpl, tpl.top, tpl.bottom), `spalace-${tpl.id}.png`);
          toast('Saved ' + tpl.title + ' as PNG.');
        } catch (_err) {
          toast('Unable to make the PNG in this browser.');
        } finally {
          btn.textContent = 'Download PNG';
        }
      });
      wall.appendChild(li);
      observeReveal(li);
    });
  }

  // Meme forge
  const forgeTemplates = $('#forge-templates');
  const forgePreview = $('#forge-preview');
  const topInput = /** @type {HTMLInputElement|null} */ (document.getElementById('forge-top'));
  const bottomInput = /** @type {HTMLInputElement|null} */ (document.getElementById('forge-bottom'));
  const forgeForm = $('#forge-form');
  const forgeStatus = $('.forge__status');
  let activeTpl = TEMPLATES[0];
  const RANDOM_LINES = [
    ['Gm from the throne', 'The swarm says hi'],
    ['Built in one night', 'Argued for three'],
    ['No roadmap', 'Just bricks'],
    ['Royal treasury', '1 billion, minted once'],
    ['Pepe approved', 'Swarm delivered'],
    ['Frogs assembled', 'Palace deployed'],
  ];

  function renderForge() {
    if (!forgePreview) return;
    forgePreview.innerHTML = renderSvg(activeTpl, topInput?.value || ' ', bottomInput?.value || ' ');
  }
  if (forgeTemplates && forgePreview) {
    TEMPLATES.forEach((tpl) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'chip';
      b.textContent = tpl.title;
      b.setAttribute('aria-pressed', String(tpl === activeTpl));
      b.addEventListener('click', () => {
        activeTpl = tpl;
        $$('.chip', forgeTemplates).forEach((c) => c.setAttribute('aria-pressed', String(c === b)));
        renderForge();
      });
      forgeTemplates.appendChild(b);
    });
    topInput?.addEventListener('input', renderForge);
    bottomInput?.addEventListener('input', renderForge);
    forgeForm?.addEventListener('submit', (e) => e.preventDefault());
    renderForge();
    $$('.js-forge-random').forEach((btn) => btn.addEventListener('click', () => {
      const pick = RANDOM_LINES[Math.floor(Math.random() * RANDOM_LINES.length)];
      if (topInput) topInput.value = pick[0];
      if (bottomInput) bottomInput.value = pick[1];
      renderForge();
    }));
    $$('.js-forge-download').forEach((btn) => btn.addEventListener('click', async () => {
      if (forgeStatus) forgeStatus.textContent = 'Preparing your decree…';
      try {
        await downloadPng(renderSvg(activeTpl, topInput?.value || ' ', bottomInput?.value || ' '), 'spalace-decree.png');
        if (forgeStatus) forgeStatus.textContent = 'Downloaded spalace-decree.png.';
      } catch (_err) {
        if (forgeStatus) forgeStatus.textContent = 'Unable to make the PNG in this browser. Try a desktop browser.';
      }
    }));
  }

  // ---------------------------------------------------------------------------
  // Signature: lay bricks, pump the hype meter
  // ---------------------------------------------------------------------------
  const BRICK_KEY = 'spalace.bricks';
  const BRICK_GOAL = 60;
  const brickLayer = document.getElementById('brick-layer');
  const brickBtn = $('.js-brick');
  const brickCount = $('.js-brick-count');
  const meter = $('.meter');
  const meterFill = $('.js-meter-fill');
  const meterText = $('.js-meter-text');
  const buildMsg = $('.js-build-msg');
  const crownEl = $('.js-crown');
  const buildSection = $('#build');
  let bricks = 0;
  try { bricks = Math.min(BRICK_GOAL, Number(localStorage.getItem(BRICK_KEY)) || 0); } catch (_e) { bricks = 0; }

  /** @param {number} i @param {boolean} animate */
  function drawBrick(i, animate) {
    if (!brickLayer) return;
    const cols = 6, w = 44, h = 20;
    const row = Math.floor(i / cols), col = i % cols;
    const x = 26 + col * (w + 2) + (row % 2 ? 22 : 0);
    const y = 226 - row * (h + 2);
    const r = document.createElementNS(SVG_NS, 'rect');
    r.setAttribute('class', 'brick');
    r.setAttribute('x', String(x)); r.setAttribute('y', String(y));
    r.setAttribute('width', String(w)); r.setAttribute('height', String(h)); r.setAttribute('rx', '3');
    if (col === cols - 1 && row % 2) r.setAttribute('width', String(w - 22));
    if (animate && !reduceMotion.matches && typeof r.animate === 'function') {
      r.animate([{ transform: 'translateY(-40px) scale(0.6)', opacity: 0 }, { transform: 'translateY(0) scale(1)', opacity: 1 }], { duration: 350, easing: 'cubic-bezier(0.2, 0, 0, 1)' });
    }
    brickLayer.appendChild(r);
  }

  const MESSAGES = [
    [1, 'First brick. The swarm notices.'],
    [10, 'Ten bricks. A frog brings you a tiny hard hat.'],
    [25, 'A wall! The king nods from the throne.'],
    [45, 'Nearly there. The swarm is chanting your name.'],
    [60, 'Palace complete. The crown is lit. Long live the swarm.'],
  ];

  function renderBuild() {
    const pct = Math.round((bricks / BRICK_GOAL) * 100);
    if (brickCount) brickCount.textContent = String(bricks);
    if (meterFill) meterFill.style.width = pct + '%';
    if (meterText) meterText.textContent = pct + '% hype';
    if (meter) { meter.setAttribute('aria-valuenow', String(pct)); meter.setAttribute('aria-valuetext', pct + ' percent'); }
    const done = bricks >= BRICK_GOAL;
    crownEl?.classList.toggle('is-lit', done);
    buildSection?.classList.toggle('is-complete', done);
    if (brickBtn instanceof HTMLButtonElement) brickBtn.textContent = done ? 'Reset the wall' : 'Lay a brick';
  }

  for (let i = 0; i < bricks; i++) drawBrick(i, false);
  renderBuild();
  brickBtn?.addEventListener('click', (e) => {
    if (bricks >= BRICK_GOAL) {
      bricks = 0;
      if (brickLayer) brickLayer.innerHTML = '';
      if (buildMsg) buildMsg.textContent = 'Wall cleared. The swarm is ready for round two.';
    } else {
      drawBrick(bricks, true);
      bricks += 1;
      const m = MESSAGES.find((pair) => pair[0] === bricks);
      if (m && buildMsg) buildMsg.textContent = String(m[1]);
      if (bricks >= BRICK_GOAL) {
        const r = brickBtn.getBoundingClientRect();
        burst(e.clientX || r.left + r.width / 2, e.clientY || r.top + r.height / 2, 80);
      }
    }
    try { localStorage.setItem(BRICK_KEY, String(bricks)); } catch (_err) { /* storage unavailable: session only */ }
    renderBuild();
  });
})();
