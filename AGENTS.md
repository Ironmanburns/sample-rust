# Agent instructions — sample-rust

You are helping on a **public sample** app for the local platform demo fleet.

## Hard rules

1. **Never push to `main`.** Create a feature branch, commit, open a PR.
2. **PR title** must be a [Conventional Commit](https://www.conventionalcommits.org/) subject (`feat:`, `fix:`, `docs:`, `chore:`, …).
3. **Stable production deploys are tag-only** (`v*`). Merging to `main` does not deploy; Harness release pipeline cuts the tag that the deploy pipeline consumes.
4. **No secrets** in the repo.
5. Keep the [sample app contract](STANDARD.md): `/healthz`, `/version`, Dockerfile, Helm, Harness YAML, `scripts/harness-semver-release.sh`.

## Preferred workflow

```text
git checkout main && git pull
git checkout -b feat/<short-name>
# edit, test locally / docker build
git commit -m "feat: ..."
git push -u origin HEAD
# open PR; wait for checks; do not self-merge unless policy says so
```

## Skills

- `.cursor/skills/conventional-commits/SKILL.md`
- `.cursor/skills/pr-workflow/SKILL.md`
- `.cursor/skills/sample-app-contract/SKILL.md`

## Stack

Language template: **rust**. Image repo on Zot: `sample-rust`.
Stable URL (kind): `https://rust-sample.burnsy.me` (when tunnel/DNS wired).
