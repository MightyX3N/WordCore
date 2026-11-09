# runtime/vendor/

Pinned third-party sources compiled into the `wordcore` program. Their licences are collected in [NOTICES.txt](NOTICES.txt), which ships inside every download.

| Library | Version | Source | Licence |
|---|---|---|---|
| Lua | 5.5.1 | tag `v5.5.1` of [github.com/lua/lua](https://github.com/lua/lua) (core `.c`/`.h` files; test files `ltests.*`, `onelua.c` left out) | MIT |
| SQLite | 3.53.4 | amalgamation (`sqlite3.c`, `sqlite3.h`) | Public domain |
| Monocypher | 4.0.3 | tag `4.0.3` of [github.com/LoupVaillant/Monocypher](https://github.com/LoupVaillant/Monocypher) (`src/monocypher.c/.h`) | CC0 / BSD-2 (used under BSD-2) |

Also embedded in the core (not C): [etlua 1.3.0](https://github.com/leafo/etlua) templates (MIT, `core/vendor/etlua.lua`) and the Inter, Space Grotesk and JetBrains Mono fonts (OFL 1.1, latin + latin-ext subsets from Fontsource, `core/assets/fonts/`).

Unmodified. To update: replace the files, update this table and `NOTICES.txt`, rebuild, and run `python tests/run.py`.
