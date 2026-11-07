# Runtime migration audit — 2026-11-06

The active Quickshell QML and shell entry points were searched for Python
invocations. The only remaining `python3` references in those entry points are
the translation maintenance scripts. The panel callers below use Rust:

| Feature | Active Rust entry point | Audit result |
| --- | --- | --- |
| Appearance Studio and semantic radius | `scripts/system/nyvorel-appearance-studio` | Binary and Settings caller match the tested build |
| Wallpaper regions, placement, thumbnails | `scripts/system/nyvorel-wallpaper-utils` | Binary and wrappers match the tested build |
| Keybind parser | `scripts/system/nyvorel-keybinds` | Binary and QML caller match the tested build |
| Arch Remote | `scripts/system/nyvorel-arch-remote` | Native contract, selftest, live snapshot and integrity verification passed with session access |
| Backup & Recovery panel | `scripts/system/nyvorel-backup-recovery` | Refreshed to tested source build; QML and wrapper call Rust |
| Operations Center, battery, calendar | `scripts/system/nyvorel-operations` | Reproducible Cargo build restored; refreshed binary passed read-only parity checks |
| Backup & Recovery system services | `/usr/local/lib/backup-recovery/nyvorel-backup-recovery-root` | Effective `ExecStart` for all ten services uses Rust drop-ins; installed root binary matches source build |

The backup unit base files still contain historical Python `ExecStart` lines,
but systemd's effective commands are the Rust drop-ins. No backup action was
started for this audit. The ten service units and the root binary were checked
read-only.

The latest rollback snapshots for semantic radius, wallpaper color, wallpaper
utilities, keybinds, full-native Arch Remote, Backup & Recovery user and system
services, and the two refreshed user binaries were inspected. Saved file hashes
matched the manifests wherever hashes were recorded. The system-service
snapshot contains all ten original unit files. Restore newer overlapping code
snapshots before older ones; notably, restore semantic radius before wallpaper
color, then the earlier Appearance Studio snapshot.

Legacy Python source files remain for rollback and differential tests. The
active shell retains copies needed if an older caller is restored. Deleting
them would make rollback less reliable, so this audit only removed generated
Python bytecode caches from the project and added ignore rules. Translation
maintenance remains Python and is outside the running shell.

Read-only startup measurements on this host, five invocations each, had median
elapsed times of 7.5 ms (Appearance status), 1.6 ms (Arch Remote contract),
1.1 ms (Backup ping), 1.2 ms (battery status), and 3.2 ms (keybind parse). Direct
peak-RSS samples were 10.1, 3.5, 2.6, 4.1, and 4.3 MiB respectively. These
one-shot processes exit after the request. The Operations Center monitor is
intentionally resident and was observed at about 4.9 MiB RSS. Measurements
are local samples, not performance guarantees.

No window, display, wallpaper, or theme was changed during this audit. Rust
unit tests passed for Operations Center (13), Backup & Recovery (4), and its
mock systemctl and collector parity flows. The native Arch Remote verification
and active binary hash checks also passed. Operations Center and Backup &
Recovery passed `cargo clippy --offline --all-targets -- -D warnings`.
