# mai-package-loader

**Status: agreed with Mike on 2026-10-03, and built.** Every hole in "What could go wrong" has a test, and every test was checked to fail when the code it guards was broken. "Known limits" lists what cannot be closed.

## The problem

Several plugins bundle the same shared library, such as mai-cache, each at its own version, and PHP can only load one copy of a class. Today the copy that loads is whichever plugin happened to load first, which is usually alphabetical.

That breaks in a way additive APIs cannot prevent. A plugin built against mai-cache 0.5 calls a method added in 0.5. If an older copy loaded first, the method is missing and the site fatals.

The libraries' own bootstraps tried to fix this and could not. Composer runs a package's `files` entry once per request, because every copy of a package gets the same file ID, so only the first plugin's bootstrap ever ran. Proven in mai-logger's `tests/negotiation.sh`.

## What it does

**One small package that loads the newest copy of every shared library, whichever plugin loads first, from the first moment any plugin uses one.**

- A shared library ships a declaration file, `mai-package.php`, and nothing else changes for it.
- A plugin using the library does nothing special. It requires the library with Composer and uses it.
- The loader finds every copy on the site, picks the newest per library, and autoloads that library's classes from it.

It is for libraries shared across plugins that opt in. A plugin's own classes have one copy and never go through it. Whole plugins, such as mai-analytics bundled inside mai-publisher, are a different problem and out of scope: swapping a plugin's copy is not safe, because of its database versions, hooks and activation.

## The declaration file

A library puts `mai-package.php` in its root:

```php
<?php
return [
	'name'      => 'maithemewp/mai-cache',
	'version'   => '0.5.0',
	'namespace' => 'Mai\\Cache\\',
	'path'      => 'src',
];
```

A library of global classes, such as mai-logger, lists them instead of a namespace:

```php
<?php
return [
	'name'    => 'maithemewp/mai-logger',
	'version' => '0.2.0',
	'classes' => [
		'Mai_Logger' => 'Mai_Logger.php',
	],
];
```

- **`version` is the library's own.** Composer's version can be `dev-develop` on a development install, which cannot be compared.
- **The library must not also autoload itself.** No `psr-4`, `classmap` or `files` entry for these classes in its `composer.json`, because Composer's own autoloader would then serve whichever copy it reached first.
- **Every name starts with `Mai`.** The loader ignores any other class before doing any work, so a page that uses no shared library pays nothing.

## How it finds copies

On the first request for a class starting with `Mai`, it looks in these vendor folders:

1. **Every vendor folder Composer has registered.** This covers anything already loaded, including must-use plugins and libraries loaded from outside any plugin folder.
2. **Every active plugin**, from the `active_plugins` option, before most of those plugins have loaded. This is what makes early use safe.
3. **Every network-active plugin** on multisite, from `active_sitewide_plugins`.
4. **The active theme and its parent**, since themes load after plugins.

**Never anything named in the request.** An earlier version read `?action=activate&plugin=...` the way Jetpack Autoloader does, so a plugin being activated could win from the start. A security review caught that WordPress loads every plugin before it checks who is asking, so a logged-out visitor could name an inactive plugin and its library code would load. Removed, with tests that a request naming one cannot load it.

In each folder it reads Composer's own record of what it installed, `composer/installed.php`, and checks only the `maithemewp/*` packages for a `mai-package.php`. With opcache that record costs next to nothing, where listing folders cost a directory read per plugin per page. A folder without the record, from Composer 1, is listed instead.

It looks again at `muplugins_loaded` and `plugins_loaded`, and when a plugin is activated later in the request. Each time, every class not loaded yet benefits. Sources 2 to 4 are read only once WordPress can read options safely, so a drop-in sees source 1 until the next look.

Inactive plugins are never used, even if they hold a newer copy, and neither are must-use plugin folders nothing loaded. Loading code someone switched off is the wrong kind of surprise.

## How it chooses

- **Per library, the highest `version` wins**, compared with `version_compare()`.
- **A copy whose declaration cannot be read is skipped**: a missing or non-array return, a missing name, or a version that is not plain numbers like `0.5.0`.
- **The same version found twice** loads from the first one found. They are the same code.
- **If the newest copy's file has gone missing**, the next newest copy is tried, so a plugin deleted mid-request does not fatal.

## Living alongside old copies

Sites already run copies of mai-logger and mai-cache with their own bootstraps. During the move:

- **The loader's autoloader is registered first in line**, so it answers before an old bootstrap does.
- **A class already loaded is left alone.** If an old bootstrap loaded it first, PHP cannot swap it, and the loader does not try or fatal.
- **The first release of each library on the loader must be a higher version than every old copy**, so it wins wherever both exist.

## The loader's own copies

Every library requires `maithemewp/mai-package-loader`, so it is bundled many times too. Composer runs its `init.php` once, from whichever plugin loads first, and that copy's class serves the whole request.

So **its public API only ever grows**. A declaration may gain keys over time, and an older loader ignores keys it does not know. Its PHP floor is the lowest of any consumer: **PHP 8.1**, set by mai-analytics and mai-engine.

## Known limits

These cannot be closed in PHP, and each is tested so its behaviour is at least known:

- **A class already loaded cannot be swapped.** If something uses a shared class before a newer copy is visible, that page load keeps the older class. The next page load is right. It happens only in three places: a drop-in such as `object-cache.php`, a must-use plugin using it before a later must-use plugin loads, and the request that activates a plugin, if the class loaded before that plugin did.
- **The first loader copy is the one in charge**, so the loader's API only ever grows.

## Performance

Measured on a throwaway site with 40 active plugins that all bundle the library, served from one long-running PHP process with opcache on, the way PHP-FPM serves a real site: **median 0.42 ms** for the first use, discovery and loading the class included. Loading each later class costs about 0.03 ms. A site that never uses a `Mai` class pays nothing.

Three changes got it there from 2.6 ms, all measured:

- Reading Composer's `installed.php` instead of listing folders.
- Not resolving every folder path through `realpath()`. Copies are counted once by their real folder anyway.
- Using `get_theme_root()` instead of reading `stylesheet_root`. That option rarely exists, so reading it cost a database query on every page.

## What could go wrong, and the test for each

Level 1 runs real Composer installs with no WordPress. Level 2 runs inside a throwaway WordPress.

**Level 1**

- Newest wins in every load order, with three copies.
- A namespaced library and a global-class library both load.
- A copy with a broken declaration is skipped: missing file, not an array, missing name, `dev-develop` version.
- The newest copy's file missing falls back to the next newest.
- The same version in two plugins loads once, with no redeclare error.
- A class requested that no copy has returns quietly, so the next autoloader can try.
- A class not starting with `Mai` triggers no discovery.
- An old-bootstrap copy present: the loader's newer copy still wins.
- The class already loaded by an old bootstrap: no fatal.
- Two loader copies at different versions: the first one serves, and finds every library.
- No `installed.php`, as Composer 1 left it: the copy is found by listing the folder.

**Level 2**

- Early use: a plugin uses a shared class at file load and still gets the newest copy from a plugin later in the alphabet.
- An inactive plugin with a newer copy is ignored.
- A listed active plugin whose folder was deleted is skipped.
- A request naming an inactive plugin, single or bulk, cannot load its copy.
- A plugin activated later in the request: classes not loaded yet use its copy.
- A library loaded from outside any plugin folder is used once plugins have loaded.
- The active theme's copy, and a parent theme's, are seen before themes load.
- Must-use plugins: one using the library sees active plugins; a later one's copy is used once they have all loaded, including by a plugin using it while plugins load.
- Drop-ins: one using the library gets the copies loaded so far, and every class loaded later gets the newest. Also with `WP_PLUGIN_DIR` set in `wp-config.php`, where reading options too early would fatal.
- Each copy is counted once after every re-check.
- Multisite: a network plugin using the library while loading sees a later network plugin's copy.
- `debug.log` stays clean across every case.

**Performance and PHP versions**

- The 40-plugin timing above, held to a 0.5 ms budget.
- Both levels pass on PHP 8.1 (through php-wasm), 8.4 and 8.5.

**Every behaviour is checked against a broken loader.** `tests/mutations.sh` makes 13 deliberate breaks, one per behaviour, and each makes at least one test fail. While writing them, three survived at first: two showed missing tests, which were added, and one showed a code path the re-checks already covered, which was removed.

## Not doing

- **A cache of the discovered copies.** The measured cost is low enough to look every request, and a cache would go stale whenever a site is deployed by copying files, which bypasses every WordPress hook.
- **Whole plugins.** See "What it does".
- **Prefixed copies per plugin**, as Strauss does. That is the right tool for third-party libraries and stays available for them.
