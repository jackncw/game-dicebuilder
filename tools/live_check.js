const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage({ viewport: { width: 540, height: 960 } });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto('https://jackncw.github.io/game-dicebuilder/', { timeout: 120000 });
  await page.waitForTimeout(35000);
  await page.mouse.click(270, 850);
  await page.waitForTimeout(6000);
  console.log('MUSIC=', await page.evaluate(() => window.__dgMusic));
  await page.screenshot({ path: 'test-results/live_menu.png' });
  await page.mouse.click(270, 576);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: 'test-results/live_after_click.png' });
  console.log('ERRORS=', JSON.stringify(errors.filter(e => !e.includes('message channel')).slice(0, 5)));
  await browser.close();
  console.log('LIVE CHECK DONE');
})().catch(e => { console.error('FAIL', e.message); process.exit(1); });
