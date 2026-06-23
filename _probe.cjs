const puppeteer = require('puppeteer'); const path = require('path');
const FILE = process.argv[2] || 'admin.html';
(async () => {
  const b = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] });
  const p = await b.newPage();
  await p.setRequestInterception(true);
  p.on('request', r => r.url().startsWith('file://') ? r.continue() : r.abort());
  const url = 'file://' + path.resolve(FILE).split(path.sep).join('/');
  try { await p.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 }); } catch (e) {}
  await p.evaluate(() => document.documentElement.setAttribute('data-theme', 'light'));
  await new Promise(res => setTimeout(res, 600)); // let CSS transitions settle
  const out = await p.evaluate(() => {
    const r = {};
    r.htmlTheme = document.documentElement.getAttribute('data-theme');
    r.bodyTheme = document.body.getAttribute('data-theme');
    r.tabTextVar = getComputedStyle(document.documentElement).getPropertyValue('--tab-text');
    const t = document.getElementById('tab-recap');
    if (t) {
      const cs = getComputedStyle(t);
      r.tabRecapColor = cs.color; r.tabRecapBg = cs.backgroundColor;
      r.tabRecapOwnVar = cs.getPropertyValue('--tab-text');
      r.ancestors = [];
      let n = t;
      while (n && n !== document.documentElement) {
        r.ancestors.push((n.tagName) + '#' + (n.id||'') + '.' + (n.className||'').toString().slice(0,30) + ' --tab-text=' + getComputedStyle(n).getPropertyValue('--tab-text'));
        n = n.parentElement;
      }
    }
    const k = document.querySelector('a[href="index.html"]');
    if (k) { r.kembaliLinkColor = getComputedStyle(k).color; }
    // enumerate which CSS rules set `color` and match tab-recap
    r.colorRules = [];
    for (const sheet of document.styleSheets) {
      let rules; try { rules = sheet.cssRules; } catch (e) { continue; }
      for (const rule of rules) {
        if (rule.style && rule.style.color) {
          try { if (t.matches(rule.selectorText)) r.colorRules.push(rule.selectorText + ' { color:' + rule.style.color + ' }'); } catch (e) {}
        }
      }
    }
    return r;
  });
  console.log(JSON.stringify(out, null, 2));
  await b.close();
})();
