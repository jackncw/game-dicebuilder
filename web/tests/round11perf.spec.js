// @ts-check
//
// 第十一輪效能驗收:最惡場面(戰鬥,粒子+浮字+搖屏+8骰齊擲)下 rAF 幀時分佈。
// 一定要 HEADED 行 —— headless 落 SwiftShader,幀數講唔出真話(第九輪已量)。
//
//   PERF=1 npx playwright test round11perf --headed
//
// 報告:平均 fps、最差幀、>33.4ms 幀數。hit-stop 係 Engine.time_scale 凍結,
// rAF 照跑,所以唔會污染呢個統計。

const { test, expect } = require('@playwright/test');

test.skip(!process.env.PERF, 'perf run only (PERF=1, --headed)');

test.use({ viewport: { width: 540, height: 960 } });

async function clickHud(page, key) {
  const r = await page.evaluate((k) => window.__dgHUD[k], key);
  await page.mouse.click(r.x + r.w / 2, r.y + r.h / 2);
}

function sample(page, frames) {
  return page.evaluate((n) => new Promise((resolve) => {
    const deltas = [];
    let last = performance.now();
    function f(t) {
      deltas.push(t - last);
      last = t;
      if (deltas.length < n) requestAnimationFrame(f);
      else resolve(deltas);
    }
    requestAnimationFrame(f);
  }), frames);
}

test('battle worst case holds 60fps', async ({ page }) => {
  await page.goto('/index.html?boot=battle');
  await page.waitForFunction(
    () => window.__dgHUD && window.__dgHUD.die0 && window.__dgHUD.die0.h > 0,
    null, { timeout: 150_000 });
  await page.waitForTimeout(3_000);

  // drive the ugliest sequence we can: three attacks (bursts+shake+floats),
  // end turn (telegraph flights, enemy hits), then the 8-dice re-roll + dust
  const run = (async () => {
    for (let i = 0; i < 3; i++) {
      await clickHud(page, 'die0');
      await page.waitForTimeout(350);
      await clickHud(page, 'enemy0');
      await page.waitForTimeout(500);
    }
    await clickHud(page, 'end_turn');
  })();
  const deltas = await sample(page, 600);   // ~10s at 60fps
  await run;

  const avg = deltas.reduce((a, b) => a + b, 0) / deltas.length;
  const worst = Math.max(...deltas);
  const over = deltas.filter((d) => d > 33.4).length;
  console.log(`PERF fps=${(1000 / avg).toFixed(1)} worst=${worst.toFixed(1)}ms over33=${over}/${deltas.length}`);
  expect(1000 / avg).toBeGreaterThan(55);
  expect(over).toBeLessThanOrEqual(4);
});
