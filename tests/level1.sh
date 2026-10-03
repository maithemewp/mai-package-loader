#!/usr/bin/env bash
#
# Level 1: real Composer installs, no WordPress.
#
#   ./tests/level1.sh
#
# Needs Composer. No network: everything installs from local path repositories.

set -euo pipefail

source "$( dirname "${BASH_SOURCE[0]}" )/fixtures.sh"

WORK="$( mktemp -d )"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PROBE="$ROOT/tests/probe.php"
failed=0

# expect <description> <expected> <check> <plugin>...
expect() {
	local what="$1" want="$2" check="$3"
	shift 3
	local got
	got="$( "${PHP_BIN:-php}" "$PROBE" "$check" "$@" 2>&1 )" || true

	if [ "$got" = "$want" ]; then
		echo "  ok   $what"
	else
		echo "  FAIL $what"
		echo "       expected: $want"
		echo "       got:      $got"
		failed=1
	fi
}

# The floor is PHP 8.1, and nothing here runs 8.1 natively, so its syntax is
# checked through php-wasm whenever npx is available.
if command -v npx > /dev/null; then
	if PHP=8.1 npx -y @php-wasm/cli@latest -l "$ROOT/init.php" 2> /dev/null | grep -q 'No syntax errors'; then
		echo "  ok   init.php parses on PHP 8.1"
	else
		echo "  FAIL init.php does not parse on PHP 8.1"
		failed=1
	fi
else
	echo "  skip PHP 8.1 syntax check: npx not found"
fi

echo "Building fixtures..."
make_loader loader-100 1.0.0
make_loader loader-110 1.1.0
make_loader loader-120-takeover 1.2.0 takeover
make_loader loader-090-takeover 0.9.0 takeover
make_loader loader-130-broken 1.3.0 takeover-broken

make_lib lib-100 1.0.0
make_lib lib-200 2.0.0
make_lib lib-300 3.0.0
make_lib lib-300b 3.0.0
make_lib lib-500-missing 5.0.0 missing-file
make_lib lib-900-none 9.0.0 none
make_lib lib-900-notarray 9.0.0 not-array
make_lib lib-900-noname 9.0.0 no-name
make_lib lib-900-dev 9.0.0 dev-version
make_lib lib-900-beta 9.0.0 beta-version
make_lib lib-900-newline 9.0.0 newline-version
make_lib lib-900-wrongpkg 9.0.0 wrong-package
make_global_lib glob-100 1.0.0
make_global_lib glob-400 4.0.0
make_old_lib old-250 2.5.0
make_old_lib old-250-eager 2.5.0 eager

make_plugin p-a loader-100 1.0.0 lib-100 maithemewp/mai-demo 1.0.0
make_plugin p-b loader-100 1.0.0 lib-300 maithemewp/mai-demo 3.0.0
make_plugin p-c loader-100 1.0.0 lib-200 maithemewp/mai-demo 2.0.0
make_plugin p-same loader-100 1.0.0 lib-300b maithemewp/mai-demo 3.0.0
make_plugin p-missing loader-100 1.0.0 lib-500-missing maithemewp/mai-demo 5.0.0
make_plugin p-none loader-100 1.0.0 lib-900-none maithemewp/mai-demo 9.0.0
make_plugin p-notarray loader-100 1.0.0 lib-900-notarray maithemewp/mai-demo 9.0.0
make_plugin p-noname loader-100 1.0.0 lib-900-noname maithemewp/mai-demo 9.0.0
make_plugin p-dev loader-100 1.0.0 lib-900-dev maithemewp/mai-demo 9.0.0
make_plugin p-beta loader-100 1.0.0 lib-900-beta maithemewp/mai-demo 9.0.0
make_plugin p-newline loader-100 1.0.0 lib-900-newline maithemewp/mai-demo 9.0.0
make_plugin p-wrongpkg loader-100 1.0.0 lib-900-wrongpkg maithemewp/mai-other 9.0.0
make_plugin p-takeover loader-120-takeover 1.2.0 lib-200 maithemewp/mai-demo 2.0.0
make_plugin p-takeover-old loader-090-takeover 0.9.0 lib-200 maithemewp/mai-demo 2.0.0
make_plugin p-takeover-broken loader-130-broken 1.3.0 lib-200 maithemewp/mai-demo 2.0.0
make_plugin g-a loader-100 1.0.0 glob-100 maithemewp/mai-demo-global 1.0.0
make_plugin g-b loader-100 1.0.0 glob-400 maithemewp/mai-demo-global 4.0.0
make_plugin p-old loader-100 1.0.0 old-250 maithemewp/mai-demo 2.5.0
make_plugin p-old-eager loader-100 1.0.0 old-250-eager maithemewp/mai-demo 2.5.0
make_plugin p-loader110 loader-110 1.1.0 lib-200 maithemewp/mai-demo 2.0.0
make_plugin p-composer1 loader-100 1.0.0 lib-300 maithemewp/mai-demo 3.0.0
# Composer 1 wrote no installed.php, so the loader has to list the folder.
rm p-composer1/vendor/composer/installed.php
# Plugins that commit vendor/ often gitignore installed.php, so production has
# none either.
make_plugin p-takeover-norecord loader-120-takeover 1.2.0 lib-200 maithemewp/mai-demo 2.0.0
rm p-takeover-norecord/vendor/composer/installed.php
make_plugin p-takeover-old-norecord loader-090-takeover 0.9.0 lib-200 maithemewp/mai-demo 2.0.0
rm p-takeover-old-norecord/vendor/composer/installed.php

echo
echo "Newest copy wins, whatever the load order"
expect "a, b, c"                "3.0.0" info p-a p-b p-c
expect "c, b, a"                "3.0.0" info p-c p-b p-a
expect "b, a, c"                "3.0.0" info p-b p-a p-c
expect "a, c, b"                "3.0.0" info p-a p-c p-b
expect "a nested class too"     "3.0.0" deep p-a p-c p-b
expect "only one copy present"  "1.0.0" info p-a

echo
echo "Global-class libraries"
expect "newest wins, first loaded older"  "4.0.0" global g-a g-b
expect "newest wins, first loaded newer"  "4.0.0" global g-b g-a
expect "two libraries side by side"       "3.0.0 4.0.0" both p-a g-a p-b g-b

echo
echo "A copy that cannot be trusted is skipped"
expect "no declaration file"        "3.0.0" info p-none p-a p-b
expect "declaration not an array"   "3.0.0" info p-notarray p-a p-b
expect "declaration with no name"   "3.0.0" info p-noname p-a p-b
expect "a dev-develop version"      "3.0.0" info p-dev p-a p-b
expect "a dev-develop copy alone is not used" "false" exists p-dev
expect "a pre-release version"      "3.0.0" info p-beta p-a p-b
expect "a version with a trailing newline" "3.0.0" info p-newline p-a p-b
expect "a declaration copied from another library" "3.0.0" info p-wrongpkg p-a p-b
expect "each skipped copy says why" "its name is not maithemewp/mai-other|its version is not plain numbers like 0.6.0" rejected p-dev p-wrongpkg p-a

echo
echo "Missing files and duplicates"
expect "newest copy's file gone, next newest used" "3.0.0" info p-missing p-a p-b
expect "a class it does have still loads from it"   "5.0.0" deep p-missing p-a p-b
expect "but once a file is missing, the whole copy is dropped" "3.0.0 3.0.0" info-deep p-missing p-a p-b
expect "same version twice loads once"             "3.0.0" info p-b p-same
expect "a class no copy has returns quietly"       "false" missing p-a p-b
expect "and the library keeps working after it"    "false 3.0.0" nope-then-info p-a p-b
expect "a non-Mai class does no discovery"         "false true" non-mai p-a p-b
expect "nor does MailPoet, Mailchimp or MainWP"    "false true" mail p-a p-b

echo
echo "Living alongside an old bootstrap"
expect "old copy loaded first, newer copy wins"    "3.0.0" info p-old p-b
expect "old copy loaded last, newer copy wins"     "3.0.0" info p-b p-old
expect "old bootstrap already loaded the class"    "2.5.0" info p-old-eager p-b
expect "and the split across two versions is recorded" "3.0.0 recorded" mix p-old-eager p-b
expect "nothing is recorded when there is no split"     "3.0.0 none" mix p-a p-b

echo
echo "Without Composer's install record"
expect "a copy is found by listing the folder"     "3.0.0" info p-a p-composer1
expect "a newer loader still takes over"           "takeover" info p-a p-takeover-norecord p-b
expect "and an older one still does not"           "3.0.0" info p-a p-takeover-old-norecord p-b

echo
echo "The loader's own copies"
expect "first loader copy serves"                  "1.0.0" loader p-a p-loader110
expect "and still finds every library"             "3.0.0" info p-a p-loader110 p-b
expect "newer loader first, same answer"           "3.0.0" info p-loader110 p-a p-b
expect "a newer loader with takeover.php takes over" "takeover" info p-a p-takeover p-b
expect "only once, and the old one steps aside"      "takeover takeover" info-twice p-a p-takeover p-b
expect "an older loader's takeover.php is ignored"   "3.0.0" info p-a p-takeover-old p-b
expect "a takeover.php that returns no autoloader is recorded, and the old loader carries on" "3.0.0 recorded" takeover-broken p-a p-takeover-broken p-b

echo
[ "$failed" -eq 0 ] && echo "All checks passed." || echo "FAILED"
exit $failed
