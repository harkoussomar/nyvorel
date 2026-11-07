# Native keybind parser

`nyvorel-keybinds` reads the keybind files used by the Nyvorel cheatsheet and
prints one JSON document, then exits. It has no background process or idle
memory use. The active Quickshell service calls this binary on startup and
after a Hyprland config reload.

The parser supports native `hyprland.lua`, the small managed Lua file, and the
older commented `keybinds.conf` format. The former Python parser remains in
the source tree for rollback and differential testing.

## Build and test

```sh
cd rust/keybinds
cargo fmt --check
cargo test --offline
cargo clippy --offline --all-targets -- -D warnings
cargo build --release --offline
python3 tests/parity.py
python3 tests/deploy_flow.py
```

`parity.py` compares the JSON tree with Python for all three active keybind
files, copies of the legacy config files, and synthetic edge cases. Tests read
files only; they do not reload Hyprland or change a display.

## Active installation

```sh
python3 rust/keybinds/deploy_active.py install
python3 rust/keybinds/deploy_active.py verify
```

The installer snapshots the previous service file and any earlier native
binary under `.migration-backups/keybinds-*/`, then installs both files
atomically. Run that snapshot's `rollback.sh` to restore the previous caller.
Keybind configuration files are never changed.
