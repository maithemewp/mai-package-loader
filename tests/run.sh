#!/usr/bin/env bash
#
# Every check, in order.
#
#   ./tests/run.sh            # level 1, level 2, then the deliberate breaks
#   ./tests/run.sh --fresh    # reinstall the throwaway WordPress first

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "== Level 1: Composer installs, no WordPress"
"$DIR/level1.sh"
echo
echo "== Level 2: inside WordPress"
"$DIR/level2.sh" "$@"
echo
echo "== Deliberate breaks"
"$DIR/mutations.sh"
