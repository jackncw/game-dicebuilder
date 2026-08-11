// @ts-check
//
// The round-6 bug, in a real browser: on a phone the battle screen's top bar —
// turn counter, Essence meter, reroll count — was not on screen at all.
//
// Two causes, and this file asserts both are gone:
//
//   1. The exporter sizes the canvas to `window.innerHeight`, which on a mobile
//      browser is the height the page WOULD have with the address bar retracted.
//      The canvas was therefore taller than the visible strip and the overflow
//      was simply cut off. `tools/web_shell.html` now drives the canvas off
//      `visualViewport`; `canvas fills the visual viewport` checks that.
//
//   2. With `viewport-fit=cover`, the notch and the home indicator sit over the
//      top and bottom of the canvas. The game insets its own HUD out of those
//      strips; `top bar clears the safe area` checks that, using `?insets=` to
//      impose a phone's geometry on a browser that has none.
//
// The heights are the reported ones — what is LEFT of a 390x844 / 360x800
// phone once the browser's chrome is off it. Nothing here reads a pixel of the
// canvas: the game publishes its laid-out rects to `window.__dgHUD` (see
// `SafeArea.publish_hud`), because everything the player looks at is drawn
// inside one canvas element and has no DOM of its own.

const { test, expect } = require('@playwright/test');

const DEVICES = [
  { name: '390x664', width: 390, height: 664 },
  { name: '360x640', width: 360, height: 640 },
];

// top / bottom CSS px. `none` is a browser tab, where the browser's own UI
// already covers the hardware; `notch` is the page on the home screen, where it
// does not.
const INSETS = [
  { name: 'browser tab', q: '', top: 0, bottom: 0 },
  { name: 'home screen', q: '&insets=47,0,34,0', top: 47, bottom: 34 },
];

/** Wait for the battle screen to have published its rects, then read them. */
async function bootBattle(page, query) {
  await page.goto('/index.html?boot=battle' + query);
  await page.waitForFunction(
    () => window.__dgHUD && window.__dgHUD.topbar && window.__dgHUD.topbar.h > 0,
    null, { timeout: 150_000 });
  return page.evaluate(() => ({
    hud: window.__dgHUD,
    vp: {
      w: window.visualViewport ? window.visualViewport.width : window.innerWidth,
      h: window.visualViewport ? window.visualViewport.height : window.innerHeight,
    },
    canvas: (() => {
      const c = document.getElementById('canvas');
      const r = c.getBoundingClientRect();
      return { w: r.width, h: r.height, top: r.top, left: r.left };
    })(),
  }));
}

for (const dev of DEVICES) {
  test.describe(`${dev.name}`, () => {
    test.use({ viewport: { width: dev.width, height: dev.height } });

    test('canvas fills the visual viewport exactly', async ({ page }) => {
      const s = await bootBattle(page, '');
      // 1px of tolerance for the rounding in `fit()`, and no more: a canvas even
      // slightly taller than the viewport is the original bug in miniature.
      expect(Math.abs(s.canvas.h - s.vp.h)).toBeLessThanOrEqual(1);
      expect(Math.abs(s.canvas.w - s.vp.w)).toBeLessThanOrEqual(1);
      expect(s.canvas.top).toBeCloseTo(0, 0);
      expect(s.canvas.left).toBeCloseTo(0, 0);
    });

    for (const ins of INSETS) {
      test(`top bar clears the safe area — ${ins.name}`, async ({ page }) => {
        const s = await bootBattle(page, ins.q);
        const bar = s.hud.topbar;
        expect(bar.h).toBeGreaterThan(4);
        // fully below the notch…
        expect(bar.y).toBeGreaterThanOrEqual(ins.top - 1);
        // …fully above the bottom of the glass, and not merely overlapping it
        expect(bar.y + bar.h).toBeLessThanOrEqual(s.vp.h - ins.bottom + 1);
        expect(bar.x).toBeGreaterThanOrEqual(-1);
        expect(bar.x + bar.w).toBeLessThanOrEqual(s.vp.w + 1);
      });

      test(`Essence meter is on the glass — ${ins.name}`, async ({ page }) => {
        const s = await bootBattle(page, ins.q);
        const e = s.hud.essence;
        // The starter party carries Essence faces, so the meter is shown; if a
        // future roster change hides it this needs to change with it rather
        // than quietly assert nothing.
        expect(e, 'the Essence meter should be on screen for the starter party').toBeTruthy();
        expect(e.y).toBeGreaterThanOrEqual(ins.top - 1);
        expect(e.y + e.h).toBeLessThanOrEqual(s.vp.h - ins.bottom + 1);
        expect(e.x + e.w).toBeLessThanOrEqual(s.vp.w + 1);
      });
    }

    test('address bar retracting re-fits the canvas', async ({ page }) => {
      // What actually happens mid-play: the visible viewport gets taller when
      // the address bar slides away. The canvas has to follow, which is the
      // whole reason the shell listens to `visualViewport` rather than sizing
      // once at boot.
      await bootBattle(page, '');
      await page.setViewportSize({ width: dev.width, height: dev.height + 84 });
      await page.waitForFunction(
        (h) => Math.abs(document.getElementById('canvas').getBoundingClientRect().height - h) <= 1,
        dev.height + 84, { timeout: 20_000 });
      const s = await page.evaluate(() => ({
        hud: window.__dgHUD,
        vp: { h: window.visualViewport.height },
      }));
      expect(s.hud.topbar.y + s.hud.topbar.h).toBeLessThanOrEqual(s.vp.h + 1);
    });
  });
}
