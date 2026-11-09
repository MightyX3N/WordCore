# runtime/vendor/

Pinned third-party sources compiled into the `wordcore` program. Their licences are collected in [NOTICES.txt](NOTICES.txt), which ships inside every download.

| Library | Version | Source | Licence |
|---|---|---|---|
| Lua | 5.5.1 | tag `v5.5.1` of [github.com/lua/lua](https://github.com/lua/lua) (core `.c`/`.h` files; test files `ltests.*`, `onelua.c` left out) | MIT |
| SQLite | 3.53.4 | amalgamation (`sqlite3.c`, `sqlite3.h`) | Public domain |

Unmodified. To update: replace the files, update this table and `NOTICES.txt`, rebuild, and run `python tests/run.py`.
