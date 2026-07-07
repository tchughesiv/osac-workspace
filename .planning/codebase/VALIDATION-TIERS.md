# OSAC Validation Tiers

**Status:** Planning document (draft)  
**Analysis date:** 2026-07-07  
**Related:** [DEVELOPMENT-VELOCITY.md](DEVELOPMENT-VELOCITY.md), [CLUSTER-POOL-REQUIREMENTS.md](CLUSTER-POOL-REQUIREMENTS.md)

This document defines a validation tier model for OSAC development. It maps change types to minimum test environments so developers and leadership can reason about *where* time is spent — and why AI-assisted code generation does not automatically shorten end-to-end delivery.

---

## Tier overview

| Tier | Environment | Typical time | RAM | What it validates |
|------|-------------|--------------|-----|-------------------|
| **T0** | Local unit tests | seconds | minimal | Go logic, mappers, auth, DAO, error handling |
| **T1** | kind IT (`fulfillment-service-it`) | ~10 min | ~4 GB | API, RBAC, tenancy, reconcilers, REST gateway |
| **T2** | kind-dev (AWX + KubeVirt) | ~20–30 min | 16+ GB recommended | ComputeInstance lifecycle, operator→AWX→playbook→VM |
| **T3** | cluster-tool SNO snapshot | ~5–15 min boot | 64 GB per cluster | Full VMaaS/CaaS pytest E2E, licensed AAP, CNV |
| **T4** | osac-installer on OpenShift | ~30–45 min install | full cluster | Production-like install, OLM operators, upgrade paths |

Tiers are cumulative: a change requiring T2 should also pass T0 and T1 where applicable.

```text
T0 (unit) → T1 (kind IT) → T2 (kind-dev) → T3 (cluster-tool) → T4 (full OCP install)
```

---

## Tier details

### T0 — Unit tests

**Command:** `ginkgo run -r internal` (per component repo)

**Covers:**
- Individual functions and methods in isolation
- Mocked dependencies (database, gRPC clients, auth)
- Proto mapping, validation, error types

**Does not cover:**
- Kubernetes reconciliation
- Real PostgreSQL or Keycloak
- Provisioning backends (AAP, Ansible)

**Repos:** `fulfillment-service`, `osac-operator`, others with `internal/` test suites.

---

### T1 — Integration tests (fulfillment-service `it/`)

**Command:** `ginkgo run it` (from `fulfillment-service/`)

**Infrastructure:**
- kind cluster named `fulfillment-service-it`
- PostgreSQL, Keycloak, cert-manager, trust-manager, Envoy Gateway, Authorino
- Helm or kustomize deployment of fulfillment-service

**DNS requirement:** `/etc/hosts` entries (unlike kind-dev):

```text
127.0.0.1 keycloak.keycloak.svc.cluster.local
127.0.0.1 fulfillment-api.osac.svc.cluster.local
127.0.0.1 fulfillment-internal-api.osac.svc.cluster.local
```

**Covers (~28 test files):**
- Auth, access control, multi-tenancy, RBAC
- Public/private API endpoints, REST gateway
- Cluster and template APIs, reconciler behavior
- Labels, annotations, CLI errors, bare metal API surface

**Does not cover:**
- Real AAP job execution
- KubeVirt VM boot
- ClusterOrder / HyperShift provisioning
- Real network fabric or storage backends

**Note:** `.planning/codebase/TESTING.md` labels these as both "integration" and "E2E." For tier purposes, treat `it/` as **T1 integration**, not full-stack E2E.

---

### T2 — kind-dev (laptop)

**Command:** `kind-dev/setup.sh` (from workspace root: `cd kind-dev && ./setup.sh`)

**Infrastructure:**
- kind cluster (`osac-dev` by default)
- Full OSAC stack: fulfillment-service, osac-operator, PostgreSQL, Keycloak
- **KubeVirt + CDI + Multus** (installed by default in `kind-dev/setup.sh`)
- **AWX** as open-source AAP substitute (~10–12 min install time)
- Real `osac-aap` playbooks for ComputeInstance create/delete

**Hostname model:** `*.localhost` (e.g. `api.osac.localhost:8443`) — no `/etc/hosts` edits needed. CoreDNS rewrite rule added by setup script.

**Covers:**
- API flows, RBAC, multi-tenancy (same as T1, plus operator on same cluster)
- Operator → AWX → Ansible playbook → KubeVirt VM lifecycle
- Hub registration, tenant namespaces, ComputeInstance CR reconciliation

**Proven end-to-end flow (documented in `kind-dev/README.md` Stage 3):**

```text
osac create computeinstance
  → fulfillment-service (PostgreSQL)
  → fulfillment-controller (ComputeInstance CR)
  → osac-operator (AWX job launch)
  → osac-aap playbook (DataVolume + VirtualMachine)
  → KubeVirt VM Running
```

**Does not cover:**
- ClusterOrder / Hosted Control Planes provisioning
- Real networking backend (networking job templates are no-op `hello_world.yml`)
- Storage fulfillment, bare metal fulfillment, MetalLB
- Licensed Red Hat AAP (uses AWX upstream)
- OpenShift Routes (uses Gateway API TLSRoute)

**Disabled in `kind-dev/values-kind.yaml`:** `clusterFulfillment`, `networkFulfillment`, `storageFulfillment`, `bmf`, `metallb`, `capiProvider`.

**Platform constraints:**
- Rootful podman required for KubeVirt VMs with KVM (`/dev/kvm`)
- Rootless podman works for API/controller dev but not VM launch
- Images loaded via `podman save` + `kind load image-archive`

---

### T3 — cluster-tool snapshot

**Workflow:** See `skills/osac-cluster/SKILL.md`

**Infrastructure:**
- OpenShift SNO VM on baremetal server (libvirt)
- 64 GB RAM, 16 vCPUs per cluster
- Pre-built flavor snapshots from Quay (vmaas or caas)
- Licensed AAP, CNV/KubeVirt, Keycloak, full OSAC stack

**Flavors:**

| Flavor | Image | Use case |
|--------|-------|----------|
| **vmaas** | `quay.io/rh-ee-ovishlit/cluster-flavors:vmaas` | VM provisioning (CNV + LVMS + AAP) |
| **caas** | `quay.io/rh-ee-ovishlit/cluster-flavors:caas` | Cluster provisioning (MCE + MetalLB + AAP) |

**Commands:**

```bash
make test-vmaas    # pytest tests/vmaas/
make test-caas     # pytest tests/caas/
make test-storage  # pytest tests/storage/
make test          # full suite
```

**Covers:**
- Full VMaaS lifecycle (create, restart, delete-during-provision, console, networking API)
- Full CaaS lifecycle (ClusterOrder, credentials, template immutability)
- Storage and catalog suites (when run explicitly)
- Real AAP job templates and execution environments

**Does not cover:**
- Netris-specific networking (separate periodic CI workflow)
- Multi-cluster management/workload separation (single-cluster mode in presubmit)

**Requirements:** Pull secret, AAP license, SSH access to baremetal server.

---

### T4 — Full OpenShift install (osac-installer)

**Workflow:** `osac-installer/scripts/setup.sh` with kustomize overlays (`vmaas-ci`, `caas-ci`, `osac-integration`)

**Covers:**
- Production-like installation via OLM subscriptions from `redhat-operators`
- Upgrade paths, installer script changes, overlay composition
- Full prerequisite chain (cert-manager, AAP operator, CNV, MCE, etc.)

**CI:** Periodic `e2e-vmaas-full-setup-helm` (bare metal, ~57 GB RAM SNO, full helm install every 4 hours).

---

## Change-type → minimum tier

| Change type | Minimum tier | Rationale |
|-------------|--------------|-----------|
| Pure Go logic (no API/proto/K8s) | **T0** | Unit tests sufficient |
| Proto/API/DB in fulfillment-service | **T0 + T1** | API contract and reconciler behavior |
| Controller reconcile logic (no new external deps) | **T0 + T2** | Needs operator + CR interaction |
| AAP playbook / job template (compute) | **T2** | AWX on kind runs real playbooks |
| AAP playbook (networking/storage) | **T3** | kind-dev uses no-op networking templates |
| New CRD type in osac-operator | **T0 + T1 + T2** | Plus cross-repo: fulfillment reconciler registration |
| CRD spec field used by AAP | **T2 or T3** | Depends on which playbook reads the field |
| ClusterOrder / HCP / licensed operator | **T3 or T4** | Not available on kind-dev |
| osac-installer overlay/submodule bump | **T3** | Match overlay: vmaas-ci or caas-ci |
| CLI flag change in fulfillment-service | **T1 + osac-test-infra** | Update `OsacCLI` helpers in test infra |
| UI-only change | **T0** (component tests) | Unless API contract changes |

---

## CI job mapping

| CI job | Tier | Trigger | Suite |
|--------|------|---------|-------|
| Per-repo unit/IT (Ginkgo) | T0–T1 | PR | `ginkgo run -r internal`, `ginkgo run it` |
| Prow presubmit `e2e-vmaas` | T3 | PR (intranet) | `pytest tests/vmaas/` on cluster-tool snapshot |
| Prow periodic `e2e-vmaas` | T3 | Hourly cron | Same as presubmit |
| Prow periodic `e2e-vmaas-full-setup-helm` | T4 | Every 4 hours | Full helm install on bare metal |
| Prow periodic `e2e-netris-caas` | T3–T4 | Every 6 hours | CaaS on Netris infrastructure |

**Gap:** caas, storage, and catalog pytest suites are not in presubmit — only vmaas runs on every PR.

---

## DNS and hostname differences

| Environment | DNS model | Setup |
|-------------|-----------|-------|
| T1 (fulfillment-service IT) | `/etc/hosts` → `127.0.0.1` | Manual entries required |
| T2 (kind-dev) | `*.localhost` via systemd-resolved | Automatic; CoreDNS rewrite inside cluster |
| T3 (cluster-tool) | dnsmasq on laptop + server HAProxy SNI | `cluster-tool setup client` |

This difference is a common source of confusion when moving between tiers.

---

## Cross-repo validation dependencies

When a change spans repos, tier validation alone is insufficient — companion changes are required. See `.planning/codebase/CONVENTIONS.md` cross-repo table:

| Change in | Also validate in |
|-----------|------------------|
| `fulfillment-service` proto | `osac-installer` image tags |
| `osac-aap` roles | `osac-installer` submodule refs |
| `osac-operator` CRD types | `fulfillment-service` reconciler registration |
| `osac-operator` CRD spec | `osac-aap` playbooks |
| `fulfillment-service` CLI flags | `osac-test-infra` test helpers |
| `osac-installer` submodule bumps | `scripts/sync-image-tags.sh --fix` |

Evidence: MGMT-24226 eval — agent fixed fulfillment-service and osac-aap but missed osac-installer CI overlays.

---

## Known documentation drift

The following existing docs are **stale** relative to current `kind-dev/setup.sh` behavior. This planning doc reflects audited reality; those files should be updated in a future pass (not part of this planning initiative):

| Document | Stale claim | Actual state (2026-07-07) |
|----------|-------------|---------------------------|
| `kind-dev/README.md` summary table | "OSAC Operator \| Runs, but no AAP backend" | AWX installed and configured by default |
| `kind-dev/README.md` summary table | "Fake CRDs (KubeVirt) \| Stubs only" | Real KubeVirt + CDI installed; fake CRDs removed |
| `kind-dev/README.md` | "Setup time: ~5–8 minutes" | Full default path is ~20–30+ min (AWX ~10–12 min) |
| `kind-dev/README.md` § AAP | "AAP: Stubbed Out" | AWX substitute proven for ComputeInstance lifecycle |
| `kind-dev/README.md` comparison table | "AAP \| Stubbed" | Should read "AWX substitute" |
| `kind-dev/README.md` Known Limitations | "ClusterOrder/ComputeInstance won't complete" | ComputeInstance *does* complete via AWX; ClusterOrder does not |
| `.planning/codebase/TESTING.md` | Labels `it/` as "E2E" | `it/` is T1 integration; pytest on cluster-tool is T3 E2E |

---

## Recommended PR labels (future)

| Label | Required tier | When to apply |
|-------|---------------|---------------|
| `validation-t0` | T0 only | Default for logic-only changes |
| `validation-t2` | T2 kind-dev | Operator, AAP compute playbook changes |
| `requires-e2e` | T3 cluster-tool | Provisioning, networking, storage changes |

These labels are proposed in [DEVELOPMENT-VELOCITY.md](DEVELOPMENT-VELOCITY.md) Phase B — not yet implemented.
