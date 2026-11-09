# runtime/

The native `wordcore` program: a static Lua runtime with the C libraries WordCore needs built in, so nothing has to be installed on the machine or host.

See [PLAN.md §3](../PLAN.md#3-how-it-runs).

## Built in

- Lua (5.4 or LuaJIT — open question)
- SQLite
- zlib + zip
- Crypto: Argon2id, secure random, SHA-256, Ed25519, encryption for saved logins
- TLS (HTTPS client and server)
- libssh2 (SSH/SFTP publishing)
- Socket / event loop for server mode
- Image resize + WebP

## Targets

`linux-x86_64`, `linux-arm64` (static, musl), `windows-x64`, `macos-arm64`, `macos-x64`.

## Planned layout

```
runtime/
├── src/        # C entry point, Lua bindings for the native libraries
├── vendor/     # pinned third-party library sources
└── build/      # build scripts per target
```

## Commands the program will have

- `wordcore serve` — built-in web server (local / VPS)
- `wordcore cgi` — handle one request (used by `.htaccess` on shared hosting)
- `wordcore build --static` — export the site as static HTML
- `wordcore backup` / `wordcore restore`
