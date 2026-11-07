# Appearance Studio native controller

Appearance Studio's user-facing backend is a one-shot Rust executable. It has
no resident process or idle memory use. The launcher invokes only Rust; the
preserved Python controller is retained solely for code rollback. Managed
Appearance Studio applies now generate the Material SCSS and terminal palette
with Rust as well. The normal shell wallpaper path now uses the same Rust
SCSS generator and native image scheme detector. Optional Kvantum SVG and
config writers also use the one-shot Rust backend. Matugen, Hyprland, and other integrations
remain external dependencies.
The Settings window-radius control invokes the same binary with
`__semantic-radius window VALUE`; it persists the radius in the active Hyprland
Lua or conf format and applies it through `hyprctl`. It has no resident process.

The native commands are `status`, `variants`, `apply` (including `--preview`),
`keep-preview`, `revert-preview`, `preview-watchdog`, `ui-profile`, `target`,
`favorite-add`, `favorite-remove`, `favorite-apply`, `history-apply`, and
`clear-history`. Preview recovery reads the same immutable snapshot layout as
the previous controller, including previews started before an upgrade. A
transient user-systemd timer expires previews; a short-lived Rust watchdog is
the fallback when the user manager is unavailable.

Apply and Keep snapshot all appearance-owned files and GNOME theme preferences
before changing them. A failed core mutation restores the captured files and
runtime material settings. Disabled targets retain their original files.
Hybrid themes merge preset surfaces with wallpaper accents; special OLED, Dim,
and High Contrast modes alter only the Quickshell palette. Video wallpapers
retain a persistent thumbnail for session restart. Saved appearance restore
keeps global target preferences.

The Matugen JSON reader supports the installed per-mode role format. The
previous Python controller's scratch config omitted `[templates]` and its
reader did not recognize the nested colors, causing an unintended fallback to
a different palette engine. The project copy is corrected for differential
testing. Native palettes and Python's corrected Matugen path match for the
sampled seeds and schemes.

Build and verify:

```sh
cargo fmt --check
cargo clippy --offline --all-targets -- -D warnings
cargo test --offline
cargo build --release --offline
python3 tests/parity.py
python3 tests/native_flow.py
python3 tests/material_scss.py
python3 tests/unmanaged_color.py
python3 tests/semantic_radius.py
python3 tests/deploy_semantic_radius.py
python3 tests/deploy_wallpaper_color.py
python3 tests/watchdog.py
python3 tools/catalog.py
```

`native_flow.py` uses isolated XDG directories and fake gsettings, Hyprland,
video, runtime, and theme helpers. It compares Python and Rust flows for
preview revisions, Keep/Revert, direct apply, custom anchors, hybrid palettes,
UI profiles, target re-enable, favorites/history, video transitions, variants,
and failed-render rollback. It never changes the live theme or displays.
`material_scss.py` compares all nine schemes in light and dark mode across two
seed colors with the preserved Python generator, checks terminal color channels
within 2/255, and exercises the real managed `switchwall.sh` in isolated XDG
directories with no Python environment. The Rust Material library and the
legacy Python library differ on a few semantic role values; managed consumers
use Matugen's separate `colors.json` for shell colors and SCSS for terminal
colors.

`unmanaged_color.py` checks image-based source colors and automatic scheme
selection against the previous Python helpers. It exercises GIF frame selection,
SVG conversion, optional Kvantum writers, and the ordinary `switchwall.sh`
flow in isolated XDG directories with the Python environment unavailable.
The Rust process exits after each request and holds no memory while idle.

`semantic_radius.py` compares the Rust writer with the preserved Python writer
in isolated XDG directories, including a copy of the current Lua runtime file.
It never changes the live radius or display. Install the tested Settings bridge
with `python3 rust/appearance-studio/deploy_semantic_radius.py install`. The
timestamped `.migration-backups/semantic-radius-*/rollback.sh` restores the
previous binary and QML caller without changing appearance data. Roll back
this migration before an earlier Appearance Studio migration if needed.

The ordinary wallpaper color code swap is installed with
`python3 rust/appearance-studio/deploy_wallpaper_color.py install`. Its
timestamped snapshot under `.migration-backups/wallpaper-color-*/` contains
the previous binary and three shell entry points. The snapshot's `rollback.sh`
restores those files without changing wallpaper, settings, or generated colors.
Use `deploy_wallpaper_color.py refresh SNAPSHOT_DIRECTORY` for a later tested
binary correction; it keeps the original rollback snapshot intact.

The active migration backup is
`.migration-backups/appearance-studio-20261103-203014`.
`deploy_active.py upgrade` saves the previous binary, launcher, and shared
color script plus a timestamped copy of the current active QML, controller,
config, state, and colors before installing the native controller. Code rollback is
`python3 rust/appearance-studio/deploy_active.py rollback` from the project
root. It restores the original QML caller and Python controller while keeping
the current appearance data. Only restore an older data backup explicitly if
the current state is damaged; it may discard later changes.
