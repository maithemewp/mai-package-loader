# mai-package-loader

**Status: agreed with Mike on 2026-10-03, built, and reviewed three times.** Every hole in "What could go wrong" has a test, and every test is checked by `tests/mutations.sh` to fail when the code it guards is broken. "Known limits" lists what PHP cannot close.

## The problem

Several plugins bundle the same shared library, such as mai-cache, each at its own version, and PHP can only load one copy of a class. Today the copy that loads is whichever plugin happened to load first, which is usually alphabetical.

That breaks in a way additive APIs cannot prevent. A plugin built against mai-cache 0.5 calls a method added in 0.5. If an older copy loaded first, the method is missing and the site fatals.

The libraries' own bootstraps tried to fix this and could not. Composer runs a package's `files` entry once per request, because every copy of a package gets the same file ID, so only the first plugin's bootstrap ever ran. Proven in mai-logger's `tests/negotiation.sh`.

## What it does

**One small package that loads the newest copy of every shared library, whichever plugin loads first, from the first moment any plugin uses one.**

- A shared library ships a declaration file, `mai-package.php`, and drops its own autoloading.
- A plugin using the library does nothing special. It requires the library with Composer and uses it.
- The loader finds every copy that this request will load, picks the newest per library, and autoloads that library's classes from it.

It is for libraries shared across plugins that opt in. A plugin's own classes have one copy and are never served by it: a `Mai\` or `Mai_` one is asked about, matches no declared library, and is left to Composer. Asking still starts discovery, the first time. Whole plugins, such as mai-analytics bundled inside mai-publisher, are a different problem and out of scope: swapping a plugin's copy is not safe, because of its database versions, hooks and activation.

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

A library of global classes lists them instead of a namespace:

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

- **`name` must be the library's Composer name.** A declaration copied from another library and not renamed is skipped, rather than passing for that library across the site.
- **`version` is the library's own, plain numbers like `0.5.0`.** Composer's version can be `dev-develop` on a development install, which cannot be compared, and a suffix such as `-beta` sorts unpredictably.
- **The library must not also autoload itself.** No `psr-4`, `classmap` or `files` entry for these classes, because Composer's autoloader would then serve whichever copy it reached first. That also means a shared library cannot ship helper functions or constants: a `files` entry only ever runs from the first plugin's copy.
- **Names start with `Mai\` or `Mai_`.** The loader ignores every other class before doing any work. Not just `Mai`, which would also catch MailPoet, Mailchimp and MainWP.

## How it finds copies

On the first request for a `Mai\` or `Mai_` class, it looks in these vendor folders:

1. **Every vendor folder Composer has loaded**, from its list of registered loaders, or under Composer 1 from each plugin's `ComposerAutoloaderInit` class, plus the loader's own folder. This covers everything already loaded: plugins, themes, must-use plugins, and libraries loaded from anywhere.
2. **The plugins WordPress will load this request**, from `wp_get_active_and_valid_plugins()` and, on multisite, `wp_get_active_network_plugins()`. These are WordPress's own lists, so a plugin WP-CLI skips, or recovery mode pauses, is left out exactly as WordPress leaves it out. This is what makes use before most plugins have loaded safe.
3. **The theme this request uses and its parent**, through `get_stylesheet()` and `get_template()`, so a theme previewed in the Customizer or the site editor counts.

Sources 2 and 3 are read only until that part of the site has loaded, `plugins_loaded` and `after_setup_theme`. From then on Composer's list is the truth, because it says what actually loaded. They are also read only once WordPress can answer for this site safely: not in a drop-in such as `object-cache.php`, and not in multisite's `sunrise.php`, before WordPress knows which site it is serving.

**It looks again when more has loaded.** Whenever Composer's list of vendor folders grows, the next `Mai` class request reads the new folders first. That covers a plugin being activated, which WordPress includes before firing `activate_plugin`, must-use plugins loading in turn, and a theme whose Composer folder is not `vendor/`. It also looks again at `muplugins_loaded`, when WordPress's lists become readable after a drop-in, and at `setup_theme`, once a preview has picked the theme. Each look reads only folders not read before.

**Never anything named in the request.** An earlier version read `?action=activate&plugin=...` the way Jetpack Autoloader does. A security review caught that WordPress loads every plugin before it checks who is asking, so a logged-out visitor could name an inactive plugin and its library code would load. Removed, with tests that a request naming one cannot load it.

In each folder it reads Composer's own record of what it installed, `composer/installed.php`, and checks only the `maithemewp/*` packages for a `mai-package.php`. With opcache that record costs next to nothing, where listing folders cost a directory read per plugin per page. A folder without the record is listed instead. Composer 1 wrote none, and every Mai plugin that commits `vendor/` gitignores it, following deployable-guard's advice, so on those sites listing is the usual path. See "Performance" for what it costs.

Inactive plugins are never used, even if they hold a newer copy. Loading code someone switched off is the wrong kind of surprise.

## How it chooses

- **Per library, the highest `version` wins**, compared with `version_compare()`.
- **Anything that goes wrong is recorded**, in `Mai_Package_Loader::rejected()`, and logged under `WP_DEBUG` when it can cause harm: an unreadable Composer record, a dropped copy, a takeover that throws or returns no autoloader, and a library split across an old bootstrap's copy and the newest. The Composer 1 fallback is recorded but not logged, since it works.
- **A copy whose declaration cannot be trusted is skipped, and the reason recorded**: it does not return an array, its name is not its Composer package, its version is not plain numbers, it declares no `Mai\` or `Mai_` names, or its path leaves its folder. `Mai_Package_Loader::rejected()` lists them, and with `WP_DEBUG` on each is logged once per request, so "class not found" can be traced without reading the loader.
- **The same version found twice** loads from the first one found. They are the same code.
- **If the newest copy lacks a file an older copy has**, say from a plugin deleted mid-request, it is damaged, since a library's classes only grow. It is dropped for the rest of the request and the next newest answers, so the rest of the library comes from one version rather than a mix. **When no copy has the file**, the class does not exist, as a `class_exists()` check may expect, and nothing is dropped. An earlier version dropped the copy in that case too, which mai-cache's own test suite caught: its test classes live under `Mai\Cache\Tests\`.

## Living alongside old copies

Sites already run copies of mai-logger and mai-cache with their own bootstraps. During the move:

- **The loader's autoloader is registered first in line**, so it answers before an old bootstrap, which appends its own.
- **A class already loaded is left alone.** If an old bootstrap loaded it first, PHP cannot swap it, and the loader does not try or fatal.
- **The first release of each library on the loader must be a higher version than every old copy**, so it wins wherever both exist.

## The loader's own copies

Every library requires `maithemewp/mai-package-loader`, so it is bundled many times too. Composer runs its `init.php` once, from whichever plugin loads first.

**Release order.** Push the loader, tag it, then tag each library. Never ship a development snapshot of the loader in a plugin: Composer records it as `dev-develop`, which never counts as newer, so a later fixed loader could not take over from it.

**A newer copy takes over.** Without this, a fix to the loader itself would only reach a site once every plugin bundling it had updated, and 0.1.0 is the only release that can add it. Composer's record holds every copy's version, so finding a newer one costs nothing on disk. A newer copy that ships `takeover.php` in its root is included once and must return an autoloader. That autoloader replaces this one and is handed the class being loaded. A copy no newer, a file that throws, or anything else returned is ignored. 0.1.0 ships no `takeover.php`; a later version that needs to fix something adds one.

So **its public API only ever grows**: `VERSION`, `boot()`, `discovered()` and `rejected()`, plus the `takeover.php` contract. A declaration may gain keys over time, and an older loader ignores keys it does not know. Its PHP floor is the lowest of any consumer: **PHP 8.1**, set by mai-analytics and mai-engine.

There is no `ABSPATH` guard. The file only defines a class, and an `exit` would end the whole request, blank and unlogged, on any site that loads Composer from `wp-config.php` before WordPress. On such a site the loader's hooks are left in `$wp_filter`, which WordPress picks up when it loads its plugin API.

## Known limits

These cannot be closed in PHP. Each is tested, so its behaviour is at least known:

- **A class already loaded cannot be swapped.** If something uses a shared class before a newer copy is visible, that page load keeps the older class, and the next one is right. It happens only where WordPress has not yet said what will load: a drop-in such as `object-cache.php`, multisite's `sunrise.php`, and a must-use plugin using it before a later must-use plugin loads.
- **Code that runs inside discovery gets the copies already loaded.** A filter on `option_active_plugins`, say, that uses a shared class is answered from what Composer has loaded so far, rather than starting discovery again inside itself, which would end in "class not found".
- **A site whose first Composer autoloader is from Composer 1** shares Composer 1's ClassLoader across every plugin, and it keeps no list of vendor folders. The loader finds them from each plugin's `ComposerAutoloaderInit` class instead, and always includes its own folder. A rollout review caught that an earlier version found nothing after `plugins_loaded`, so a library's first use fatalled; Favorites 2.3.8 is such a plugin, on three local sites. What remains: new folders are only noticed at the stage hooks, not on every class request, so a plugin using a library the moment it is activated gets the copies already known.

## Performance

Measured on a throwaway site with 40 active plugins that all bundle the library, served from one long-running PHP process with opcache on, the way PHP-FPM serves a real site: **about 0.5 ms** for the first use, discovery and loading the class included, in the upper middle of ten warm runs. The level 2 test holds it under 0.6 ms, retrying up to three times and keeping the best median, because load on the machine only ever adds time. Loading each later class costs about 0.03 ms. A site that never uses a `Mai\` or `Mai_` class pays nothing. Forty bundling plugins is the worst case; a real site has a handful.

What got it there, all measured:

- Reading Composer's `installed.php` instead of listing folders, from 2.6 ms.
- Not resolving every folder path through `realpath()`. Copies are counted once by their real folder anyway.
- Using `get_theme_root()` instead of reading `stylesheet_root`. That option rarely exists, so reading it cost a database query on every page.
- Checking files with `is_file()`, which PHP caches, rather than `is_readable()`, which it cannot and which cost eight times as much.
- Finding newer loader copies from Composer's record rather than looking on disk.

**Without `installed.php` it costs more**, because each plugin's `vendor/maithemewp` folder is listed instead. Measured on 2026-10-03 the same way, medians of ten warm runs:

- **40 plugins, all bundling:** 0.53 ms with the record, 1.4 ms without.
- **40 plugins, 5 bundling:** 0.11 ms with the record, 0.25 ms without.

A newer loader is still found without the record: only a copy that ships `takeover.php` can take over, so the loader checks for that one file, one file check per folder, and reads that copy's version from its `init.php`.

The first version measured 0.42 ms. The fixes from review, chiefly respecting WordPress's own plugin list, cost about 0.08 ms. Skipping the `installed.php` existence check got back 0.1 ms, but made every active plugin without a `vendor` folder raise a suppressed warning on every page, which Query Monitor lists, so it was not kept.

## What could go wrong, and the test for each

Level 1 runs real Composer installs with no WordPress. Level 2 runs inside a throwaway WordPress, single site and multisite.

**Level 1**

- `init.php` parses on PHP 8.1.
- Newest wins in every load order, with three copies, for a namespaced library and a global-class one.
- A copy that cannot be trusted is skipped: no declaration, not an array, no name, a `dev-develop`, `-beta` or newline-suffixed version, a declaration copied from another library. Each skipped copy says why.
- A file missing from the newest copy: the next newest answers, and the whole copy is dropped for the rest of the request. A class no copy has drops nothing, and the library keeps working after it.
- The same version in two plugins loads once.
- A class no copy has returns quietly.
- A non-`Mai` class, and MailPoet, Mailchimp and MainWP classes, trigger no discovery.
- An old-bootstrap copy present: the loader's newer copy still wins, and a class the old bootstrap already loaded causes no fatal.
- Two loader copies at different versions: the first one serves, and finds every library.
- A library split across an old bootstrap's copy and the newest is recorded, and nothing is recorded when there is no split.
- A `takeover.php` returning no autoloader is recorded, and the old loader carries on.
- A newer loader copy with `takeover.php` takes over, answers the class in flight, and the old loader leaves the autoloader list. An older copy's `takeover.php` is ignored.
- No `installed.php`, as Composer 1 left it and as plugins that gitignore it deploy: the copy is found by listing the folder, a newer loader with `takeover.php` still takes over, and an older one still does not.

**Level 2**

- Early use: a plugin uses a shared class at file load and still gets the newest copy from a plugin later in the alphabet.
- An inactive plugin with a newer copy is ignored, a listed active plugin whose folder was deleted is skipped, and a listed plugin file that does not exist does not make its folder count.
- A request naming an inactive plugin, single or bulk, cannot load its copy.
- Activation: a plugin activated later in the request is used for classes not loaded yet, and a plugin that uses the library the moment it is activated gets its own newer copy.
- WP-CLI: a plugin `--skip-plugins` names does not count.
- A filter on a list discovery reads, using the library itself: no fatal, and the rest of the request gets the newest copy.
- A library loaded from outside any plugin folder is used once plugins have loaded.
- Themes: the active theme's copy, and a parent's, are seen before themes load. A theme keeping its Composer folder outside `vendor/` is used once it loads.
- Theme previews: the previewed theme's copy is used while the theme loads and after.
- Composer loaded from `wp-config.php` before WordPress: the re-checks still run, shown by a theme preview, which needs one.
- Must-use plugins: one using the library sees active plugins; a later one's copy is used once they have all loaded, including by a plugin using it while plugins load.
- Drop-ins: one using the library gets the copies loaded so far, and every class loaded later gets the newest. Also with `WP_PLUGIN_DIR` set in `wp-config.php`, where reading options too early would fatal.
- Each copy is counted once after every re-check, including a symlinked plugin found by two paths.
- A Composer 1 plugin loading first: a library first used after plugins load is found, and so are one loaded from outside any plugin folder, including when used on `plugins_loaded`, and a theme's copy outside `vendor/`.
- Multisite: a network plugin using the library while loading sees a later network plugin's copy; a damaged network plugin list does not fatal; `sunrise.php` on a second site never reads the first site's plugins, and that site then gets its own copies.
- `debug.log` stays clean across every case.
- The 40-plugin timing, under 0.6 ms.

**Every behaviour is checked against a broken loader.** `tests/mutations.sh` makes 35 deliberate breaks, one per behaviour, and each makes at least one test fail. The first full run caught 23; the four that survived each showed a missing test, now added. The breaks skip the timing check, which a busy machine could fail and so make any break look caught.

## Not doing

- **A cache of the discovered copies.** The measured cost is low enough to look every request, and a cache would go stale whenever a site is deployed by copying files, which bypasses every WordPress hook.
- **Whole plugins.** See "What it does".
- **Prefixed copies per plugin**, as Strauss does. That is the right tool for third-party libraries. A consumer using Strauss must exclude `maithemewp/*` from prefixing, or it renames this loader and starts a second one.
