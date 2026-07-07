# OSAC Development Velocity Strategy

**Status:** Planning document (draft)  
**Analysis date:** 2026-07-07  
**Related:** [VALIDATION-TIERS.md](VALIDATION-TIERS.md), [CLUSTER-POOL-REQUIREMENTS.md](CLUSTER-POOL-REQUIREMENTS.md)

---

## Executive summary (leadership)

### Why AI has not linearly accelerated OSAC delivery

AI coding tools have meaningfully reduced the time to **write** code — drafting controllers, tests, proto definitions, and Ansible playbooks. They have not proportionally reduced the time to **prove** changes work in OSAC's full stack.

The bottleneck is **validation fidelity**, not code generation:

1. **OSAC is platform engineering, not app development.** A single feature touches 10+ repositories, async reconciliation loops, licensed Red Hat operators, and bare-metal infrastructure. A "small" controller change can require validating a chain from gRPC API → PostgreSQL → operator → AAP job → Ansible playbook → KubeVirt VM → network fabric.

2. **Licensed infrastructure is scarce and slow.** A production-like test environment requires a 64 GB RAM OpenShift cluster with AAP license, pull secrets, and bare-metal hosting. Boot time is measured in minutes; provisioning lifecycle tests run in tens of minutes. Developers cannot spin up unlimited parallel environments.

3. **Cross-repo coordination is manual.** Changing a proto field requires updating osac-installer image tags. Adding a CRD requires registering it in fulfillment-service. AI agents routinely miss companion changes (documented: MGMT-24226 eval scored 3/5 for missing installer updates).

4. **Process gates are intentional.** Every feature passes through PRD → Design (Enhancement Proposal) → Jira sync → Implement, with 9 cross-cutting dimensions (tenant onboarding, inventory, provisioning, networking, storage, installation, E2E, documentation, UI). This prevents production surprises but adds calendar time that commit-count metrics ignore.

### What would actually move the needle

| Lever | Impact |
|-------|--------|
| **Tier validation by change type** | Stop requiring T3 (64 GB cluster) for changes that T2 (laptop kind-dev) can prove |
| **Expand T2 coverage** | kind-dev now runs AWX + KubeVirt by default — use it for operator and compute playbook changes |
| **Automate cross-repo checks** | Catch missing installer/test-infra updates before full-stack validation |
| **Shared cluster pool** | Serialize T3 access through booking, not per-developer cluster ownership |
| **Measure validation lead time** | Track code-complete → first green at required tier, not just PR merge count |

### Recommended metrics (not yet instrumented)

- **Validation lead time:** hours from "code complete" to first green run at required tier
- **Tier distribution:** percentage of PRs requiring T2, T3, or T4
- **Cross-repo miss rate:** component PRs merged without required companion installer PR
- **Time-to-diagnose:** CI failure to root cause identified

Current tooling (`tools/pr-notify/`) tracks PR age and CI pass rate only — no validation-tier or lead-time metrics exist.

---

## Problem statement

### Architecture complexity

OSAC is a multi-tier distributed system:

```text
Client (gRPC/REST)
  → fulfillment-service (PostgreSQL, OPA, Keycloak)
    → controllers/reconcilers (in-process)
      → osac-operator (Kubernetes, multicluster-runtime)
        → AAP / AWX (Ansible job execution)
          → osac-aap playbooks (compute, network, storage)
            → Infrastructure (OpenStack, KubeVirt, HyperShift, Netris)
```

Each layer has its own test suite, deployment mechanism, and failure modes. A bug in reconciliation may only surface after an AAP job completes — minutes later, across multiple log streams.

See `.planning/codebase/ARCHITECTURE.md` for the full data flow.

### Multi-repo coordination

The workspace bootstraps 10+ component repos. Cross-repo dependencies are documented in `.planning/codebase/CONVENTIONS.md` but enforced only reactively (installer CI catches tag drift on installer PRs, not on component PRs).

### Process overhead

`.design/context/osac-dimensions.md` requires every feature to address:
- 5 services (BMaaS, CaaS, VMaaS, MaaS, Enclave)
- 4 personas (Cloud Provider Admin, Cloud Infrastructure Admin, Tenant Admin, Tenant User)
- 9 cross-cutting dimensions (tenant onboarding, inventory, provisioning, networking, storage, installation, E2E, documentation, UI)

The AI-assisted SDLC (`AI-assisted-development-workflow.md`) runs Feature → PRD → Design → Jira sync → Implement → E2E. This is appropriate for multi-repo features but heavyweight for single-repo bug fixes.

### Infrastructure scarcity

| Environment | RAM | Setup | Concurrent clusters per server |
|-------------|-----|-------|-------------------------------|
| kind-dev (T2) | 16+ GB recommended | ~20–30 min | 1 per laptop |
| cluster-tool (T3) | 64 GB | ~5–15 min boot | `floor(total_RAM / 64)` |
| osac-installer (T4) | Full cluster | ~30–45 min | 1 per baremetal |

See `skills/osac-cluster/SKILL.md` and `kind-dev/README.md`.

---

## Validation tier model

See [VALIDATION-TIERS.md](VALIDATION-TIERS.md) for the full tier matrix (T0–T4), change-type mapping, CI job mapping, and documentation drift notes.

---

## Phased improvement program

All phases below are **future work**. Phase A is this planning document set only.

### Phase A — Planning docs (this initiative)

**Scope:** osac-workspace, new files only under `.planning/codebase/`

- [x] `VALIDATION-TIERS.md` — tier matrix and change-type mapping
- [x] `DEVELOPMENT-VELOCITY.md` — this document
- [x] `CLUSTER-POOL-REQUIREMENTS.md` — shared cluster pool design

**Not in scope:** Changes to existing code, skills, scripts, or documentation.

---

### Phase B — CI strategy

**Scope:** osac-test-infra, openshift/release Prow config

| Item | Description |
|------|-------------|
| PR label `requires-e2e` | Gate T3 validation for provisioning/networking/storage PRs |
| Presubmit expansion | Add caas/storage/catalog suites as optional required checks by changed-path |
| Nightly T4 | Existing periodic `e2e-vmaas-full-setup-helm` — document as T4 regression |
| Path-based CI | Trigger T3 only when `osac-operator/`, `osac-aap/`, or provisioning paths change |

**Current state:** Only `pytest tests/vmaas/` runs on PR presubmit. caas, storage, catalog are periodic or separate workflows.

---

### Phase C — kind-dev improvements

**Scope:** osac-workspace `kind-dev/`

| Item | Description |
|------|-------------|
| README accuracy | Fix stale claims (AAP stubbed, 5–8 min setup, fake KubeVirt) — see VALIDATION-TIERS.md drift table |
| `--fast` flag | Skip AWX/KubeVirt for T1-equivalent path (~5–8 min) vs default full T2 |
| Resource guidance | Document honest minimums: 4 GB for fast path, 16+ GB for AWX+KubeVirt |
| Gather hook | Optional `gather-osac-logs.sh` before `teardown.sh` for failure forensics |

---

### Phase D — Cross-repo automation

**Scope:** osac-workspace skills and scripts

| Item | Description |
|------|-------------|
| `skills/cross-repo-checklist/SKILL.md` | Input: changed files → output: CONVENTIONS.md checklist + commands |
| Update `skills/create-pr/SKILL.md` | Invoke cross-repo checklist before PR creation |
| Update implement/bugfix guidelines | Reference CONVENTIONS table during validate phase |
| `scripts/check-cross-repo-impact.sh` | Detect touched paths → print required companion changes |

**Goal:** Prevent MGMT-24226-class misses (component fixed, installer not updated).

---

### Phase E — Observability and forensics

**Scope:** osac-workspace + osac-test-infra

| Item | Description |
|------|-------------|
| `skills/debug-e2e/SKILL.md` | Wire upstream skill into workspace; fix artifact layout drift |
| `scripts/gather-osac-logs.sh` wrapper | Delegate to `osac-test-infra/scripts/gather-osac-logs.sh` with kubeconfig auto-detect |
| Bootstrap hint | Note debug-e2e availability after `./bootstrap.sh` |
| Operator runbook | Reconciliation debugging guide in osac-operator/docs/ (separate repo) |
| Artifact layout sync | Reconcile debug-e2e skill docs with actual gather script output format |

**Current state:** `gather-osac-logs.sh` exists in osac-test-infra with CI integration. `debug-e2e` skill exists in osac-test-infra but is not installed by bootstrap. No workspace-level gather wrapper.

---

### Phase F — Process right-sizing

**Scope:** Documentation and skill guidance (no gate changes)

Clarify when to use full SDLC vs lightweight paths:

| Change size | Process | Validation tier |
|-------------|---------|-----------------|
| Single-repo bug, no API change | `/bugfix` or `/quick-fix` | T0–T1 |
| Single-repo with downstream deps | `/bugfix` + cross-repo checklist | T1–T2 |
| Multi-repo feature | `/prd` → `/design` → `/design:sync` → `/implement` per task | Per story (see VALIDATION-TIERS.md) |
| Installer-only pin bump | Submodule PR + `sync-image-tags.sh --fix` | T3 (matching overlay) |
| QE test addition | `/e2e` workflow | T3 |

**Principle:** PRD/Design gates exist for features with cross-cutting impact. They should not be required for bug fixes or narrow refactors — but this is guidance only, not enforced by tooling today.

---

### Phase G — Metrics and reporting

**Scope:** `tools/pr-notify/`, leadership reporting

| Metric | Definition | Source |
|--------|------------|--------|
| Validation lead time | Code-complete → first green at required tier | Manual today; future: CI timestamps |
| Tier distribution | % PRs tagged T0/T1/T2/T3/T4 | Future: PR labels |
| Cross-repo miss rate | Component PRs without companion installer PR | Future: PR dashboard cross-repo tracking |
| Time-to-diagnose | CI failure → root cause in Jira/PR comment | Future: debug-e2e usage tracking |
| PR age / CI pass rate | Already tracked | `tools/pr-notify/` |

Extend `docs/pr-dashboard/` spec as follow-up. No implementation in this planning initiative.

---

## Comparison: OSAC vs typical app development

| Dimension | Typical web app | OSAC |
|-----------|----------------|------|
| Repos per feature | 1 | 2–5+ |
| Deploy target | Container / serverless | OpenShift + operators + AAP + Ansible |
| Test feedback loop | Seconds (unit) to minutes (integration) | Minutes (T1) to hours (T3 provisioning lifecycle) |
| Licensed dependencies | Rare | AAP, OpenShift, CNV, MCE, pull secrets |
| Infra per developer | Shared staging env or ephemeral preview | 64 GB cluster per validation run |
| AI code generation impact | High (most code is self-contained) | Moderate (cross-repo and async validation dominate) |
| Process gates | Optional design doc | PRD + EP + Jira sync for features |

---

## What AI *has* accelerated

- Drafting proto definitions, Go servers, controller reconcile logic
- Generating unit test scaffolding (Ginkgo/Gomega patterns)
- Navigating large multi-repo codebase via progressive CLAUDE.md disclosure
- PRD and design document drafting with osac-dimensions coverage
- CI failure investigation via debug-e2e skill (when available)

## What AI has *not* accelerated

- Booting and waiting for licensed cluster environments
- Running full provisioning lifecycle tests (AAP job → VM boot → network attach)
- Cross-repo companion change detection (installer, test-infra)
- Async reconciliation debugging across operator → AAP → Ansible → infra
- Calendar time through PRD/Design review gates

---

## Next steps

1. Review and refine these planning docs
2. Share executive summary with leadership (§ Executive summary above)
3. Prioritize phases B–G based on team capacity and pain points
4. Delete or archive this branch when planning is complete, or open a PR if the tier model should become team policy
