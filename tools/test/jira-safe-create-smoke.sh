#!/usr/bin/env bash
# Smoke test for tools/jira-safe-create.sh — run from osac-workspace:
#   bash tools/test/jira-safe-create-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE="${SCRIPT_DIR}/../jira-safe-create.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$SOURCE" ]] || fail "missing $SOURCE"

# Regression: add_temp must run in the parent shell after $(new_temp ...).
# If temps are not registered, EXIT trap does not remove them.
test_registered_temp_cleaned_on_exit() {
  local path
  path=$(
    # shellcheck source=/dev/null
    source "$SOURCE"
    local f
    f=$(new_temp smoke-test)
    add_temp "$f"
    echo "$f"
  )
  [[ -n "$path" ]] || fail "new_temp returned empty path"
  [[ ! -f "$path" ]] || fail "registered temp not removed on EXIT: $path"
  pass "registered temp cleaned on EXIT"
}

# Unregistered temp (no add_temp) is intentionally not cleaned — documents the subshell footgun.
test_unregistered_temp_leaks() {
  local path
  path=$(
    # shellcheck source=/dev/null
    source "$SOURCE"
    new_temp smoke-leak
  )
  [[ -f "$path" ]] || fail "expected unregistered temp to exist for leak demo"
  rm -f "$path"
  pass "unregistered temp not tracked (add_temp required in parent shell)"
}

test_double_source_idempotent() {
  # shellcheck source=/dev/null
  source "$SOURCE"
  # shellcheck source=/dev/null
  source "$SOURCE"
  pass "double source is idempotent"
}

test_registered_temp_cleaned_on_exit
test_unregistered_temp_leaks
test_double_source_idempotent

echo "All jira-safe-create smoke tests passed."
