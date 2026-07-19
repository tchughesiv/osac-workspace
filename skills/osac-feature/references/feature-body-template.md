# Feature body template and create

**Read this file when creating the Feature issue** (after user confirms the gate).

The User Stories section must include a subsection for each OSAC persona
defined in `osac-docs/personas.md` (canonical source:
[osac-project/docs/personas.md](https://github.com/osac-project/docs/blob/main/personas.md)).
For each persona, either write an outcome-focused story ("As a X, I want Y
so that Z") or explicitly mark the persona as not affected by this feature.

Write the Feature body to `$BODY` using this structure (`BODY=$(new_temp osac-feature-body)` first). Use a blank line before
each `###` persona heading so jira-cli preserves separate subsections in Jira.

```markdown
## Feature Goal
<What this feature aims to accomplish>

## Problem Statement
<The problem this feature solves>

## User Stories

### Cloud Provider Admin

- As a Cloud Provider Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Cloud Infrastructure Admin

- As a Cloud Infrastructure Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Tenant Admin

- As a Tenant Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Tenant User

- As a Tenant User, I want <outcome> so that <reason>
- (or: not affected by this feature)

## Definition of Done
- [ ] <criterion>

## Out of Scope
<What is excluded>
```

## Duplicate check

Exact summary match, project-scoped (Features have no parent):

```bash
collect_keys_from_jql "project = OSAC AND type = Feature AND summary = \"${FEATURE_SUMMARY}\"" \
  || { echo "Feature duplicate-check failed — stopping before create" >&2; exit 1; }
if [ "$KEY_COUNT" -gt 0 ]; then
  echo "Existing Feature(s) with this summary (e.g. ${FIRST_KEY}) — ask user whether to reuse or proceed anyway" >&2
  exit 1
fi
```

A failed lookup must stop here — do not fall through with `KEY_COUNT=0` and
create a duplicate Feature on a transient Jira error.

Safe-create — use patterns from [bash-patterns.md](bash-patterns.md) (`new_temp`, `require_osac_key`):

```bash
BODY=$(new_temp osac-feature-body)
add_temp "$BODY"
# write markdown body to $BODY, then:
OUT=$(new_temp osac-jira-feature-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-feature-err)
add_temp "$ERR"

FEATURE_LABELS=()
[ "$REQUIRES_UI" = "yes" ] && FEATURE_LABELS+=(--label osac-ux --label osac-ui)
[ -n "${CUSTOMER:-}" ] && FEATURE_LABELS+=(--label customer --label "customer:${CUSTOMER}")

jira issue create -t Feature --project OSAC \
  -s "${FEATURE_SUMMARY}" \
  --template "$BODY" \
  --component "${COMPONENT}" \
  "${FEATURE_LABELS[@]}" \
  --no-input --raw >"$OUT" 2>"$ERR" </dev/null

KEY=$(jq -r '.key // empty' "$OUT")
require_osac_key "$KEY" "Feature" "$OUT" "$ERR"
if apply_feature_fix_version "$KEY" "$FIX_VERSION"; then
  BOOTSTRAP_FIX_VERSION="$FIX_VERSION"
else
  echo "Feature fix version not applied — bootstrap epic will not receive a copy; set both manually" >&2
  BOOTSTRAP_FIX_VERSION="backlog"
fi
```

Allow up to 3 minutes for create to complete.

Order after Feature create: **fix version → assign (if any) → bootstrap epic**.
Gate tasks never receive `--fix-version`. Use `$BOOTSTRAP_FIX_VERSION` (not
`$FIX_VERSION`) when applying bootstrap epic metadata below — it reflects
whether the Feature edit actually succeeded.

## Assign if specified

If user specified an assignee:

```bash
ASSIGN_ERR=$(new_temp osac-jira-assign-err)
add_temp "$ASSIGN_ERR"
if ! jira issue assign "$KEY" "$ASSIGNEE" 2>"$ASSIGN_ERR"; then
  echo "Assign failed for ${KEY} — continuing bootstrap" >&2
  cat "$ASSIGN_ERR" >&2
fi
```
