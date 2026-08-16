// RetroLAN Protocol — reference WebSocket client (plays the role of the Flutter controller).
'use strict';
const WebSocket = require('ws');

function connect(url = 'ws://127.0.0.1:8877', opts = {}) {
  const { device = 'ReferenceClient', player = 1, onMessage } = opts;
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
    if (onMessage) ws.on('message', (raw) => onMessage(JSON.parse(raw.toString('utf8'))));
    // Convenience helpers
    ws.sendMsg = (o) => ws.send(JSON.stringify(o));
    ws.hello = () => ws.sendMsg({ type: 'hello', device, role: 'controller', player });
    ws.press = (button, state) => ws.sendMsg({ type: 'input', player, button, state });
    ws.ping = (ts = Date.now()) => ws.sendMsg({ type: 'ping', ts });
  });
}

const HOST = process.env.HOST || '127.0.0.1';
const PORT = process.env.PORT || 8877;
const PLAYER = parseInt(process.env.PLAYER || '1', 10);

async function main() {
  const seen = [];
  const ws = await connect(`ws://${HOST}:${PORT}`, {
    player: PLAYER,
    onMessage: (m) => { seen.push(m); console.log('  ◀ received:', JSON.stringify(m)); }
  });
  console.log('▶ connected');
  console.log('▶ hello'); ws.hello();
  console.log("▶ press a/down"); ws.press('a', 'down');
  console.log("▶ press dpad_up/down"); ws.press('dpad_up', 'down');
  console.log("▶ release a/up"); ws.press('a', 'up');
  console.log('▶ ping'); ws.ping();
  console.log("▶ bad button (expect error)"); ws.press('turbo', 'down');
  await new Promise(r => setTimeout(r, 300));
  ws.close();
  return seen;
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
module.exports = { connect, main };
