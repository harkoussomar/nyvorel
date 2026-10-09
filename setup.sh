#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
mode=plan
yes=0
resume=0
replace_existing=0
recommended=0
ocr=0
recording=0
enable_networkmanager=0
wheelhouse=""
vulkan_driver=""

usage() {
  cat <<'EOF'
Nyvorel setup for an existing minimal Arch installation

Usage: ./setup.sh [--plan|--install --yes] [options]

--plan                   Print package groups and user-file steps (default).
--install --yes          Consent to a full pacman system upgrade, selected
                         official packages, and Nyvorel user-file setup.
--resume                 Continue after an interrupted user-file setup.
--replace-existing       Back up and replace conflicting personal config files.
--with-recommended       Add Zed, Kate, Ark, btop and appearance tools.
--vulkan-driver PACKAGE   Select an official Vulkan provider for Zed.
--with-ocr-english       Add Tesseract with English language data.
--with-recording         Add GPU screen recording tools.
--enable-networkmanager  Enable/start NetworkManager after package install.
--wheelhouse PATH         Use local materialyoucolor wheel(s), without PyPI.

Run as the intended desktop user with internet and sudo. This does not
partition disks, install a display manager, use an AUR helper, activate VPN,
or enable remote services. Existing network management is preserved unless
--enable-networkmanager is explicitly selected.
EOF
}

while (($#)); do
  case "$1" in
    --plan) mode=plan; shift ;;
    --install) mode=install; shift ;;
    --yes) yes=1; shift ;;
    --resume) resume=1; shift ;;
    --replace-existing) replace_existing=1; shift ;;
    --with-recommended) recommended=1; shift ;;
    --vulkan-driver)
      (($# >= 2)) || { echo '--vulkan-driver needs a package.' >&2; exit 2; }
      vulkan_driver="$2"; shift 2 ;;
    --with-ocr-english) ocr=1; shift ;;
    --with-recording) recording=1; shift ;;
    --enable-networkmanager) enable_networkmanager=1; shift ;;
    --wheelhouse)
      (($# >= 2)) || { echo '--wheelhouse needs a directory.' >&2; exit 2; }
      wheelhouse="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown setup option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$mode" == plan && ( "$yes" == 1 || "$resume" == 1 || "$replace_existing" == 1 ) ]]; then
  echo '--yes, --resume and --replace-existing require --install.' >&2
  exit 2
fi
[[ $(id -u) != 0 ]] || { echo 'Run setup as the intended desktop user, not root.' >&2; exit 1; }
os_release="${NYVOREL_SETUP_OS_RELEASE:-/etc/os-release}"
[[ -f "$os_release" ]] || { echo "OS identity file is missing: $os_release" >&2; exit 1; }
os_id="$(sed -n 's/^ID=//p' "$os_release" | head -1 | tr -d '"')"
[[ "$os_id" == arch ]] || { echo "Nyvorel setup supports Arch Linux (found $os_id)." >&2; exit 1; }
command -v pacman >/dev/null || { echo 'pacman is required.' >&2; exit 1; }
[[ -f "$root/install.sh" && -f "$root/dependencies/arch.json" ]] || {
  echo 'Run setup.sh from a complete Nyvorel source checkout.' >&2; exit 1;
}

# Keep the default group to official packages needed for a usable desktop.
# The rootless plan stays available before Python, Hyprland, or Qt is present.
core=(
  bash coreutils findutils grep sed gawk git python python-pip python-pillow
  pacman-contrib hyprland quickshell mesa polkit
  xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  qt6-positioning qt6-5compat kirigami
  noto-fonts noto-fonts-emoji ttf-dejavu ttf-material-symbols-variable
  ttf-jetbrains-mono-nerd adwaita-cursors
  kitty fish firefox dolphin plasma-integration hyprlock qt6-multimedia-ffmpeg
  pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber
  networkmanager libnotify fuzzel wl-clipboard cliphist grim slurp
  matugen jq bc xdg-utils xdg-user-dirs
)
recommended_packages=(zed kate ark btop imagemagick ffmpeg playerctl hypridle)
ocr_packages=(tesseract tesseract-data-eng)
recording_packages=(gpu-screen-recorder libpulse)
packages=("${core[@]}")
case "$vulkan_driver" in
  ''|vulkan-intel|vulkan-radeon|vulkan-swrast|vulkan-virtio|vulkan-nouveau|nvidia-utils) ;;
  *) echo "Unsupported Vulkan package selection: $vulkan_driver" >&2; exit 2 ;;
esac
if [[ -n "$vulkan_driver" && "$recommended" != 1 ]]; then
  echo '--vulkan-driver applies only with --with-recommended (Zed).' >&2
  exit 2
fi
gpu_vendor=""
for vendor_file in /sys/class/drm/card*/device/vendor; do
  [[ -f "$vendor_file" ]] || continue
  gpu_vendor="$(<"$vendor_file")"
  break
done
if (( recommended )); then
  if [[ -z "$vulkan_driver" ]]; then
    case "$gpu_vendor" in
      0x8086) vulkan_driver=vulkan-intel ;;
      0x1002) vulkan_driver=vulkan-radeon ;;
      0x10de) vulkan_driver=manual-nvidia-selection ;;
      *) vulkan_driver=vulkan-swrast ;;
    esac
  fi
  [[ "$vulkan_driver" == manual-nvidia-selection ]] || recommended_packages+=("$vulkan_driver")
fi
(( recommended == 0 )) || packages+=("${recommended_packages[@]}")
(( ocr == 0 )) || packages+=("${ocr_packages[@]}")
(( recording == 0 )) || packages+=("${recording_packages[@]}")
[[ -z "$wheelhouse" || -d "$wheelhouse" ]] || { echo "Wheelhouse missing: $wheelhouse" >&2; exit 1; }

printf 'Nyvorel minimal-Arch setup\n'
printf '  Source: %s\n' "$root"
printf '  User:   %s (%s)\n' "${USER:-$(id -un)}" "$HOME"
printf '  Core official packages (%d): %s\n' "${#core[@]}" "${core[*]}"
(( recommended == 0 )) || printf '  Recommended: %s\n' "${recommended_packages[*]}"
(( recommended == 0 )) || printf '  GPU vendor: %s; Vulkan provider: %s\n' "${gpu_vendor:-unknown}" "$vulkan_driver"
(( ocr == 0 )) || printf '  English OCR: %s\n' "${ocr_packages[*]}"
(( recording == 0 )) || printf '  Recording:   %s\n' "${recording_packages[*]}"
printf '  NetworkManager activation: %s\n' "$([[ "$enable_networkmanager" == 1 ]] && echo requested || echo no)"
printf '  Follow-up: backed-up user install, isolated color environment, default wallpaper/palette.\n'
printf '  First login: start-hyprland through nyvorel session; user services activate there.\n'

if [[ "$mode" == plan ]]; then
  printf 'No packages, services, or user files changed.\n'
  exit 0
fi

[[ "$yes" == 1 ]] || { echo 'Review --plan, then use --install --yes.' >&2; exit 2; }
if [[ "$vulkan_driver" == manual-nvidia-selection ]]; then
  echo 'NVIDIA GPU detected. Choose and configure its kernel driver, then pass --vulkan-driver vulkan-nouveau or nvidia-utils explicitly.' >&2
  exit 2
fi
[[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || {
  echo 'Refusing setup inside an active Hyprland desktop.' >&2; exit 1;
}
command -v sudo >/dev/null || {
  echo 'sudo is required; install/configure it as part of the base Arch setup.' >&2; exit 1;
}
[[ -w "$HOME" ]] || { echo "HOME is not writable: $HOME" >&2; exit 1; }

pointer="$HOME/.local/state/nyvorel/current-install"
if [[ -s "$pointer" && "$resume" != 1 ]]; then
  echo 'Nyvorel is already installed here. Use nyvorel update, or --resume only for an interrupted setup.' >&2
  exit 3
fi
if [[ -s "$pointer" ]]; then
  command -v python3 >/dev/null || { echo 'Python is required to verify the existing install.' >&2; exit 1; }
  python3 - "$pointer" "$root" "$HOME" <<'PY'
import json
from pathlib import Path
import sys
pointer, root, home = map(Path, sys.argv[1:])
state = Path(pointer.read_text().strip())
manifest = json.loads((state / 'manifest.json').read_text())
if (manifest.get('product') != 'Nyvorel' or manifest.get('status') != 'installed'
        or manifest.get('source_kind') != 'source-clone'
        or manifest.get('source_root') != str(root)
        or manifest.get('target_home') != str(home)):
    raise SystemExit('Existing installation is from another source or home; refusing resume')
PY
fi

missing=()
for package in "${packages[@]}"; do
  pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
done
qs_supported() {
  local line version
  line="$(qs --version 2>/dev/null)" || return 1
  [[ "$line" =~ Quickshell[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]] || return 1
  version="${BASH_REMATCH[1]}"
  [[ "$(printf '%s\n%s\n' 0.3.2 "$version" | sort -V | head -1)" == 0.3.2 ]]
}
if ((${#missing[@]})) || ! qs_supported; then
  [[ -t 0 ]] || {
    echo 'Package installation needs an interactive terminal to review the pacman transaction. Rerun setup from a local terminal or SSH with a PTY (ssh -t).' >&2
    exit 2
  }
  printf 'Installing %d missing official packages and updating Quickshell with a full system upgrade.\n' "${#missing[@]}"
  sudo pacman -Syu --needed "${packages[@]}"
else
  printf 'All selected official packages are installed; skipping pacman.\n'
fi
qs_supported || {
  echo 'Quickshell 0.3.2 or newer is required after the pacman upgrade; check your mirror and package versions.' >&2
  exit 1
}

if (( enable_networkmanager )); then
  sudo systemctl enable --now NetworkManager.service
fi

command -v python3 >/dev/null || { echo 'Python still missing after pacman.' >&2; exit 1; }
if [[ ! -s "$pointer" ]]; then
  dry_output="$("$root/install.sh" --target-home "$HOME" --dry-run --no-activate)"
  printf '%s\n' "$dry_output"
  replacements="$(sed -n 's/^Existing replacements  : //p' <<< "$dry_output")"
  [[ "$replacements" =~ ^[0-9]+$ ]] || { echo 'Could not read the installer conflict count.' >&2; exit 1; }
  if (( replacements > 0 && replace_existing == 0 )); then
    echo "$replacements existing managed files require review; rerun with --replace-existing to back them up." >&2
    exit 3
  fi
  "$root/install.sh" --yes --no-activate
fi

cli="$HOME/.local/bin/nyvorel"
[[ -x "$cli" ]] || { echo 'Installed Nyvorel CLI is missing.' >&2; exit 1; }
color_args=(--install --yes)
[[ -z "$wheelhouse" ]] || color_args+=(--wheelhouse "$wheelhouse")
"$cli" color-env "${color_args[@]}"
first_run_args=(--initialize --yes)
(( replace_existing == 0 )) || first_run_args+=(--repair)
"$cli" first-run "${first_run_args[@]}"
"$cli" first-run --check
"$cli" session --check
printf '\nNyvorel user setup is ready. Start the desktop with: %s session\n' "$cli"
printf 'For recovery, inspect ~/.local/state/nyvorel/installations and first-run snapshots.\n'
