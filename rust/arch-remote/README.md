# Arch Remote — native Rust controller

The active Arch Remote panel and `arch-remote` CLI now execute the on-demand
Rust binary directly. Live snapshots, cache, SSH proof policy, service
preflight and postchecks, operation workers, pairing, reference, logs, and
activity persistence no longer invoke the Python controller. The binary starts
no daemon and uses no memory while idle. The former Python file is retained
solely as rollback material; the stage-29 binary is in the private backup.

The controller preserves the 2.4.1 UI schema, private file permissions,
allowlisted actions, lock ordering, bounded subprocesses, and credential
redaction. The live snapshot performs the local HTTP Serve probe in Rust and
verifies the package inventory before reporting readiness. An exited operation
worker publishes a failed result. The log path allows four journal units, up
to 240 entries, a 10-second timeout, and private redacted exports.

The latest active deployment backup is
`.migration-backups/arch-remote-full-native-20261104-231838/`.
It stores the previous panel QML, screen-placement wrapper, launcher, binary,
CLI, and deployment manifest;
rollback does not overwrite newer live state or change service state.

```sh
python3 rust/arch-remote/deploy_full_native.py verify
python3 rust/arch-remote/deploy_full_native.py rollback
```

The Python commands above are deployment tooling only. Runtime entry points
are `scripts/arch-remote/nyvorel-arch-remote` and `~/.local/bin/arch-remote`.

## Historical migration stages

Stages 1–29 incrementally moved collectors, policy evaluation, pairing,
service commands, logs, and operation scheduling to Rust. The full-native
install completed the remaining evidence collection, SSH policy cache,
preflight/postchecks, persistence, and UI/CLI wiring.

Build and test:

```sh
cd rust/arch-remote
cargo fmt --check
cargo clippy --release --offline -- -D warnings
cargo test --release --offline
cargo build --release --offline
python3 tests/full_native_runtime.py target/release/nyvorel-arch-remote
```

The isolated runtime test stubs `systemctl`, asserts that the Python controller
was never executed, and exercises the native worker without changing host
services or displays. Earlier `*_parity.py` scripts document and compare the
incremental stage contracts against the former Python implementation.

The active installation was backed up to
`.migration-backups/arch-remote-20261104-013347/` with mode `0700`. It contains
the original QML and controller plus snapshots of relevant Arch Remote state.
Installation and code rollback never restore state over a newer live version.
Stage 2 has a separate private backup at
`.migration-backups/arch-remote-logs-20261104-015243/` containing the stage-1
QML caller, launcher, and binary. Stage 3 has a private backup at
`.migration-backups/arch-remote-services-20261104-020648/` containing the
stage-2 Python controller and binary. Stage 4 has a private backup at
`.migration-backups/arch-remote-listeners-20261104-021233/` containing the
stage-3 controller and binary.
Stage 5 has a private backup at
`.migration-backups/arch-remote-tailscale-20261104-022053/` containing the
stage-4 controller and binary. Stage 6 has a private backup at
`.migration-backups/arch-remote-interfaces-20261104-023050/`, and stage 7 at
`.migration-backups/arch-remote-exposure-20261104-023455/`. Stage 8 has a private
backup at `.migration-backups/arch-remote-serve-funnel-20261104-024220/`, and stage 9
at `.migration-backups/arch-remote-domain-20261104-024733/`. Stage 10 has a private
backup at `.migration-backups/arch-remote-host-graphical-20261104-025317/`, and
stage 11 at `.migration-backups/arch-remote-power-20261104-025944/`. Stage 12
has a private backup at `.migration-backups/arch-remote-ssh-evidence-20261104-030408/`,
and stage 13 at `.migration-backups/arch-remote-sshd-effective-20261104-030822/`.
Stage 14 has a private backup at
`.migration-backups/arch-remote-hardening-20261104-031311/`, stage 15 at
`.migration-backups/arch-remote-integrity-20261104-144333/`, stage 16 at
`.migration-backups/arch-remote-wayvnc-security-20261104-145313/`, and stage 17 at
`.migration-backups/arch-remote-lan-share-security-20261104-145926/`.
Stage 18 is backed up at `.migration-backups/arch-remote-pair-support-20261104-150952/`.
Stage 19 is backed up at `.migration-backups/arch-remote-audit-20261104-152721/`,
and stage 20 at `.migration-backups/arch-remote-pairing-readiness-20261104-153619/`.
Stage 21 is backed up at `.migration-backups/arch-remote-phone-guide-20261104-154137/`.
Stage 22 is backed up at `.migration-backups/arch-remote-activity-20261104-155121/`.
Stage 23 is backed up at `.migration-backups/arch-remote-live-derive-20261104-155908/`.
Stage 24 is backed up at `.migration-backups/arch-remote-reference-20261104-160830/`.
Stage 25 is backed up at `.migration-backups/arch-remote-pairing-create-20261104-161457/`,
and stage 26 at `.migration-backups/arch-remote-pairing-cancel-20261104-161902/`.
Stage 27 is backed up at `.migration-backups/arch-remote-user-service-action-20261104-162744/`.
Stage 28 is backed up at `.migration-backups/arch-remote-system-service-action-20261104-163236/`.
Stages 14–28 also retain a private copy of the deployment manifest before its
verified Arch Remote entries were reconciled. Rollback restores the prior
controller hash without overwriting unrelated inventory entries.
Roll back in reverse
order if needed:

```sh
python3 rust/arch-remote/deploy_active.py verify
python3 rust/arch-remote/deploy_active.py verify_logs
python3 rust/arch-remote/deploy_active.py verify_services
python3 rust/arch-remote/deploy_active.py verify_listeners
python3 rust/arch-remote/deploy_active.py verify_tailscale
python3 rust/arch-remote/deploy_active.py verify_interfaces
python3 rust/arch-remote/deploy_active.py verify_exposure
python3 rust/arch-remote/deploy_active.py verify_serve_funnel
python3 rust/arch-remote/deploy_active.py verify_domain
python3 rust/arch-remote/deploy_active.py verify_host_graphical
python3 rust/arch-remote/deploy_active.py verify_power
python3 rust/arch-remote/deploy_active.py verify_ssh_evidence
python3 rust/arch-remote/deploy_active.py verify_sshd_effective
python3 rust/arch-remote/deploy_active.py verify_hardening
python3 rust/arch-remote/deploy_active.py verify_integrity
python3 rust/arch-remote/deploy_active.py verify_wayvnc_security
python3 rust/arch-remote/deploy_active.py verify_lan_share_security
python3 rust/arch-remote/deploy_active.py verify_pair_support
python3 rust/arch-remote/deploy_active.py verify_audit
python3 rust/arch-remote/deploy_active.py verify_pairing_readiness
python3 rust/arch-remote/deploy_active.py verify_phone_guide
python3 rust/arch-remote/deploy_active.py verify_activity
python3 rust/arch-remote/deploy_active.py verify_live_derive
python3 rust/arch-remote/deploy_active.py verify_reference
python3 rust/arch-remote/deploy_active.py verify_pairing_create
python3 rust/arch-remote/deploy_active.py verify_pairing_cancel
python3 rust/arch-remote/deploy_active.py verify_user_service_action
python3 rust/arch-remote/deploy_active.py verify_system_service_action
python3 rust/arch-remote/deploy_active.py rollback_system_service_action
python3 rust/arch-remote/deploy_active.py rollback_user_service_action
python3 rust/arch-remote/deploy_active.py rollback_pairing_cancel
python3 rust/arch-remote/deploy_active.py rollback_pairing_create
python3 rust/arch-remote/deploy_active.py rollback_reference
python3 rust/arch-remote/deploy_active.py rollback_live_derive
python3 rust/arch-remote/deploy_active.py rollback_activity
python3 rust/arch-remote/deploy_active.py rollback_phone_guide
python3 rust/arch-remote/deploy_active.py rollback_pairing_readiness
python3 rust/arch-remote/deploy_active.py rollback_audit
python3 rust/arch-remote/deploy_active.py rollback_pair_support
python3 rust/arch-remote/deploy_active.py rollback_lan_share_security
python3 rust/arch-remote/deploy_active.py rollback_wayvnc_security
python3 rust/arch-remote/deploy_active.py rollback_integrity
python3 rust/arch-remote/deploy_active.py rollback_hardening
python3 rust/arch-remote/deploy_active.py rollback_sshd_effective
python3 rust/arch-remote/deploy_active.py rollback_ssh_evidence
python3 rust/arch-remote/deploy_active.py rollback_power
python3 rust/arch-remote/deploy_active.py rollback_host_graphical
python3 rust/arch-remote/deploy_active.py rollback_domain
python3 rust/arch-remote/deploy_active.py rollback_serve_funnel
python3 rust/arch-remote/deploy_active.py rollback_exposure
python3 rust/arch-remote/deploy_active.py rollback_interfaces
python3 rust/arch-remote/deploy_active.py rollback_tailscale
python3 rust/arch-remote/deploy_active.py rollback_listeners
python3 rust/arch-remote/deploy_active.py rollback_services
python3 rust/arch-remote/deploy_active.py rollback_logs
python3 rust/arch-remote/deploy_active.py rollback
```

The stage 29 rollback is `python3 rust/arch-remote/deploy_active.py
rollback_controller_completion`. Its private backup is
`.migration-backups/arch-remote-controller-completion-20261104-201914/`.
Rollback checks installed file hashes before restoring the previous controller
and binary. This deployment did not restart Quickshell or change display state.
