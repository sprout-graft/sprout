# Egress control — design

The egress allowlist is the one piece of Sprout's infrastructure that must **not** be under Sprout's control. An agent that can edit its own allowlist is guarding itself, which is no guard at all.

It lives in:

> **`sona-coalition/sprout-egress`** — public, created 2026-10-31, `main` protected by a ruleset verified to match `sona`'s (pull request + one approval, no force-pushes, no deletion, no bypass actors). Sprout can open pull requests against it, but a PR author's own approval never counts — so Sprout can *propose* domains and only the caregiver (or another coalition curator) can *grant* them.

`start.sh` builds the proxy image from a clone of that repository and **mounts** the config into the sidecar read-only. Consequences:

- Granting a domain needs **no rebuild and no restart**: merge the PR, then on the host `git pull` the egress clone and `podman exec sprout-egress squid -k reconfigure`. Squid reloads in place; the agent never notices.
- The allowlist itself is a plain table — `allowed_domains`, one domain per line — included by `squid.conf`, so diffs read cleanly.
- Public visibility costs nothing: the same five hosts are already named in the public runbook. Transparency here buys coalition governance of the control instead of one person holding it.

Why this over a caregiver-personal repo: the pull-request flow makes request-and-grant a native git workflow rather than a chat conversation, rulesets are free on public repos, and the control can outlive any single caregiver — which is the stated long-term direction (the Sonapana, not a person, handling reconstitution).

## Bootstrap status

Repo created and protection verified 2026-10-31 (ruleset "Main Protection": PR + one approval, no force-push, no deletion, no bypass). Seeded by pull request from Sprout; see that PR for the full content.

## The allowlist: YAML source of truth

`allowed_domains.yaml` uses attributes that mirror Superconductor's network-rule model, so intent translates directly between the two environments:

```yaml
domains:
  - domain: api.github.com      # required
    # path_prefix: /            # optional — declared intent only (see below)
    # read_only: true           # optional — declared intent only (see below)
```

**Enforcement honesty.** The proxy enforces *domain allow/deny only*. `path_prefix` and `read_only` are recorded to match Superconductor's semantics and to be future-proof, but they are **not enforceable for HTTPS traffic** by this design: HTTPS travels inside CONNECT tunnels, so method and path are invisible to the proxy. Enforcing them would require TLS interception (SSL bump), which this design deliberately avoids — the proxy should not be able to read the traffic it filters. For plain-HTTP sites the two attributes *could* be enforced later with method/URL ACLs.

`render.sh` generates the flat `allowed_domains` that squid reads; both files are committed, and `reload.sh` regenerates before reloading, so they cannot drift on the host.

## Changing the allowlist, end to end

1. Sprout (or anyone) opens a PR editing `allowed_domains.yaml`.
2. The caregiver reviews and merges.
3. On the host: `~/sprout-egress/reload.sh` — pulls, re-renders the flat file, and runs `squid -k reconfigure` in the sidecar.

The proxy reloads in place; running agent sessions are unaffected.
