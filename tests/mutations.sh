#!/usr/bin/env bash
#
# Breaks the loader on purpose, one behaviour at a time, and checks a test
# notices. A test that passes against broken code is not testing anything.
#
#   ./tests/mutations.sh
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
		"if ( is_readable( $file ) ) {\n\t\t\t\t\t\trequire $file;\n\n\t\t\t\t\t\treturn;\n\t\t\t\t\t}",
		"require $file;\n\n\t\t\t\t\treturn;"),
	("declarations not checked", 1,
		"! is_string( $name ) || '' === $name || ! is_string( $version ) || ! preg_match( '/^\\d+(\\.\\d+){0,3}(-[0-9A-Za-z.]+)?$/', $version )",
		"! is_string( $version )"),
	("no folder listing without installed.php", 1,
		"return glob( $vendor . '/' . self::VENDOR . '/*/' . self::DECLARATION ) ?: [];", "return [];"),
	("WordPress lists ignored", 2,
		"if ( self::optionsReady() ) {\n\t\t\t\tforeach ( self::activePlugins() as $plugin ) {",
		"if ( false ) {\n\t\t\t\tforeach ( self::activePlugins() as $plugin ) {"),
	("a request chooses folders", 2,
		"return $plugins;\n\t\t}", "return array_merge( $plugins, isset( $_REQUEST['plugin'] ) && is_string( $_REQUEST['plugin'] ) ? [ $_REQUEST['plugin'] ] : [] );\n\t\t}"),
	("themes ignored", 2,
		"foreach ( self::themeDirs() as $theme ) {", "foreach ( [] as $theme ) {"),
	("network-active plugins ignored", 2,
		"is_multisite() && function_exists( 'get_site_option' )", "false"),
	("no re-check after must-use plugins", 2,
		"add_action( 'muplugins_loaded', [ self::class, 'refresh' ], PHP_INT_MIN );", ""),
	("no re-check after plugins", 2,
		"add_action( 'plugins_loaded', [ self::class, 'refresh' ], PHP_INT_MIN );", ""),
	("later activation ignored", 2,
		"add_action( 'activate_plugin', [ self::class, 'activating' ], 0 );", ""),
	("options read too early", 2,
		"&& isset( $GLOBALS['wpdb'], $GLOBALS['wp_object_cache'] )", ""),
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
