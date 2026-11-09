# runtime/vendor/

Pinned third-party sources compiled into the `wordcore` program. Their licences are collected in [NOTICES.txt](NOTICES.txt), which ships inside every download.

| Library | Version | Source | Licence |
|---|---|---|---|
| Lua | 5.5.1 | tag `v5.5.1` of [github.com/lua/lua](https://github.com/lua/lua) (core `.c`/`.h` files; test files `ltests.*`, `onelua.c` left out) | MIT |
| SQLite | 3.53.4 | amalgamation (`sqlite3.c`, `sqlite3.h`) | Public domain |
| Monocypher | 4.0.3 | tag `4.0.3` of [github.com/LoupVaillant/Monocypher](https://github.com/LoupVaillant/Monocypher) (`src/monocypher.c/.h`) | CC0 / BSD-2 (used under BSD-2) |
| cmark-gfm | 0.29.0.gfm.13 | tag `0.29.0.gfm.13` of [github.com/github/cmark-gfm](https://github.com/github/cmark-gfm) (`src/` and `extensions/` flattened, `main.c` left out; hand-written `config.h` and export/version headers) | BSD-2 + others (see `cmark-gfm/COPYING`) |

Also embedded in the core (not C): [etlua 1.3.0](https://github.com/leafo/etlua) templates (MIT, `core/vendor/etlua.lua`), [luaqrcode](https://github.com/speedata/luaqrcode) QR codes for 2-step login (BSD-3, `core/vendor/qrencode.lua`) and the Inter, Space Grotesk and JetBrains Mono fonts (OFL 1.1, latin + latin-ext subsets from Fontsource, `core/assets/fonts/`).

Unmodified, except `qrencode.lua`: its 256×256 xor table is filled on demand with Lua 5.5's native `~` instead of at load time (saves ~45 ms per CGI request). To update: replace the files, update this table and `NOTICES.txt`, rebuild, and run `python tests/run.py`.
