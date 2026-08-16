// RetroLAN Protocol — reference WebSocket server (plays the role of the TV host).
// Listens on :8877, speaks the JSON protocol, applies input to a virtual button grid.
'use strict';
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8877;
const BUTTONS = ['dpad_up','dpad_down','dpad_left','dpad_right','a','b','x','y','start','select','l','r'];

async function makeServer(port = PORT) {
  const wss = new WebSocketServer({ port, host: '0.0.0.0' });
  // If we bound to an ephemeral port (0), wait for the real port to be assigned.
  if (port === 0) {
    await new Promise((resolve, reject) => {
      wss.once('listening', resolve);
      wss.once('error', reject);
    });
    port = wss.address().port;
  }

  // Virtual "held" state per player — proves input transitions are applied.
  const held = { 1: new Set(), 2: new Set() };
  const log = [];

  function emit(msg) { log.push(JSON.stringify(msg)); }

  function send(ws, msg) {
    if (ws.readyState === 1) { ws.send(JSON.stringify(msg)); emit(msg); }
  }

  wss.on('connection', (ws) => {
    send(ws, { type: 'hello_ack', name: 'RetroLAN Reference TV', cores: ['fceumm','snes9x','gambatte'] });

    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString('utf8')); }
      catch { return send(ws, { type: 'error', code: 'malformed', message: 'invalid JSON' }); }

      switch (msg.type) {
        case 'hello':
          send(ws, { type: 'state', status: 'idle', paused: false, fps: 0 });
          break;

        case 'input': {
          if (![1, 2].includes(msg.player)) {
            return send(ws, { type: 'error', code: 'unknown_player', message: 'player must be 1 or 2' });
          }
          if (!BUTTONS.includes(msg.button)) {
            return send(ws, { type: 'error', code: 'invalid_button', message: `unknown button '${msg.button}'` });
          }
          const s = held[msg.player];
          if (msg.state === 'down') s.add(msg.button);
          else if (msg.state === 'up') s.delete(msg.button);
          break;
        }

        case 'ping':
          send(ws, { type: 'pong', ts: msg.ts });
          break;

        default:
          send(ws, { type: 'error', code: 'malformed', message: `unknown type '${msg && msg.type}'` });
      }
    });

    ws.on('close', () => {
      held[1].clear(); held[2].clear();
    });
  });

  return { wss, held, log, port };
}

// Allow running directly, or being imported by test.js.
if (require.main === module) {
  makeServer().then(({ wss, port }) => {
    console.log(`RetroLAN reference server listening on ws://0.0.0.0:${port}`);
  });
  process.on('SIGINT', () => process.exit(0));
}

module.exports = { makeServer };
