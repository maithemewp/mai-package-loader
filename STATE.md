# State
Updated: 2026-10-03 by Claude (Opus 5.5)

## Now

Released. `v0.1.0` is tagged on `main` (c666181), and `main` and `develop` are pushed. mai-dom 1.1.0, mai-cache 0.6.0 and mai-logger 0.2.0 are tagged on it, and a fresh `composer install` from GitHub finds all three with nothing rejected.

Every Mai plugin gitignored `vendor/composer/installed.php`, so production took the folder-listing path, where a newer loader could never take over. Fixed before tagging. Mike decided the fleet commits `installed.php` from now on, and deployable-guard v1.1.0 (`v1` moved to it) fails CI without it.

Consumers are on the new versions and pushed to `develop`: mai-analytics (released as 1.3.7), mai-auth, mai-reactions, mai-sportsdataio, springwire-publish-wp, balloon-juice-plugin and the balloon-juice theme. horizonwesthappenings is committed locally; it has no remote. mai-publisher requires mai-logger `^0.2` directly with mai-analytics 1.3.7, committed locally (4c5c6b1), not pushed.

## Next

1. Mike: push mai-publisher `develop`, and release consumers when ready.
2. mai-engine moves to mai-cache `^0.6` in its beta.5 release step, Task 15 of `docs/plans/2026-10-01-grid-cache-beta-5.md`, already rewritten for it.

## Blocked / waiting on

Mike, for the push and releases above.

## Verify

```sh
./tests/run.sh
```

Expect "All checks passed" twice and "35 caught, 0 survived". `ONLY="name|name" ./tests/mutations.sh` runs chosen breaks. `PHP_BIN` runs levels 1 and 2 on another PHP.

## Gotchas

- mai-engine's vendored mai-cache is a hand copy of 0.5.0 code, but its lock says v0.4.0, so a fresh `composer install` restores 0.4.0 and fatals on `unlock()` in `class-mai-query-cache.php:301`. The fix: require `^0.6`, add this repo's VCS entry, `composer update maithemewp/mai-cache maithemewp/mai-package-loader`, `composer dump-autoload --no-dev`, drop the `installed.php` gitignore line, and replace plan Task 7's hand copy and Task 15's `v0.5.0` tag. Fix the `Mai_Cache_Bootstrap` comments in `tests/phpunit/integration/plugin-loader.php` and `tests/phpunit/unit/bootstrap.php`.
- Without `installed.php` the loader costs about 1.4 ms on 40 bundling plugins instead of 0.53 ms (0.25 ms against 0.11 ms with 5 bundling). Measured warm, see the spec's "Performance".
- Strauss in mai-auth and mai-sportsdataio runs on every `composer update` and rewrites `vendor-prefixed` with the latest strauss.phar. Revert that unless you mean to change it.
- Time performance warm, and on a quiet machine; the budget check retries up to three times.
- `tests/.wp` is a cached throwaway WordPress; `./tests/level2.sh --fresh` rebuilds it.
- Composer tracks a path repository by its git commit: commit loader changes before reinstalling them into a consumer.
