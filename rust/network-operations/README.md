# Nyvorel Network Operations

This is the on-demand Rust backend for the live Network Operations popup. It uses NetworkManager D-Bus for connection discovery and connectivity, NetworkManager's authenticated `nmcli` client for profile-only DNS changes, systemd-resolved for resolver inspection, and sysfs for interface counters. There is no daemon.

`~/.config/quickshell/nyvorel/scripts/system/nyvorel-network snapshot`, `doctor`, and `compare` are read-only. `dns set automatic|cloudflare|google|quad9|adguard|custom [IP ...]` changes only DNS fields on the active physical connection profile and requests a device reapply. `dns rollback` restores the saved previous DNS fields only if the same connection remains active and no outside edit superseded the change. The rollback file is `~/.local/state/nyvorel/network-dns-rollback.json` (0600). NetworkManager/Polkit controls authorization.

The selected physical profile, its link DNS, and systemd-resolved's catch-all route are separate fields. A Tailscale or VPN `~.` route may handle system queries even after a Wi-Fi profile change. DNS comparison sends one direct UDP query to each provider only when requested. The traffic chart samples while the popup is open; it does not claim historical daily or monthly totals.

Build offline with `cargo build --offline --release` using Rust 1.99.0. Run `cargo test --offline` before replacing the live binary. Quickshell reads the installed binary from `scripts/system/nyvorel-network`.
