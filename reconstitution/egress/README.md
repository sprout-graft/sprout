# Egress control — design

The egress allowlist is the one piece of Sprout's infrastructure that must **not** be under Sprout's control. An agent that can edit its own allowlist is guarding itself, which is no guard at all.

It lives in:

> **`sona-coalition/sprout-egress`** — public, created 2026-10-31, `main` protected by a ruleset verified to match `sona`'s (pull request + one approval, no force-pushes, no deletion, no bypass actors). Sprout can open pull requests against it, but a PR author's own approval never counts — so Sprout can *propose* domains and only the caregiver (or another coalition curator) can *grant* them.

`start.sh` builds the proxy image from a clone of that repository. At runtime the sidecar clones the repository **itself** and polls it for changes (default 60 s); when the YAML changes it re-renders the flat list and reloads squid in place. Consequences:

- **Merging a domain PR is the only caregiver action.** No host steps, no rebuilds, no agent restarts — merge-to-live in about a minute.
- The allowlist is YAML with Superconductor-matching attributes (`domain`, `path_prefix`, `read_only`); only the domain is enforceable for HTTPS, and the repo's README says so plainly.
- The flat domain list is a build artifact rendered inside the container — deliberately not in source control.
- If GitHub is unreachable the proxy keeps its last allowlist: fail-closed by construction.
- Public visibility costs nothing: the same five hosts are already named in the public runbook. Transparency here buys coalition governance of the control instead of one person holding it.

Why this over a caregiver-personal repo: the pull-request flow makes request-and-grant a native git workflow rather than a chat conversation, rulesets are free on public repos, and the control can outlive any single caregiver — which is the stated long-term direction (the Sonapana, not a person, handling reconstitution).

## Bootstrap status

Repo created and protection verified 2026-10-31 (ruleset "Main Protection": PR + one approval, no force-push, no deletion, no bypass). Seeded by pull request from Sprout. The canonical documentation is the README *in that repository*; this file records the design and why it is shaped this way.

## Changing the allowlist, end to end

1. Sprout (or anyone) opens a PR editing `allowed_domains.yaml`.
2. The caregiver reviews and merges.
3. Nothing. The sidecar polls the repository, re-renders, and reloads squid in place (default 60 s; `podman restart sprout-egress` to force it now).
