#!/usr/bin/env bash
#
# Level 2: inside a throwaway WordPress, on SQLite so it needs no database
# server.
#
#   ./tests/level2.sh            # reuse the cached WordPress in tests/.wp
#   ./tests/level2.sh --fresh    # download and install it again
#
# Needs Composer and network access the first time.

set -euo pipefail

source "$( dirname "${BASH_SOURCE[0]}" )/fixtures.sh"

WP_VERSION="${WP_VERSION:-7.1.2}"
CACHE="$ROOT/tests/.wp"
WP="$CACHE/core"
PROBE="$ROOT/tests/wp-probe.php"
failed=0

install_wp() {
	local core="$1" multisite="${2:-}"

	mkdir -p "$CACHE/downloads"
	[ -f "$CACHE/downloads/wp.zip" ] || curl -sSL -o "$CACHE/downloads/wp.zip" "https://wordpress.org/wordpress-$WP_VERSION.zip"
	[ -f "$CACHE/downloads/sqlite.zip" ] || curl -sSL -o "$CACHE/downloads/sqlite.zip" "https://downloads.wordpress.org/plugin/sqlite-database-integration.latest-stable.zip"

	local unpack
	unpack="$( mktemp -d )"
	unzip -q "$CACHE/downloads/wp.zip" -d "$unpack"
	mv "$unpack/wordpress" "$core"
	unzip -q "$CACHE/downloads/sqlite.zip" -d "$core/wp-content/plugins/"
	rm -rf "$unpack"

	mkdir -p "$core/wp-content/database"
	sed "s|{SQLITE_IMPLEMENTATION_FOLDER_PATH}|$core/wp-content/plugins/sqlite-database-integration|; s|{SQLITE_PLUGIN}|sqlite-database-integration/load.php|" \
		"$core/wp-content/plugins/sqlite-database-integration/db.copy" > "$core/wp-content/db.php"

	cat > "$core/wp-config.php" <<'CONFIG'
<?php
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', '' );
define( 'DB_PASSWORD', '' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );
foreach ( [ 'AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY', 'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT' ] as $salt ) {
	define( $salt, 'mai-package-loader-test' );
}
$table_prefix = 'wp_';
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', true );
define( 'WP_DEBUG_DISPLAY', false );
define( 'WP_HOME', 'http://localhost:8421' );
define( 'WP_SITEURL', 'http://localhost:8421' );
// MULTISITE
// Some sites load Composer from here, before WordPress has a hook API.
if ( getenv( 'PROBE_SUNRISE' ) ) {
	define( 'SUNRISE', true );
}
if ( getenv( 'PROBE_EARLY_AUTOLOAD' ) ) {
	require __DIR__ . '/wp-content/plugins/zzz-newest/vendor/autoload.php';
}
// Some sites set their plugin folder here, Bedrock among them, which makes
// WP_PLUGIN_DIR exist before WordPress can read options.
if ( getenv( 'PROBE_CUSTOM_PLUGIN_DIR' ) ) {
	define( 'WP_PLUGIN_DIR', __DIR__ . '/wp-content/plugins' );
}
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
CONFIG

	( cd "$core" && php -r '
		define( "WP_INSTALLING", true );
		require "wp-load.php";
		require ABSPATH . "wp-admin/includes/upgrade.php";
		wp_install( "Loader test", "admin", "admin@example.com", true, "", "password" );
	' > /dev/null )

	if [ "$multisite" = "multisite" ]; then
		( cd "$core" && php -r '
			define( "WP_INSTALLING_NETWORK", true );
			define( "WP_ALLOW_MULTISITE", true );
			require "wp-load.php";
			require ABSPATH . "wp-admin/includes/upgrade.php"; require ABSPATH . "wp-admin/includes/network.php";
			foreach ( $wpdb->tables( "ms_global" ) as $table => $prefixed ) { $wpdb->$table = $prefixed; }
			install_network();
			$result = populate_network( 1, "localhost:8421", "admin@example.com", "Loader test", "/", false );
			if ( is_wp_error( $result ) ) { fwrite( STDERR, $result->get_error_message() . "\n" ); exit( 1 ); }
		' > /dev/null )
		sed -i.bak "s|// MULTISITE|define( 'MULTISITE', true ); define( 'SUBDOMAIN_INSTALL', false ); define( 'DOMAIN_CURRENT_SITE', 'localhost:8421' ); define( 'PATH_CURRENT_SITE', '/' ); define( 'SITE_ID_CURRENT_SITE', 1 ); define( 'BLOG_ID_CURRENT_SITE', 1 );|" "$core/wp-config.php"
		rm -f "$core/wp-config.php.bak"
	fi
}

# The plugins, themes and must-use plugins every scenario picks from.
install_fixtures() {
	local core="$1" work
	work="$( mktemp -d )"
	local plugins="$core/wp-content/plugins" themes="$core/wp-content/themes" mu="$core/wp-content/mu-plugins"

	(
		cd "$work"
		make_loader loader 1.0.0
		for v in 1.0.0 3.0.0 4.0.0 5.0.0 5.5.0 6.0.0 7.0.0 7.2.0 7.5.0 7.8.0 8.0.0 9.0.0; do
			make_lib "lib-$v" "$v"
		done

		# The first plugin alphabetically uses the library while plugins are
		# still loading, which is the case that needs WordPress's own lists.
		make_plugin "$plugins/aaa-early" loader 1.0.0 lib-1.0.0 maithemewp/mai-demo 1.0.0
		make_plugin "$plugins/zzz-newest" loader 1.0.0 lib-3.0.0 maithemewp/mai-demo 3.0.0
		make_plugin "$plugins/mmm-inactive" loader 1.0.0 lib-9.0.0 maithemewp/mai-demo 9.0.0
		make_plugin "$plugins/ppp-activating" loader 1.0.0 lib-4.0.0 maithemewp/mai-demo 4.0.0
		make_plugin "$plugins/qqq-later" loader 1.0.0 lib-5.0.0 maithemewp/mai-demo 5.0.0
		make_plugin "$plugins/rrr-eager" loader 1.0.0 lib-5.5.0 maithemewp/mai-demo 5.5.0
		make_plugin "$plugins/net-wide" loader 1.0.0 lib-6.0.0 maithemewp/mai-demo 6.0.0
		make_plugin "$themes/demo-parent" loader 1.0.0 lib-8.0.0 maithemewp/mai-demo 8.0.0
		make_plugin "$themes/demo-child" loader 1.0.0 lib-7.5.0 maithemewp/mai-demo 7.5.0
		# A theme that keeps its Composer folder somewhere other than vendor/.
		make_plugin "$themes/demo-odd/lib" loader 1.0.0 lib-7.8.0 maithemewp/mai-demo 7.8.0
		make_plugin "$mu/mu-a-lib" loader 1.0.0 lib-1.0.0 maithemewp/mai-demo 1.0.0
		make_plugin "$mu/mu-z-lib" loader 1.0.0 lib-7.0.0 maithemewp/mai-demo 7.0.0

		# A library loaded from outside any plugin's own folder, which no list
		# of plugins can point to.
		make_plugin "$core/wp-content/shared-lib" loader 1.0.0 lib-7.2.0 maithemewp/mai-demo 7.2.0
		make_plugin "$core/wp-content/dropin-lib" loader 1.0.0 lib-1.0.0 maithemewp/mai-demo 1.0.0
		# A plugin that lives elsewhere and is symlinked in, as plugins under
		# development usually are.
		make_plugin "$core/wp-content/real-sym" loader 1.0.0 lib-3.0.0 maithemewp/mai-demo 3.0.0
		mkdir -p "$plugins/bbb-includer"
	)

	for plugin in aaa-early zzz-newest mmm-inactive ppp-activating qqq-later rrr-eager net-wide; do
		printf "<?php\n/**\n * Plugin Name: %s\n */\nrequire_once __DIR__ . '/vendor/autoload.php';\n" "$plugin" > "$plugins/$plugin/$plugin.php"
	done
	echo "\$GLOBALS['mai_demo_early'] = Mai\\Demo\\Info::VERSION;" >> "$plugins/aaa-early/aaa-early.php"
	echo "if ( getenv( 'PROBE_MU' ) || getenv( 'PROBE_DROPIN' ) ) { \$GLOBALS['mai_demo_early_deep'] = Mai\\Demo\\Sub\\Deep::VERSION; }" >> "$plugins/aaa-early/aaa-early.php"
	# Uses the library the moment its file loads, which during activation is
	# before WordPress fires activate_plugin.
	echo "\$GLOBALS['mai_demo_eager'] = Mai\\Demo\\Sub\\Deep::VERSION;" >> "$plugins/rrr-eager/rrr-eager.php"
	printf "<?php\n/**\n * Plugin Name: sym-link\n */\nrequire_once __DIR__ . '/vendor/autoload.php';\n" > "$core/wp-content/real-sym/sym-link.php"
	ln -s "$core/wp-content/real-sym" "$plugins/sym-link"
	printf "<?php\n/**\n * Plugin Name: bbb-includer\n */\nrequire_once WP_CONTENT_DIR . '/shared-lib/vendor/autoload.php';\n" > "$plugins/bbb-includer/bbb-includer.php"

	printf "/*\nTheme Name: Demo Parent\n*/\n" > "$themes/demo-parent/style.css"
	printf "/*\nTheme Name: Demo Child\nTemplate: demo-parent\n*/\n" > "$themes/demo-child/style.css"
	for theme in demo-parent demo-child; do
		printf "<?php\nrequire_once __DIR__ . '/vendor/autoload.php';\n" > "$themes/$theme/functions.php"
		echo "<?php" > "$themes/$theme/index.php"
	done
	# The child theme uses the library while it loads, which is after the
	# theme is chosen but before after_setup_theme.
	echo "if ( getenv( 'PROBE_PREVIEW' ) ) { \$GLOBALS['mai_demo_theme'] = Mai\\Demo\\Sub\\Deep::VERSION; }" >> "$themes/demo-child/functions.php"
	printf "/*\nTheme Name: Demo Odd\n*/\n" > "$themes/demo-odd/style.css"
	printf "<?php\nrequire_once __DIR__ . '/lib/vendor/autoload.php';\n" > "$themes/demo-odd/functions.php"
	echo "<?php" > "$themes/demo-odd/index.php"

	# Must-use plugins only switch on when a scenario asks, so the others
	# never see their copies.
	printf "<?php\nif ( ! getenv( 'PROBE_MU' ) ) { return; }\nrequire_once __DIR__ . '/mu-a-lib/vendor/autoload.php';\n\$GLOBALS['mai_demo_mu_early'] = Mai\\\\Demo\\\\Info::VERSION;\n" > "$mu/mu-a.php"
	printf "<?php\nif ( ! getenv( 'PROBE_MU' ) ) { return; }\nrequire_once __DIR__ . '/mu-z-lib/vendor/autoload.php';\n" > "$mu/mu-z.php"

	# A filter on a list discovery reads, using the library itself.
	cat > "$mu/reentry.php" <<'PHP'
<?php
if ( getenv( 'PROBE_REENTRY' ) ) {
	add_filter( 'option_active_plugins', static function ( $plugins ) {
		if ( class_exists( 'Mai_Package_Loader', false ) && ! isset( $GLOBALS['mai_demo_reentry'] ) ) {
			$GLOBALS['mai_demo_reentry'] = Mai\Demo\Sub\Deep::VERSION;
		}
		return $plugins;
	} );
}
PHP

	# sunrise.php runs on multisite before WordPress knows which site this is.
	cat > "$core/wp-content/sunrise.php" <<'PHP'
<?php
if ( getenv( 'PROBE_SUNRISE' ) ) {
	require_once WP_CONTENT_DIR . '/dropin-lib/vendor/autoload.php';
	$GLOBALS['mai_demo_sunrise'] = Mai\Demo\Info::VERSION;
}
PHP

	# A theme preview, the way core's block theme Live Preview does it:
	# filters on stylesheet and template, added at plugins_loaded.
	cat > "$mu/preview.php" <<'PHP'
<?php
if ( getenv( 'PROBE_PREVIEW' ) ) {
	add_action( 'plugins_loaded', static function (): void {
		add_filter( 'stylesheet', static fn(): string => 'demo-child' );
		add_filter( 'template', static fn(): string => 'demo-parent' );
	}, 1 );
}
PHP

	# An object cache drop-in runs before WordPress can read any option. This
	# one is WordPress's own cache, plus a use of the library, when asked.
	cat > "$core/wp-content/object-cache.php" <<'PHP'
<?php
require_once ABSPATH . WPINC . '/cache.php';
if ( getenv( 'PROBE_DROPIN' ) ) {
	require_once WP_CONTENT_DIR . '/dropin-lib/vendor/autoload.php';
	$GLOBALS['mai_demo_dropin'] = Mai\Demo\Info::VERSION;
}
PHP

	# Forty plugins that all bundle the library, the worst case for
	# discovery. Copies of one install, each given its own Composer class
	# names so they can load side by side.
	local hash
	hash="$( sed -n 's/.*ComposerAutoloaderInit\([0-9a-f]*\).*/\1/p' "$plugins/zzz-newest/vendor/autoload.php" )"
	for i in $( seq -w 1 40 ); do
		mkdir -p "$plugins/perf-$i"
		cp -R "$plugins/zzz-newest/vendor" "$plugins/perf-$i/"
		grep -rl "$hash" "$plugins/perf-$i/vendor" | xargs sed -i.bak "s/$hash/${hash}p$i/g"
		find "$plugins/perf-$i/vendor" -name '*.bak' -delete
		printf "<?php\n/**\n * Plugin Name: perf-%s\n */\nrequire_once __DIR__ . '/vendor/autoload.php';\n" "$i" > "$plugins/perf-$i/perf-$i.php"
	done

	rm -rf "$work"
}

# configure <core> <stylesheet> <template> <plugin>...
configure() {
	local core="$1" stylesheet="$2" template="$3"
	shift 3
	( cd "$core" && php -r '
		require "wp-load.php";
		$args = array_slice( $argv, 1 );
		update_option( "stylesheet", array_shift( $args ) );
		update_option( "template", array_shift( $args ) );
		update_option( "active_plugins", array_map( fn( $p ) => "$p/$p.php", array_filter( $args, fn( $p ) => "ghost" !== $p ) ) + ( in_array( "ghost", $args, true ) ? [ 99 => "ghost/ghost.php" ] : [] ) );
	' -- "$stylesheet" "$template" "$@" )
}

# expect <description> <expected> <check> [ENV=value...]
expect() {
	local what="$1" want="$2" check="$3"
	shift 3
	local got
	got="$( env "$@" WP="$CORE" "${PHP_BIN:-php}" "$PROBE" "$check" 2>&1 )" || true

	if [ "$got" = "$want" ]; then
		echo "  ok   $what"
	else
		echo "  FAIL $what"
		echo "       expected: $want"
		echo "       got:      $got"
		failed=1
	fi
}

log_clean() {
	local log="$CORE/wp-content/debug.log"
	if [ -s "$log" ]; then
		echo "  FAIL debug.log is not clean:"
		sed 's/^/       /' "$log"
		failed=1
	else
		echo "  ok   debug.log clean"
	fi
}

if [ "${1:-}" = "--fresh" ] || [ ! -d "$WP" ]; then
	echo "Installing WordPress $WP_VERSION and fixtures..."
	rm -rf "${CACHE:?}/core" "${CACHE:?}/multisite"
	install_wp "$WP"
	install_fixtures "$WP"
	install_wp "$CACHE/multisite" multisite
	install_fixtures "$CACHE/multisite"
	# A second site, to tell this site's plugins from another's.
	( cd "$CACHE/multisite" && php -r 'require "wp-load.php"; $id = wp_insert_site( [ "domain" => "localhost:8421", "path" => "/two/" ] ); if ( is_wp_error( $id ) ) { fwrite( STDERR, $id->get_error_message() ); exit( 1 ); }' )
fi

# Every installed copy of the loader runs the code under test, not whatever
# was current when the sites were built. LOADER_INIT swaps in a broken one
# for tests/mutations.sh.
find "$CACHE" -path '*vendor/maithemewp/mai-package-loader/init.php' -print0 | xargs -0 -n1 cp "${LOADER_INIT:-$ROOT/init.php}"

CORE="$WP"
: > "$CORE/wp-content/debug.log"

echo
echo "Early use, before most plugins have loaded"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "the first plugin gets the newest copy from a later plugin" "3.0.0" early
expect "and so does everything after"                              "3.0.0" info

echo
echo "Only what is switched on"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "an inactive plugin's newer copy is ignored"  "3.0.0" info
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest ghost
expect "an active plugin whose folder is gone is skipped" "3.0.0" info
# A listed plugin file that does not exist, inside a folder that does. WordPress
# will not load it, so neither may its folder's copy.
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
( cd "$CORE" && php -r 'require "wp-load.php"; update_option( "active_plugins", array_merge( get_option( "active_plugins" ), [ "mmm-inactive/not-a-plugin.php" ] ) );' )
expect "a listed plugin file that does not exist does not count" "3.0.0" early

echo
echo "Activating a plugin"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
# Anyone can send these, logged in or not, and WordPress loads every plugin
# before it checks. Naming an inactive plugin must never load its code.
expect "a request naming an inactive plugin cannot load its copy" "3.0.0" early \
	PROBE_REQUEST='{"action":"activate","plugin":"ppp-activating/ppp-activating.php"}'
expect "nor a bulk request" "3.0.0" early \
	PROBE_REQUEST='{"action":"activate-selected","checked":["ppp-activating/ppp-activating.php"]}'
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "activated later in the request: classes not loaded yet use its copy" "3.0.0 5.0.0" activate-later
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "a plugin using it the moment it is activated gets its own newer copy" "5.5.0" activate-eager

echo
echo "WP-CLI"
configure "$CORE" twentytwentyfive twentytwentyfive ppp-activating qqq-later
got="$( cd "$CORE" && wp --skip-plugins=qqq-later eval 'echo Mai\Demo\Info::VERSION;' 2>&1 )" || true
if [ "$got" = "4.0.0" ]; then
	echo "  ok   a plugin WP-CLI skips does not count"
else
	echo "  FAIL a plugin WP-CLI skips does not count"
	echo "       expected: 4.0.0"
	echo "       got:      $got"
	failed=1
fi

echo
echo "Something discovery runs uses the library itself"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "no fatal, and the rest of the request gets the newest copy" "3.0.0" early PROBE_REENTRY=1
expect "the filter itself gets a copy already loaded"                "1.0.0" reentry PROBE_REENTRY=1

configure "$CORE" twentytwentyfive twentytwentyfive aaa-early bbb-includer zzz-newest
expect "a copy loaded from outside any plugin folder is used once plugins have loaded" "7.2.0" deep

echo
echo "Themes"
configure "$CORE" demo-child demo-parent aaa-early zzz-newest
expect "a parent theme's copy is seen before themes load" "8.0.0" early
configure "$CORE" demo-child demo-child aaa-early zzz-newest
expect "the active theme's copy is seen too" "7.5.0" early

configure "$CORE" demo-odd demo-odd aaa-early zzz-newest
expect "a theme's copy outside vendor/ is used once the theme has loaded" "7.8.0" deep

echo
echo "Theme previews"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "the previewed theme's copy is used while the theme loads" "8.0.0" theme PROBE_PREVIEW=1
expect "and after it"                                              "8.0.0" deep PROBE_PREVIEW=1

echo
echo "Composer loaded before WordPress"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "the re-checks still run" "8.0.0" theme PROBE_EARLY_AUTOLOAD=1 PROBE_PREVIEW=1

echo
echo "Must-use plugins"
configure "$CORE" twentytwentyfive twentytwentyfive zzz-newest
expect "one using the library while loading sees active plugins" "3.0.0" mu-early PROBE_MU=1
configure "$CORE" twentytwentyfive twentytwentyfive
expect "a later must-use plugin's copy is used once they have all loaded" "7.0.0" deep PROBE_MU=1
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early
expect "and by a plugin using it while plugins load" "7.0.0" early-deep PROBE_MU=1

echo
echo "Drop-ins, before WordPress can read its lists"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "a drop-in using it gets the copies loaded so far" "1.0.0" dropin PROBE_DROPIN=1
expect "every class loaded later gets the newest copy"   "3.0.0" early-deep PROBE_DROPIN=1
expect "a drop-in on a site with its own plugin folder setting" "1.0.0" dropin PROBE_DROPIN=1 PROBE_CUSTOM_PLUGIN_DIR=1

echo
echo "Each copy counted once"
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
expect "after every re-check, two plugins mean two copies" "2" copies
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early sym-link
expect "a symlinked plugin found by two paths is one copy" "2" copies

# tests/mutations.sh skips the timing: a busy machine failing it would make
# every deliberate break look caught.
if [ -z "${SKIP_PERF:-}" ]; then
echo
echo "Performance, forty active plugins that all bundle it, served warm"
configure "$CORE" twentytwentyfive twentytwentyfive $( for i in $( seq -w 1 40 ); do printf "perf-%s " "$i"; done )
# Timed from one long-running PHP process with opcache on, the way a PHP-FPM
# worker serves a real site. A fresh command-line run has neither opcache nor
# a warm file cache, and measures something no visitor ever waits for.
# Load can only add time, never remove it, so over budget is retried up to
# three times and the best median kept: the closest measure of the code's
# own cost on a busy machine.
best=""
for attempt in 1 2 3; do
	port="$( php -r '$s = stream_socket_server( "tcp://127.0.0.1:0" ); echo explode( ":", stream_socket_get_name( $s, false ) )[1];' )"
	php -d opcache.enable=1 -d opcache.enable_cli=1 -S "127.0.0.1:$port" -t "$CORE" "$ROOT/tests/perf-router.php" > /dev/null 2>&1 &
	server=$!
	trap 'kill "$server" 2> /dev/null || true' EXIT
	sleep 1
	times=""
	for run in $( seq 1 20 ); do
		t="$( curl -s "http://127.0.0.1:$port/perf" )"
		if [ "$run" -gt 10 ]; then
			times="$times $t"
		fi
	done
	{ kill "$server" && wait "$server"; } 2> /dev/null || true

	# The upper of the two middle values, so the budget is not met by luck.
	median="$( echo $times | tr ' ' '\n' | sort -n | sed -n 6p )"
	echo "  attempt $attempt, warm runs (ms):$times"

	if [ -z "$best" ] || awk "BEGIN { exit !( $median < $best ) }"; then
		best="$median"
	fi

	if awk "BEGIN { exit !( $best < 0.6 ) }"; then
		break
	fi
done

if awk "BEGIN { exit !( $best < 0.6 ) }"; then
	echo "  ok   median $best ms, under the 0.6 ms budget"
else
	echo "  FAIL median $best ms, over the 0.6 ms budget on three attempts"
	failed=1
fi
fi

echo
log_clean

echo
echo "Multisite"
CORE="$CACHE/multisite"
: > "$CORE/wp-content/debug.log"
configure "$CORE" twentytwentyfive twentytwentyfive
( cd "$CORE" && php -r 'require "wp-load.php"; update_site_option( "active_sitewide_plugins", [ "aaa-early/aaa-early.php" => time(), "net-wide/net-wide.php" => time() ] );' )
expect "a network plugin using it while loading sees a later network plugin's copy" "6.0.0" early
configure "$CORE" twentytwentyfive twentytwentyfive aaa-early zzz-newest
( cd "$CORE" && php -r 'require "wp-load.php"; update_site_option( "active_sitewide_plugins", "" );' )
expect "a damaged network plugin list does not fatal" "3.0.0" info

# The first site runs a plugin with a newer copy than anything the second
# site runs. sunrise.php, on a request for the second site, must not find it.
( cd "$CORE" && php -r 'require "wp-load.php";
	update_site_option( "active_sitewide_plugins", [] );
	update_option( "active_plugins", [ "mmm-inactive/mmm-inactive.php" ] );
	switch_to_blog( 2 );
	update_option( "active_plugins", [ "zzz-newest/zzz-newest.php" ] );
	update_option( "stylesheet", "twentytwentyfive" );
	update_option( "template", "twentytwentyfive" );' )
expect "sunrise.php never reads another site's plugins"  "1.0.0" sunrise PROBE_SUNRISE=1 PROBE_CUSTOM_PLUGIN_DIR=1 PROBE_SITE=/two/
expect "and the second site then gets its own copies"    "3.0.0" deep PROBE_SUNRISE=1 PROBE_CUSTOM_PLUGIN_DIR=1 PROBE_SITE=/two/
log_clean

echo
[ "$failed" -eq 0 ] && echo "All checks passed." || echo "FAILED"
exit $failed
