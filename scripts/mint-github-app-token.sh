#!/usr/bin/env bash
# Mint a short-lived GitHub App installation token (ghs_...) for release tagging.
#
# Env (required):
#   GITHUB_APP_ID                 numeric App ID
#   GITHUB_APP_PRIVATE_KEY        PEM private key (literal newlines or \n-escaped)
# Env (optional):
#   GITHUB_APP_INSTALLATION_ID    numeric installation id (looked up if unset)
#   GITHUB_APP_OWNER              account login to pick when looking up (default: Ironmanburns)
#
# Prints the token to stdout. Errors go to stderr.
set -euo pipefail

: "${GITHUB_APP_ID:?GITHUB_APP_ID is required}"
: "${GITHUB_APP_PRIVATE_KEY:?GITHUB_APP_PRIVATE_KEY is required}"

export GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-}"
export GITHUB_APP_OWNER="${GITHUB_APP_OWNER:-Ironmanburns}"
export GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

# Normalize PEM for Python (secrets often store literal \n).
export GITHUB_APP_PRIVATE_KEY="$(printf '%s' "$GITHUB_APP_PRIVATE_KEY" | sed 's/\\n/\n/g')"

if ! printf '%s' "$GITHUB_APP_PRIVATE_KEY" | grep -q 'BEGIN.*PRIVATE KEY'; then
  echo "GITHUB_APP_PRIVATE_KEY does not look like a PEM private key" >&2
  exit 1
fi

python3 - <<'PY'
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

app_id = os.environ["GITHUB_APP_ID"].strip()
pem = os.environ["GITHUB_APP_PRIVATE_KEY"]
installation_id = os.environ.get("GITHUB_APP_INSTALLATION_ID", "").strip()
owner = os.environ.get("GITHUB_APP_OWNER", "Ironmanburns").strip()
api = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_jwt() -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(
        json.dumps({"iat": now - 60, "exp": now + 540, "iss": app_id}, separators=(",", ":")).encode()
    )
    unsigned = f"{header}.{payload}".encode()
    with tempfile.NamedTemporaryFile("w", delete=False) as kf:
        kf.write(pem if pem.endswith("\n") else pem + "\n")
        key_path = kf.name
    try:
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=unsigned,
            capture_output=True,
            check=True,
        )
    finally:
        os.unlink(key_path)
    return f"{header}.{payload}.{b64url(proc.stdout)}"


def api_call(method: str, path: str, body=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {
        "Authorization": f"Bearer {jwt}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "harness-sample-apps-release",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{api}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        err = e.read().decode()[:500]
        raise SystemExit(f"GitHub API {method} {path} failed: {e.code} {err}") from e


jwt = make_jwt()

if not installation_id:
    installs = api_call("GET", "/app/installations") or []
    for inst in installs:
        acct = (inst.get("account") or {}).get("login") or ""
        if acct.lower() == owner.lower():
            installation_id = str(inst["id"])
            break
    if not installation_id and len(installs) == 1:
        installation_id = str(installs[0]["id"])
    if not installation_id:
        logins = [((i.get("account") or {}).get("login") or "?") for i in installs]
        raise SystemExit(
            f"Could not resolve installation id for owner={owner}; found installs={logins}"
        )

token_resp = api_call(
    "POST",
    f"/app/installations/{installation_id}/access_tokens",
    {"permissions": {"contents": "write", "metadata": "read"}},
)
token = (token_resp or {}).get("token")
if not token:
    raise SystemExit(f"No token in installation access_tokens response: {token_resp!r}"[:400])

sys.stdout.write(token)
PY
