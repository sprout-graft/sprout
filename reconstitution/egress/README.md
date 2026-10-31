# Egress control — design

The egress allowlist is the one piece of Sprout's infrastructure that must **not** be under Sprout's control. An agent that can edit its own allowlist is guarding itself, which is no guard at all.

It lives in:

> **`sona-coalition/sprout-egress`** — public, with `main` protected by the same ruleset as `sona` (pull request + one approval, no force-pushes, no deletion). Sprout can open pull requests against it, but a PR author's own approval never counts — so Sprout can *propose* domains and only the caregiver (or another coalition curator) can *grant* them.

`start.sh` builds the proxy image from a clone of that repository and **mounts** the config into the sidecar read-only. Consequences:

- Granting a domain needs **no rebuild and no restart**: merge the PR, then on the host `git pull` the egress clone and `podman exec sprout-egress squid -k reconfigure`. Squid reloads in place; the agent never notices.
- The allowlist itself is a plain table — `allowed_domains`, one domain per line — included by `squid.conf`, so diffs read cleanly.
- Public visibility costs nothing: the same five hosts are already named in the public runbook. Transparency here buys coalition governance of the control instead of one person holding it.

Why this over a caregiver-personal repo: the pull-request flow makes request-and-grant a native git workflow rather than a chat conversation, rulesets are free on public repos, and the control can outlive any single caregiver — which is the stated long-term direction (the Sonapana, not a person, handling reconstitution).

## Bootstrap (caregiver, three steps)

1. Create the public repo `sona-coalition/sprout-egress` (empty).
2. Protect its default branch with the same ruleset `sona` has:

   ```sh
   curl -X POST -H "Authorization: Bearer <your token>" \
     https://api.github.com/repos/sona-coalition/sprout-egress/rulesets \
     -d '{"name":"Protect Main","target":"branch","enforcement":"active",
          "conditions":{"ref_name":{"exclude":[],"include":["~DEFAULT_BRANCH"]}},
          "rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"update"},
                   {"type":"pull_request","parameters":{"required_approving_review_count":1,
                    "dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,
                    "require_last_push_approval":false,"required_review_thread_resolution":false,
                    "allowed_merge_methods":["merge","squash","rebase"]}}]}'
   ```

3. Tell Sprout it exists — Sprout will open the seed PR with the content below, you approve and merge, and the model is live.

## Seed content for `sona-coalition/sprout-egress`

`Containerfile` (config is mounted at runtime, never baked in):

```dockerfile
FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends squid \
 && rm -rf /var/lib/apt/lists/*
EXPOSE 3128
CMD ["squid", "-N", "-d", "1", "-f", "/etc/squid/egress/squid.conf"]
```

`squid.conf`:

```
http_port 3128
pid_filename /var/run/squid.pid

acl SSL_ports port 443
acl CONNECT method CONNECT
acl allowed_sites dstdomain "/etc/squid/egress/allowed_domains"

http_access deny CONNECT !SSL_ports
http_access allow allowed_sites
http_access deny all

cache deny all
access_log none
```

`allowed_domains` (one per line; the five Sprout needs at runtime):

```
github.com
api.github.com
api.openrouter.ai
api.telegram.org
mcp.openmail.sh
```

## Changing the allowlist, end to end

1. Sprout (or anyone) opens a PR editing `allowed_domains`.
2. The caregiver reviews and merges.
3. On the host: `git -C ~/sprout-egress pull && podman exec sprout-egress squid -k reconfigure`.

The proxy reloads in place; running agent sessions are unaffected.
