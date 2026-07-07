# Shared Ephemeral Cluster Pool — Requirements

**Status:** Planning document (draft)  
**Analysis date:** 2026-07-07  
**Related:** [VALIDATION-TIERS.md](VALIDATION-TIERS.md), [DEVELOPMENT-VELOCITY.md](DEVELOPMENT-VELOCITY.md)

This document specifies requirements for a shared pool of ephemeral OSAC development clusters. It is design-only — no infrastructure build is included in the current planning initiative.

---

## Problem

T3 validation (cluster-tool SNO snapshots) requires **64 GB RAM per cluster**. Developers who vet changes on production-like infrastructure either:

- Maintain personal baremetal access and cluster-tool setup
- Queue behind limited shared servers
- Skip T3 validation and rely on Prow presubmit (which runs only vmaas pytest)

This serializes validation and makes "fully vet every change" impractical at scale.

---

## Proposal

A **shared pool** of cluster-tool snapshots on known baremetal servers, with booking/scheduling so developers can request T3 validation without owning dedicated hardware.

```text
Developer laptop
  → booking API or shared calendar/queue
    → baremetal server (pool member)
      → libvirt VM (OpenShift SNO, COW clone from flavor snapshot)
        → refresh-after-snapshot → pytest → release
```

---

## Functional requirements

### FR-1: Flavor support

| Flavor | Priority | Use case |
|--------|----------|----------|
| **vmaas** | Required (default) | VM provisioning E2E (`pytest tests/vmaas/`) |
| **caas** | On-demand | Cluster provisioning E2E (`pytest tests/caas/`) |

Flavors are pre-built OCI images distributed via Quay (existing cluster-tool model):
- `quay.io/rh-ee-ovishlit/cluster-flavors:vmaas`
- `quay.io/rh-ee-ovishlit/cluster-flavors:caas`

### FR-2: Cluster lifecycle

1. **Pull** — flavor image pulled to server (once per server, ~60–90 GB, ~10–15 min)
2. **Boot** — COW clone from snapshot + recert (~5–10 min)
3. **Refresh** — `refresh-after-snapshot.py` updates OSAC stack to latest (~10–20 min)
4. **Validate** — developer runs pytest or manual testing
5. **Release** — cluster destroyed, resources returned to pool

Maximum concurrent clusters per server: `floor(total_RAM_GB / 64)`

### FR-3: Access model

- Developer receives **kubeconfig** for the allocated cluster
- SSH access to baremetal server for cluster-tool operations (or delegated via automation)
- **Pull secret** and **AAP license** managed centrally — not per-developer
- DNS: existing cluster-tool client setup (dnsmasq + NetworkManager on Linux laptop)

### FR-4: Booking

- Request specifies: flavor (vmaas/caas), estimated duration, purpose (PR validation, manual testing)
- Queue when no capacity available
- Maximum booking duration (proposed: 4 hours default, extendable)
- Notification when cluster is ready

### FR-5: CaaS agent setup

CaaS flavor requires additional agent VM setup via `scripts/setup-caas-agents.sh`. Pool operator or automated workflow must handle this — not left to individual developers.

---

## Non-functional requirements

### NFR-1: SLA targets

| Metric | Target |
|--------|--------|
| Boot-to-ready (flavor already pulled) | < 15 minutes |
| Boot-to-ready (first pull on server) | < 30 minutes |
| Queue wait time | Tracked as metric; no hard SLA in v1 |
| Cluster availability | Business hours minimum; 24/7 stretch goal |

### NFR-2: Capacity planning

| Server RAM | Max concurrent clusters |
|------------|------------------------|
| 256 GB | 4 |
| 512 GB | 8 |
| 768 GB | 12 |

Recommend starting with 1–2 servers (256–512 GB) serving a team of 5–10 developers.

### NFR-3: Security

- Pull secrets and AAP licenses stored securely on pool servers, not in developer repos
- kubeconfig access scoped to allocated cluster lifetime
- Clusters destroyed after release — no persistent tenant data
- SSH access to baremetal servers restricted to pool operators and automation

### NFR-4: Observability

Track and report:
- Pool utilization (clusters active / max capacity)
- Queue depth and wait time
- Boot/refresh failure rate
- Average validation session duration

---

## Roles and responsibilities

| Role | Responsibility |
|------|----------------|
| **Pool operator** (infra admin) | Maintain baremetal servers, pull flavors, manage licenses/secrets, handle failures |
| **Developer** | Book cluster, run validation, release promptly |
| **CI system** (future) | Automated booking for Prow-style presubmit (optional v2) |

---

## Out of scope (v1)

- Automated provisioning of new baremetal servers
- Multi-cluster management/workload separation testing
- Netris-specific infrastructure (separate periodic CI)
- Replacing Prow presubmit — pool is for **developer-initiated** T3 validation
- kind-dev (T2) — pool addresses T3 only

---

## Existing tooling leverage

The pool builds on existing cluster-tool workflow documented in `skills/osac-cluster/SKILL.md`:

```bash
cluster-tool connect <server> --host root@<server>
cluster-tool pull quay.io/rh-ee-ovishlit/cluster-flavors:vmaas
cluster-tool boot <name> vmaas
# refresh, test, destroy
cluster-tool destroy <name>
```

No new cluster provisioning technology is required — only scheduling, access management, and central credential handling.

---

## Open questions

1. **Booking mechanism:** Shared calendar, Slack bot, simple web UI, or Jira integration?
2. **Server ownership:** Existing baremetal lab machines or new procurement?
3. **Cost model:** Chargeback per cluster-hour or free internal resource?
4. **CI integration:** Should Prow presubmit use the same pool, or remain on dedicated CI machines?
5. **Refresh policy:** Always refresh to latest OSAC on boot, or allow testing against pinned versions?

---

## Success criteria

- Developer can request and receive a T3 cluster within 30 minutes (flavor pre-pulled) without personal baremetal setup
- Pool utilization metrics visible to leadership
- Reduction in "skipped T3 validation" due to hardware unavailability
- No increase in validation lead time compared to personal cluster-tool usage

---

## Relationship to validation tiers

| Tier | Environment | Pool role |
|------|-------------|-----------|
| T0–T1 | Laptop / CI unit tests | Not applicable |
| T2 | kind-dev on laptop | Not applicable — developer-owned |
| **T3** | cluster-tool snapshot | **Primary pool target** |
| T4 | Full osac-installer install | Out of scope v1 — remains periodic CI |

See [VALIDATION-TIERS.md](VALIDATION-TIERS.md) for full tier definitions.
