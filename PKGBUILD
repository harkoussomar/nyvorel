# Maintainer: Nyvorel <https://github.com/harkoussomar/nyvorel>
# Phase 7B source-tree package. AUR/release-source publication is intentionally
# deferred until a future release phase.
pkgname=nyvorel
pkgver=0.1.0.dev
pkgrel=1
pkgdesc='Nyvorel Hyprland + Quickshell desktop environment'
arch=('any')
url='https://github.com/harkoussomar/nyvorel'
license=('GPL-3.0-only' 'Apache-2.0' 'CC-BY-4.0' 'MIT')
depends=(
  'bash'
  'python'
  'python-pillow'
  'python-pip'
  'hyprland'
  'quickshell'
  'systemd'
  'dbus'
  'git'
  'coreutils'
  'findutils'
  'grep'
  'sed'
  'gawk'
  'qt6-positioning'
  'qt6-5compat'
  'ttf-material-symbols-variable'
  'jq'
  'bc'
  'matugen'
)
optdepends=(
  'libnotify: Desktop notifications and fallback user feedback.'
  'wl-clipboard: Clipboard integration and clipboard history transport.'
  'cliphist: Clipboard history storage and decoding.'
  'fuzzel: Fallback clipboard and emoji picker UI.'
  'grim: Region/fullscreen screenshot and visual selection workflows.'
  'slurp: Region/fullscreen screenshot and visual selection workflows.'
  'hyprshot: Fallback region screenshot workflow.'
  'hyprpicker: Color picker shortcut.'
  'tesseract: OCR region-to-clipboard workflow.'
  'gpu-screen-recorder: GPU screen recording.'
  'ffmpeg: Video wallpaper, recording and appearance media processing.'
  'libpulse: Audio capture for recording workflows.'
  'wireplumber: Volume and microphone media-key controls.'
  'easyeffects: EasyEffects session processing and toggle.'
  'playerctl: Media playback keybindings.'
  'brightnessctl: Brightness media-key fallback.'
  'gnome-keyring: Secrets keyring session component.'
  'networkmanager: Network integration used by shell modules.'
  'imagemagick: Wallpaper profiling and image processing.'
  'mpvpaper: Video wallpaper playback.'
  'kitty: Preferred terminal and Kitty theme synchronization.'
  'xdg-utils: Open URLs/files from shell modules and keybindings.'
  'xdg-user-dirs: Resolve user Pictures/Screenshots paths.'
  'procps-ng: Process probing and fallback process control.'
  'geoclue: GeoClue agent used by location-aware shell functionality.'
  'fprintd: Fingerprint-aware lock/login integration.'
  'cloudflare-warp-bin: Cloudflare WARP quick toggle.'
  'wtype: Wayland synthetic keyboard input for supported integrations.'
  'cava: Audio visualization widgets.'
  'numlockx: Num Lock startup preference.'
  'curl: Favicon/download and network-backed shell helpers.'
  'file: Directory/file MIME inspection.'
)
install=nyvorel.install
source=()
sha256sums=()
options=('!strip')

_nyvorel_source="${NYVOREL_PKG_SOURCE:-$startdir}"

prepare() {
  [[ -s "$_nyvorel_source/VERSION" ]] || {
    echo "ERROR: Nyvorel VERSION missing from source tree" >&2
    return 1
  }

  [[ -s "$_nyvorel_source/packaging/ownership-contract.json" ]] || {
    echo "ERROR: Phase 7A ownership contract missing" >&2
    return 1
  }
}

package() {
  local _src="$_nyvorel_source"
  local _share="$pkgdir/usr/share/nyvorel"
  local _helpers="$pkgdir/usr/lib/nyvorel/bin"
  local _units="$pkgdir/usr/lib/systemd/user"

  install -Dm755 "$_src/bin/nyvorel" "$pkgdir/usr/bin/nyvorel"
  install -Dm644 "$_src/packaging/nyvorel.desktop" "$pkgdir/usr/share/wayland-sessions/nyvorel.desktop"
  install -Dm755 "$_src/install.sh" "$pkgdir/usr/lib/nyvorel/install.sh"
  install -Dm755 "$_src/uninstall.sh" "$pkgdir/usr/lib/nyvorel/uninstall.sh"

  install -d "$_helpers"
  for _helper in "$_src"/bin/*; do
    [[ -f "$_helper" ]] || continue
    [[ "$(basename "$_helper")" == "nyvorel" ]] && continue
    install -m755 "$_helper" "$_helpers/$(basename "$_helper")"
  done
  install -m755 "$_src/packaging/nyvorel-package-install"     "$_helpers/nyvorel-package-install"

  install -d "$_share"
  for _dir in quickshell hypr matugen integrations dependencies assets; do
    cp -a "$_src/$_dir" "$_share/$_dir"
  done
  install -m644 "$_src/VERSION" "$_share/VERSION"

  python3 - "$_share" "$_src/bin" <<'PYPAYLOAD'
from pathlib import Path
import re
import sys

share=Path(sys.argv[1])
bin_root=Path(sys.argv[2])
helper_root="/usr/lib/nyvorel/bin"

helpers=sorted(
    p.name for p in bin_root.iterdir()
    if p.is_file() and p.name != "nyvorel"
)
prefixes=(
    b"@HOME@/.local/bin/",
    b"$HOME/.local/bin/",
    b"${HOME}/.local/bin/",
    b"~/.local/bin/",
    b"%h/.local/bin/",
    b"${Directories.home}/.local/bin/",
)

for path in share.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    # Remove interpreter caches only from the disposable package payload.
    if ("__pycache__" in path.relative_to(share).parts
            or path.suffix in {".pyc", ".pyo"}
            or ".before-" in path.name or ".pre-" in path.name):
        path.unlink()
        continue
    data=path.read_bytes()
    original=data

    for name in helpers:
        target=f"{helper_root}/{name}".encode()
        for prefix in prefixes:
            data=data.replace(prefix+name.encode(), target)

        # Python helpers can be built with pathlib from HOME instead of a
        # string prefix. Package mode replaces that complete expression.
        data=data.replace(
            f'HOME / ".local/bin/{name}"'.encode(),
            f'Path("{helper_root}/{name}")'.encode(),
        )
        data=data.replace(
            f"HOME / '.local/bin/{name}'".encode(),
            f"Path('{helper_root}/{name}')".encode(),
        )

    # The public CLI is package-owned at /usr/bin/nyvorel. Match only the
    # exact command name so nyvorel-* helpers cannot be misrouted to /usr/bin.
    for prefix in prefixes:
        data=re.sub(
            re.escape(prefix)+rb"nyvorel(?=$|[^A-Za-z0-9_-])",
            b"/usr/bin/nyvorel",
            data,
        )

    if data != original:
        path.write_bytes(data)
PYPAYLOAD

  # Public package payload must be readable/traversable by arbitrary users.
  # cp -a preserves source modes, so normalize only package-consumption bits
  # while leaving regular-file executable bits unchanged.
  find "$_share" -type d -exec chmod 755 {} +
  find "$_share" -type f -exec chmod a+r,go-w {} +

  while IFS= read -r -d '' _unit; do
    _rel="${_unit#"$_src/systemd/"}"
    _rel="${_rel%.in}"
    install -Dm644 "$_unit" "$_units/$_rel"
  done < <(find "$_src/systemd" -type f -print0)

  python3 - "$_units" "$_src/bin" <<'PYUNITS'
from pathlib import Path
import re
import sys

root=Path(sys.argv[1])
bin_root=Path(sys.argv[2])
helpers=sorted(
    p.name for p in bin_root.iterdir()
    if p.is_file() and p.name != "nyvorel"
)
prefixes=(
    b"@HOME@/.local/bin/",
    b"$HOME/.local/bin/",
    b"${HOME}/.local/bin/",
    b"~/.local/bin/",
    b"%h/.local/bin/",
    b"${Directories.home}/.local/bin/",
)

for path in root.rglob("*"):
    if not path.is_file():
        continue
    data=path.read_bytes()

    for name in helpers:
        target=f"/usr/lib/nyvorel/bin/{name}".encode()
        for prefix in prefixes:
            data=data.replace(prefix+name.encode(), target)

    for prefix in prefixes:
        data=re.sub(
            re.escape(prefix)+rb"nyvorel(?=$|[^A-Za-z0-9_-])",
            b"/usr/bin/nyvorel",
            data,
        )

    data=data.replace(b"@HOME@", b"%h")
    path.write_bytes(data)
PYUNITS

  install -Dm644 "$_src/assets/nyvorel.svg"     "$pkgdir/usr/share/icons/hicolor/scalable/apps/nyvorel.svg"

  install -Dm644 "$_src/README.md" "$pkgdir/usr/share/doc/nyvorel/README.md"
  install -Dm644 "$_src/INSTALL.md" "$pkgdir/usr/share/doc/nyvorel/INSTALL.md"
  install -Dm644 "$_src/PACKAGING.md" "$pkgdir/usr/share/doc/nyvorel/PACKAGING.md"
  install -Dm644 "$_src/DEPENDENCIES.md" "$pkgdir/usr/share/doc/nyvorel/DEPENDENCIES.md"

  install -Dm644 "$_src/LICENSE" "$pkgdir/usr/share/licenses/nyvorel/LICENSE"
  cp -a "$_src/LICENSES" "$pkgdir/usr/share/licenses/nyvorel/LICENSES"
  find "$pkgdir/usr/share/licenses/nyvorel/LICENSES" -type d -exec chmod 755 {} +
  find "$pkgdir/usr/share/licenses/nyvorel/LICENSES" -type f -exec chmod a+r,go-w {} +

  python3 - "$_src" "$_share/package-metadata.json" "$pkgver-$pkgrel" <<'PYMETA'
from pathlib import Path
import json
import subprocess
import sys

src=Path(sys.argv[1])
out=Path(sys.argv[2])
package_version=sys.argv[3]

roots=[
    src/"quickshell",
    src/"hypr",
    src/"matugen",
    src/"bin",
    src/"dependencies",
    src/"integrations",
    src/"systemd",
]
token=b"@HOME@"
count=0
files=0

for root in roots:
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        n=path.read_bytes().count(token)
        if n:
            files+=1
            count+=n

try:
    commit=subprocess.check_output(
        ["git","-C",str(src),"rev-parse","HEAD"],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()
except Exception:
    commit=""

payload={
    "schema":1,
    "product":"Nyvorel",
    "source_kind":"package",
    "package_name":"nyvorel",
    "package_version":package_version,
    "upstream_version":(src/"VERSION").read_text().strip(),
    "source_commit":commit,
    "source_home_token_files":files,
    "source_home_token_occurrences":count,
    "package_payload_root":"/usr/share/nyvorel",
    "package_helper_root":"/usr/lib/nyvorel/bin",
    "package_unit_root":"/usr/lib/systemd/user",
}
out.write_text(json.dumps(payload,indent=2)+"\n")
PYMETA

  [[ "$(python3 -c 'import json; print(json.load(open("'"$_share"'/package-metadata.json"))["source_home_token_occurrences"])')" == 29 ]] || {
    echo "ERROR: package metadata lost the 29-token source contract" >&2
    return 1
  }

  if grep -RIlF '@HOME@' "$_units" >/dev/null 2>&1; then
    echo "ERROR: package-owned systemd unit contains @HOME@" >&2
    return 1
  fi

  if grep -RInIF '.local/bin/nyvorel' "$_units" "$_share" >"$srcdir/nyvorel-residual-user-helper-paths.txt" 2>/dev/null; then
    echo "ERROR: package payload/unit still points at legacy user-local Nyvorel paths:" >&2
    sed -n '1,80p' "$srcdir/nyvorel-residual-user-helper-paths.txt" >&2
    return 1
  fi
}
