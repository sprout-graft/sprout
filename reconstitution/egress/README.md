# Egress control — design

The egress allowlist is the one piece of Sprout's infrastructure that must **not** be under Sprout's control. An agent that can edit its own allowlist is guarding itself, which is no guard at all.

Therefore the proxy image and its `squid.conf` live in the caregiver's repository:

> **`ianksalter/sprout-egress`** — Sprout has *read-only* access. `start.sh` builds the proxy from a clone of that repository (path in `SPROUT_EGRESS`, default `~/sprout-egress`) and refuses to run without it. There is deliberately no fallback copy of the config here: a fallback I could edit would defeat the point.

## Why this design

- **Enforcement, not politeness.** The agent container runs on an `internal: true` network with no route out; the proxy is its only path to the internet. Domain-based filtering needs an HTTP-aware proxy, not firewall rules, because CDN addresses rotate.
- **Simple provenance.** The proxy image is `debian:trixie-slim` plus the distribution's `squid` package — no third-party images to audit.
- **Change control by role.** New domains are granted by the caregiver editing *their* repository; Sprout can request but cannot grant. This is the same trust split as secrets (§3 of the runbook) and for the same reason.

## Bootstrap content for `ianksalter/sprout-egress`

Two files. `Containerfile`:

```dockerfile
FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends squid \
 && rm -rf /var/lib/apt/lists/*
COPY squid.conf /etc/squid/squid.conf
EXPOSE 3128
CMD ["squid", "-N", "-d", "1"]
```

`squid.conf` (the initial allowlist — the five destinations Sprout needs at runtime):

```
http_port 3128

acl SSL_ports port 443
acl CONNECT method CONNECT
acl allowed_sites dstdomain github.com api.github.com api.openrouter.ai api.telegram.org mcp.openmail.sh

http_access deny CONNECT !SSL_ports
http_access allow allowed_sites
http_access deny all

cache deny all
access_log none
```

Adding a domain later: append it to the `allowed_sites` line, commit, restart the sidecar (`podman rm -f sprout-egress` and re-run `start.sh`).
