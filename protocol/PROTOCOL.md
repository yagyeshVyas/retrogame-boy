# RetroLAN Wire Protocol v1

Minimal, human-readable **JSON over WebSocket** (TCP). Messages are sent only on
*state change*, never every frame — that is what keeps LAN latency near zero
(typically sub-10 ms).

## Transport

- **Type**: WebSocket, text frames, UTF-8 JSON.
- **Default port**: `8877` (TV host listens; controller connects).
- **Discovery**: mDNS/DNS-SD, service type `_retrolan._tcp`. Manual IP fallback.

## Connection lifecycle

```
Controller ──hello──▶ TV          "I am a controller, player 1/2"
TV          ──hello_ack─▶ Controller  "acknowledged, here is my state"
TV          ──state──▶ Controller  "ROM now running, etc."
Controller ──ping──▶ TV
TV          ──pong──▶ Controller  (timestamp echoed for latency calc)
```

## Message definitions

### `hello` (controller → TV)
```json
{ "type": "hello", "device": "iPhone 15", "role": "controller", "player": 1 }
```
| field | type | notes |
|---|---|---|
| `type` | string | `"hello"` |
| `device` | string | human-readable device label |
| `role` | string | always `"controller"` for now |
| `player` | int | `1` or `2` (multiplayer selector chosen at connect) |

### `hello_ack` (TV → controller)
```json
{ "type": "hello_ack", "name": "Living Room TV", "cores": ["fceumm","snes9x","gambatte"] }
```

### `input` (controller → TV)
```json
{ "type": "input", "player": 1, "button": "a", "state": "down" }
{ "type": "input", "player": 1, "button": "dpad_up", "state": "up" }
```
| field | type | notes |
|---|---|---|
| `type` | string | `"input"` |
| `player` | int | `1` or `2` |
| `button` | string | see button vocabulary below |
| `state` | string | `"down"` or `"up"` |

A single message carries exactly one `(button, state)` transition — that keeps
messages tiny and lets the TV apply them with zero parsing ambiguity.

### Button vocabulary
```
dpad_up | dpad_down | dpad_left | dpad_right
a | b | x | y
start | select
l | r
```

### `ping` / `pong` (both directions)
```json
{ "type": "ping", "ts": 1734000000000 }
{ "type": "pong", "ts": 1734000000000 }
```
Controller pings; TV echoes `ts` back in `pong`. Controller computes
`latency = now - ts` for the live pill display.

### `state` (TV → controller, informational)
```json
{ "type": "state", "status": "running", "rom": "Metroid.nes", "paused": false, "fps": 60 }
```
Used by the controller status pill / pause menu. `status` ∈
`idle | loading | running | paused`.

### `error` (either side)
```json
{ "type": "error", "code": "invalid_button", "message": "unknown button 'foo'" }
```

## Errors / edge cases

- Unknown `button` → TV replies `error` with `invalid_button`.
- Malformed JSON → TV replies `error` with `malformed`.
- Controller may send `input` before `hello_ack`; TV tolerates it but the
  `player` field must be valid (`1`/`2`) or the message is dropped.
- Duplicate `down` without `up` is ignored (idempotent application).

## JSON Schema (draft)

A formal JSON Schema lives in `protocol/schema.json`. It is referenced by both
clients for validation and documentation.
