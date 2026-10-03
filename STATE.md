# State
Updated: 2026-10-03 by Claude (Opus 5.5)

## Now

Built and tested locally. Not on GitHub yet, nothing released, and no library uses it yet.

## Next

1. Mike decides on creating `maithemewp/mai-package-loader` on GitHub.
2. Move mai-cache, mai-dom and mai-logger onto it, each in a release newer than every old copy.

## Blocked / waiting on

Mike: the GitHub repository.

## Verify

```sh
./tests/run.sh
```

Expect level 1, level 2 and the deliberate breaks all to end in "All checks passed" or "13 caught, 0 survived".

## Gotchas

- Time performance warm, never from a fresh command-line run. See AGENTS.md.
- `tests/.wp` is a cached throwaway WordPress. `./tests/level2.sh --fresh` rebuilds it.
- PHP's built-in server only runs opcache with both `opcache.enable=1` and `opcache.enable_cli=1`.
