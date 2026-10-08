// Prints the body parts (items/body.js PARTS) as JSON, for render_queue.py.
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const head = fs.readFileSync(`${root}/scenes/head.html`, 'utf8');
fs.writeFileSync(`${root}/scenes/_list.html`, `${head}<script type="module">
import { PARTS } from '/items/body.js';
const out = {};
for (const [mode, parts] of Object.entries(PARTS)) {
  out[mode] = {};
  for (const [name, p] of Object.entries(parts)) {
    const { build, ...meta } = p; out[mode][name] = meta;
  }
}
window.__parts = out;
</script></body></html>`);
const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage();
p.on('pageerror', (e) => console.error(e.message));
await p.goto('http://localhost:8765/scenes/_list.html');
const parts = await (await p.waitForFunction(() => window.__parts, null, { timeout: 60000 })).jsonValue();
console.log(JSON.stringify(parts));
await b.close();
