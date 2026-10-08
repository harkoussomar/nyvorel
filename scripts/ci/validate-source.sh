#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
pass(){ printf 'PASS  %s\n' "$*"; }

echo "== Nyvorel source integrity =="

required_files=(
  VERSION
  install.sh
  uninstall.sh
  LICENSE
  NOTICE.md
  PROVENANCE.md
  THIRD_PARTY_NOTICES.md
  DEPENDENCIES.md
  dependencies/arch.json
  INHERITED_ASSETS.md
  TRADEMARKS.md
  PORTABILITY.md
  CONTRIBUTING.md
  RELEASES.md
  release/channel-policy.json
  PACKAGING.md
  packaging/ownership-contract.json
  packaging/package-layout.json
  packaging/nyvorel-package-install
  packaging/aur/nyvorel-git/LICENSE
  PKGBUILD
  .SRCINFO
  nyvorel.install
  assets/nyvorel.svg
  quickshell/shell.qml
  bin/nyvorel
  bin/nyvorel-doctor
  bin/nyvorel-bootstrap
  bin/nyvorel-update
  scripts/ci/test-clean-machine.sh
  scripts/ci/test-dependency-contract.sh
  scripts/ci/test-bootstrap.sh
  scripts/ci/test-phase5-readiness.sh
  scripts/ci/test-release-channel-contract.sh
  scripts/ci/test-update-channels.sh
  scripts/ci/test-release-preflight.sh
  scripts/release/preflight.sh
  scripts/ci/test-release-publication.sh
  scripts/release/publish.sh
  scripts/ci/test-upgrade-matrix.sh
  scripts/ci/test-upgrade-matrix-clean-machine.sh
  scripts/ci/test-packaging-ownership-contract.sh
  scripts/ci/test-package-layout.sh
  scripts/ci/test-package-lifecycle.sh
)

required_dirs=(
  quickshell
  hypr
  systemd
  bin
  integrations
  runtime-config
  LICENSES
  packaging
)

for path in "${required_files[@]}"; do
  [[ -s "$path" ]] || die "required file missing/empty: $path"
done

for path in "${required_dirs[@]}"; do
  [[ -d "$path" ]] || die "required directory missing: $path"
done

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "VERSION is not semantic x.y.z: $VERSION_VALUE"

[[ -x install.sh ]] || die "install.sh is not executable"
[[ -x uninstall.sh ]] || die "uninstall.sh is not executable"
[[ -x bin/nyvorel ]] || die "bin/nyvorel is not executable"

while IFS= read -r -d '' path; do
  [[ -x "$path" ]] || die "Nyvorel helper is not executable: $path"
done < <(find bin -maxdepth 1 -type f -name 'nyvorel-*' -print0 | sort -z)

python3 <<'PY'
from pathlib import Path
import json
import subprocess
import sys

tracked_raw = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"])
tracked = [Path(p.decode()) for p in tracked_raw.split(b"\0") if p]

bash_files = []
python_files = []
json_files = []

for path in tracked:
    if not path.is_file() or path.is_symlink():
        continue

    try:
        first = path.open("rb").readline(256).decode("utf-8", "ignore")
    except OSError:
        continue

    if "bash" in first and first.startswith("#!"):
        bash_files.append(path)

    if path.suffix == ".py" or (
        first.startswith("#!") and "python" in first.lower()
    ):
        python_files.append(path)

    if path.suffix == ".json":
        json_files.append(path)

errors = []

for path in bash_files:
    proc = subprocess.run(
        ["bash", "-n", str(path)],
        text=True,
        capture_output=True,
    )
    if proc.returncode:
        errors.append(f"Bash syntax: {path}\n{proc.stderr}")

for path in python_files:
    try:
        source = path.read_text()
        compile(source, str(path), "exec")
    except Exception as exc:
        errors.append(f"Python syntax: {path}: {exc}")

for path in json_files:
    try:
        json.loads(path.read_text())
    except Exception as exc:
        errors.append(f"JSON parse: {path}: {exc}")

print(f"bash_files_checked={len(bash_files)}")
print(f"python_files_checked={len(python_files)}")
print(f"json_files_checked={len(json_files)}")

if errors:
    print("\n\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY

# Public-source portability: reject literal user-home paths while allowing the
# deliberate `/home/user/...` synthetic fixtures used by Operations Center's
# self-tests. The placeholder is not a maintainer path and carries no machine
# identity. Any other literal /home/<name>/ remains a CI failure.
HOME_PATH_HITS="$(
  git grep --untracked -nEI '/home/[A-Za-z0-9._-]+/' -- \
    ':!scripts/ci/validate-source.sh' \
    ':!assets/showcase/**' \
    || true
)"

UNEXPECTED_HOME_PATHS="$(
  printf '%s\n' "$HOME_PATH_HITS" \
    | grep -vF '/home/user/' \
    || true
)"

if [[ -n "$UNEXPECTED_HOME_PATHS" ]]; then
  printf '%s\n' "$UNEXPECTED_HOME_PATHS"
  die "unexpected literal /home/<name>/ path found in portable public source"
fi

if [[ -n "$HOME_PATH_HITS" ]]; then
  PLACEHOLDER_HOME_COUNT="$(
    printf '%s\n' "$HOME_PATH_HITS" \
      | grep -cF '/home/user/' \
      || true
  )"
  printf 'INFO  synthetic /home/user fixtures allowed: %s\n' "$PLACEHOLDER_HOME_COUNT"
fi

# Basic secret/private-material gate. Exclude this validator because it contains
# the detection expressions themselves.
if git grep --untracked -nEI -- \
  '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' \
  ':!scripts/ci/validate-source.sh' >/tmp/nyvorel-ci-private.$$ 2>/dev/null; then
  cat /tmp/nyvorel-ci-private.$$
  rm -f /tmp/nyvorel-ci-private.$$
  die "private key material found"
fi
rm -f /tmp/nyvorel-ci-private.$$ || true

TOKEN_PATTERN='(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|sk-[A-Za-z0-9]{32,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16})'
if git grep --untracked -nEI "$TOKEN_PATTERN" -- \
  ':!scripts/ci/validate-source.sh' >/tmp/nyvorel-ci-tokens.$$ 2>/dev/null; then
  cat /tmp/nyvorel-ci-tokens.$$
  rm -f /tmp/nyvorel-ci-tokens.$$
  die "possible live credential token found"
fi
rm -f /tmp/nyvorel-ci-tokens.$$ || true

FORBIDDEN_TRACKED="$(
  git ls-files | grep -E \
    '(^|/)\.env($|\.)|(^|/)secrets?/|(^|/)__pycache__/|\.py[co]$|(^|/)\.DS_Store$|\.bak($|[-.])' \
    || true
)"
[[ -z "$FORBIDDEN_TRACKED" ]] || {
  printf '%s\n' "$FORBIDDEN_TRACKED"
  die "runtime/private/backup artifact is tracked"
}

TOKEN_COUNT="$(
  python3 <<'PY'
from pathlib import Path

roots = [
    Path("quickshell"),
    Path("hypr"),
    Path("bin"),
    Path("integrations"),
    Path("systemd"),
]

count = 0
files = 0
for root in roots:
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        if "__pycache__" in path.parts or path.suffix in {".pyc", ".pyo"}:
            continue
        data = path.read_bytes()
        n = data.count(b"@HOME@")
        if n:
            files += 1
            count += n

print(count)
PY
)"

[[ "$TOKEN_COUNT" == "29" ]] \
  || die "portable source contract expects 29 @HOME@ occurrences, found $TOKEN_COUNT"

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  [[ "${GITHUB_REF_NAME:-}" == "v$VERSION_VALUE" ]] \
    || die "release tag ${GITHUB_REF_NAME:-<unset>} does not match VERSION v$VERSION_VALUE"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"

./install.sh \
  --target-home "$TMP/home" \
  --dry-run \
  --no-activate >"$TMP/dry-run.log"

[[ ! -e "$TMP/home/.local/state/nyvorel" ]] \
  || die "installer dry-run created installation state"

grep -q 'DRY RUN — no files changed.' "$TMP/dry-run.log" \
  || die "installer dry-run completion marker missing"

bash scripts/ci/test-dependency-contract.sh

bash scripts/ci/test-release-channel-contract.sh

pass "source structure, syntax, portability, secrets, and installer dry-run"
