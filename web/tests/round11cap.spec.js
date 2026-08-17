// @ts-check
//
// 第十一輪動效驗收:每個關鍵時刻錄一段 video(動效冇得靠靜態截圖驗)。
// 唔入常規迴歸 —— 要 CAP=1 先行:
//
//   CAP=1 npx playwright test round11cap --config playwright.config.js
//
// Videos land in web/test-results/**/video.webm; tools/collect_caps.py
// copies them into qa/round11/ with readable names.
//
// The game has no DOM. Clicks land on rects published via window.__dgHUD;
// music switches are asserted via window.__dgMusic (both web-only probes).

const { test, expect } = require('@playwright/test');

test.skip(!process.env.CAP, 'capture run only (CAP=1)');

test.use({
  // 540x960 = the 720x1280 design at exactly 0.75, so design coords map cleanly
  viewport: { width: 540, height: 960 },
  video: { size: { width: 540, height: 960 } },
});

async function bootTo(page, url, hudKey) {
  await page.goto(url);
  if (hudKey) {
    await page.waitForFunction(
      (k) => window.__dgHUD && window.__dgHUD[k] && window.__dgHUD[k].h > 0,
      hudKey, { timeout: 150_000 });
  } else {
    await page.waitForTimeout(25_000); // cold wasm boot under SwiftShader
  }
}

async function clickHud(page, key) {
  const r = await page.evaluate((k) => window.__dgHUD[k], key);
  await page.mouse.click(r.x + r.w / 2, r.y + r.h / 2);
}

test.describe('round11 moment capture', () => {
  test('menu: sign drop, sway, shafts, music', async ({ page }) => {
    await bootTo(page, '/index.html', null);
    await page.mouse.click(270, 850);      // first gesture unlocks audio
    await page.waitForTimeout(4_000);
    const music = await page.evaluate(() => window.__dgMusic);
    expect(music).toBe('title');
  });

  test('map: chapter card, walk to node, battle wipe, dice roll', async ({ page }) => {
    await bootTo(page, '/index.html?boot=map', 'map_avail0');
    await page.waitForTimeout(1_200);      // chapter title card holds
    await page.mouse.click(270, 480);      // dismiss card
    await page.waitForTimeout(600);
    await clickHud(page, 'map_avail0');    // pawn walks, then battle wipe
    await page.waitForFunction(
      () => window.__dgHUD && window.__dgHUD.die0 && window.__dgHUD.die0.h > 0,
      null, { timeout: 60_000 });
    await page.waitForTimeout(2_500);      // dice tumble + dust
    expect(await page.evaluate(() => window.__dgMusic)).toBe('ch1');
  });

  test('battle: tap-attack hits, end turn, enemy beats', async ({ page }) => {
    await bootTo(page, '/index.html?boot=battle', 'die0');
    await page.waitForTimeout(2_000);      // roll settles
    for (let i = 0; i < 3; i++) {
      await clickHud(page, 'die0');        // select the first die
      await page.waitForTimeout(400);
      await clickHud(page, 'enemy0');      // resolve onto the first enemy
      await page.waitForTimeout(900);      // floats/shake/burst
    }
    await clickHud(page, 'end_turn');
    await page.waitForTimeout(6_000);      // telegraphs + enemy hits + reroll
  });

  test('boss: entrance banner, fog, music switch', async ({ page }) => {
    await bootTo(page, '/index.html?boot=bossbattle', 'end_turn');
    await page.waitForTimeout(3_500);      // black-out → banner → reveal
    expect(await page.evaluate(() => window.__dgMusic)).toBe('boss');
  });

  test('reward: staggered entrance, gold roll-up', async ({ page }) => {
    await bootTo(page, '/index.html?boot=reward', 'offer2');
    await page.waitForTimeout(3_000);
  });

  test('treasure: light column reveal', async ({ page }) => {
    await bootTo(page, '/index.html?boot=treasure', null);
    await page.waitForTimeout(3_000);
  });

  test('victory: tally walks in', async ({ page }) => {
    await bootTo(page, '/index.html?boot=victory', null);
    await page.waitForTimeout(3_000);
  });

  test('gameover: slow fade, toll stats, one-more-run', async ({ page }) => {
    await bootTo(page, '/index.html?boot=gameover', null);
    await page.waitForTimeout(3_000);
  });
});
