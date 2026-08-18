// @ts-check
//
// 第十四輪任務A:event 擲骰要真係擲,而且要誠實。
//
// 兩個真機 viewport(390x664 / 360x640,同 viewport.spec 同源),hasTouch
// context,經 CDP 派真 touch:
//   · `?boot=event:V03` 直入賭骰攤 → tap「下注」→ 應該出骰,唔係即刻出結果;
//   · tap 顆骰 → 停低之後,cube 面上嘅點數 === 引擎擲出嘅數(__dgHUD.dice_check
//     入面 shown 同 roll 兩個 field 分別由 widget 讀返同由引擎交落嚟);
//   · 未撳確認之前,錢包唔郁;撳完先按點數結算。
//
// The game has no DOM: the event screen and the check die publish their rects
// and their state to window.__dgHUD (see SafeArea.publish_hud / _hud_value).

const { test, expect } = require('@playwright/test');

const DEVICES = [
  { name: '390x664', width: 390, height: 664 },
  { name: '360x640', width: 360, height: 640 },
];

/** A real finger tap through CDP, at a CSS-pixel point. */
async function touchTap(page, x, y) {
  const cdp = await page.context().newCDPSession(page);
  const pt = [{ x, y, radiusX: 2, radiusY: 2, force: 1, id: 1 }];
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: pt });
  await page.waitForTimeout(60);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await cdp.detach();
}

const centre = (r) => [r.x + r.w / 2, r.y + r.h / 2];

for (const dev of DEVICES) {
  test.describe(`event dice check @ ${dev.name}`, () => {
    test.use({
      viewport: { width: dev.width, height: dev.height },
      hasTouch: true,
      isMobile: true,
    });

    test('the player throws it, and the cube shows the engine number', async ({ page }) => {
      // LIVE_URL=https://… reruns this against the deployed Pages build
      await page.goto((process.env.LIVE_URL || '') + '/index.html?boot=event:V03');
      await page.waitForFunction(
          () => window.__dgHUD && window.__dgHUD.event_id === 'V03'
              && window.__dgHUD.event_opt0 && window.__dgHUD.event_opt0.h > 0,
          null, { timeout: 150_000 });
      const goldBefore = await page.evaluate(() => window.__dgHUD.event_gold);
      const opt = await page.evaluate(() => window.__dgHUD.event_opt0);

      // ① taking the wager brings out a die instead of announcing a number
      await touchTap(page, ...centre(opt));
      await page.waitForFunction(
          () => window.__dgHUD.dice_check && window.__dgHUD.dice_check.state === 'ready',
          null, { timeout: 30_000 });
      const ready = await page.evaluate(() => window.__dgHUD.dice_check);
      expect(ready.need, 'the success condition is stated up front').toBe(4);
      expect(ready.roll, 'the engine has already rolled').toBeGreaterThanOrEqual(1);
      expect(ready.roll).toBeLessThanOrEqual(6);

      // ② the die only throws when the finger says so
      const die = await page.evaluate(() => window.__dgHUD.dice_check_die);
      expect(die && die.h > 20, 'the die published a tappable rect').toBeTruthy();
      await touchTap(page, ...centre(die));
      await page.waitForFunction(
          () => window.__dgHUD.dice_check.state === 'landed', null, { timeout: 30_000 });

      // ③ the honesty rule: the face that is up IS the engine's number.
      // `shown` is read back off the cube, `roll` is what the run rolled.
      const landed = await page.evaluate(() => window.__dgHUD.dice_check);
      expect(landed.shown, 'the cube shows the number the engine rolled')
          .toBe(landed.roll);
      expect(landed.roll, 'and the roll did not change under the animation')
          .toBe(ready.roll);

      // ④ nothing is settled until the player has read it
      await page.waitForFunction(
          () => window.__dgHUD.dice_check_confirm
              && window.__dgHUD.dice_check_confirm.h > 0,
          null, { timeout: 30_000 });
      const confirm = await page.evaluate(() => window.__dgHUD.dice_check_confirm);
      expect(confirm.h, 'the result waits behind a confirm').toBeGreaterThan(0);
      const stillOut = await page.evaluate(() => window.__dgHUD.event_outcome);
      expect(stillOut, 'no outcome before the confirm').toBeFalsy();

      await touchTap(page, ...centre(confirm));
      await page.waitForFunction(
          () => Boolean(window.__dgHUD.event_outcome), null, { timeout: 30_000 });
      const out = await page.evaluate(() => window.__dgHUD.event_outcome);
      const want = Number(goldBefore) - 30 + (landed.roll >= 4 ? 60 : 0);
      expect(out.gold, `payout follows the face that was shown (rolled ${landed.roll})`)
          .toBe(want);
      expect(out.text, 'and the outcome line names that same number')
          .toContain(String(landed.roll));
    });
  });
}
