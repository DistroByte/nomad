---
title: Architecture Decision Records
tags: [docs]
---

# Architecture Decision Records

Decisions that shape this homelab, in [Michael Nygard's
format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
as implemented by [adr-tools](https://github.com/npryce/adr-tools).

Accepted records are immutable. Changing course means a new record that supersedes
the old one; the old text stays and gains a link in both directions. The value is
the trail, not the current state - `docs/DNS.md` and the rest of `docs/` describe
how things are now, these describe why.

One decision per record, numbered sequentially, numbers never reused.

| # | Title | Date | Status |
|---|---|---|---|
| [1](0001-resolve-homelab-host-names-with-split-horizon-internal-dns.md) | Resolve homelab host names with split-horizon .internal DNS | 2026-09-18 | Accepted |
