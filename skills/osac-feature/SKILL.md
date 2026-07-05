---
name: osac-feature
description: Create Feature issues in the OSAC Jira project. Use when the user wants to create a Feature, enhancement, or new capability request for OSAC.
---

# OSAC Feature Creation

Create Feature issues in the OSAC Jira project using jira-cli.

## When to Use

- User asks to create a Feature, enhancement, or new capability request for OSAC
- User wants to track a new feature idea in Jira
- User provides feature requirements that should be formalized as a Jira issue

## Gather Inputs

Collect from conversation context. Ask only if truly ambiguous:

| Input | Required | Default |
|-------|----------|---------|
| Feature summary | Yes | From conversation context |
| Description | Yes | From conversation context |
| Assignee | No | Unassigned — only assign if user specifies |
| Label | No | `OSAC` |

**Note:** Features do not have parent epics in the OSAC project.

## Create the Feature

The User Stories section must include a subsection for each OSAC persona
defined in [`docs/personas.md`](https://github.com/osac-project/docs/blob/main/personas.md).
For each persona, either write an outcome-focused story ("As a X, I want Y
so that Z") or explicitly mark the persona as not affected by this feature.

```bash
KEY=$(jira issue create -t Feature --project OSAC \
  --summary "<concise feature title>" \
  --body "## Feature Goal

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

- [ ] <Completion criterion 1>
- [ ] <Completion criterion 2>

## Out of Scope

<What is explicitly excluded from this feature>" \
  --label OSAC \
  --no-input --raw 2>/dev/null | jq -r '.key')
```

**Key extraction notes:**
- Use `--raw` to get JSON output on stdout, then `jq -r '.key'` to extract the issue key reliably.
- Redirect stderr to `/dev/null` — the success message (`✓ Issue created`) goes to stderr and is not needed.
- Do **not** use `grep -oP` on the text output — it can match multiple keys in the URL or fail silently.

### Assign if specified

If user specified an assignee:
```bash
jira issue assign $KEY <assignee>
```

## Report

Output to user:

```
Feature created:

Jira:   https://redhat.atlassian.net/browse/<KEY>
Label:  OSAC
Status: New
```

## Standard Feature Format

Features should include these sections (shown in the body template above):

- **Feature Goal** — What the feature aims to accomplish
- **Problem Statement** — The problem this feature solves
- **User Stories** — Outcome-focused stories organized by persona (all four OSAC personas must be addressed — either with stories or an explicit "not affected" note)
- **Definition of Done** — Checklist of completion criteria
- **Out of Scope** — What is explicitly excluded from this feature

## Notes

- OSAC project key: `OSAC`
- Default label: `OSAC`
- Features do not link to parent epics in the OSAC project
- jira-cli handles markdown-to-ADF conversion automatically
