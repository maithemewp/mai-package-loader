#!/usr/bin/env bash
#
# Breaks the loader on purpose, one behaviour at a time, and checks a test
# notices. A test that passes against broken code is not testing anything.
#
#   ./tests/mutations.sh
#   ONLY="first copy wins|themes ignored" ./tests/mutations.sh
#
# Runs level 2 against the cached WordPress in tests/.wp, so run
# ./tests/level2.sh once first.

set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
WORK="$( mktemp -d )"
trap 'rm -rf "$WORK"' EXIT

# Each mutation: a name, the level it should be caught at, the exact text to
# find in init.php, and what to replace it with.
python3 - "$ROOT/init.php" "$WORK" <<'PY'
import json, sys
source, work = sys.argv[1], sys.argv[2]
code = open(source).read()
mutations = [
	("first copy wins", 1,
		"usort( $list, static fn( array $a, array $b ): int => version_compare( $b['version'], $a['version'] ) );", ""),
	("no fallback when a file is missing", 1,
		"if ( @is_file( $file ) ) {\n\t\t\t\t\t\trequire $file;\n\n\t\t\t\t\t\treturn;\n\t\t\t\t\t}",
		"require $file;\n\n\t\t\t\t\treturn;"),
	("a copy with a missing file is kept", 1,
		"unset( self::$libraries[ $name ][ $index ] );", ""),
	("versions not checked", 1,
		"if ( ! is_string( $version ) || ! preg_match( '/^\\d+(\\.\\d+){0,3}\\z/', $version ) ) {", "if ( ! is_string( $version ) ) {"),
	("pre-release versions accepted", 1,
		"if ( ! is_string( $version ) || ! preg_match( '/^\\d+(\\.\\d+){0,3}\\z/', $version ) ) {",
		"if ( ! is_string( $version ) || ! preg_match( '/^\\d+(\\.\\d+){0,3}(-[0-9A-Za-z.]+)?$/', $version ) ) {"),
	("declared name not checked against the package", 1,
		"if ( $package !== $name ) {", "if ( ! is_string( $name ) ) {"),
	("skipped copies not recorded", 1,
		"self::$rejected[ $file ] = $reason;", ""),
	("no folder listing without installed.php", 1,
		"foreach ( @glob( $vendor . '/' . self::VENDOR . '/*/' . self::DECLARATION ) ?: [] as $file ) {",
		"foreach ( [] as $file ) {"),
	("any name starting Mai triggers discovery", 1,
		"private const PREFIXES = [ 'Mai\\\\', 'Mai_' ];", "private const PREFIXES = [ 'Mai' ];"),
	("newer loaders never take over", 1,
		"\t\t\tself::takeOver();\n", ""),
	("the class in flight not handed over", 1,
		"( self::$successor )( $class );", ""),
	("the old loader stays registered", 1,
		"spl_autoload_unregister( self::$autoloader );", ""),
	("WordPress lists ignored", 2,
		"if ( self::optionsReady() ) {\n\t\t\t\tif ( function_exists( 'did_action' ) && ! did_action( 'plugins_loaded' ) ) {",
		"if ( false ) {\n\t\t\t\tif ( function_exists( 'did_action' ) && ! did_action( 'plugins_loaded' ) ) {"),
	("the raw plugin list instead of WordPress's own", 2,
		"$files = array_merge( $files, wp_get_active_and_valid_plugins() );",
		"$files = array_merge( $files, array_map( static fn( $p ) => WP_PLUGIN_DIR . '/' . $p, (array) get_option( 'active_plugins', [] ) ) );"),
	("plugin lists read after plugins have loaded", 2,
		"if ( function_exists( 'did_action' ) && ! did_action( 'plugins_loaded' ) ) {", "if ( true ) {"),
	("a request chooses folders", 2,
		"return array_values( array_filter( $files, 'is_string' ) );",
		"return array_merge( array_values( array_filter( $files, 'is_string' ) ), isset( $_REQUEST['plugin'] ) && is_string( $_REQUEST['plugin'] ) ? [ WP_PLUGIN_DIR . '/' . $_REQUEST['plugin'] ] : [] );"),
	("themes ignored", 2,
		"foreach ( self::themeDirs() as $theme ) {", "foreach ( [] as $theme ) {"),
	("theme previews ignored", 2,
		"$slug   = function_exists( $getter ) ? $getter() : get_option( $which );", "$slug   = get_option( $which );"),
	("network-active plugins ignored", 2,
		"if ( function_exists( 'is_multisite' ) && is_multisite() && function_exists( 'wp_get_active_network_plugins' ) ) {",
		"if ( false ) {"),
	("new Composer loaders not read", 2,
		"} elseif ( self::composerCount() !== self::$composerCount ) {", "} elseif ( false ) {"),
	("no re-check once options are readable", 2,
		"self::hook( 'muplugins_loaded', $refresh, PHP_INT_MIN );", ""),
	("no re-check once the theme is chosen", 2,
		"self::hook( 'setup_theme', $refresh, PHP_INT_MAX );", ""),
	("hooks lost when Composer loads before WordPress", 2,
		"$GLOBALS['wp_filter'][ $name ][ $priority ][] = [", "return;\n\t\t\t$GLOBALS['wp_filter'][ $name ][ $priority ][] = ["),
	("options read too early", 2,
		"if ( ! function_exists( 'get_option' ) || ! defined( 'WP_PLUGIN_DIR' ) || ! isset( $GLOBALS['wpdb'], $GLOBALS['wp_object_cache'] ) ) {",
		"if ( ! function_exists( 'get_option' ) || ! defined( 'WP_PLUGIN_DIR' ) ) {"),
	("sunrise.php reads options", 2,
		"return function_exists( 'did_action' ) && did_action( 'ms_loaded' ) > 0;", "return true;"),
	("discovery can restart itself", 2,
		"if ( self::$discovering ) {\n\t\t\t\tself::loadFrom(", "if ( false ) {\n\t\t\t\tself::loadFrom("),
	("copies counted twice", 2,
		"if ( $existing['dir'] === $copy['dir'] ) {\n\t\t\t\t\t\tcontinue 2;\n\t\t\t\t\t}", ""),
]
index = []
for i, (name, level, find, replace) in enumerate(mutations):
	if code.count(find) != 1:
		sys.exit(f"mutation '{name}': text not found exactly once in init.php")
	path = f"{work}/m{i}.php"
	open(path, "w").write(code.replace(find, replace))
	index.append({"name": name, "level": level, "path": path})
json.dump(index, open(f"{work}/index.json", "w"))
PY

caught=0
survived=0

while IFS=$'\t' read -r name level path; do
	# ONLY="name|name" runs just those, by exact name.
	if [ -n "${ONLY:-}" ] && ! printf '%s' "|$ONLY|" | grep -qF "|$name|"; then
		continue
	fi

	if [ "$level" = "1" ]; then
		failures="$( LOADER_INIT="$path" "$ROOT/tests/level1.sh" 2>&1 | grep -c 'FAIL ' || true )"
	else
		failures="$( LOADER_INIT="$path" "$ROOT/tests/level2.sh" 2>&1 | grep -c 'FAIL ' || true )"
	fi

	if [ "$failures" -gt 0 ]; then
		echo "  ok   caught: $name ($failures failing)"
		caught=$(( caught + 1 ))
	else
		echo "  FAIL survived: $name"
		survived=$(( survived + 1 ))
	fi
done < <( python3 -c "import json,sys; [print(f\"{m['name']}\t{m['level']}\t{m['path']}\") for m in json.load(open('$WORK/index.json'))]" )

echo
echo "$caught caught, $survived survived."
[ "$survived" -eq 0 ]
