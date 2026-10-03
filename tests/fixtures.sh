#!/usr/bin/env bash
#
# Builders for throwaway libraries and plugins, shared by both test levels.
# Every plugin gets a real `composer install`, because the bug this package
# exists to fix lived in how Composer treats one package installed many times.

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# A copy of this loader, stamped with a version, to install from.
#   make_loader <dir> <version> [takeover]
# takeover: ship a takeover.php whose autoloader serves Mai\Demo\Info itself,
# with VERSION 'takeover', so a test can see who answered.
make_loader() {
	local dir="$1" version="$2"
	mkdir -p "$dir"
	cp "${LOADER_INIT:-$ROOT/init.php}" "$dir/init.php"; cp "$ROOT/composer.json" "$dir/"
	sed -i.bak "s/^\([[:space:]]*\)public const VERSION = '[^']*';/\1public const VERSION = '$version';/" "$dir/init.php"
	rm -f "$dir/init.php.bak"

	if [ "${3:-}" = "takeover" ]; then
		cat > "$dir/takeover.php" <<'PHP'
<?php
return static function ( string $class ): void {
	if ( 'Mai\Demo\Info' === $class ) {
		require __DIR__ . '/takeover-info.php';
	}
};
PHP
		printf "<?php\nnamespace Mai\\Demo;\nfinal class Info { public const VERSION = 'takeover'; }\n" > "$dir/takeover-info.php"
	fi
	return 0
}

# A namespaced shared library, Mai\Demo\, at a version.
#   make_lib <dir> <version> [declaration]
# declaration: ok (default), none, not-array, no-name, dev-version, missing-file,
#   beta-version, newline-version, wrong-package
make_lib() {
	local dir="$1" version="$2" declaration="${3:-ok}" package="maithemewp/mai-demo"
	mkdir -p "$dir/src/Sub"

	# A library that copied mai-demo's declaration without renaming it.
	[ "$declaration" = "wrong-package" ] && package="maithemewp/mai-other"

	cat > "$dir/composer.json" <<JSON
{
	"name": "$package",
	"type": "library",
	"require": { "maithemewp/mai-package-loader": "*" }
}
JSON

	cat > "$dir/src/Info.php" <<PHP
<?php
namespace Mai\Demo;
final class Info {
	public const VERSION = '$version';
}
PHP

	cat > "$dir/src/Sub/Deep.php" <<PHP
<?php
namespace Mai\Demo\Sub;
final class Deep {
	public const VERSION = '$version';
}
PHP

	case "$declaration" in
		ok|missing-file|wrong-package)
			printf "<?php\nreturn [ 'name' => 'maithemewp/mai-demo', 'version' => '%s', 'namespace' => 'Mai\\\\\\\\Demo\\\\\\\\', 'path' => 'src' ];\n" "$version" > "$dir/mai-package.php"
			if [ "$declaration" = "missing-file" ]; then
				rm "$dir/src/Info.php"
			fi
			;;
		not-array)   echo "<?php return 'nope';" > "$dir/mai-package.php" ;;
		no-name)     printf "<?php\nreturn [ 'version' => '%s', 'namespace' => 'Mai\\\\\\\\Demo\\\\\\\\', 'path' => 'src' ];\n" "$version" > "$dir/mai-package.php" ;;
		dev-version) printf "<?php\nreturn [ 'name' => 'maithemewp/mai-demo', 'version' => 'dev-develop', 'namespace' => 'Mai\\\\\\\\Demo\\\\\\\\', 'path' => 'src' ];\n" > "$dir/mai-package.php" ;;
		beta-version) printf "<?php\nreturn [ 'name' => 'maithemewp/mai-demo', 'version' => '%s-beta', 'namespace' => 'Mai\\\\\\\\Demo\\\\\\\\', 'path' => 'src' ];\n" "$version" > "$dir/mai-package.php" ;;
		newline-version) printf "<?php\nreturn [ 'name' => 'maithemewp/mai-demo', 'version' => \"%s\\\\n\", 'namespace' => 'Mai\\\\\\\\Demo\\\\\\\\', 'path' => 'src' ];\n" "$version" > "$dir/mai-package.php" ;;
		none)        ;;
	esac
}

# A library of global classes, Mai_Demo_Global, at a version.
make_global_lib() {
	local dir="$1" version="$2"
	mkdir -p "$dir"
	cat > "$dir/composer.json" <<JSON
{
	"name": "maithemewp/mai-demo-global",
	"type": "library",
	"require": { "maithemewp/mai-package-loader": "*" }
}
JSON
	printf "<?php\nfinal class Mai_Demo_Global { public const VERSION = '%s'; }\n" "$version" > "$dir/Mai_Demo_Global.php"
	printf "<?php\nreturn [ 'name' => 'maithemewp/mai-demo-global', 'version' => '%s', 'classes' => [ 'Mai_Demo_Global' => 'Mai_Demo_Global.php' ] ];\n" "$version" > "$dir/mai-package.php"
}

# The same library the old way, as mai-cache works today: its own bootstrap
# through Composer's "files" entry, appending an autoloader, no declaration.
make_old_lib() {
	local dir="$1" version="$2"
	mkdir -p "$dir/src"
	cat > "$dir/composer.json" <<JSON
{
	"name": "maithemewp/mai-demo",
	"type": "library",
	"autoload": { "files": [ "init.php" ] }
}
JSON
	printf "<?php\nnamespace Mai\\\\Demo;\nfinal class Info { public const VERSION = '%s'; }\n" "$version" > "$dir/src/Info.php"
	cat > "$dir/init.php" <<'PHP'
<?php
spl_autoload_register( static function ( string $class ): void {
	if ( str_starts_with( $class, 'Mai\\Demo\\' ) ) {
		$file = __DIR__ . '/src/' . str_replace( '\\', '/', substr( $class, 9 ) ) . '.php';
		if ( is_readable( $file ) ) {
			require $file;
		}
	}
} );
PHP
	# Old bootstraps sometimes used a class at load time.
	if [ "${3:-}" = "eager" ]; then
		echo "class_exists( 'Mai\\Demo\\Info' );" >> "$dir/init.php"
	fi
	return 0
}

# A plugin folder with a real Composer install.
#   make_plugin <dir> <loader-dir> <loader-version> [<package-dir> <package-name> <version>]...
make_plugin() {
	local dir="$1" loader="$PWD/$2" loader_version="$3"
	shift 3
	mkdir -p "$dir"

	local repos requires
	repos="{ \"type\": \"path\", \"url\": \"$loader\", \"options\": { \"symlink\": false, \"versions\": { \"maithemewp/mai-package-loader\": \"$loader_version\" } } }"
	requires=""

	while [ $# -ge 3 ]; do
		repos="$repos, { \"type\": \"path\", \"url\": \"$PWD/$1\", \"options\": { \"symlink\": false, \"versions\": { \"$2\": \"$3\" } } }"
		requires="$requires\"$2\": \"$3\","
		shift 3
	done

	cat > "$dir/composer.json" <<JSON
{
	"name": "demo/$( basename "$dir" )",
	"repositories": [ $repos ],
	"require": { ${requires%,} }
}
JSON

	( cd "$dir" && composer install --quiet --no-interaction )
}
