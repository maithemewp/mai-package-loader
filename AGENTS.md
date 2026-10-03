# Rules for working in this repo

One file, `init.php`, loaded by Composer into every plugin that bundles a shared mai library. The why is in `docs/specs/2026-10-03-mai-package-loader.md`. Read it before changing behaviour.

## Invariants

- **The public API only grows.** Composer runs `init.php` once per request, from whichever plugin loads first, so an old copy of this class may be the one serving a site. Never remove or rename a public method, constant, or declaration key. Unknown declaration keys must be ignored.
- **PHP 8.1.** The lowest floor of any plugin that bundles it (mai-analytics, mai-engine). No readonly classes, DNF types or anything else newer. Check with `PHP_BIN` pointing at php-wasm 8.1.
- **Nothing on a page that uses no `Mai` class.** `load()` turns away any other class name before doing any work.
- **Never load from a plugin that is switched off.** Inactive plugins and unloaded must-use folders are not looked in.
- **Never let the request choose folders.** WordPress loads every plugin before it checks who is asking, so anything read from `$_REQUEST`, `$_GET` or `$_POST` is chosen by whoever sent it, logged in or not. A security review caught this once.
- **No persistent cache of what was found.** Sites are deployed by copying files, which bypasses every WordPress hook, so a cache goes stale.
- **No `get_option()` before the object cache exists.** `optionsReady()` guards it. A drop-in runs before that.
- **Every behaviour has a mutation in `tests/mutations.sh`** that a test catches. Adding a behaviour means adding its test and its mutation.

## Performance

Budget: under 0.5 ms for first use on 40 bundling plugins, served warm. Level 2 enforces it. Measure warm, from a long-running PHP process with opcache on. A fresh command-line run has neither and overstates the cost several times over.

## Testing

```sh
./tests/run.sh
```

## Code

- `declare( strict_types=1 );`, the class `final`, comments explain why.
- Plain language in docs, no em-dashes.
