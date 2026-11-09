# tests/

See [PLAN.md §11](../PLAN.md#11-testing).

```
tests/
├── unit/          # headless Lua tests for core modules and the addon API
├── integration/   # start `wordcore serve` / simulate CGI, drive HTTP, check the database
├── e2e/           # Playwright: fresh install → setup → pages → addons → themes → publish, per mode
└── security/      # CSRF, sandbox escapes, path traversal, open redirects, rate limits, proxy spoofing
```

Nothing counts as done until its tests pass and it's been clicked through as a real user.
