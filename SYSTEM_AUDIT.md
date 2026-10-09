# Nyvorel stabilization audit — 2026-10-08

This is an in-progress engineering audit, not a release-readiness certificate.
The desktop, clean installation, and website phases are not complete.

## Baseline and boundaries

- Source began clean on `main`, commit `d8090edb3bc9c89d7a54e3578c89bf5e7a34df8a`, version 0.1.0.
- Website began clean at `d1161510f75aeb309f2ee0e22bdc6c612d36a9c5`; inspected, not modified.
- Main PC baseline: Hyprland 0.56.2, Quickshell 0.3.1 (AUR quickshell-git revision `2d3b3e9`). The approved stabilization installed a local Quickshell 0.3.2 package against Qt 6.12.0; live `hyprctl configerrors` remains empty.
- One Quickshell process runs `qs -c nyvorel` under `nyvorel-quickshell.service`. The operations monitor is active. The shell RSS sample was about 1 GiB after approximately 20 hours of uptime; this alone does not establish a leak.
- Main PC has no `current-install` pointer. A normal reinstall is unsafe for this customized desktop. The installed Hyprland tree contains a customization differing from source.
- After the narrow appearance patch, comparison found 911 matching shell files; Hyprland had 31 matching and one differing file; 18 source helpers matched and five were absent. Python caches were excluded from comparison.
- `arch-fresh` exists in system libvirt but was shut off. No snapshots were listed. Its current IP and a clean pre-Nyvorel baseline have **not** been established.
- Arch Remote has a separate sibling Git repository. Nyvorel includes a controller copy, and the installed `arch-remote` wrapper points at that copy. No separate-project or remote-access changes were made.

## Findings

| Severity | Component | Reproduction / evidence | Root cause | Impact | Fix / next action | Validation |
| --- | --- | --- | --- | --- | --- | --- |
| Critical | Quickshell/Qt compatibility | Approved restart loaded successfully but warned build Qt 6.11.2 versus runtime Qt 6.12.0 | AUR binary was not rebuilt after Qt update | Potential runtime crashes; current baseline cannot be certified stable | Upstream 0.3.2 (`4f508be`) built locally against Qt 6.12.0 and installed as a local pacman package after a verified rollback rehearsal | `pacman -Qkk` reports 120 files/zero alterations; service `/usr/bin/qs` active with zero restarts; bar/search/both sidebars/Appearance Studio/Settings rendered; former ABI warning gone; future Qt upgrades still require compatible Quickshell builds |
| Critical | Appearance apply | Isolated `applycolor.sh` exits 1 with nonexistent `quickshell/ii`; installed and source files matched before patch | Legacy shell directory in five active helpers | Theme transaction fails on renamed installation | Fixed active paths in source and five backed-up installed scripts; retained intentional compatibility identifiers | Six isolated regressions pass; real generator fixture passes; installed palette reader exits 0; live panel opens with rendered icons |
| High | Required dependencies | Settings imports QtPositioning and Qt5Compat; font ligatures need Material Symbols Rounded | Contract only checked commands | Preflight can pass while core UI cannot load | Added required QML/font asset probes, jq/bc, promoted Matugen; synchronized local package metadata | Five probe regressions; doctor, contract and package metadata checks pass; installed assets detected |
| Medium | GeoClue detection | Installed daemon is `/usr/lib/geoclue`; agent and system unit are present | Contract looked for `geoclue` on PATH | False missing-dependency warning | Check daemon, agent, and unit files together | All/partial/missing file fixtures and actual main-PC file probes pass; location acquisition remains untested |
| Critical | Clean color generation | Source initially contained no Matugen templates or Python provisioning | Runtime depended on prerequisites present on maintainer desktop | Path fix alone could not produce a fresh working installation | Added source-owned Matugen templates and an explicit `nyvorel color-env` plan/check/install helper; automatic integration into a consented beginner install remains open | Real Matugen rendered all eight outputs; a disposable source install provisioned a Python 3.14 venv from a reviewed local wheel and passed generator smoke/repair; this is **not** clean-VM validation |
| High | Python color runtime | System Python cannot import materialyoucolor; existing private environment is Python 3.12 while host Python is 3.14; scheme helper formerly imported cv2/numpy | Environment was assumed; shell used `eval` and sourced an unprovisioned activation file | Fragile generation and incomplete dependency contract | Source `switchwall.sh` invokes the resolved environment Python; wallpaper scheme detection uses Pillow and standard statistics; `nyvorel color-env --install --yes` provisions a version-pinned binary wheel in a user venv after an explicit plan | Existing v2.0.10 and disposable v3.0.4 engines both pass the full real-generator fixture; v3 key-role aliases preserve every v2 SCSS name; source image/representative colorfulness scores stayed within 0.014 of old detector and chose the same schemes; no clean-VM claim |
| High | Theme service lifecycle | btop, fuzzel, kde-app and zen-code services/path units failed with `start-limit-hit`; preceding exits were 0 and all four started at the same times | A burst of shared style/palette changes triggered the four independent paths; precise producer remains unproven | Theme propagation stops until recovery | Source and backed-up live paths now trigger one-second coalescing timers before their services, retaining start limits | Rendered units pass `systemd-analyze verify`; all four live paths remained active through five appearance previews and their journals show successful repeated service runs with no Nyvorel failed units; 11 current generated style files exactly matched fresh isolated renders from the restored Fluid palette; long-term behavior still needs observation |
| Medium | Startup screen geometry | New Quickshell trial logged an undefined OSD screen; standalone Settings logged `availableGeometry.width` before geometry existed | Focused monitor and window geometry can lag QML object creation | Transient startup warnings and possible misplacement on first show | OSD falls back to the first Quickshell screen and Settings guards geometry; the two byte-matched installed QML files were backed up and narrowly deployed | Quickshell restarted once at PID 447193 with Result=success, NRestarts=0, `Configuration Loaded`, visible bar layer and no Hyprland config errors; the OSD screen warning did not recur; Settings mapped for five seconds with no width TypeError; full OSD behavior remains unverified |
| High | Runtime ownership | Glass/Fluid helpers wrote `hypr/custom/rules.conf`; radius wrote `custom/general.conf`; video restore script was regenerated inside the managed tree | Runtime and manifest-managed files overlapped | Normal use looked like drift and complicated updates | Source now stores style/radius in `custom/appearance-runtime.conf`, explicitly marks that file runtime-owned in manifests, and stores generated video restore commands under `~/.config/nyvorel/`; the managed video script is a launcher | Isolated helper/update/doctor/uninstall tests pass; a synthetic legacy migration preserves Fluid/radius while rejecting unrelated edits; backed-up main-PC migration preserved selected Fluid, all 13 deployed hashes, unchanged Quickshell PID and empty Hyprland config errors; Default/Inlay/Prism/Fluid live previews each cancelled to the exact 24-path/GSettings baseline |
| High | Startup selection | Current source installs `.conf`; modern Hyprland may select existing `.lua` | No explicit Nyvorel session entry/config selection | Shell may run on autogenerated compositor configuration | Added `nyvorel session` launcher and package-owned Wayland session entry that invokes `start-hyprland -- --config` with the installed config | Fake launcher argument/active-session tests pass; disposable source install passed `Hyprland --verify-config` on host 0.56.2; no new graphical session launched |
| High | First-run completeness | Source install left wallpaper, Matugen palettes, terminal colors and initial appearance state ungenerated | Source installer only copied shell/config trees | The first graphical login could start with missing generated assets | Added `nyvorel first-run` with staged color generation, private checksummed backup, guarded rollback and refusal to overwrite personal GTK/Fuzzel files; `setup.sh` now calls it after provisioning a color venv | Real disposable-home setup generated all initial assets, passed `first-run --check` and Hyprland config parsing, then separate fixture rollback restored original bytes/absence; six transaction tests pass. No graphical VM claim |
| High | Installer payload | Python imports created ignored bytecode containing an extra template token; fresh install failed with count 30 instead of 29 | Installer included interpreter caches | Local testing can break reproducibility and distribute stale paths | Exclude caches from source installation and disposable package payload; tests suppress cache creation | Contaminated-source install regression passes without deleting source caches; first-run and installer recovery pass |
| Medium | Historical files | Four tracked `.before-*` and `.pre-*` source snapshots include stale references | Installer and package copied all source files | Unnecessary stale payload and confusing audits | Narrow payload filters now exclude historical snapshots while retaining them in Git | Installer cache/backup-file fixture and package-layout checks pass; package build not rerun yet |
| Medium | Arch Remote loopback classification | Controller marks non-tailnet port 5900 critical and labels it LAN/broader | Strict bind compliance conflated with exposure scope; classification is port-based | Misleading security presentation for loopback | Separate-project scope must be agreed before remediation; preserve Tailscale/WayVNC policy | Source confirmed; current listener sample contained SSH but no port 5900 |
| Medium | SSH effective configuration | Controller invokes unprivileged `sshd -T`; user reported unavailable host keys | Inability to read protected keys is a plausible cause, not proof keys are missing | Effective-policy verification unavailable | Open: verify with approved read-only privileged check, never loosen key permissions/authentication | Hypothesis distinguished from confirmed source behavior; no SSH changes |
| Medium | Transaction recovery coverage | Controller snapshots known targets and re-synchronizes runtime; rollback helpers suppressed file errors | Preview/transaction snapshots omitted compositor rules, Kitty config and generated terminal files; Glass/Fluid helpers can normalize restored rules; Code Insiders settings were absent from the editor list | A cancelled preview or failed apply might not restore personal compositor/terminal/editor edits exactly | Added affected files to snapshots; replay exact bytes after runtime re-synchronization; refuse symlinked targets and surface restore failures; cover Code Insiders; skip compositor/terminal resync for palette-only previews | Injected helper rewrite, symlink, editor-failure and palette-only regressions pass; approved live previews returned tracked paths and GSettings to exact baseline |
| Low | Glass runtime idempotence | Applying the already-selected Fluid/wallpaper theme added one blank line to `appearance-runtime.conf`; isolated repeated Glass/Fluid cycles added another each time | Glass helper removed and re-appended its existing block after Fluid, preserving an extra separator on every cycle | Runtime file grows on repeated applies and needlessly reloads the compositor | Existing exact Glass block is now left in place | New repeated-sync regression passes; second live committed apply left runtime file byte-identical |

## Tests actually executed

- `python3 scripts/ci/test-appearance-studio.py`: eleven passing tests. Uses a stubbed generator/session in its subprocess fixture and injected controller failures; checks that a crafted virtual-environment value is not executed, preview rollback restores compositor rules and Kitty configuration, symlinked personal configuration is not overwritten, a failed editor integration restores Code Insiders settings, and palette-only previews skip unnecessary runtime reloads.
- `python3 scripts/ci/test-runtime-dependencies.py`: five passing tests for file presence, alternatives, complete groups and invalid selectors.
- Real-generator fixture (now retained as `scripts/ci/test-appearance-runtime.py --venv PATH`): source-owned Matugen templates rendered all eight configured outputs; dark/light preset application for Default, Inlay, Prism and Fluid; preview/cancel; preview/keep; wallpaper-derived apply; injected failure recovery. Uses actual Matugen 4.2.0 and an explicitly supplied existing Python environment, isolated HOME/XDG paths and stubbed compositor calls. It does not verify visual output, terminal escape propagation, or a fresh Python installation.
- The same fixture passed using a newly created disposable Python 3.14 venv with `materialyoucolor` 3.0.4, after the generator normalized renamed palette-key roles. A separate `test-color-env.sh` installed source files into a disposable HOME, required explicit consent, provisioned the environment from a local wheel, ran the generator, refused to replace a broken existing environment without `--repair`, and preserved its marker in a backup. The venv wheel was obtained from PyPI for the local test; no main-PC environment or system package was changed.
- Source structure, Bash/Python/JSON syntax, portability/secrets gate and dry-run validation passed.
- Rendered user-unit syntax and the four new path-to-timer service chains passed `systemd-analyze verify`. The four live path units were backed up, replaced, reloaded, and recovered to active/waiting. A double start of the Fuzzel timer produced one successful service invocation and refreshed its auto-generated style from stale Default to the selected Fluid profile. The other three coalesced paths have not been manually triggered yet.
- Installer backup/manifest/update-conflict recovery tests passed. Added interpreter-cache contamination regression passed.
- Appearance ownership regression passed: Glass, Fluid and radius helpers wrote only the dedicated runtime file; the managed compositor rules remained byte-identical; the video restore launcher executed a generated runtime script. The extended update fixture passed runtime-state preservation, deep-doctor integrity, uninstall archival, and synthetic legacy migration while rejecting an unrelated rule edit.
- The four style-sync service programs for btop, Fuzzel, KDE apps, and Zen/Code executed in an isolated user home for Default, Inlay, Prism and Fluid. Each produced its expected style marker/output; KDE and Code returned to their baseline identity for Fluid. This verifies generated files and script exit status, not visual application rendering or live four-service burst behavior.
- During the five live previews, all four timer-backed style services ran repeatedly with successful exits and no `start-limit-hit`; all four path units remained active. After the final cancel, 11 live generated btop/Fuzzel/KDE/Zen/Code outputs matched fresh isolated renders from the restored Fluid config and palette byte-for-byte. This demonstrates convergence for those outputs, not every optional integration.
- The main-PC appearance ownership migration was backed up under `runtime/audit-20261008/appearance-ownership-20261009T125054Z/` and rehearsed with byte-exact rollback in a disposable home before live application. It migrated the selected Fluid/Glass/radius blocks, updated only 13 allowlisted paths, reloaded Hyprland rules, and checked every deployed checksum. Fluid remained selected; `hyprctl configerrors` was empty and Quickshell remained PID 447193 with zero restarts. A fresh private snapshot under `runtime/audit-20261008/live-preview-after-migration-20261009T125132Z/` captured 24 transaction paths (21 present) plus two GSettings values. Live preset previews of Default, Inlay, Prism and Fluid all returned the files and GSettings byte-for-byte after cancel. A wallpaper-derived Light preview resolved `scheme-monochrome` and also cancelled to the exact baseline. All five left no preview active and kept Quickshell on the same PID. These are preview/cancel tests, not committed full apply tests.
- A narrow live controller update added Code Insiders to the editor rollback list after confirming that was the only source/live difference. Its previous bytes are under `runtime/audit-20261008/editor-snapshot-20261009T130245Z/`. A separate 45-path, 40-present private snapshot plus GSettings under `runtime/audit-20261008/live-committed-apply-20261009T130412Z/` preceded a committed apply of the already-selected wallpaper, dark mode and Fluid profile. Apply returned no warnings. The active theme survived a Quickshell-only restart from PID 447193 to 468388; bar/sidebar layers reappeared, service Result=success/NRestarts=0, Hyprland config errors remained empty, and all four style-sync paths stayed active with successful post-apply service runs. Only Appearance Studio history and the runtime rules file differed across the 45 backed-up paths. The latter had gained one blank line, leading to the Glass idempotence fix. The repeated committed apply after that backed-up one-helper deployment left the runtime file byte-identical. This does not establish a different theme's committed persistence or a full visual check of every integration.
- Further main-PC read-only and reversible checks: a 1.2-second notification returned ID 1 and the D-Bus notification name was owned by Quickshell PID 447193; `grim` streamed a valid 1920×1080 PNG to an in-memory file-type probe without saving a screenshot; Tesseract with installed English data read a synthetic image as `NYVOREL TEST 123`. PipeWire/PulseAudio, WirePlumber, NetworkManager, the desktop portal and the terminal/Dolphin/Zed style-sync paths were active; Wi-Fi connectivity was full. Two `wl-paste` watcher processes ran, but clipboard contents were not read or replaced. Audio controls and network toggles were not actuated. `mpvpaper` is absent on the main PC, so video wallpaper could not be tested there. `hypridle` is installed but not running; the source `exec-once` is commented, so automatic idle locking is not currently verified or enabled by default. The shell reported about 547 MiB RSS shortly after its restart; this single sample does not establish a leak.
- A new Dolphin window opened on `/tmp`, mapped under Hyprland, and rendered its dark KDE palette with legible toolbar/icons and warm folder accents in a private cropped screenshot; only that window was closed and prior focus restored. No Dolphin window remained. Existing Kitty and Zen windows were left untouched. Kitty/Fish generated theme files, btop/Fuzzel Fluid markers, KDE `IllogicalImpulse` scheme, the active Zen Fluid CSS, VS Code `Nyvorel System` selection and Zed's managed theme block were present. These file checks do not prove a live Kitty, Fish, Zen, Zed or browser visual result.
- The update sandbox initially tried to copy the ignored private audit directory and hit a root-owned transaction log; its fixture now copies Git-tracked and non-ignored working source only. Update/uninstall recovery then passed without reading private host backups.
- Doctor dependency/drift/JSON/strict behavior and first-run guidance tests passed.
- Package layout and local AUR metadata static checks passed, including `.SRCINFO` equivalence with `makepkg --printsrcinfo`. Nothing was published.
- Existing bootstrap planner regression passed in a disposable Arch container. Dependencies and repository responses are controlled fixtures; package mutation stays inside the disposable container. This is not a graphical VM install.
- Main PC early stabilization check: patched installed palette reader exited 0 with terminal output suppressed; Appearance Studio opened with rendered text/icons; Hyprland reported no config errors. An explicitly approved Quickshell restart changed the main PID from 1269 to 256755 and loaded the configuration. It exposed the Qt mismatch plus OSD-screen and cross-thread Qt warnings. Later package, guard, appearance and restart checks supersede this early snapshot; logout, lock and reboot remain untested.
- The original 0.3.1 Quickshell revision failed to build against Qt 6.12 at MOC metatype checks. Upstream 0.3.2 built successfully against host Qt 6.12.0, with the QML tooling install path explicitly set. Its staged binary reports 0.3.2; a no-window QML file importing Quickshell, Hyprland and Io reached `Configuration Loaded` on the host. The smoke process was intentionally terminated after 12 seconds; the subsequent live package/service checks provide separate full-shell evidence.
- A separate Settings process using the staged 0.3.2 binary mapped and rendered, then closed. It revealed a transient geometry TypeError. After the source guard was added, the source Settings QML mapped again without that error. A minimal no-window OSD fallback expression loaded; the complete source OSD was not exercised live.
- The two QML guards were later deployed to the active shell after confirming both installed preimages matched the original Git commit exactly. A private checksum-verified backup and automatic rollback script are under `runtime/audit-20261008/qml-guards-20261009T124427Z/` and `runtime/audit-20261008/deploy-qml-guards.sh`. The approved Quickshell-only restart returned active at PID 447193, zero restarts, `Configuration Loaded`, bar layer present, empty Hyprland config errors and no OSD-screen startup warning. Standalone Settings mapped and closed after five seconds without the geometry TypeError. Qt cross-thread warnings remain; the OSD was not triggered end-to-end.
- Private local pacman artifacts exist for both 0.3.2 and the installed 0.3.1. The latter was reconstructed from 1,048 installed payload files; its binary SHA-256 matches `/usr/bin/quickshell`. The user approved a swap and automatic rollback, but noninteractive `sudo` cannot authenticate on this account. A temporary user-service override launched the staged 0.3.2 binary and restarted only Quickshell; the executable path, new PID, active state, zero restarts, loaded QML, bar/search/both sidebars/Appearance Studio rendering, and empty Hyprland config errors were verified. The Qt ABI mismatch warning disappeared. OSD screen assignment and Qt cross-thread warnings remain.
- An approved graphical administrator-authentication attempt installed the 0.3.2 local package at 03:34:04 UTC. The client incorrectly treated `kill -0` returning permission-denied on the now-root `pkexec` process as proof it had exited; it therefore never sent the verification marker. Its 120-second root watchdog automatically downgraded to the byte-matched 0.3.1 package at 03:36:05 UTC and restarted the original service. Pacman logs confirm both transactions, and `pacman -Qkk quickshell-git` reported 1,477 files with zero alterations after rollback. The client check was corrected to observe `/proc/$pid` existence instead. An approved retry installed 0.3.2 and completed its live verification handshake. The audit override was removed; systemd now runs `/usr/bin/qs` at PID 335639, active with zero restarts. `pacman -Qkk` reports 120 files with zero alterations, and the installed binary SHA-256 matches the staged tested binary. The exact 0.3.1 rollback package remains under `runtime/audit-20261008/quickshell-packages/old/`; restoring it later requires administrator authentication and a Quickshell-only service restart. The staged build directory is no longer on the service execution path.
- The user approved one initial live preset preview/cancel. An immediate private checksum backup covered 25 appearance paths (23 present) and GSettings. The first cancel returned one extra blank line in `hypr/custom/rules.conf` because the Glass/Fluid resync reformatted it after snapshot restoration. A byte diff showed no other change, and the file was restored from the verified immediate backup. The controller now replays the exact snapshot after resync; a regression simulates helper rewrites. All 25 paths and GSettings then compared equal to the pre-preview baseline; no preview remained active. Quickshell stayed on the same PID with zero restarts, and `hyprctl configerrors` was empty. Five later live preview/cancel checks exercised the updated rollback implementation.

## Backup and rollback

Private evidence and backups are under ignored `runtime/audit-20261008/`, mode 0700.
A timestamped archive was read back and verified against 1,446 live files before
patching installed helpers. `backup.json` records its SHA-256. An immutable source
archive preserves the original Git commit. No personal configuration was added
to the distributable tree.

`runtime/audit-20261008/rollback-appearance.sh` defaults to checksum and conflict
verification with no mutation. `--restore` restores only the five patched helpers.
It refuses files changed since the patch and never extracts the whole desktop
archive over a live home. A disposable-home restore rehearsal verified every
restored byte against the archive. Restoring these scripts does not restart the
shell but reinstates the original appearance path defect.

The two QML guards have a separate checksum-verified backup in
`runtime/audit-20261008/qml-guards-20261009T124427Z/`. Restoring those exact
files and restarting only `nyvorel-quickshell.service` reverts this deployment;
the deployment script performs that rollback automatically if its shell/bar or
Hyprland verification fails. Do not restore these files over later edits without
checking their hashes first.

The appearance ownership migration has its own 13-path checksum manifest and
byte-exact backups in `runtime/audit-20261008/appearance-ownership-20261009T125054Z/`.
`runtime/audit-20261008/deploy-appearance-ownership.py rollback` accepts that
exact directory and refuses concurrent changes before restoring all originals;
the live apply script also performs rollback automatically if its post-reload
checks fail. A disposable-home migration/rollback rehearsal verified all 12
preexisting files and removal of the newly added runtime file.

The committed appearance test has 45 captured paths and GSettings under
`runtime/audit-20261008/live-committed-apply-20261009T130412Z/`. The private
`runtime/audit-20261008/live-committed-apply.py rollback` command now checks
sealed post-apply checksums before restoring; it refuses later changes. Its
byte/mode/absence restore routine passed a disposable-home test, but a live
rollback was unnecessary. The Glass helper's exact previous bytes are under
`runtime/audit-20261008/glass-idempotence-20261009T131257Z/`.

The four style-sync path units and four new timers have a separate verified
backup in `runtime/audit-20261008/style-sync-20261009T035947Z/`. Run
`python3 runtime/audit-20261008/rollback-style-sync.py runtime/audit-20261008/style-sync-20261009T035947Z`
to check the backup and deployed bytes without mutation. Add `--restore` only
to stop these four paths/timers, restore the original four path files, remove
the four added timer files and reload the user manager. The rollback refuses
concurrent edits and leaves the old paths stopped; its byte restoration was
rehearsed in a disposable home with a stubbed user manager. The original path
units were already failed before deployment, so rolling back would reintroduce
that service-limit defect. The prior auto-generated Fuzzel style was also
backed up separately; the live output now correctly reflects selected Fluid.

## Phase 5 source progress (2026-10-09)

Local stabilization commits are `df65e347512457be8fcd9267c0e6e8202ba9b30f`
and `c81a63bcd195f2abfa788bc236fbcbbda4442baa`. Neither was pushed.
The first includes the appearance ownership, QML, startup and test fixes
described above; the second makes the AUR Git package test actually execute
its container script. A source-owned beginner setup change is under review
after those commits.

The new `setup.sh` prints a Bash-only package plan before Python is present.
Its consented path selects official pacman packages for the graphical session,
Qt/QML imports, fonts, browser/file manager, audio, shell integrations, and
safe defaults. Recommended apps, English OCR data and recording tools are
explicit groups. It uses a full `pacman -Syu` when packages are missing or
Quickshell is older than 0.3.2, and refuses to materialize user files if that
version gate still fails. A refreshed disposable Arch container installed the
current official `quickshell` and reported 0.3.2. Existing host sync metadata
still reported 0.3.1; this is precisely why the setup checks the installed
binary after the synchronized transaction. The default flow does not use AUR,
start NetworkManager, enable VPN/remote services, or enter an active Hyprland
desktop. Enabling NetworkManager requires an explicit option to avoid
overriding an existing network setup.

Source install now tags Matugen-generated Hyprland and Hyprlock color files as
runtime-owned. Update preserves their live bytes, including older manifests
where Appearance Studio already changed them; doctor accepts these known
runtime destinations, and uninstall archives them. Update/doctor/install and
uninstall sandbox regressions pass. First-session activation has its own
`nyvorel activate` command: it imports the Wayland environment, enables the
Nyvorel style paths/monitor, Polkit agent and PipeWire user units, starts the
shell and checks its active state. Hyprland calls that command on first login.
The activation control flow passed a fake-manager test, but a real new login
has not been exercised.

An isolated real setup run, with a fake pacman/sudo that would fail on any
system mutation and a reviewed local materialyoucolor wheel, passed user
materialization, color environment creation, first-run palette generation,
`first-run --check`, `activate --check`, and session launcher inspection. An
explicit second run with `--resume` was idempotent; a run without `--resume`
refused the already-installed home. `Hyprland --verify-config` passed for an
independent first-run fixture. The fresh package lifecycle also passed again
from a sanitized mirror of the current source: real makepkg/pacman install,
upgrade, remove, reinstall, source-to-package migration and recovery in a
disposable Arch container. No graphical output was verified by those runs.

The previously documented VM is no longer registered in system or user
libvirt, and SSH to `192.168.122.39` returns no route. The Arch installer ISO
is present in the libvirt ISO pool, but no clean graphical guest has been
recreated. README and website therefore remain unchanged.

## Remaining phase gates

1. Finish Phase 2/3: generated-file ownership is live and passed four style previews plus one wallpaper-derived Light preview, all with exact core-state cancel restoration and 11 style outputs converged to the restored palette. A committed apply of the existing wallpaper/dark/Fluid theme persisted through a Quickshell restart, and a second apply was byte-stable after the Glass helper fix. A different theme's committed persistence and video wallpaper remain unverified on the active desktop. Longer-term style-sync burst behavior still needs observation.
2. Complete actual main-PC functional checks, including all appearance paths and external integrations. Quickshell 0.3.2 and the two QML geometry guards are live. Startup no longer logged the OSD screen assignment warning, but Qt cross-thread warnings remain and the complete OSD interaction is still unverified. Lock/logout/compositor restart need separate scheduling.
3. Review the Phase 5 candidate diff, finish relevant CI and create a scoped local commit. The earlier two stabilization commits are local; nothing has been pushed or tagged.
4. Complete the beginner install validation, including a real first graphical login, audio/portal/Polkit checks, and any package gaps discovered there. Its present isolated setup and package tests are narrower evidence.
5. Establish a genuinely clean VM baseline and follow only public instructions through install, reboot, update, recovery and uninstall. The previous VM is unavailable.
6. Synchronize README and website only after those steps pass. Website deployment/release/AUR publication remain prohibited without explicit approval.

Current assessment: **not release-ready**. The confirmed appearance path defect
is repaired, but the complete clean-install experience remains unproven and has
known blockers.

## External verification

- [Hyprland startup documentation](https://wiki.hypr.land/configuring/core/) documents explicit config selection through `start-hyprland -- --config`.
- [Hyprland Lua migration announcement](https://hypr.land/news/26_lua/) explains startup selection and legacy fallback; this supports investigating config selection rather than assuming all legacy syntax fails.
- Arch lists [Qt Positioning](https://archlinux.org/packages/extra/x86_64/qt6-positioning/), [Qt compatibility](https://archlinux.org/packages/extra/x86_64/qt6-5compat/), [Material Symbols font files](https://archlinux.org/packages/extra/any/ttf-material-symbols-variable/files/), and [GeoClue files](https://archlinux.org/packages/extra/x86_64/geoclue/files/). Local pacman metadata and installed file lists were also checked. Installed-file detection is not end-to-end feature validation.
