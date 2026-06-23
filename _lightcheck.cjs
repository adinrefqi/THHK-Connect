// Light-mode visual audit harness (temporary)
const puppeteer = require('puppeteer');
const path = require('path');

const FILE = process.argv[2] || 'index.html';
const TAG = process.argv[3] || 'before';

(async () => {
  const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 420, height: 900, deviceScaleFactor: 1.5 });

  const url = 'file://' + path.resolve(FILE).replace(/\\/g, '/');
  const SELF = path.basename(FILE).toLowerCase();
  // Block external network (supabase/leaflet/fonts) so it loads fast & offline.
  // Also abort the auth-guard redirect to another page (e.g. index.html) so the
  // page we actually want to audit stays loaded instead of bouncing to login.
  await page.setRequestInterception(true);
  page.on('request', req => {
    const u = req.url();
    if (!u.startsWith('file://')) return req.abort();
    if (req.isNavigationRequest() && req.frame() === page.mainFrame()
        && !u.toLowerCase().endsWith('/' + SELF)) return req.abort();
    req.continue();
  });
  page.on('console', () => {}); // swallow page errors from blocked scripts

  // Seed fake auth sessions so pages that guard on localStorage render their
  // real dashboard instead of bouncing to index.html, and neutralize any
  // location-based redirect as a safety net. Runs before page scripts.
  await page.evaluateOnNewDocument(() => {
    try {
      const seed = {
        piket_session: 'auditor', staff_token: 'audit', staff_session: 'auditor',
        guru_session: 'auditor', admin_session: 'auditor', user_session: 'auditor',
        session: 'auditor', loggedIn: 'true'
      };
      for (const k in seed) localStorage.setItem(k, seed[k]);
    } catch (e) {}
    const block = () => {};
    try { Object.defineProperty(window, 'onbeforeunload', { value: null }); } catch (e) {}
    // Stop full-page navigations to a different file (auth redirects)
    const here = location.pathname.split('/').pop().toLowerCase();
    const guard = (val) => { try { return String(val).toLowerCase().endsWith(here); } catch (e) { return true; } };
    try {
      const desc = Object.getOwnPropertyDescriptor(window.HTMLAnchorElement.prototype, 'href');
    } catch (e) {}
  });

  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
  } catch (e) { /* ignore network-driven timeouts */ }
  // Give DOMContentLoaded handlers a beat to run (some toggle views)
  await new Promise(res => setTimeout(res, 400));

  // Force light theme + reveal all hidden views/sections for a full audit
  await page.evaluate(() => {
    document.documentElement.setAttribute('data-theme', 'light');
    document.querySelectorAll('.hidden').forEach(el => el.classList.remove('hidden'));
    // hide modals (they are intentionally dark) and bottom-nav overlay to reduce clutter
    ['modal-izin', 'modal-bullying'].forEach(id => { const e = document.getElementById(id); if (e) e.style.display = 'none'; });
  });

  // Let CSS color transitions settle — reading mid-transition reports stale
  // dark-mode colors and produces false positives.
  await new Promise(res => setTimeout(res, 600));

  // --- Heuristic: find text nodes that are "invisible" (near-white text on near-white bg) ---
  const lowContrast = await page.evaluate(() => {
    function parseRGB(s) {
      const m = s.match(/rgba?\(([^)]+)\)/); if (!m) return null;
      const p = m[1].split(',').map(x => parseFloat(x));
      return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
    }
    function lum({r,g,b}) {
      const f = c => { c/=255; return c<=0.03928 ? c/12.92 : Math.pow((c+0.055)/1.055,2.4); };
      return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b);
    }
    function effectiveBg(el) {
      let node = el;
      while (node && node !== document.documentElement) {
        const bg = getComputedStyle(node).backgroundColor;
        const c = parseRGB(bg);
        if (c && c.a > 0.4) return c;
        node = node.parentElement;
      }
      return { r:248, g:250, b:252, a:1 }; // page bg in light mode
    }
    const out = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      const t = n.textContent.trim();
      if (!t || t.length < 2) continue;
      const el = n.parentElement;
      if (!el) continue;
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) < 0.1) continue;
      const rect = el.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) continue;
      const fg = parseRGB(cs.color); if (!fg) continue;
      const bg = effectiveBg(el);
      const L1 = lum(fg) + 0.05, L2 = lum(bg) + 0.05;
      const ratio = L1 > L2 ? L1/L2 : L2/L1;
      if (ratio < 2.0) {
        out.push({ text: t.slice(0, 40), color: cs.color, bg: `rgb(${bg.r|0},${bg.g|0},${bg.b|0})`, ratio: +ratio.toFixed(2) });
      }
    }
    return out;
  });

  console.log(`\n=== [${FILE}] LOW-CONTRAST TEXT in light mode (${TAG}) — ${lowContrast.length} items ===`);
  lowContrast.slice(0, 60).forEach(o => console.log(`  ratio ${o.ratio}  "${o.text}"  color=${o.color}  bg=${o.bg}`));

  await page.screenshot({ path: `_audit_${path.basename(FILE,'.html')}_${TAG}.png`, fullPage: true });
  await browser.close();
})();
