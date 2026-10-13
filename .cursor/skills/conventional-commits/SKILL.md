---
name: conventional-commits
description: Write Conventional Commit PR titles for Harness semver release.
---

# Conventional Commits

Harness `scripts/harness-semver-release.sh` reads subjects since the last `v*` tag:

| Commit | Bump |
|--------|------|
| `feat:` / `feat(scope):` | minor |
| `fix:` / `perf:` | patch |
| `type!:` or `BREAKING CHANGE` | major |
| `docs:` / `chore:` / `ci:` / … | no release |

When squash-merging, the **PR title** is the release signal:

```text
feat: expose build sha on /version
```
