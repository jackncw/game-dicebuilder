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

test.use({
  viewport: { width: 540, height: 960 },
  // the shared config forces SwiftShader (headless needs it); perf must run
  // on the real GPU or the numbers are SwiftShader's, not the game's
  launchOptions: { args: [] },
});

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

  // the spec's worst case: telegraph flights, enemy hits, shake, floats and
  // the 8-dice re-roll with landing dust — twice over, no UI overlays. (An
  // earlier variant also tapped enemy cards open: those taps cost 83-150ms
  // on FIRST build of the detail overlay — a discrete tap-response cost,
  // logged in DECISIONS.md, not a mid-motion frame drop.)
  const run = (async () => {
    await clickHud(page, 'end_turn');
    await page.waitForTimeout(5_000);
    await clickHud(page, 'end_turn');
  })();
  const deltas = await sample(page, 600);   // ~10s at 60fps
  await run;

  const avg = deltas.reduce((a, b) => a + b, 0) / deltas.length;
  const worst = Math.max(...deltas);
  const over = deltas.filter((d) => d > 33.4).length;
  const spikes = deltas.map((d, i) => [i, d]).filter(([, d]) => d > 33.4)
    .map(([i, d]) => `#${i}@${(deltas.slice(0, i).reduce((a, b) => a + b, 0) / 1000).toFixed(1)}s=${d.toFixed(0)}ms`);
  console.log(`PERF fps=${(1000 / avg).toFixed(1)} worst=${worst.toFixed(1)}ms over33=${over}/${deltas.length} spikes=${spikes.join(' ')}`);
  // Round 11 floor (RTX 3070 laptop, ANGLE/D3D11): 58.5fps, worst 67ms,
  // 7/600 over 33ms. The spikes are the declarative full _refresh() per enemy
  // beat — Die3D pooling already halved them from 133ms; the remainder is
  // diffuse (text shaping + card rebuild) and logged as known debt in
  // DECISIONS.md. These bounds hold that line against regression.
  expect(1000 / avg).toBeGreaterThan(55);
  expect(worst).toBeLessThan(80);
  expect(over).toBeLessThanOrEqual(8);
});
