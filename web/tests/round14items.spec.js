// @ts-check
//
// 第十四輪任務C:長按睇效果,tap 藥水要確認先飲。
//
// 兩個真機 viewport(390x664 / 360x640),hasTouch context,經 CDP 派真 touch:
//   · 短 tap 遺物圖示 → 開成個遺物清單(舊行為冇變);
//   · 長按同一粒 → 開嗰件遺物自己嘅效果卡(唔使喺清單度搵);
//   · tap 藥水 → 出「使用/取消」卡,藥水數量唔郁;撳「使用」先減一;
//   · 長按藥水 → 淨係睇效果,一支都唔會少。
//
// `?boot=battleitems` 係一場真係帶住三件遺物 + 兩支藥水嘅戰鬥(見 main.gd)。
// The game has no DOM: screen_battle publishes the icon rects and which card is
// up to window.__dgHUD.

const { test, expect } = require('@playwright/test');

const DEVICES = [
  { name: '390x664', width: 390, height: 664 },
  { name: '360x640', width: 360, height: 640 },
];

async function touchPress(page, x, y, holdMs) {
  const cdp = await page.context().newCDPSession(page);
  const pt = [{ x, y, radiusX: 2, radiusY: 2, force: 1, id: 1 }];
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: pt });
  await page.waitForTimeout(holdMs);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await cdp.detach();
}

const tap = (page, r) => touchPress(page, r.x + r.w / 2, r.y + r.h / 2, 60);
// comfortably past PressGesture.LONG_PRESS (0.45s)
const hold = (page, r) => touchPress(page, r.x + r.w / 2, r.y + r.h / 2, 750);

/** Close whatever card is up by tapping the scrim in the top-left corner. */
async function closeCard(page) {
  await touchPress(page, 6, 6, 60);
  await page.waitForTimeout(400);
}

const potions = (page) => page.evaluate(() => window.__dgHUD.potion_count);

for (const dev of DEVICES) {
  test.describe(`hold to read @ ${dev.name}`, () => {
    test.use({
      viewport: { width: dev.width, height: dev.height },
      hasTouch: true,
      isMobile: true,
    });

    test('relics and potions answer a hold, and a potion asks before it is drunk',
        async ({ page }) => {
      await page.goto((process.env.LIVE_URL || '') + '/index.html?boot=battleitems');
      await page.waitForFunction(
          () => window.__dgHUD && window.__dgHUD.relic0 && window.__dgHUD.relic0.h > 0
              && window.__dgHUD.potion0 && window.__dgHUD.potion0.h > 0,
          null, { timeout: 150_000 });
      const relic0 = await page.evaluate(() => window.__dgHUD.relic0);
      const potion0 = await page.evaluate(() => window.__dgHUD.potion0);
      expect(await potions(page), 'the boot battle is carrying two potions').toBe(2);

      // ① a short tap on a relic icon still opens the whole pack
      await tap(page, relic0);
      await page.waitForFunction(
          () => window.__dgHUD.battle_card === 'relic_list', null, { timeout: 30_000 });
      await closeCard(page);

      // ② holding the same icon reads THAT relic
      await hold(page, relic0);
      await page.waitForFunction(
          () => window.__dgHUD.battle_card === 'relic_info', null, { timeout: 30_000 });
      await closeCard(page);

      // ③ a tap on a potion asks; it does not drink
      await tap(page, potion0);
      await page.waitForFunction(
          () => window.__dgHUD.battle_card === 'potion_use', null, { timeout: 30_000 });
      expect(await potions(page), 'the tap spent nothing').toBe(2);

      const confirm = await page.evaluate(() => window.__dgHUD.card_confirm);
      expect(confirm && confirm.h > 0, 'the card carries a Use button').toBeTruthy();
      await tap(page, confirm);
      await page.waitForFunction(
          () => window.__dgHUD.potion_count === 1, null, { timeout: 30_000 });

      // ④ holding the remaining potion reads it, and spends nothing
      const potionLeft = await page.evaluate(() => window.__dgHUD.potion0);
      await hold(page, potionLeft);
      await page.waitForFunction(
          () => window.__dgHUD.battle_card === 'potion_info', null, { timeout: 30_000 });
      expect(await potions(page), 'holding a potion spends nothing').toBe(1);
    });
  });
}
