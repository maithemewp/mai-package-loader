# State
Updated: 2026-10-03 by Claude (Opus 5.5)

## Now

Released. `v0.1.0` is tagged on `main` (c666181), and `main` and `develop` are pushed. mai-dom 1.1.0, mai-cache 0.6.0 and mai-logger 0.2.0 are tagged on it, and a fresh `composer install` from GitHub finds all three with nothing rejected.

The last fix before tagging: every Mai plugin gitignored `vendor/composer/installed.php`, so production took the folder-listing path, where a newer loader could never take over. It now can. Mike decided the fleet commits `installed.php` from now on; deployable-guard enforces it (committed locally, not released).

Consumers moved to the new versions, each committed locally on its own branch, nothing pushed: mai-analytics, mai-auth, mai-reactions, mai-sportsdataio, springwire-publish-wp, balloon-juice-plugin, the balloon-juice and horizonwesthappenings themes, and mai-publisher (repository entry only).

## Next

1. Mike: push and tag deployable-guard (`v1.1.0`, and move `v1`, which every plugin's CI pins).
2. Mike: push each consumer, and release them when ready.
3. mai-engine to mai-cache `^0.6`, inside its beta.5 plan's release step (Task 15), once the other session's verification on eurweb is done. Steps in "Gotchas".
4. mai-publisher moves to mai-logger 0.2 after a mai-analytics release that requires `^0.2`: `composer update maithemewp/mai-analytics maithemewp/mai-logger maithemewp/mai-package-loader`.

## Blocked / waiting on

Mike, for every push and release above.

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
