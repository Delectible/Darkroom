import http from 'node:http'; import fs from 'node:fs'; import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
const types = {'.js':'text/javascript','.mjs':'text/javascript','.html':'text/html','.png':'image/png','.json':'application/json','.wasm':'application/wasm'};
http.createServer((req,res)=>{ const p = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  fs.readFile(p,(e,d)=>{ if(e){res.writeHead(404);res.end();return;} res.writeHead(200,{'Content-Type':types[path.extname(p)]||'application/octet-stream'}); res.end(d);});
}).listen(8765, ()=>console.log('up'));
