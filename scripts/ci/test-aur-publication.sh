#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${NYVOREL_PUBLISH_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
AUR="${NYVOREL_AUR_CANDIDATE:-$ROOT/packaging/aur/nyvorel-git}"
CONTRACT="${NYVOREL_AUR_PUBLICATION_CONTRACT:-$ROOT/packaging/aur-publication-contract.json}"
EXPORTER="${NYVOREL_AUR_EXPORTER:-$ROOT/packaging/aur/export-nyvorel-git.sh}"
MODE="${1:---full}"
[[ "$MODE" == --static-only || "$MODE" == --full ]] || { echo 'ERROR: choose --static-only or --full' >&2; exit 2; }
command -v python3 >/dev/null && command -v git >/dev/null || { echo 'ERROR: missing python3 or git' >&2; exit 1; }

python3 - "$ROOT" "$AUR" "$CONTRACT" "$EXPORTER" <<'PYAUDIT'
from pathlib import Path
import json,sys,re
root,aur,contract_path,exporter=map(Path,sys.argv[1:])
c=json.loads(contract_path.read_text())
p=(aur/'PKGBUILD').read_text()
src=(aur/'.SRCINFO').read_text()
hook=(aur/'nyvorel.install').read_text()
deps=json.loads((root/'dependencies/arch.json').read_text())
assert c['phase']=='7D' and c['status']=='aur-submission-preflight-human-review-pending'
assert c['aur_remote_writes_permitted'] is False
assert c['aur_credentials_used'] is False
assert c['aur_repository_created'] is False
assert c['stable_release_created'] is False
assert c['release_tag_changes_permitted'] is False
assert c['explicit_separate_publication_approval_required'] is True
assert c['aur_package_files']==['PKGBUILD','.SRCINFO','nyvorel.install']
assert exporter.is_file()
assert 'pkgname=nyvorel-git\n' in p
assert 'source=(\'nyvorel::git+https://github.com/harkoussomar/nyvorel.git#branch=main\')' in p
assert "sha256sums=('SKIP')" in p
assert 'makedepends=(\'git\')' in p
assert 'conflicts=(\'nyvorel\')' in p
assert 'provides=("nyvorel=${pkgver}")' in p
assert 'pkgver() {' in p
assert 'replaces=(' not in p
assert '.local/state/nyvorel' not in hook
assert re.search(r'^\s*(systemctl|install|cp|rm|mv|chown|chmod)\s',hook,re.M) is None
assert (aur/'nyvorel.install').read_bytes()==(root/'nyvorel.install').read_bytes()
assert not any(x in p for x in ('ssh://aur@','aur.archlinux.org','git push'))

def parse_srcinfo(text):
    out={}
    for line in text.splitlines():
        line=line.strip()
        if ' = ' in line:
            k,v=line.split(' = ',1)
            out.setdefault(k,[]).append(v)
    return out

metadata=parse_srcinfo(src)
assert metadata['pkgbase']==['nyvorel-git']
assert metadata['pkgname']==['nyvorel-git']
assert metadata['install']==['nyvorel.install']
assert metadata['source']==['nyvorel::git+https://github.com/harkoussomar/nyvorel.git#branch=main']
assert metadata['sha256sums']==['SKIP']
assert metadata['conflicts']==['nyvorel']
assert metadata['makedepends']==['git']
assert len(metadata['provides'])==1 and metadata['provides'][0].startswith('nyvorel=')
assert metadata['arch']==['any']

required=[]
optional=[]
for group,name in ((deps['required'],required),(deps['optional'],optional)):
    for row in group:
        first=row.get('arch_packages_any_of',[])
        whole=row.get('arch_packages_all_of',[])
        if first:
            name.append(first[0])
        name.extend(whole)
assert len(deps['required'])==12 and len(deps['optional'])==32 and len(deps['test-only'])==2
assert len(required)==len(set(required)),'duplicate required package names'
assert len(optional)==len(set(optional)),'duplicate optional package names'
assert set(metadata['depends'])==set(required),('required difference',set(metadata['depends'])^set(required))
actual_optional=[s.split(':',1)[0] for s in metadata['optdepends']]
assert set(actual_optional)==set(optional),('optional difference',set(actual_optional)^set(optional))
assert len(metadata['depends'])==len(required)
assert len(metadata['optdepends'])==len(optional)
for row in deps['test-only']:
    for candidate in row.get('arch_packages_all_of',[]):
        assert candidate not in metadata['depends'],f'test-only provider in depends: {candidate}'
assert 'cloudflare-warp-bin' in optional and 'cloudflare-warp-bin' not in required
# Detect dormant commit-specific, private path or deprecated package-home references.
for text in (p,src):
    assert re.search(r'/home/[A-Za-z0-9._-]+/',text) is None
    assert '/usr/local/' not in text
print('dependency_contract_required=12_PASS')
print('dependency_contract_optional_features=32_PASS')
print('test_only_runtime_separation=PASS')
print('AUR_VCS_metadata_provides_conflicts=PASS')
print('AUR_publication_forbidden=PASS')
PYAUDIT
bash -n "$AUR/PKGBUILD"
bash -n "$AUR/nyvorel.install"
bash -n "$EXPORTER"
if command -v makepkg >/dev/null 2>&1; then
  TMP_SRC="$(mktemp)"
  trap 'rm -f "$TMP_SRC"' EXIT
  (cd "$AUR" && makepkg --printsrcinfo) > "$TMP_SRC"
  diff -u "$AUR/.SRCINFO" "$TMP_SRC"
  echo 'SRCINFO_matches_makepkg=PASS'
fi
if [[ "$MODE" == --static-only ]]; then
  echo 'PASS Phase 7D AUR static publication readiness'
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$EXPORTER" --output "$TMP/aur-submission"
mapfile -t FILES < <(find "$TMP/aur-submission" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
[[ "${FILES[*]}" == '.SRCINFO PKGBUILD nyvorel.install' ]] || { echo 'ERROR: export contains unapproved files' >&2; exit 1; }
for f in "${FILES[@]}"; do cmp "$AUR/$f" "$TMP/aur-submission/$f"; done

git init -q --bare --initial-branch=master "$TMP/mock-aur.git"
git init -q --initial-branch=master "$TMP/mock-checkout"
cp "$TMP/aur-submission/PKGBUILD" "$TMP/aur-submission/.SRCINFO" "$TMP/aur-submission/nyvorel.install" "$TMP/mock-checkout/"
(
  cd "$TMP/mock-checkout"
  git add -- PKGBUILD .SRCINFO nyvorel.install
  git -c user.name='Nyvorel CI Only' -c user.email='ci@example.invalid' commit -qm 'local-only submission rehearsal'
  # The destination below is a throwaway LOCAL bare repository, never AUR.
  git push -q "$TMP/mock-aur.git" HEAD:refs/heads/master
)
mapfile -t REMOTE_FILES < <(git --git-dir="$TMP/mock-aur.git" ls-tree --name-only master | LC_ALL=C sort)
[[ "${REMOTE_FILES[*]}" == '.SRCINFO PKGBUILD nyvorel.install' ]] || { echo 'ERROR: simulated AUR Git tree differs' >&2; exit 1; }
[[ "$(git --git-dir="$TMP/mock-aur.git" symbolic-ref HEAD)" == refs/heads/master ]]
echo 'local_git_submission_rehearsal=PASS'
echo 'remote_AUR_writes=NONE'
echo 'PASS Phase 7D AUR publication readiness rehearsal'
