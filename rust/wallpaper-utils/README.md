# Wallpaper utilities

One-shot Rust replacements for the active Nyvorel image helpers:

| Command | Existing Quickshell entry point | Purpose |
| --- | --- | --- |
| `find-regions` | `scripts/images/find-regions-venv.sh` | Rectangle and rounded rectangle hints for region selection |
| `least-busy-region` | `scripts/images/least-busy-region-venv.sh` | Quiet or busy wallpaper placement and sampled color |
| `thumbnails` | `scripts/thumbnails/thumbgen-venv.sh` | Freedesktop PNG thumbnail cache |

The wrappers preserve the current call sites. Each invocation exits when its work is done; there is no resident worker. Thumbnail conversion uses at most four workers, image dimensions are bounded, and external converters have timeouts. SVG, AVIF and video thumbnails can use the installed ImageMagick or FFmpeg tools when the Rust image decoder cannot read them.

## Build and verify

```sh
cd rust/wallpaper-utils
cargo fmt --check
cargo test --offline
cargo clippy --offline --all-targets -- -D warnings
cargo build --release --offline
python3 tests/native_flow.py
python3 tests/deploy_flow.py
```

`native_flow.py` uses generated image files and an isolated thumbnail cache. It compares the Rust output with the former Python implementations and checks the existing shell entry points. It does not capture a screen, move windows, or open a UI.

## Active installation and rollback

```sh
python3 rust/wallpaper-utils/deploy_active.py install
python3 rust/wallpaper-utils/deploy_active.py verify
```

Installation snapshots the three active wrappers, the active wallpaper service, and any earlier binary under `.migration-backups/wallpaper-utils-*/`. The printed `rollback.sh` restores the previous entry points after checking they have not been edited since installation. It leaves wallpapers, settings, and thumbnail caches alone.

If a tested project file needs a small correction after installation, use `deploy_active.py refresh SNAPSHOT_DIRECTORY`. It checks the active hashes before replacing changed files and updates the snapshot manifest, so the same `rollback.sh` still restores the pre-migration state.

The former Python implementations remain in the repository as migration references. The live Quickshell callers use the Rust binary through the original wrapper paths.
