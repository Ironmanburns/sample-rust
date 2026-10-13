#!/usr/bin/env bash
# Conventional-commits → next semver tag (and optional version-file bump).
# Harness CI Run step on push to main. Does NOT deploy (tag-only CD elsewhere).
#
# Env:
#   GITHUB_TOKEN              required (push tag / optional GitHub Release)
#   GITHUB_REPOSITORY         owner/repo (optional; inferred from origin)
#   RELEASE_BRANCH            default main
#   CREATE_GITHUB_RELEASE     true|false (default true)
#   DRY_RUN                   true|false
#   VERSION_FILE              optional explicit path to bump
#   GIT_USER_NAME / GIT_USER_EMAIL
set -euo pipefail

RELEASE_BRANCH="${RELEASE_BRANCH:-main}"
CREATE_GITHUB_RELEASE="${CREATE_GITHUB_RELEASE:-true}"
DRY_RUN="${DRY_RUN:-false}"
GIT_USER_NAME="${GIT_USER_NAME:-harness-release[bot]}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-harness-release[bot]@users.noreply.github.com}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required" >&2
  exit 1
fi

git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

# Best-effort fetch (Harness workspace is already cloned; local dry-runs may have no creds).
git fetch --tags --force origin "$RELEASE_BRANCH" 2>/dev/null || git fetch --tags --force origin 2>/dev/null || true
if git show-ref --verify --quiet "refs/remotes/origin/$RELEASE_BRANCH"; then
  git checkout -B "$RELEASE_BRANCH" "origin/$RELEASE_BRANCH"
else
  git checkout "$RELEASE_BRANCH" 2>/dev/null || git checkout -b "$RELEASE_BRANCH"
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "$RELEASE_BRANCH" ]]; then
  echo "Refusing release on branch '$BRANCH' (want $RELEASE_BRANCH)" >&2
  exit 1
fi

TIP="$(git rev-parse HEAD)"
if git describe --exact-match --tags "$TIP" >/dev/null 2>&1; then
  echo "HEAD already tagged ($(git describe --exact-match --tags "$TIP")); nothing to do."
  exit 0
fi

LAST_TAG="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
if [[ -z "$LAST_TAG" ]]; then
  RANGE=()
  MAJOR=0
  MINOR=1
  PATCH=0
  echo "No prior v* tag; initial candidate v0.1.0"
else
  RANGE=("${LAST_TAG}..HEAD")
  ver="${LAST_TAG#v}"
  IFS=. read -r MAJOR MINOR PATCH <<<"$ver"
  echo "Last tag: $LAST_TAG"
fi

mapfile -t SUBJECTS < <(git log "${RANGE[@]}" --pretty=%s 2>/dev/null || true)
if [[ ${#SUBJECTS[@]} -eq 0 && -n "$LAST_TAG" ]]; then
  echo "No commits since $LAST_TAG; skipping release."
  exit 0
fi

BUMP=""
for subject in "${SUBJECTS[@]:-}"; do
  [[ -z "$subject" ]] && continue
  # Breaking: footer text or type!: / type(scope)!:
  if [[ "$subject" == *"BREAKING CHANGE"* ]] || [[ "$subject" == *\!:* ]]; then
    BUMP=major
    break
  fi
  case "$subject" in
    feat:*|feat\(*\):*)
      [[ "$BUMP" != major ]] && BUMP=minor
      ;;
    fix:*|fix\(*\):*|perf:*|perf\(*\):*)
      [[ -z "$BUMP" ]] && BUMP=patch
      ;;
  esac
done

if [[ -z "$BUMP" ]]; then
  if [[ -z "$LAST_TAG" ]]; then
    BUMP=minor
    echo "No conventional feat/fix yet; cutting initial v0.1.0"
  else
    echo "No releasable conventional commits since $LAST_TAG; skipping."
    exit 0
  fi
fi

# No prior tag: keep the initial candidate (v0.1.0). Otherwise apply the bump.
if [[ -n "$LAST_TAG" ]]; then
  case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac
fi

VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${VERSION}"
echo "Next release: $TAG (bump=$BUMP)"

bump_version_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  case "$file" in
    package.json)
      if command -v node >/dev/null; then
        VERSION="$VERSION" FILE="$file" node -e '
          const fs=require("fs");
          const p=JSON.parse(fs.readFileSync(process.env.FILE,"utf8"));
          p.version=process.env.VERSION;
          fs.writeFileSync(process.env.FILE, JSON.stringify(p,null,2)+"\n");
        '
      else
        sed -i -E "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]+\"/\"version\": \"$VERSION\"/" "$file"
      fi
      ;;
    pyproject.toml)
      sed -i -E "s/^version[[:space:]]*=[[:space:]]*\"[^\"]+\"/version = \"$VERSION\"/" "$file"
      ;;
    pom.xml)
      awk -v ver="$VERSION" '
        /<artifactId>/ { a=1 }
        a && /<version>/ && !done {
          sub(/<version>[^<]+<\/version>/, "<version>" ver "</version>");
          done=1
        }
        { print }
      ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
      ;;
    Cargo.toml)
      sed -i -E "0,/^version[[:space:]]*=/{s/^version[[:space:]]*=[[:space:]]*\"[^\"]+\"/version = \"$VERSION\"/}" "$file"
      ;;
    *.csproj|Directory.Build.props)
      sed -i -E "s#<Version>[^<]+</Version>#<Version>$VERSION</Version>#" "$file"
      ;;
    build.gradle.kts|build.gradle)
      sed -i -E "s/^version[[:space:]]*=[[:space:]]*\".*\"/version = \"$VERSION\"/" "$file"
      ;;
    *)
      echo "Unknown VERSION_FILE type: $file (tag only)" >&2
      return 0
      ;;
  esac
  git add "$file"
}

if [[ -n "${VERSION_FILE:-}" ]]; then
  bump_version_file "$VERSION_FILE"
elif [[ -f package.json ]]; then
  bump_version_file package.json
elif [[ -f pyproject.toml ]]; then
  bump_version_file pyproject.toml
elif [[ -f pom.xml ]]; then
  bump_version_file pom.xml
elif [[ -f Cargo.toml ]]; then
  bump_version_file Cargo.toml
elif [[ -f build.gradle.kts ]]; then
  bump_version_file build.gradle.kts
fi

NOTES="$(git log "${RANGE[@]}" --pretty='- %s (%h)' 2>/dev/null || true)"

if ! git diff --cached --quiet; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY_RUN: would commit version bump for $VERSION"
    git reset HEAD
  else
    git commit -m "chore(release): ${VERSION}"
  fi
fi

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
OWNER_REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$OWNER_REPO" && -n "$REMOTE_URL" ]]; then
  OWNER_REPO="$(echo "$REMOTE_URL" | sed -E 's#(git@github.com:|https://([^@]+@)?github.com/)##; s#\.git$##')"
fi
OWNER_REPO="${OWNER_REPO:-unknown/unknown}"
PUSH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER_REPO}.git"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY_RUN: would tag $TAG and push to $OWNER_REPO"
  printf '%s\n' "$NOTES"
  exit 0
fi

git tag -a "$TAG" -m "Release $TAG"

# Only push the branch when we have a version-bump commit; tag push is required.
if ! git push "$PUSH_URL" "HEAD:${RELEASE_BRANCH}"; then
  echo "WARN: branch push failed (branch protection?). Continuing with tag push." >&2
fi
if ! git push "$PUSH_URL" "$TAG"; then
  echo "ERROR: tag push failed — ensure the release GitHub App can write contents/tags on ${OWNER_REPO}" >&2
  exit 1
fi

if [[ "$CREATE_GITHUB_RELEASE" == "true" ]]; then
  # Prefer curl (always present after apk); never fail the release if GH Release API errs.
  body_file="$(mktemp)"
  notes_file="$(mktemp)"
  printf '%s' "$NOTES" >"$notes_file"
  if command -v python3 >/dev/null 2>&1; then
    NOTES_FILE="$notes_file" TAG="$TAG" python3 - <<'PY' >"$body_file"
import json, os
print(json.dumps({
    "tag_name": os.environ["TAG"],
    "name": os.environ["TAG"],
    "body": open(os.environ["NOTES_FILE"], encoding="utf-8").read(),
    "generate_release_notes": False,
}))
PY
  else
    # Minimal JSON escape for body
    body_escaped=$(sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' "$notes_file" | tr -d '\n' | sed 's/\\n$//')
    printf '{"tag_name":"%s","name":"%s","body":"%s","generate_release_notes":false}\n' \
      "$TAG" "$TAG" "$body_escaped" >"$body_file"
  fi
  code=$(curl -sS -o /tmp/gh-release-out -w '%{http_code}' \
    -X POST "https://api.github.com/repos/${OWNER_REPO}/releases" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    --data @"$body_file" || true)
  echo "GitHub Release HTTP $code"
  rm -f "$body_file" "$notes_file"
fi

echo "Released $TAG"
