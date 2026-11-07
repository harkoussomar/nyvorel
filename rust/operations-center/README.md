# Operations Center Rust backend

The active Quickshell panel calls `scripts/system/nyvorel-operations` for
Operations Center, battery controls, calendar plans, and the bar's system
overview. The command handlers exit after each request. The separate `monitor`
command is a resident sampler and was observed using about 4.9 MiB RSS during
the 2026-11-06 audit.

The Cargo manifest and lockfile make this existing backend reproducible:

```sh
cd rust/operations-center
cargo fmt --check
cargo clippy --offline --all-targets -- -D warnings
cargo test --offline
cargo build --release --offline
```

The active binary was refreshed alongside Backup & Recovery's user-level
binary after testing. The previous binaries are preserved in
`.migration-backups/rust-user-binaries-20261106-192222/`; its `rollback.sh`
restores only those executables. No display, user settings, or state file is
changed by that rollback.
