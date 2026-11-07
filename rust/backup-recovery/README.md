# Backup & Recovery controller

The Backup & Recovery panel launches the on-demand `nyvorel-backup-recovery`
Rust binary. It emits the existing JSON contract (`schema_version: 2`,
`ui_contract: 1.6.0`) and exits after every request. The separate
`nyvorel-backup-recovery-root` Rust binary handles the systemd state collector
and privileged actions. Both are one-shot processes, with no idle resident
memory. The QML panel asks systemd to start allowlisted services; it never
runs privileged operations directly.

Build and verify without starting real backup actions:

```sh
cargo test --offline
cargo build --release --offline
python3 tests/mock_systemctl.py
python3 tests/collector_parity.py
```

`deploy_active.py` installs the binary and QML route into the active Nyvorel
configuration. The same deployment removes Project Launcher's active shell
loader, module, shortcut, surface policy, and Hyprland rules. It creates a
timestamped snapshot under the repository's `.migration-backups` directory
before changing any active files. Run that snapshot's `rollback.sh` to restore
the previous active configuration.

After building the release binary, `deploy_system.py install` switches the ten
system services to the Rust root helper. It snapshots the prior commands and
automatically restores them if the state collector fails its live contract
check. Run `deploy_system.py rollback SNAPSHOT` as root to undo the switch.
The previous Python service files remain inert in `/usr/local/lib/backup-recovery`
until the Rust services have been exercised with a connected backup disk.
