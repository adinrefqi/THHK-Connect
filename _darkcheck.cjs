const puppeteer = require('puppeteer');
const path = require('path');
const FILE = process.argv[2] || 'index.html';
(async () => {
  const b = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] });
  const p = await b.newPage();
  await p.setViewport({ width: 420, height: 900, deviceScaleFactor: 1.5 });
  const SELF = path.basename(FILE).toLowerCase();
  await p.setRequestInterception(true);
  p.on('request', r => {
    const u = r.url();
    if (!u.startsWith('file://')) return r.abort();
    if (r.isNavigationRequest() && r.frame() === p.mainFrame()
        && !u.toLowerCase().endsWith('/' + SELF)) return r.abort();
    r.continue();
  });
  await p.evaluateOnNewDocument(() => {
    try {
      const seed = { piket_session: 'auditor', staff_token: 'audit', staff_session: 'auditor',
        guru_session: 'auditor', admin_session: 'auditor', user_session: 'auditor',
        session: 'auditor', loggedIn: 'true' };
      for (const k in seed) localStorage.setItem(k, seed[k]);
    } catch (e) {}
  });
  const url = 'file://' + path.resolve(FILE).split(path.sep).join('/');
  try { await p.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 }); } catch (e) {}
  await new Promise(res => setTimeout(res, 400));
  await p.evaluate(() => {
    document.documentElement.setAttribute('data-theme', 'dark');
    document.querySelectorAll('.hidden').forEach(e => e.classList.remove('hidden'));
    ['modal-izin', 'modal-bullying'].forEach(id => { const e = document.getElementById(id); if (e) e.style.display = 'none'; });
  });
  const leaked = await p.evaluate(() => {
    const out = [];
    document.querySelectorAll('.text-white').forEach(el => {
      const c = getComputedStyle(el).color;
      if (c !== 'rgb(255, 255, 255)') out.push(c);
    });
    return out.slice(0, 8);
  });
  console.log(`[${FILE}] dark-mode .text-white that are NOT white: ${leaked.length}`, leaked);
  await p.screenshot({ path: `_audit_${path.basename(FILE, '.html')}_dark.png`, fullPage: true });
  await b.close();
})();
