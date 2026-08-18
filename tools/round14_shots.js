// Three frames of the round-14 event check die, for the round report.
//
//   node tools/serve.js 8131 &
//   node tools/round14_shots.js                       # local docs/ build
//   node tools/round14_shots.js https://…             # the live Pages build
//
// Shoots at 390x664 with touch, through the same deep boots the regressions
// use (`?boot=event:V03`, `?boot=battleitems`), into qa/round14/.
// The filename of the last one carries the number that was rolled, because the
// whole point of the feature is that the cube is showing the engine's roll.

const fs = require('fs');
const path = require('path');
const { chromium } = require(path.join(__dirname, '..', 'web', 'node_modules', 'playwright'));

const BASE = process.argv[2] || 'http://127.0.0.1:8131';
const OUT = path.join(__dirname, '..', 'qa', 'round14');

async function tapXY(cdp, page, x, y, holdMs = 60) {
  const pt = [{ x, y, radiusX: 2, radiusY: 2, force: 1, id: 1 }];
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: pt });
  await page.waitForTimeout(holdMs);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

const tap = (cdp, page, r) => tapXY(cdp, page, r.x + r.w / 2, r.y + r.h / 2, 60);
// past PressGesture.LONG_PRESS (0.45s)
const hold = (cdp, page, r) => tapXY(cdp, page, r.x + r.w / 2, r.y + r.h / 2, 750);

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 664 }, deviceScaleFactor: 2,
    hasTouch: true, isMobile: true,
  });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);

  await page.goto(BASE + '/index.html?boot=event:V03');
  await page.waitForFunction(
      () => window.__dgHUD && window.__dgHUD.event_opt0 && window.__dgHUD.event_opt0.h > 0,
      null, { timeout: 180_000 });
  await page.waitForTimeout(800);
  await page.screenshot({ path: path.join(OUT, '1_offer.png') });

  await tap(cdp, page, await page.evaluate(() => window.__dgHUD.event_opt0));
  await page.waitForFunction(() => window.__dgHUD.dice_check, null, { timeout: 30_000 });
  await page.waitForTimeout(600);
  await page.screenshot({ path: path.join(OUT, '2_die.png') });

  await tap(cdp, page, await page.evaluate(() => window.__dgHUD.dice_check_die));
  await page.waitForFunction(
      () => window.__dgHUD.dice_check.state === 'landed', null, { timeout: 30_000 });
  await page.waitForTimeout(700);
  const st = await page.evaluate(() => window.__dgHUD.dice_check);
  await page.screenshot({ path: path.join(OUT, '3_landed.png') });
  console.log(`rolled ${st.roll}, cube shows ${st.shown} — ${st.shown === st.roll ? 'MATCH' : 'MISMATCH'}`);

  // --- the item icons: the battle strip, a relic read, a potion asking first
  await page.goto(BASE + '/index.html?boot=battleitems');
  await page.waitForFunction(
      () => window.__dgHUD && window.__dgHUD.relic0 && window.__dgHUD.relic0.h > 0
          && window.__dgHUD.potion0 && window.__dgHUD.potion0.h > 0,
      null, { timeout: 180_000 });
  await page.waitForTimeout(1200);
  await page.screenshot({ path: path.join(OUT, '4_hud.png') });

  const relic0 = await page.evaluate(() => window.__dgHUD.relic0);
  await hold(cdp, page, relic0);
  await page.waitForFunction(
      () => window.__dgHUD.battle_card === 'relic_info', null, { timeout: 30_000 });
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(OUT, '5_relic_held.png') });
  await tapXY(cdp, page, 6, 6);           // scrim: close
  await page.waitForTimeout(500);

  await tap(cdp, page, await page.evaluate(() => window.__dgHUD.potion0));
  await page.waitForFunction(
      () => window.__dgHUD.battle_card === 'potion_use', null, { timeout: 30_000 });
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(OUT, '6_potion_confirm.png') });

  await browser.close();
})();
