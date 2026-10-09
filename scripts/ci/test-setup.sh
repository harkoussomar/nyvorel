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
export PATH="$tmp/bin:$PATH"
export NYVOREL_SETUP_OS_RELEASE="$tmp/os-release"
export NYVOREL_TEST_PACMAN_LOG="$tmp/pacman.log"
export NYVOREL_TEST_SUDO_LOG="$tmp/sudo.log"
: > "$NYVOREL_TEST_PACMAN_LOG"
: > "$NYVOREL_TEST_SUDO_LOG"
unset HYPRLAND_INSTANCE_SIGNATURE || true

"$root/setup.sh" --plan --with-recommended --with-ocr-english > "$tmp/plan.log"
grep -q 'tesseract-data-eng' "$tmp/plan.log"
grep -q 'No packages, services, or user files changed' "$tmp/plan.log"
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
grep -q 'enable --now hyprpolkitagent.service' "$NYVOREL_TEST_SYSTEMCTL_LOG"
grep -q 'nyvorel-operations-monitor.service' "$NYVOREL_TEST_SYSTEMCTL_LOG"
grep -q 'start nyvorel-quickshell.service' "$NYVOREL_TEST_SYSTEMCTL_LOG"
echo 'PASS setup plan/consent/live guard/existing-install refusal and session activation'
