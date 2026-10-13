# Sample app contract

Platform master copy: `platform/sample-apps/STANDARD.md` in **local-platform-demo**.

## Runtime

- `PORT` default `8080`; `GET /healthz`; `GET /version` → `{"version","service":"sample-rust"}`
- Non-root container

## Delivery

- Harness **release** on push to `main` → annotated `v*` tag (`scripts/harness-semver-release.sh`)
- Harness **stable deploy** on tag `v*` only (`harness/pipeline-deploy-tag.yaml`)
- PR preview + teardown pipelines
- No release-please; no stable deploy from bare `main`
