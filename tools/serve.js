#!/usr/bin/env node
// Static file server for the web build, with no dependencies.
//
//   node tools/serve.js [port] [dir]
//
// Exists because the Playwright regression has to load `docs/` over HTTP —
// `file://` refuses the wasm fetch — and pulling in a server package for eight
// lines of `fs.createReadStream` would put a node_modules tree in a repo that
// otherwise has none.
//
// Two things it must get right or the game does not boot:
//   · `application/wasm` on the .wasm, or the browser refuses to stream-compile
//   · no caching, so a rebuilt pack is actually re-read between runs

const http = require('http');
const fs = require('fs');
const path = require('path');

const port = parseInt(process.argv[2] || '8130', 10);
const root = path.resolve(process.argv[3] || path.join(__dirname, '..', 'docs'));

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
};

http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  let file = path.join(root, url === '/' ? 'index.html' : url);
  // no escaping the served directory
  if (!file.startsWith(root)) {
    res.writeHead(403).end();
    return;
  }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' }).end('not found');
      return;
    }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': 'no-store',
    });
    fs.createReadStream(file).pipe(res);
  });
}).listen(port, () => console.log('serving ' + root + ' on http://127.0.0.1:' + port));
