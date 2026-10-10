import { chromium } from 'playwright';

const browser = await chromium.launch({ args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
page.on('console', msg => { if (msg.type() === 'error') console.log('CONSOLE ERROR:', msg.text()); });

await page.goto('http://localhost:5173');
await page.waitForSelector('text=BEHAVIORS', { timeout: 15000 });

// Ensure a path exists: generate a blank shape via + Add is track-only; use Generate dialog isn't guaranteed.
// Simplest robust path: click "+ Add" then "fireMode" under EVENTS to add a trigger.
await page.click('button:has-text("+ Add")');
await page.waitForSelector('text=EVENTS');
await page.click('.bp-add-item:has-text("fireMode")');

// Click the diamond marker on the fireMode compact bar to select it (opens the pos editor).
await page.waitForSelector('.bpanel-kf-diamond');
await page.click('.bpanel-kf-diamond');

await page.waitForSelector('.bpanel-pos-scrub');

// Measure actual pixel x of the compact-row marker vs the pos-scrub marker.
const rects = await page.evaluate(() => {
  const compactDiamond = document.querySelector('.bpanel-track-row .bpanel-kf-diamond');
  const scrubDiamond   = document.querySelector('.bpanel-pos-scrub .bpanel-kf-diamond');
  const r1 = compactDiamond?.getBoundingClientRect();
  const r2 = scrubDiamond?.getBoundingClientRect();
  return {
    compact: r1 ? { x: r1.x + r1.width / 2, y: r1.y } : null,
    scrub:   r2 ? { x: r2.x + r2.width / 2, y: r2.y } : null,
  };
});
console.log('MEASURED:', JSON.stringify(rects));
if (rects.compact && rects.scrub) {
  console.log('DELTA_X_PX:', Math.abs(rects.compact.x - rects.scrub.x).toFixed(2));
}

await page.screenshot({ path: '/tmp/claude-1000/-var-home-don-Downloads--installers-qb64pe-code-3d/eaaf97c3-46f1-4bf7-95a2-b09d2654800a/scratchpad/trigger-align-check.png' });
await browser.close();
