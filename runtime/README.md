# runtime/

The native `wordcore` program: Lua 5.5 with SQLite and a few native helpers built in, plus the Lua core from [`core/`](../core/) embedded inside it. One file per platform, nothing to install. See [PLAN.md §3](../PLAN.md#3-how-it-runs).

## Layout

```
runtime/
├── VERSION          # program version (0.1.0 = Phase 0)
├── src/             # C: entry point, native module, SQLite binding
│   ├── main.c       #   starts Lua, registers modules, runs core/boot.lua
│   ├── wc_native.c  #   wc.native: platform, time, files, env, sockets, poll, secure random
│   └── wc_sqlite.c  #   wc.sqlite: open / exec / prepared statements
├── vendor/          # pinned Lua 5.5.1 and SQLite 3.53.4 sources (see vendor/README.md)
├── build/build.py   # cross-compiles every target with Zig
└── host/            # files that go into the downloads (.htaccess, READMEs)
```

## Building

Needs Python 3.8+ and Zig (used as the C cross-compiler, any OS can build every target):

```
pip install ziglang==0.15.2
python runtime/build/build.py              # all targets → dist/<target>/
python runtime/build/build.py linux-x86_64 # just one
python tools/package.py                    # zips → dist/packages/
```

| Target | Output | Notes |
|---|---|---|
| `linux-x86_64` | `wordcore` | fully static (musl) — runs on any Linux host, used for shared hosting |
| `linux-arm64` | `wordcore` | fully static (musl) — Raspberry Pi, ARM servers |
| `windows-x64` | `wordcore.exe` | |
| `macos-arm64` | `wordcore` | ad-hoc signed (required on Apple Silicon) |
| `macos-x64` | `wordcore` | |

Each build is about 2 MB. The first build compiles SQLite once per target (~1 min); later builds take seconds.

## Commands

```
wordcore                      start the local server (same as `serve`)
wordcore serve [--host H] [--port N] [--site DIR] [--trust-proxy]
wordcore cgi                  one CGI request (chosen automatically when a web server runs it)
wordcore version
wordcore run <file.lua>       run a Lua script with the core available (development, tests)
```

When a web server runs the program (the `GATEWAY_INTERFACE` variable is set) the command line is ignored entirely, so visitors can never pick a command.

## Developing the core

Set `WORDCORE_CORE_DIR=core` to load the Lua core from the folder instead of the copy inside the program — no rebuild needed while editing Lua.

## Design notes

- **No C addons.** Lua's `package.loadlib`, C searchers and file searchers are removed at startup; the core is loaded from inside the program and addons will be Lua in a sandbox.
- **Server mode** uses non-blocking sockets, one coroutine per connection and a `poll()` loop, with keep-alive. Idle or slow clients can't hold anyone else up.
- **CGI mode** starts, answers one request and exits — about 2–3 ms on a normal server.
