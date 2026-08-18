// @ts-check
//
// 第十三輪任務A迴歸:真機報告「圖鑑拖唔郁」。根因係 STOP mouse filter 食咗
// ScrollContainer 要嘅 ScreenDrag(見 tests/codex_scroll_test.gd — headless
// 冇 touchscreen,drag-scroll 條路只有呢度先驗到)。
//
// 兩個真機 viewport(390x664 / 360x640,同 viewport.spec 同源),hasTouch
// context,經 CDP 派真 touch 序列:
//   · 由圖鑑中間(tile 上面)向上拖 → __dgHUD.codex_scroll_v 要郁;
//   · 拖完唔准彈詳情卡;
//   · 短 tap 一下 tile → 詳情卡要開(__dgHUD.codex_detail 出現)。
//
// The game has no DOM: the codex publishes its scroll offset and the
// detail-card event to window.__dgHUD (web-only probes in screen_codex.gd).

const { test, expect } = require('@playwright/test');

const DEVICES = [
  { name: '390x664', width: 390, height: 664 },
  { name: '360x640', width: 360, height: 640 },
];

/** Dispatch a real touch drag through CDP: start → N moves → end. */
async function touchDrag(page, from, to, steps = 8) {
  const cdp = await page.context().newCDPSession(page);
  const mk = (x, y) => [{ x, y, radiusX: 2, radiusY: 2, force: 1, id: 1 }];
  await cdp.send('Input.dispatchTouchEvent',
      { type: 'touchStart', touchPoints: mk(from.x, from.y) });
  for (let i = 1; i <= steps; i++) {
    const x = from.x + ((to.x - from.x) * i) / steps;
    const y = from.y + ((to.y - from.y) * i) / steps;
    await cdp.send('Input.dispatchTouchEvent',
        { type: 'touchMove', touchPoints: mk(x, y) });
    await page.waitForTimeout(30);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await cdp.detach();
}

for (const dev of DEVICES) {
  test.describe(`codex touch @ ${dev.name}`, () => {
    test.use({
      viewport: { width: dev.width, height: dev.height },
      hasTouch: true,
      isMobile: true,
    });

    test('finger scroll works, and a tap still opens the detail card', async ({ page }) => {
      // LIVE_URL=https://… reruns this against the deployed Pages build —
      // the round-13 standing check that the fix reached the thing people play
      await page.goto((process.env.LIVE_URL || '') + '/index.html?boot=codex');
      await page.waitForFunction(
          () => window.__dgHUD && window.__dgHUD.codex_scroll
              && window.__dgHUD.codex_scroll.h > 0,
          null, { timeout: 150_000 });
      const area = await page.evaluate(() => window.__dgHUD.codex_scroll);
      const cx = area.x + area.w / 2;

      // ① a drag that starts ON codex content scrolls the page
      const v0 = await page.evaluate(() => window.__dgHUD.codex_scroll_v.y);
      await touchDrag(page,
          { x: cx, y: area.y + area.h * 0.7 },
          { x: cx, y: area.y + area.h * 0.2 });
      await page.waitForTimeout(600);
      const v1 = await page.evaluate(() => window.__dgHUD.codex_scroll_v.y);
      expect(v1, 'the codex scrolled under the finger').toBeGreaterThan(v0 + 20);

      // ② the drag did NOT open a face detail
      const detailAfterDrag = await page.evaluate(
          () => Boolean(window.__dgHUD.codex_detail));
      expect(detailAfterDrag, 'a scroll gesture is not a tap').toBe(false);

      // ③ a short tap on a face tile opens the detail card. Drag back until
      // the codex is genuinely at the top (inertia can leave it short — seen
      // against the live CDN), so the tile's published rect is where it is.
      for (let i = 0; i < 6; i++) {
        const v = await page.evaluate(() => window.__dgHUD.codex_scroll_v.y);
        if (v < 20) break;
        await touchDrag(page,
            { x: cx, y: area.y + area.h * 0.2 },
            { x: cx, y: area.y + area.h * 0.9 });
        await page.waitForTimeout(700);
      }
      const vTop = await page.evaluate(() => window.__dgHUD.codex_scroll_v.y);
      expect(vTop, 'scrolled back to the top').toBeLessThan(20);
      const tile = await page.evaluate(() => window.__dgHUD.codex_tile0);
      expect(tile && tile.h > 0, 'the first face tile published its rect').toBeTruthy();
      let opened = false;
      for (let i = 0; i < 3 && !opened; i++) {
        await page.touchscreen.tap(tile.x + tile.w / 2, tile.y + tile.h / 2);
        opened = await page.waitForFunction(
            () => Boolean(window.__dgHUD.codex_detail), null, { timeout: 5_000 })
            .then(() => true).catch(() => false);
      }
      expect(opened, 'a short tap opened the face detail card').toBe(true);
    });
  });
}
