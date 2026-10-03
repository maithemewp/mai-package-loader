# State
Updated: 2026-10-03 by Claude (Opus 5.5)

## Now

Built and reviewed five times; every finding fixed or recorded in the spec's "Known limits". mai-cache 0.6.0, mai-dom 1.1.0, mai-logger 0.2.0 and the mai-slots engine now load through it, all committed locally. On GitHub: main and develop as of 612f071 only; everything since is local. Nothing tagged.

## Next

1. Ask Mike, then: push this repo, tag `v0.1.0`, then push and tag mai-dom 1.1.0, mai-cache 0.6.0 and mai-logger 0.2.0. Order matters: see README "Releasing".
2. Consumers, each a separate change: raise the constraint and add this repo's VCS entry. mai-engine (`mai-cache` `^0.4.0` to `^0.6`), mai-analytics, mai-auth, mai-reactions, mai-sportsdataio, springwire-publish-wp, mai-publisher and balloon-juice-plugin (`mai-logger` to `^0.2`). Without the repo entry Composer silently keeps the old version.

## Blocked / waiting on

Mike: pushing and tagging, step 2.

## Verify

```sh
./tests/run.sh
```

Expect "All checks passed" twice and "33 caught, 0 survived". `ONLY="name|name" ./tests/mutations.sh` runs chosen breaks. `PHP_BIN` runs levels 1 and 2 on another PHP.

## Gotchas

- mai-engine's vendored mai-cache is a hand copy of 0.5.0 code, but its lock says v0.4.0. A fresh `composer install` there restores 0.4.0, which lacks `unlock()`, and fatals in `class-mai-query-cache.php:301`. Move it to `^0.6` through a real `composer update`.
- deployable-guard only checks `autoload_files.php`, so it no longer protects libraries on the loader. Not fixed; it lives in bizbudding/deployable-guard.
- Time performance warm, and on a quiet machine; the budget check retries up to three times. See AGENTS.md.
- `tests/.wp` is a cached throwaway WordPress; `./tests/level2.sh --fresh` rebuilds it. Level 2 copies the current `init.php` in on every run.
- Fixtures stamp versions with `sed`. Anchor it to the start of the line.
- Composer tracks a path repository by its git commit: commit loader changes before reinstalling them into a consumer, or the old copy stays.
