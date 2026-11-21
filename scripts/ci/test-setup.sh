#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/user-profile/.local/bin" "$tmp/user-profile/.config/hypr" "$tmp/bin"
printf 'ID=arch\n' > "$tmp/os-release"

cat > "$tmp/bin/pacman" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NYVOREL_TEST_PACMAN_LOG:?}"
exit 20
MOCK
cat > "$tmp/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NYVOREL_TEST_SUDO_LOG:?}"
exit 20
MOCK
chmod +x "$tmp/bin/pacman" "$tmp/bin/sudo"

export HOME="$tmp/user-profile"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export PATH="$tmp/bin:$PATH"
export NYVOREL_SETUP_OS_RELEASE="$tmp/os-release"
export NYVOREL_TEST_PACMAN_LOG="$tmp/pacman.log"
export NYVOREL_TEST_SUDO_LOG="$tmp/sudo.log"
: > "$NYVOREL_TEST_PACMAN_LOG"
: > "$NYVOREL_TEST_SUDO_LOG"
unset HYPRLAND_INSTANCE_SIGNATURE || true

"$root/setup.sh" --plan --with-recommended --with-ocr-english > "$tmp/plan.log"
grep -q 'tesseract-data-eng' "$tmp/plan.log"
grep -q 'pipewire-jack' "$tmp/plan.log"
grep -q 'qt6-multimedia-ffmpeg' "$tmp/plan.log"
grep -q 'pacman-contrib' "$tmp/plan.log"
grep -q 'brightnessctl' "$tmp/plan.log"
grep -q 'cava' "$tmp/plan.log"
grep -q 'Vulkan provider:' "$tmp/plan.log"
grep -q 'install SDDM' "$tmp/plan.log"
grep -q 'No packages, services, or user files changed' "$tmp/plan.log"
"$root/setup.sh" --plan --no-graphical-login > "$tmp/text-plan.log"
grep -q 'Graphical login: skipped' "$tmp/text-plan.log"
[[ ! -s "$NYVOREL_TEST_PACMAN_LOG" && ! -s "$NYVOREL_TEST_SUDO_LOG" ]]

if "$root/setup.sh" --install > "$tmp/no-consent.log" 2>&1; then
  echo 'setup accepted package mutation without --yes' >&2; exit 1
fi
grep -q 'Review --plan' "$tmp/no-consent.log"

HYPRLAND_INSTANCE_SIGNATURE=live "$root/setup.sh" --install --yes > "$tmp/live.log" 2>&1 && {
  echo 'setup accepted an active desktop' >&2; exit 1;
}
grep -q 'active Hyprland' "$tmp/live.log"

mkdir -p "$HOME/.local/state/nyvorel"
printf 'existing\n' > "$HOME/.local/state/nyvorel/current-install"
"$root/setup.sh" --install --yes > "$tmp/existing.log" 2>&1 && {
  echo 'setup replaced an existing installation' >&2; exit 1;
}
grep -q 'already installed' "$tmp/existing.log"
[[ ! -s "$NYVOREL_TEST_PACMAN_LOG" && ! -s "$NYVOREL_TEST_SUDO_LOG" ]]

rm "$HOME/.local/state/nyvorel/current-install"
cat > "$tmp/bin/pacman" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == -Qq ]] && exit 1
exit 20
MOCK
chmod +x "$tmp/bin/pacman"
"$root/setup.sh" --install --yes > "$tmp/no-tty.log" 2>&1 && {
  echo 'setup attempted package installation without an interactive terminal' >&2; exit 1
}
grep -q 'interactive terminal' "$tmp/no-tty.log"
[[ ! -s "$NYVOREL_TEST_SUDO_LOG" ]]

cat > "$tmp/bin/pacman" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == -Qq ]]
MOCK
cat > "$tmp/bin/qs" <<'MOCK'
#!/usr/bin/env bash
printf 'Quickshell 0.3.2 (test)\n'
MOCK
chmod +x "$tmp/bin/pacman" "$tmp/bin/qs"
printf 'personal config\n' > "$HOME/.config/hypr/hyprland.conf"
"$root/setup.sh" --install --yes > "$tmp/conflict.log" 2>&1 && {
  echo 'setup accepted an existing managed config without explicit replacement' >&2; exit 1;
}
grep -q 'require review' "$tmp/conflict.log"
[[ "$(cat "$HOME/.config/hypr/hyprland.conf")" == 'personal config' ]]
printf 'existing\n' > "$HOME/.local/state/nyvorel/current-install"

printf 'stub\n' > "$HOME/.config/hypr/hyprland.conf"
cat > "$HOME/.local/bin/nyvorel" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == 'first-run --check' ]]
MOCK
chmod +x "$HOME/.local/bin/nyvorel"
cat > "$tmp/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${NYVOREL_TEST_SYSTEMCTL_LOG:?}"
exit 0
MOCK
chmod +x "$tmp/bin/systemctl"
export NYVOREL_TEST_SYSTEMCTL_LOG="$tmp/systemctl.log"
: > "$NYVOREL_TEST_SYSTEMCTL_LOG"
"$root/bin/nyvorel-activate" --check > "$tmp/activate-check.log"
[[ ! -s "$NYVOREL_TEST_SYSTEMCTL_LOG" ]]
WAYLAND_DISPLAY=wayland-test HYPRLAND_INSTANCE_SIGNATURE=hyprland-test \
  "$root/bin/nyvorel-activate" --session > "$tmp/activate.log"
if grep -q 'hyprpolkitagent.service' "$NYVOREL_TEST_SYSTEMCTL_LOG"; then
  echo 'external Polkit agent would conflict with Quickshell agent' >&2; exit 1
fi
grep -q 'nyvorel-operations-monitor.service' "$NYVOREL_TEST_SYSTEMCTL_LOG"
grep -q 'start nyvorel-quickshell.service' "$NYVOREL_TEST_SYSTEMCTL_LOG"
mkdir -p "$HOME/.config/nyvorel"
printf '%s\n' '{"appearance":{"interfaceStyle":"fluid","transparency":{"enable":true}}}' \
  > "$HOME/.config/nyvorel/config.json"
for helper in nyvorel-glass-runtime nyvorel-fluid-runtime; do
  cat > "$HOME/.local/bin/$helper" <<'MOCK'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$1" >> "${NYVOREL_TEST_APPEARANCE_LOG:?}"
MOCK
  chmod +x "$HOME/.local/bin/$helper"
done
export NYVOREL_TEST_APPEARANCE_LOG="$tmp/appearance.log"
WAYLAND_DISPLAY=wayland-test HYPRLAND_INSTANCE_SIGNATURE=hyprland-test \
  "$root/bin/nyvorel-activate" --session > "$tmp/activate-fluid.log"
grep -qx 'nyvorel-glass-runtime glass' "$NYVOREL_TEST_APPEARANCE_LOG"
grep -qx 'nyvorel-fluid-runtime fluid' "$NYVOREL_TEST_APPEARANCE_LOG"
mkdir -p "$tmp/package-helpers"
cp "$HOME/.local/bin/nyvorel-glass-runtime" "$HOME/.local/bin/nyvorel-fluid-runtime" "$tmp/package-helpers/"
: > "$NYVOREL_TEST_APPEARANCE_LOG"
NYVOREL_PACKAGE_MODE=1 NYVOREL_PACKAGE_HELPER_ROOT="$tmp/package-helpers" \
  WAYLAND_DISPLAY=wayland-test HYPRLAND_INSTANCE_SIGNATURE=hyprland-test \
  "$root/bin/nyvorel-activate" --session > "$tmp/activate-package-fluid.log"
grep -qx 'nyvorel-glass-runtime glass' "$NYVOREL_TEST_APPEARANCE_LOG"
grep -qx 'nyvorel-fluid-runtime fluid' "$NYVOREL_TEST_APPEARANCE_LOG"

# Exercise the complete setup ordering without changing the host's boot services.
mkdir -p "$tmp/source/dependencies" "$tmp/source/packaging" "$tmp/fresh-home"
cp "$root/setup.sh" "$tmp/source/"
cp "$root/dependencies/arch.json" "$tmp/source/dependencies/"
cp "$root/packaging/"{nyvorel.desktop,nyvorel-graphical-login} "$tmp/source/packaging/"
cat > "$tmp/source/install.sh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *--dry-run* ]]; then
  echo 'Existing replacements  : 0'
  exit 0
fi
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/nyvorel" <<'CLI'
#!/usr/bin/env bash
echo "$*" >> "$NYVOREL_TEST_FULL_SETUP"
if [[ "$*" == 'session --check' && "${NYVOREL_TEST_BROKEN_SESSION:-0}" == 1 ]]; then
  exit 1
fi
CLI
chmod +x "$HOME/.local/bin/nyvorel"
MOCK
cat > "$tmp/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
echo "sudo $*" >> "$NYVOREL_TEST_FULL_SETUP"
MOCK
chmod +x "$tmp/source/install.sh" "$tmp/bin/sudo"
export NYVOREL_TEST_FULL_SETUP="$tmp/full-setup.log"
HOME="$tmp/fresh-home" "$tmp/source/setup.sh" --install --yes > "$tmp/full-setup.out"
asserted_setup="$(tail -n 2 "$NYVOREL_TEST_FULL_SETUP")"
[[ "$asserted_setup" == $'session --check\n'"sudo /usr/bin/python3 -I $tmp/source/packaging/nyvorel-graphical-login --source $tmp/source/packaging/nyvorel.desktop" ]]
: > "$NYVOREL_TEST_FULL_SETUP"
HOME="$tmp/fresh-home" "$tmp/source/setup.sh" --install --yes --no-graphical-login > "$tmp/text-setup.out"
grep -q 'Start the desktop with' "$tmp/text-setup.out"
! grep -q '^sudo ' "$NYVOREL_TEST_FULL_SETUP"
: > "$NYVOREL_TEST_FULL_SETUP"
if HOME="$tmp/fresh-home" NYVOREL_TEST_BROKEN_SESSION=1 "$tmp/source/setup.sh" --install --yes > "$tmp/broken-setup.out"; then
  echo 'Graphical login setup accepted a broken session' >&2; exit 1
fi
! grep -q '^sudo ' "$NYVOREL_TEST_FULL_SETUP"

mkdir -p "$tmp/package/bin" "$tmp/package-source"
cat > "$tmp/package/install.sh" <<'MOCK'
#!/usr/bin/env bash
echo "materialize $*" >> "$NYVOREL_TEST_FULL_SETUP"
MOCK
for helper in nyvorel-color-env nyvorel-first-run nyvorel-session nyvorel-update; do
  cat > "$tmp/package/bin/$helper" <<'MOCK'
#!/usr/bin/env bash
echo "${0##*/} $*" >> "$NYVOREL_TEST_FULL_SETUP"
MOCK
done
chmod +x "$tmp/package/install.sh" "$tmp/package/bin/"*
export NYVOREL_PACKAGE_LIB_ROOT="$tmp/package"
export NYVOREL_SOURCE_ROOT="$tmp/package-source"
: > "$NYVOREL_TEST_FULL_SETUP"
HOME="$tmp/fresh-home" "$root/packaging/nyvorel-package-install" --with-graphical-login --dry-run
grep -qx 'materialize --dry-run' "$NYVOREL_TEST_FULL_SETUP"
! grep -q '^sudo ' "$NYVOREL_TEST_FULL_SETUP"
: > "$NYVOREL_TEST_FULL_SETUP"
HOME="$tmp/fresh-home" "$root/packaging/nyvorel-package-install" --with-graphical-login --yes
asserted_setup="$(tail -n 2 "$NYVOREL_TEST_FULL_SETUP")"
[[ "$asserted_setup" == $'nyvorel-session --check\n'"sudo /usr/bin/python3 -I $tmp/package/bin/nyvorel-graphical-login --package" ]]
PYTHONDONTWRITEBYTECODE=1 python3 "$root/scripts/ci/test-graphical-login.py"
echo 'PASS setup plan/consent/live guard/existing-install refusal and session activation'
