# Reference protocol tools

A tiny Node reference implementation of the RetroLAN wire protocol — proves the
message flow end to end without needing the Android/Flutter builds.

```bash
npm install
npm test
```

- `server.js` — a WebSocket server that speaks the protocol (like the TV host).
- `client.js` — a controller client that sends `hello`, `input`, `ping` and
  prints replies (like the Flutter app).
- `test.js` — runs server + client together and asserts the flow.
