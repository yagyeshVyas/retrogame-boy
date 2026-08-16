# Licensing Notes

## Why /tv-app is GPLv3 and /controller-app is MIT

The TV host app statically links **libretro emulator cores** — `fceumm` (NES),
`snes9x` (SNES), `gambatte` (GB/GBC) and friends. Those cores are themselves
**GPL-licensed** (almost all classic libretro cores are GPLv3 or GPLv2).

GPL's copyleft is triggered by *distribution* of a work that links GPL code:
if you ship a binary that statically links a GPL core, the recipient must be
able to re-derive the whole work, which practically means the containing app
must be offered under a GPL-compatible license too.

So:

- **`/tv-app`** (which links cores) — **GPLv3**. Its *original* code is isolated
  behind a thin JNI interface and is clearly separated from core internals, but
  we still license the app GPLv3 so a distributed build is compliant out of the
  box.
- **`/controller-app`** (Flutter) — **MIT**. It contains no core code and never
  links it; only talks the JSON protocol over the network. It can therefore stay
  permissively licensed.

### Original-code isolation (good practice regardless)

The JNI bridge in `tv-app/.../core/` deliberately keeps all RetroLAN-original
code on one side of a narrow C ABI. The libretro API itself is a stable C API;
our bridge just forwards callbacks and runs the core's `retro_run()` on a
dedicated emulation thread. This means the *original* code is easy to
reimplement even if a core's globals change — no entangled code.

## Box art / metadata

We do **not** bundle or scrape copyrighted box art or game metadata from
third-party databases. ROM picker cards show a **placeholder art** component
the user can point at their own image files, or leave blank. If you add a
metadata provider, verify its license terms first.

## ROM files

**Hard rule:** no copyrighted ROMs are bundled, downloaded, or linked. The app
loads user-owned local ROM files chosen via the Android Storage Access
Framework. The `.gitignore` explicitly excludes all ROM extensions so none can
be accidentally committed.

## Credits

- [Libretro](https://www.libretro.com/) and its core authors (GPL).
- [Lemuroid](https://github.com/Swordfish90/Lemuroid) — used as a *reference*
  for the JNI/libretro wiring pattern (not copied wholesale).
- [Ktor](https://ktor.io/) web framework for the WebSocket server.
