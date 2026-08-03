# Adjacent Enhancement Proposal Check

Before a PRD or design document locks in In Scope/Out of Scope content for
a specific resource or data element, check whether an existing or
in-flight Enhancement Proposal on the same resource already covers part
of that scope through a different mechanism. Skipping this check let
[OSAC-3254](https://redhat.atlassian.net/browse/OSAC-3254)'s draft PRD
propose exposing `BareMetalInstance` IP address via the inventory backend
when `OSAC-1437-bmaas-networking`'s already-accepted PRD had committed to
exposing it via a completely different mechanism (network-attachment
status, DHCP-lease discovery) — see OSAC-3573 for the full incident.

## When to run this check

Run it during `/prd:ingest`'s Initial Observations, or during
`/prd:clarify`'s gap analysis (Scope category) if it wasn't caught at
ingest — whichever surfaces it first. Trigger the check when the source
Jira issue's In Scope or Definition of Done names a specific resource or
data element that is:

- A shared, cross-service resource (e.g., `BareMetalInstance`,
  `ComputeInstance`, `VirtualNetwork`) rather than something obviously new
  and single-purpose, and
- Not already ruled out by a linked issue or design doc the ticket itself
  points to.

Skip the check for features that only introduce a new, clearly
independent resource — there's nothing adjacent to search for.

**Networking data specifically:** IP address, MAC address, DHCP, or
network-attachment status for any provisioned resource is very likely
already covered by `.design/context/networking-decisions.md`'s
DHCP-based IP assignment decision — read that file first before
searching further; it names the specific EPs (OSAC-1433, OSAC-1435,
OSAC-1436, OSAC-1437, dns-api) most likely to already own this data.

## How to run it

```bash
grep -rl -i "<resource name>" enhancement-proposals/enhancements/*/{prd,design}.md
```

Read any hits' relevant sections (Goals, In Scope, Functional
Requirements) for overlap with the specific data element or capability in
question — a resource name appearing in another EP does not by itself
mean a conflict; read enough to tell whether the two features would write
or expose the same information.

## What to do with a hit

Surface it as a `/clarify` question rather than silently assuming the new
PRD should include or exclude the overlapping content:

- Does the existing EP already deliver this data/capability, wholly or
  partially?
- Through what mechanism, and does it conflict with (a second source for
  the same information) or complement (a genuine prerequisite/dependency)
  the new feature?

Record the resolution as a Locked Decision in `02-clarifications.md`, and
cite the adjacent EP by its Jira/EP identifier in the PRD's Out of Scope
(if excluding overlapping content) or Dependencies (if the new feature
builds on the adjacent EP) section.

## Design doc equivalent

`/design:ingest` should run the same check — a design document is even
more likely to duplicate CRD fields, controller phases, or reconcile
logic that an adjacent EP's design already specifies.
