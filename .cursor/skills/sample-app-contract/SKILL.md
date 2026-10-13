---
name: sample-app-contract
description: Keep health endpoints, Dockerfile, Helm, and Harness release/tag deploy intact.
---

# Sample app contract

Before finishing a change, verify:

- `GET /healthz` and `GET /version` still work
- Dockerfile still multi-stage / non-root
- Helm probes still hit `/healthz`
- `harness/pipeline-release-main.yaml` still documents push-to-main → tag only
- `harness/pipeline-deploy-tag.yaml` still guards / triggers on **tags only**
- `scripts/harness-semver-release.sh` remains present
- No credentials added to the tree
