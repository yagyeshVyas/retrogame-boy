import http from 'http';
import { readFile } from 'fs/promises';
import { extname, join, normalize } from 'path';
const ROOT = process.env.ROOT || '.';
const PORT = +(process.env.STPORT || 8899);
const INDEX = process.env.INDEX || 'index.html';
const MIME = { '.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.png':'image/png', '.css':'text/css', '.wasm':'application/wasm', '.otf':'font/otf', '.ttf':'font/ttf', '.ico':'image/x-icon', '.svg':'image/svg+xml', '.jsm':'text/javascript' };
http.createServer(async (req,res)=>{
  try{
    let p = decodeURIComponent(req.url.split('?')[0]); if(p==='/') p='/'+INDEX;
    let f = normalize(join(ROOT, p));
    if(!f.startsWith(normalize(ROOT))) { res.writeHead(403); res.end('forbidden'); return; }
    let data;
    try { data = await readFile(f); }
    catch { // try index fallback
      f = normalize(join(ROOT, INDEX));
      data = await readFile(f);
    }
    res.writeHead(200, {'Content-Type': MIME[extname(f)]||'application/octet-stream'});
    res.end(data);
  }catch(e){ res.writeHead(404); res.end('not found'); }
}).listen(PORT, ()=>console.log('static on', PORT, 'root', ROOT, 'index', INDEX));
