#!/usr/bin/env bash
# Run every automated test and print one overall result.
# Usage: ./tests/run_all.sh        (takes roughly 30-60 seconds)
set -uo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
failed=()
for t in test_modules test_config test_history test_shutdown test_edge_cases test_terminal; do
    echo; echo "=== $t ==="
    bash "$DIR/$t.sh" || failed+=("$t")
done
echo
if ((${#failed[@]}==0)); then
    echo "ALL TEST SUITES PASSED"
else
    echo "FAILED SUITES: ${failed[*]}"; exit 1
fi
