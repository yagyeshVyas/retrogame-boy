// End-to-end assertion of the RetroLAN protocol flow.
'use strict';
const assert = require('assert');
const { makeServer } = require('./server');
const { connect } = require('./client');

async function run() {
  // Use an ephemeral port so the test never collides with a running server.
  const server = await makeServer(0); // returns {wss, held, log, port} once listening
  const port = server.port;
  await new Promise(r => setTimeout(r, 50));

  const received = [];
  const ws = await connect(`ws://127.0.0.1:${port}`, {
    player: 1,
    onMessage: (m) => received.push(m),
  });
  ws.hello();
  ws.press('a', 'down');
  ws.press('dpad_up', 'down');
  ws.press('a', 'up');
  ws.ping();
  ws.press('turbo', 'down'); // should trigger invalid_button error

  await new Promise(r => setTimeout(r, 300));

  const types = received.map(m => m.type);
  console.log('Messages received by client:', types.join(', '));

  // Assertions
  assert(types.includes('hello_ack'), 'expected hello_ack');
  assert(types.includes('pong'), 'expected pong');

  // After down+up of 'a', it should NOT be held; dpad_up should still be held.
  assert(server.held[1].has('dpad_up'), 'dpad_up should still be held after only down');
  assert(!server.held[1].has('a'), 'a should be released after up');
  assert.strictEqual(server.held[1].size, 1, 'exactly one button held');

  const err = received.find(m => m.type === 'error');
  assert(err && err.code === 'invalid_button', 'expected invalid_button error');

  console.log('\n✅ ALL PROTOCOL ASSERTIONS PASSED');
  console.log('held[1] at end:', [...server.held[1]]);
  server.wss.close();
  // Exit explicitly so npm test does not hang on open WS handles.
  process.exit(0);
}

run().catch((e) => { console.error('\n❌ TEST FAILED:', e.message); process.exit(1); });
