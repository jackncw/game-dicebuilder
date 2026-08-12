// @ts-check
//
// 第十輪嘅兩個真人試玩走位修正,喺真瀏覽器兩個手機幾何度迴歸:
//
//   · 任務2 — 勝利(戰利品)畫面:全隊四人同一場升級(最壞情況,`?boot=reward`
//     就係擺呢個盤)曾經令三張戰利品卡被升級訊息推出畫面。而家升級訊息摺疊、
//     內容區可捲動 —— 呢度 assert 捲到底之後三張卡完整喺視野入面。
//   · 任務4 — 地圖畫面:手機高度下九行梯子唔再壓縮,改為捲動 + 自動捲到當前
//     可去節點 —— 呢度 assert 開圖嗰刻可去節點已經完整喺視野入面,唔使玩家搵。
//
// The game has no DOM: rects come from `window.__dgHUD` (`Safe.publish_hud`),
// re-published on every scroll tick.

const { test, expect } = require('@playwright/test');

const DEVICES = [
  { name: '390x664', width: 390, height: 664 },
  { name: '360x640', width: 360, height: 640 },
];

for (const dev of DEVICES) {
  test.describe(`round10 ${dev.name}`, () => {
    test.use({ viewport: { width: dev.width, height: dev.height } });

    test('reward: all three offer cards fully visible after scrolling', async ({ page }) => {
      await page.goto('/index.html?boot=reward');
      await page.waitForFunction(
        () => window.__dgHUD && window.__dgHUD.offer2 && window.__dgHUD.offer2.h > 0,
        null, { timeout: 150_000 });

      // scroll the reward column to the bottom with the wheel, over the canvas
      await page.mouse.move(dev.width / 2, dev.height / 2);
      for (let i = 0; i < 12; i++) {
        await page.mouse.wheel(0, 400);
        await page.waitForTimeout(120);
      }

      // 捲動後:三張戰利品卡每一張都完整喺視窗入面(冇被摘要/角色列/footer 遮)
      await page.waitForFunction((vpH) => {
        const hud = window.__dgHUD;
        if (!hud) { return false; }
        for (const k of ['offer0', 'offer1', 'offer2']) {
          const r = hud[k];
          if (!r || r.h <= 0) { return false; }
          if (r.y < -1 || r.y + r.h > vpH + 1) { return false; }
        }
        return true;
      }, dev.height, { timeout: 30_000 });

      const hud = await page.evaluate(() => window.__dgHUD);
      for (const k of ['offer0', 'offer1', 'offer2']) {
        expect(hud[k].y).toBeGreaterThanOrEqual(-1);
        expect(hud[k].y + hud[k].h).toBeLessThanOrEqual(dev.height + 1);
        expect(hud[k].w).toBeGreaterThan(40);
      }
    });

    test('map: the reachable node is auto-scrolled into view', async ({ page }) => {
      await page.goto('/index.html?boot=map');
      await page.waitForFunction(
        () => window.__dgHUD && window.__dgHUD.map_avail0 && window.__dgHUD.map_avail0.h > 0,
        null, { timeout: 150_000 });
      const hud = await page.evaluate(() => window.__dgHUD);
      const n = hud.map_avail0;
      // 完整喺視野:唔喺 topbar 條帶入面、又未跌落 footer 下面
      expect(n.y).toBeGreaterThanOrEqual(-1);
      expect(n.y + n.h).toBeLessThanOrEqual(dev.height + 1);
      expect(n.w).toBeGreaterThan(10);
    });
  });
}
