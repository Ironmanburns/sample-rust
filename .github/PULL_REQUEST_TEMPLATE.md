## Summary

<!-- What changed and why (1–3 sentences). -->

## Conventional Commit title

PR title **must** be the release signal for Harness semver on `main`, e.g.:

- `feat: add readiness detail to /healthz`
- `fix: correct version JSON field`
- `docs: clarify local run steps`

Breaking: `feat!: ...` or footer `BREAKING CHANGE: ...`

## Checklist

- [ ] Does not push to `main` directly (branch + PR only)
- [ ] `/healthz` and `/version` still work
- [ ] No secrets or credentials in the diff
- [ ] Chart / Dockerfile updated if runtime changed
- [ ] I understand: merge → Harness **release tag**; stable deploy is **tag-only** (`v*`)

## Test plan

<!-- How you verified locally or via PR preview. -->
