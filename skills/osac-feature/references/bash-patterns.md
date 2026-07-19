# Reusable bash patterns

**Read this file before any `jira issue create` or `jira issue edit`.**

Define once before any Jira create: source `tools/jira-safe-create.sh` (see
`jira-task-management` Safe create pattern), then define skill-specific helpers
below. Reference these from each create step instead of duplicating key
validation or `--plain` parsing.

## Source safe-create script

```bash
source "$(git rev-parse --show-toplevel)/tools/jira-safe-create.sh"
```

## Key validation and JQL helpers

```bash
# After jq -r '.key // empty' — stop on empty/malformed keys
require_osac_key() {
  local key=$1 label=$2 out=$3 err=$4
  if ! [[ "${key}" =~ ^OSAC-[0-9]+$ ]]; then
    echo "Invalid or empty ${label} key: ${key:-<empty>}" >&2
    cat "$err" >&2
    jq -r '.errorMessages[]? // .errors? // empty' "$out" 2>/dev/null >&2
    exit 1
  fi
}

# Parse KEY column from jira issue list --plain (skip header row).
# jira-cli --plain is tab-separated: TYPE, KEY, SUMMARY, … — column 2 is KEY.
# If layout changes, fall back to first OSAC-NNNN token on the line.
parse_plain_keys() {
  tail -n +2 | while IFS= read -r line; do
    [ -z "$line" ] && continue
    key=$(printf '%s\n' "$line" | awk -F'\t' '$2 ~ /^OSAC-[0-9]+$/ {print $2; exit}')
    if [ -n "$key" ]; then
      echo "$key"
    else
      printf '%s\n' "$line" | grep -Eo 'OSAC-[0-9]+' | head -1
    fi
  done
}

# Collect keys for JQL into variables (bash 3.2 / zsh — no mapfile).
# Usage: read keys from list_keys_for_jql "…" into FIRST_KEY and KEY_COUNT.
# On jira-cli failure, returns non-zero — callers must stop before create/edit.
#
# jira-cli exits 1 for BOTH genuine failures (bad JQL, network/auth errors)
# AND a valid query that simply matches nothing ("No result found for given
# query…" on stderr) — verified against jira-cli v1.7.0. Treat the latter as
# a normal empty result, not a failure, or every first-time duplicate check
# (which by definition finds nothing) would incorrectly abort create.
list_keys_for_jql() {
  local jql=$1 out err rc
  out=$(new_temp osac-jira-list-out)
  add_temp "$out"
  err=$(new_temp osac-jira-list-err)
  add_temp "$err"
  jira issue list -q "$jql" --plain >"$out" 2>"$err"
  rc=$?
  if [ "$rc" -ne 0 ] && ! grep -qi "no result found" "$err"; then
    echo "Jira issue list failed for: ${jql}" >&2
    cat "$err" >&2
    return 1
  fi
  parse_plain_keys <"$out"
}

collect_keys_from_jql() {
  local jql=$1 out k
  FIRST_KEY=""
  KEY_COUNT=0
  out=$(new_temp osac-jira-keys-collect)
  add_temp "$out"
  # Redirect list_keys_for_jql output to a temp file — do not use command
  # substitution ($(…)), which runs in a subshell and prevents add_temp inside
  # list_keys_for_jql from registering with the parent shell's EXIT trap.
  if ! list_keys_for_jql "$jql" >"$out"; then
    return 1
  fi
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    KEY_COUNT=$((KEY_COUNT + 1))
    [ -n "$FIRST_KEY" ] || FIRST_KEY=$k
  done <"$out"
}
```

## Fix version helpers

```bash
# Portable version sort (GNU sort -V or Homebrew gsort). macOS BSD sort lacks -V.
version_sort_desc() {
  if sort -V </dev/null >/dev/null 2>&1; then
    sort -Vr
  elif command -v gsort >/dev/null 2>&1; then
    gsort -Vr
  else
    echo "version sort unavailable — install GNU coreutils (gsort)" >&2
    return 1
  fi
}

# Fetch OSAC fix-version candidates (exclude 0.0 — pre-team legacy bucket —
# and the literal "Backlog" release, which collides with this skill's own
# "backlog" sentinel for "no fix version"; see validate_fix_version).
# jira release list does NOT support useful --plain output; parse tab format.
# Columns: ID, NAME, RELEASED, DESCRIPTION
# Output: one version name per line, newest first.
# Returns non-zero on Jira or sort failure — not the same as an empty list.
list_fix_version_suggestions() {
  local out err
  out=$(new_temp osac-jira-release-out)
  add_temp "$out"
  err=$(new_temp osac-jira-release-err)
  add_temp "$err"
  if ! jira release list -p OSAC >"$out" 2>"$err"; then
    echo "Jira release list failed:" >&2
    cat "$err" >&2
    return 1
  fi
  awk -F'\t' 'NR>1 && $2 != "0.0" && tolower($2) != "backlog" && $3 == "false" {print $2}' <"$out" \
    | version_sort_desc
}

# Validate user-chosen version. Returns: backlog | <version> | invalid
# backlog only when user explicitly says backlog/none/skip (not empty string).
# Returns 1 with "lookup_failed" on stdout when release list fails.
validate_fix_version() {
  local trimmed choice list_out
  trimmed=$(printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  choice=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')
  case "$choice" in
    backlog|none|skip) echo "backlog"; return 0 ;;
    '') echo "invalid"; return 0 ;;
  esac
  list_out=$(new_temp osac-jira-fixver-list)
  add_temp "$list_out"
  if ! list_fix_version_suggestions >"$list_out"; then
    echo "lookup_failed"
    return 1
  fi
  if grep -Fxq "$trimmed" <"$list_out"; then
    echo "$trimmed"
  else
    echo "invalid"
  fi
}

# Set fixVersion on Feature when FIX_VERSION is not backlog.
# Run after require_osac_key on Feature KEY, before assign/bootstrap; use </dev/null>.
# jira issue edit --fix-version appends; safe on new Features (empty fixVersions).
# Returns 1 on edit failure (non-fatal — does not exit) so the caller can avoid
# copying an unset version onto the bootstrap epic. Backlog is not a failure.
apply_feature_fix_version() {
  local key=$1 version=$2
  [ "$version" = "backlog" ] && return 0
  local err
  err=$(new_temp osac-jira-fixver-err)
  add_temp "$err"
  if ! jira issue edit "$key" --fix-version "$version" --no-input 2>"$err" </dev/null; then
    echo "Fix version edit failed for ${key} (${version}) — set manually:" >&2
    echo "  jira issue edit ${key} --fix-version \"${version}\" --no-input </dev/null" >&2
    cat "$err" >&2
    return 1
  fi
}
```

## Bootstrap epic metadata

```bash
# After bootstrap epic parent verified. Label at create; copy fix version here.
# Re-run safe on reuse: add label if missing; set fix version only when epic has none.
# Caller passes "backlog" for fix_version when the Feature edit did not succeed,
# so a failed Feature update never results in a copied version on the epic.
apply_bootstrap_epic_metadata() {
  local epic_key=$1 feature_key=$2 fix_version=$3
  local err
  err=$(new_temp osac-jira-bootstrap-meta-err)
  add_temp "$err"

  if ! jira issue edit "$epic_key" -l bootstrap --no-input 2>>"$err" </dev/null; then
    echo "Bootstrap label edit failed for ${epic_key} — set manually:" >&2
    echo "  jira issue edit ${epic_key} -l bootstrap --no-input </dev/null" >&2
    cat "$err" >&2
  fi

  [ "$fix_version" = "backlog" ] && return 0

  local epic_version_count raw
  if ! raw=$(jira issue view "$epic_key" --raw 2>>"$err"); then
    echo "Could not read ${epic_key} for fix version check — set manually if needed" >&2
    cat "$err" >&2
    return 0
  fi
  epic_version_count=$(printf '%s' "$raw" | jq -r '[.fields.fixVersions[]?.name] | length')
  [ "${epic_version_count:-0}" -gt 0 ] && return 0

  if ! jira issue edit "$epic_key" --fix-version "$fix_version" --no-input 2>>"$err" </dev/null; then
    echo "Bootstrap fix version copy failed for ${epic_key} (${fix_version}) — set manually:" >&2
    echo "  jira issue edit ${epic_key} --fix-version \"${fix_version}\" --no-input </dev/null" >&2
    cat "$err" >&2
    return 0
  fi
}
```

## Safe-create rules

Safe-create rules (all create/edit steps):
- Append **`</dev/null`** to every `jira issue create` and `jira issue edit` — jira-cli
  blocks on stdin in non-TTY shells ([jira-cli#948](https://github.com/ankitpokhrel/jira-cli/issues/948))
- Run `jira issue create` directly — not inside `$(...)`
- Write bodies to `--template` files; capture stdout/stderr to temps
- Allow up to 3 minutes per operation; **never kill** and retry
- Before retry, re-search Jira — duplicate creates are worse than slow creates
- If stdout is slow, poll Jira (`jira issue view`) instead of killing the in-flight command

## Example create pattern

```bash
BODY=$(new_temp osac-feature-body)
add_temp "$BODY"
OUT=$(new_temp osac-jira-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-err)
add_temp "$ERR"
# ... jira issue create ... >"$OUT" 2>"$ERR" </dev/null
KEY=$(jq -r '.key // empty' "$OUT")
require_osac_key "$KEY" "Feature" "$OUT" "$ERR"
```

## Duplicate search pattern

```bash
collect_keys_from_jql "parent = ${EPIC_KEY} AND type = Task AND summary = \"PRD\"" \
  || { echo "Duplicate-check lookup failed — stopping before create" >&2; exit 1; }
# KEY_COUNT == 1 → reuse FIRST_KEY; KEY_COUNT > 1 → ask user; 0 → create
```

**Always check the return value.** `collect_keys_from_jql` sets `KEY_COUNT=0`
before running the lookup, so a failed `jira issue list` looks identical to
"no duplicate found" if the caller doesn't check the exit status — that would
silently defeat the failure propagation above and risk creating a duplicate
issue on a transient Jira error.
