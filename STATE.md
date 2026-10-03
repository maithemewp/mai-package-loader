# State
Updated: 2026-10-03 by Claude (Opus 5.5)

## Now

Built, reviewed three times (a security review and two code reviews), and every finding fixed or written up as a known limit in the spec. Local only: not on GitHub, nothing released, and no library uses it yet.

## Next

1. Mike decides on creating `maithemewp/mai-package-loader` on GitHub.
2. Move mai-cache, mai-dom and mai-logger onto it, each in a release newer than every old copy.

## Blocked / waiting on

Mike: the GitHub repository, and whether the 0.6 ms speed budget (raised from 0.5) is fine.

## Verify

```sh
./tests/run.sh
```

Expect level 1 and level 2 to end "All checks passed", and the deliberate breaks to end "27 caught, 0 survived". `ONLY="name|name" ./tests/mutations.sh` runs chosen breaks. `PHP_BIN` runs levels 1 and 2 on another PHP; `/tmp/php81` style wrappers around `npx @php-wasm/cli` give PHP 8.1.

## Gotchas

- Time performance warm, never from a fresh command-line run. See AGENTS.md.
- `tests/.wp` is a cached throwaway WordPress, single site and multisite. `./tests/level2.sh --fresh` rebuilds it. Level 2 copies the current `init.php` into it on every run.
- PHP's built-in server only runs opcache with both `opcache.enable=1` and `opcache.enable_cli=1`.
- Fixtures stamp versions with `sed`. Anchor it to the start of the line, or it rewrites patterns in the loader's own source.
- `@include` of a missing file looks cheaper than checking first, but every active plugin without a vendor folder then raises a suppressed warning per page, which Query Monitor shows.
