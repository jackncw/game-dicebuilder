// @ts-check
const { defineConfig } = require('@playwright/test');

// The game is a ~40MB wasm compiled by SwiftShader in headless Chromium; a cold
// boot is tens of seconds, not hundreds of milliseconds. These timeouts are
// sized for that, not padded for flakiness.
module.exports = defineConfig({
  testDir: './tests',
  timeout: 180_000,
  expect: { timeout: 120_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:8130',
    // deviceScaleFactor 1 keeps CSS pixels and device pixels the same number,
    // so an assertion in CSS px is an assertion about what is on the glass
    deviceScaleFactor: 1,
    launchOptions: {
      // headless Chromium falls back to SwiftShader for WebGL2; without these
      // the canvas never gets a context and the game stops at "Preparing…"
      args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
    },
  },
  webServer: {
    command: 'node ../tools/serve.js 8130',
    url: 'http://127.0.0.1:8130/index.html',
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
