import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property real screenWidth: root.QsWindow?.window?.screen?.width ?? 1200
    readonly property real screenHeight: root.QsWindow?.window?.screen?.height ?? 900
    implicitWidth: Math.max(360, Math.min(1128,
        screenWidth - (Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 0) - 52))
    implicitHeight: Math.max(360, Math.min(696,
        screenHeight - (Config.options.bar.vertical ? 32 : 88)))

    readonly property int expectedSchemaVersion: 5
    readonly property string expectedUiContract: "1.1.0"

    property string helperPath:
        Quickshell.shellPath(
            "scripts/system/nyvorel-operations"
        )

    property int selectedTab: 0
    property int activeView: 0
    property int previousTab: 0
    property real contentShift: 0
    property bool contentShown: true
    property bool entered: false
    property bool loading: true
    property bool systemLoading: true
    property bool snapshotReady: false
    property bool systemReady: false
    property string snapshotError: ""
    property string systemError: ""
    // Never drop a refresh while a snapshot or a mutating action is running.
    property bool queuedSnapshot: false
    property bool queuedFreshSnapshot: false
    property int actionRevision: 0
    property int snapshotRevision: 0
    property bool actionIsMutating: false
    property string actionCommandName: ""
    property string runtimeQuery: ""
    property string runtimeFilter: "all"
    property string jobQuery: ""
    // Repeater delegates are recreated when the 5-second runtime snapshot
    // replaces the array. Keep expansion state above the delegates.
    property var expandedRuntimeKeys: []

    property var snapshotData: ({
        schema_version: 5,
        ui_contract: "1.0.0",
        backend_revision: "6.1-runtime-control",
        monitor: {
            active: false,
            age_seconds: -1,
            interval_seconds: 2,
            error: ""
        },
        runtimes: [],
        jobs: [],
        job_groups: [],
        job_history: [],
        history_groups: [],
        attention: [],
        summary: {
            runtime_count: 0,
            local_runtime_count: 0,
            remote_managed_count: 0,
            job_count: 0,
            operation_count: 0,
            tracked_process_count: 0,
            job_group_count: 0,
            attention_count: 0,
            maintenance_count: 0,
            update_count: -1
        }
    })

    property var systemData: ({
        updates: {
            total: -1,
            official_count: 0,
            aur_count: 0
        },
        failed_units: [],
        failed_unit_count: 0,
        disk: {
            percent: 0,
            free: "—"
        },
        memory: {
            percent: 0,
            used: "—",
            total: "—"
        },
        load: "—",
        hostname: ""
    })

    property string toastMessage: ""
    property bool toastError: false

    focus: true

    Component.onCompleted: {
        Qt.callLater(() => {
            root.entered = true
            root.requestSnapshot()
            systemDelay.restart()
        })
    }

    function tabName(index) {
        if (index === 0)
            return "Overview"
        if (index === 1)
            return "Runtime"
        if (index === 2)
            return "Jobs"
        return "Diagnostics"
    }

    function tabIcon(index) {
        if (index === 0)
            return "space_dashboard"
        if (index === 1)
            return "dns"
        if (index === 2)
            return "work_history"
        return "troubleshoot"
    }

    function switchTab(index) {
        const next =
            Math.max(
                0,
                Math.min(3, index)
            )

        if (next === root.selectedTab)
            return

        root.previousTab = root.selectedTab
        root.inspectorOpen = false
        root.optionsOpen = false
        root.stopConfirmKey = ""
        root.selectedTab = next
        root.contentShift =
            next > root.previousTab
                ? 9
                : -9
        root.contentShown = false
        tabSwitchTimer.restart()

        // Workbench attention items may include maintenance signals.
        // Keep the original system refresh, without adding a new monitor.
        if (next === 3) {
            root.requestSystem(false)
            if (!root.officialUpgradeChecked)
                root.requestOfficialUpgrades()
        }
    }

    function payloadCompatible(payload) {
        return payload
            && payload.schema_version === root.expectedSchemaVersion
            && payload.ui_contract === root.expectedUiContract
    }

    function rejectIncompatiblePayload(payload) {
        const schema =
            payload && payload.schema_version !== undefined
                ? payload.schema_version
                : "missing"
        const contract =
            payload && payload.ui_contract !== undefined
                ? payload.ui_contract
                : "missing"
        const message = `Operations backend/UI mismatch (schema ${schema}, contract ${contract})`
        root.snapshotError = message
        root.systemError = message
        root.showToast(message, true)
    }

    function requestSnapshot(forceFresh) {
        const fresh = forceFresh === true
        if (snapshotProcess.running || (actionProcess.running && root.actionIsMutating)) {
            root.queuedSnapshot = true
            root.queuedFreshSnapshot = root.queuedFreshSnapshot || fresh
            return
        }

        root.snapshotRevision = root.actionRevision
        root.loading = true
        const command = [root.helperPath, "snapshot"]
        if (fresh)
            command.push("--fresh")
        snapshotProcess.command = command
        snapshotProcess.running = true
    }

    function flushQueuedSnapshot() {
        if (!root.queuedSnapshot || snapshotProcess.running
                || (actionProcess.running && root.actionIsMutating))
            return
        const fresh = root.queuedFreshSnapshot
        root.queuedSnapshot = false
        root.queuedFreshSnapshot = false
        root.requestSnapshot(fresh)
    }

    function requestSystem(force) {
        if (systemProcess.running)
            return

        root.systemLoading = true

        const command = [
            root.helperPath,
            "system"
        ]

        if (force)
            command.push("--force")

        systemProcess.command = command
        systemProcess.running = true
    }

    function runAction(args) {
        if (actionProcess.running)
            return

        root.actionCommandName = String(args[0] || "")
        root.actionIsMutating = ["stop", "stop-operation", "toggle-pin"].indexOf(root.actionCommandName) >= 0
        if (root.actionIsMutating) {
            root.actionRevision += 1
            root.queuedSnapshot = true
            root.queuedFreshSnapshot = (
                root.queuedFreshSnapshot
                || root.actionCommandName === "stop"
                || root.actionCommandName === "stop-operation"
            )
        }
        actionProcess.command = [root.helperPath].concat(args)
        actionProcess.running = true
    }

    function refreshAll() {
        root.requestSnapshot()

        if (root.selectedTab === 3) {
            root.requestSystem(true)
            root.requestOfficialUpgrades()
        }
    }

    function showToast(message, isError) {
        root.toastMessage = message
        root.toastError = isError
        toastTimer.restart()
    }

    function runtimeCount() {
        return root.snapshotData.summary.runtime_count || 0
    }

    function jobCount() {
        return root.snapshotData.summary.operation_count
            || root.snapshotData.summary.job_count
            || 0
    }

    function trackedProcessCount() {
        return root.snapshotData.summary.tracked_process_count || 0
    }

    function countText(count, singular, plural) {
        const value = Number(count) || 0
        return `${value} ${value === 1 ? singular : (plural || singular + "s")}`
    }

    function attentionCount() {
        return root.snapshotData.summary.attention_count || 0
    }

    function updateCount() {
        const count = root.snapshotData.summary.update_count

        if (count === undefined || count < 0)
            return "—"

        return String(count)
    }


    // Diagnostics is on-demand; no new periodic package polling is added.
    property var officialUpgradeRows: []
    property var aurUpgradeRows: []
    property bool officialUpgradeChecked: false
    property bool aurUpgradeChecked: false
    property bool officialUpgradeLoading: false
    property bool aurUpgradeLoading: false
    property string aurUpgradeNote: ""

    function parseUpgradeRows(raw) {
        const result = []
        const lines = String(raw || "").split("\n")
        for (let i = 0; i < lines.length; ++i) {
            // Output format of pacman -Qu and yay/paru -Qua:
            // package-name installed-version -> available-version
            const match = lines[i].trim().match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/)
            if (match)
                result.push({ name: match[1], installed: match[2], available: match[3] })
        }
        return result
    }

    function requestOfficialUpgrades() {
        if (officialUpgradesProcess.running)
            return
        root.officialUpgradeLoading = true
        officialUpgradesProcess.command = ["pacman", "-Qu"]
        officialUpgradesProcess.running = true
    }

    function requestAurUpgrades() {
        if (aurUpgradesProcess.running)
            return
        root.aurUpgradeLoading = true
        root.aurUpgradeNote = ""
        aurUpgradesProcess.command = [
            "sh", "-c",
            "if command -v yay >/dev/null 2>&1; then exec yay -Qua; "
            + "elif command -v paru >/dev/null 2>&1; then exec paru -Qua; "
            + "else printf 'NYVOREL_AUR_HELPER_MISSING\n'; fi"
        ]
        aurUpgradesProcess.running = true
    }

    function localRuntimeCount() {
        return root.snapshotData.summary.local_runtime_count || 0
    }

    function remoteManagedCount() {
        return root.snapshotData.summary.remote_managed_count || 0
    }

    // Workbench reads the existing snapshot only. No new backend endpoints,
    // polling loops or guessed success/failure outcomes.
    function pinnedWorkbenchRuntimes() {
        return (root.snapshotData.runtimes || []).filter(
            item => item.pinned === true && !item.managed_by_arch_remote
        ).slice(0, 5)
    }

    function totalPinnedWorkbenchRuntimes() {
        return (root.snapshotData.runtimes || []).filter(
            item => item.pinned === true && !item.managed_by_arch_remote
        ).length
    }

    function runningWorkbenchJobs() {
        return (root.snapshotData.job_groups || []).slice(0, 3)
    }

    function recentWorkbenchJobs() {
        return (root.snapshotData.job_history || []).slice(0, 4)
    }

    function urgentWorkbenchIssues() {
        return (root.snapshotData.attention || []).filter(
            item => item.severity === "critical" || item.severity === "warning"
        ).slice(0, 3)
    }

    function maintenanceCount() {
        return root.snapshotData.summary.maintenance_count || 0
    }

    function localRuntimes() {
        return root.snapshotData.runtimes.filter(item => !item.managed_by_arch_remote)
    }

    function remoteManagedRuntimes() {
        return root.snapshotData.runtimes.filter(item => item.managed_by_arch_remote)
    }

    function runtimeSearchText(runtime) {
        return [
            runtime.name || "",
            runtime.kind || "",
            runtime.scope || "",
            runtime.bind || "",
            runtime.cwd || "",
            runtime.url || ""
        ].join(" ").toLowerCase()
    }

    function runtimeMatches(runtime) {
        const query = root.runtimeQuery.trim().toLowerCase()
        if (query.length > 0 && root.runtimeSearchText(runtime).indexOf(query) < 0)
            return false

        if (root.runtimeFilter === "local")
            return runtime.scope === "Local"
        if (root.runtimeFilter === "exposed")
            return runtime.exposed === true
        if (root.runtimeFilter === "pinned")
            return runtime.pinned === true
        return true
    }

    function filteredLocalRuntimes() {
        return root.localRuntimes().filter(item => root.runtimeMatches(item))
    }

    function filteredRemoteManagedRuntimes() {
        return root.remoteManagedRuntimes().filter(item => root.runtimeMatches(item))
    }

    function runtimeStableKey(runtime) {
        if (!runtime)
            return ""

        const pinKey = runtime.pin_key ? String(runtime.pin_key) : ""
        if (pinKey.length > 0)
            return pinKey

        return runtime.key ? String(runtime.key) : ""
    }

    function runtimeExpanded(runtime) {
        const key = root.runtimeStableKey(runtime)
        return key.length > 0
            && root.expandedRuntimeKeys.indexOf(key) >= 0
    }

    function toggleRuntimeExpanded(runtime) {
        const key = root.runtimeStableKey(runtime)
        if (key.length === 0)
            return

        const next = root.expandedRuntimeKeys.slice()
        const index = next.indexOf(key)

        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(key)

        root.expandedRuntimeKeys = next
    }

    function pruneExpandedRuntimeKeys(runtimes) {
        const valid = ({})
        const rows = runtimes || []

        for (let index = 0; index < rows.length; ++index) {
            const key = root.runtimeStableKey(rows[index])
            if (key.length > 0)
                valid[key] = true
        }

        root.expandedRuntimeKeys =
            root.expandedRuntimeKeys.filter(key => valid[key] === true)
    }

    function jobSearchText(job) {
        return [
            job.name || "",
            job.kind || "",
            job.project || "",
            job.result_label || ""
        ].join(" ").toLowerCase()
    }

    function filteredJobGroups() {
        const query = root.jobQuery.trim().toLowerCase()
        if (query.length === 0)
            return root.snapshotData.job_groups
        return root.snapshotData.job_groups.filter(
            job => root.jobSearchText(job).indexOf(query) >= 0
        )
    }

    function filteredJobHistory() {
        const query = root.jobQuery.trim().toLowerCase()
        if (query.length === 0)
            return root.snapshotData.job_history
        return root.snapshotData.job_history.filter(
            job => root.jobSearchText(job).indexOf(query) >= 0
        )
    }

    function openArchRemote() {
        root.runAction(["open-remote"])
    }

    function severityColor(severity) {
        if (severity === "critical")
            return Appearance.m3colors.m3error

        if (severity === "warning")
            return Appearance.colors.colPrimary

        return Appearance.colors.colSubtext
    }

    function runtimeStatusColor(runtime) {
        if (runtime.exposed)
            return Appearance.colors.colPrimary

        return Appearance.colors.colPrimary
    }

    Process {
        id: snapshotProcess
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => root.flushQueuedSnapshot())
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                // An older scan must not overwrite the outcome of a later action.
                if (root.snapshotRevision !== root.actionRevision)
                    return

                try {
                    const payload =
                        JSON.parse(this.text)

                    if (payload.error) {
                        root.snapshotError = payload.message || "Operations refresh failed"
                        root.showToast(
                            payload.message || "Operations refresh failed",
                            true
                        )
                        return
                    }

                    if (!root.payloadCompatible(payload)) {
                        root.rejectIncompatiblePayload(payload)
                        return
                    }

                    root.snapshotData = payload
                    root.snapshotReady = true
                    root.snapshotError = ""
                    root.pruneExpandedRuntimeKeys(payload.runtimes || [])
                } catch (error) {
                    root.snapshotError = `Operations data error: ${error}`
                    root.showToast(
                        `Operations data error: ${error}`,
                        true
                    )
                }
            }
        }
    }

    Process {
        id: systemProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.systemLoading = false

                try {
                    const payload =
                        JSON.parse(this.text)

                    if (payload.error) {
                        root.systemError = payload.message || "System refresh failed"
                        root.showToast(
                            payload.message || "System refresh failed",
                            true
                        )
                        return
                    }

                    if (!root.payloadCompatible(payload)) {
                        root.rejectIncompatiblePayload(payload)
                        return
                    }

                    root.systemData = payload
                    root.systemReady = true
                    root.systemError = ""
                    root.requestSnapshot()
                } catch (error) {
                    root.systemError = `System data error: ${error}`
                    root.showToast(
                        `System data error: ${error}`,
                        true
                    )
                }
            }
        }
    }

    Process {
        id: officialUpgradesProcess
        stdout: StdioCollector {
            onStreamFinished: {
                root.officialUpgradeRows = root.parseUpgradeRows(this.text)
                root.officialUpgradeChecked = true
                root.officialUpgradeLoading = false
            }
        }
    }

    Process {
        id: aurUpgradesProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(this.text || "")
                root.aurUpgradeRows = root.parseUpgradeRows(raw)
                root.aurUpgradeNote = raw.indexOf("NYVOREL_AUR_HELPER_MISSING") >= 0
                    ? "Install yay or paru to inspect AUR upgrades."
                    : ""
                root.aurUpgradeChecked = true
                root.aurUpgradeLoading = false
            }
        }
    }

    Process {
        id: actionProcess
        onRunningChanged: {
            if (!running) {
                root.actionIsMutating = false
                Qt.callLater(() => root.flushQueuedSnapshot())
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload =
                        JSON.parse(this.text)

                    root.showToast(
                        payload.message || (
                            payload.error
                                ? "Action failed"
                                : "Action complete"
                        ),
                        payload.error === true
                    )
                } catch (error) {
                    root.showToast(
                        `Action error: ${error}`,
                        true
                    )
                }

                if (["stop", "stop-operation", "toggle-pin"].indexOf(root.actionCommandName) >= 0) {
                    root.queuedSnapshot = true
                    // Jobs terminate asynchronously after SIGTERM; verify again.
                    if (root.actionCommandName === "stop" || root.actionCommandName === "stop-operation") {
                        root.queuedFreshSnapshot = true
                        postStopRefreshTimer.restart()
                    }
                }
            }
        }
    }

    Timer {
        id: postStopRefreshTimer
        interval: 1200
        repeat: false
        onTriggered: root.requestSnapshot(true)
    }

    Timer {
        id: systemDelay
        interval: 450
        repeat: false
        onTriggered: root.requestSystem(false)
    }

    Timer {
        id: tabSwitchTimer
        interval: 75
        repeat: false

        onTriggered: {
            root.activeView = root.selectedTab
            root.contentShift = 0
            root.contentShown = true
        }
    }

    Timer {
        id: toastTimer
        interval: 3200
        repeat: false

        onTriggered: {
            root.toastMessage = ""
        }
    }

    Timer {
        interval:
            root.selectedTab === 0
            || root.selectedTab === 1
            || root.selectedTab === 2
                ? 5000
                : 15000

        repeat: true
        running: GlobalStates.sidebarLeftOpen

        onTriggered: root.requestSnapshot()
    }

    Connections {
        target: GlobalStates

        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                root.requestSnapshot()

                if (root.selectedTab === 3)
                    root.requestSystem(false)
            }
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if (
            event.modifiers === Qt.ControlModifier
            && event.key === Qt.Key_R
        ) {
            root.refreshAll()
            event.accepted = true
            return
        }

        if (
            event.modifiers === Qt.AltModifier
            && event.key >= Qt.Key_1
            && event.key <= Qt.Key_4
        ) {
            root.switchTab(
                event.key - Qt.Key_1
            )
            event.accepted = true
            return
        }

        if (event.modifiers !== Qt.NoModifier)
            return

        if (event.key === Qt.Key_Left) {
            root.switchTab(
                (root.selectedTab + 3) % 4
            )
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            root.switchTab(
                (root.selectedTab + 1) % 4
            )
            event.accepted = true
        }
    }

    // Workbench data projection. Every row is built from the existing snapshot,
    // system, or package queries; the visual reference contributes no data.
    property var selectedKeys: ["", "", "", ""]
    property bool inspectorOpen: false
    property bool optionsOpen: false
    property string stopConfirmKey: ""
    readonly property bool wideWorkbench: root.width >= 1060
    readonly property bool compactWorkbench: root.width < 680
    readonly property var currentRows: root.rowsForTab(root.activeView)
    readonly property var currentSelection: root.selectedRow(root.activeView, root.currentRows)

    function row(kind, key, title, detail, value, scope, icon, source) {
        return { kind, key, title, detail, value, scope, icon, source }
    }

    function rowsForTab(tab) {
        const rows = []
        const summary = root.snapshotData.summary || ({})
        if (tab === 0) {
            const failed = Number(root.systemData.failed_unit_count || 0)
            const jobs = root.jobCount()
            const local = root.localRuntimeCount()
            const upgrades = root.updateCount()
            const history = (root.snapshotData.job_history || []).length
            const firstRuntime = root.localRuntimes()[0]
            rows.push(root.row("overview-failed", "overview:failed", "Failed user services",
                !root.systemReady ? "Checking user services…"
                    : failed > 0 ? root.countText(failed, "unit") + " need review" : "No failed user services",
                !root.systemReady ? "Checking" : failed > 0 ? "Attention" : "Clear",
                !root.systemReady ? "—" : root.countText(failed, "unit"), "error_outline", null))
            rows.push(root.row("overview-jobs", "overview:jobs", "Running operations",
                root.snapshotReady ? root.countText(root.trackedProcessCount(), "tracked process") : "Checking current operations…",
                root.snapshotReady ? String(jobs) + " active" : "Checking", "Live", "progress_activity", null))
            rows.push(root.row("overview-runtime", "overview:runtime", "Local endpoints",
                !root.snapshotReady ? "Checking local listeners…"
                    : firstRuntime ? (firstRuntime.name || "Service") + " · " + (firstRuntime.bind || "local") : "No local listener detected",
                root.snapshotReady ? String(local) + " listening" : "Checking", "Local", "dns", null))
            rows.push(root.row("overview-packages", "overview:packages", "Repository upgrades",
                !root.snapshotReady ? "Checking package status…"
                    : root.officialUpgradeChecked && root.officialUpgradeRows.length > 0
                    ? root.officialUpgradeRows[0].name + " package update"
                    : upgrades !== "—" && Number(upgrades) > 0
                    ? root.countText(Number(upgrades), "package update") : "Local package database",
                upgrades === "—" ? "Not checked" : root.countText(Number(upgrades), "update"),
                "Available", "inventory_2", null))
            rows.push(root.row("overview-history", "overview:history", "Operation history",
                root.snapshotReady ? "Recent tasks and earlier runs" : "Checking operation history…",
                root.snapshotReady ? root.countText(history, "entry") : "Checking",
                "History", "history", null))
            return rows
        }
        if (tab === 1) {
            const runtimes = root.filteredLocalRuntimes().concat(root.filteredRemoteManagedRuntimes())
            for (const runtime of runtimes) {
                rows.push(root.row("runtime", "runtime:" + root.runtimeStableKey(runtime),
                    runtime.name || "Unnamed service",
                    runtime.managed_by_arch_remote
                        ? (runtime.bind || "Remote endpoint") + " · Arch Remote"
                        : (runtime.scope || "Local") + " · "
                            + (runtime.protocol && runtime.port
                                ? String(runtime.protocol).toUpperCase() + " " + runtime.port
                                : runtime.bind || "Endpoint unavailable"),
                    runtime.memory || "—", String(runtime.cpu ?? 0) + "% CPU",
                    runtime.icon || "dns", runtime))
            }
            return rows
        }
        if (tab === 2) {
            for (const job of root.filteredJobGroups()) {
                rows.push(root.row("job", "job:" + String(job.key || job.operation_id || job.root_pid),
                    root.jobDisplayName(job),
                    root.countText(job.process_count || 1, "process") + " · " + (job.memory || "—"),
                    String(job.cpu ?? 0) + "%", job.uptime || "Active",
                    "progress_activity", job))
            }
            for (const job of root.filteredJobHistory()) {
                rows.push(root.row("history", "history:" + String(job.key || job.operation_id || job.name),
                    root.jobDisplayName(job),
                    (job.project ? job.project + " · " : "") + (job.result_label || "Result unknown"),
                    String(job.cpu ?? 0) + "%", job.time_label || "History", "history", job))
            }
            return rows
        }
        for (const unit of root.systemData.failed_units || []) {
            rows.push(root.row("failed-unit", "unit:" + unit, String(unit),
                "Failed systemd --user unit", "Failed", "User", "error_outline", unit))
        }
        for (const pkg of root.officialUpgradeRows) {
            rows.push(root.row("package", "repo:" + pkg.name, pkg.name,
                pkg.installed + " → " + pkg.available, "Update", "Repo", "inventory_2", pkg))
        }
        for (const pkg of root.aurUpgradeRows) {
            rows.push(root.row("aur-package", "aur:" + pkg.name, pkg.name,
                pkg.installed + " → " + pkg.available, "Update", "AUR", "deployed_code", pkg))
        }
        const attention = root.snapshotData.attention || []
        for (let i = 0; i < attention.length; ++i) {
            const issue = attention[i]
            rows.push(root.row("attention", "attention:" + i + ":" + issue.title,
                issue.title || "System signal", issue.detail || "Review recommended",
                issue.severity || "Signal", "Monitor", issue.icon || "warning", issue))
        }
        return rows
    }

    function selectedRow(tab, rows) {
        if (rows.length === 0) return null
        const key = root.selectedKeys[tab]
        for (const item of rows) if (item.key === key) return item
        return rows[0]
    }

    function selectRow(entry) {
        const keys = root.selectedKeys.slice()
        keys[root.activeView] = entry.key
        root.selectedKeys = keys
        if (!root.wideWorkbench) root.inspectorOpen = true
    }

    function diagnosticCount() {
        const knownUpdates = root.systemData.updates?.total ?? -1
        return Number(root.systemData.failed_unit_count || 0)
            + Math.max(0, knownUpdates, root.officialUpgradeRows.length)
            + root.aurUpgradeRows.length + root.attentionCount()
    }

    function headerTitle(tab) {
        return ["System overview", "Services & endpoints", "Current jobs", "System diagnostics"][tab]
    }
    function headerDetail(tab) {
        return ["Choose an area to inspect. Items are grouped by work type.",
                "Local and remote-managed runtime connections.",
                "Active processes and recent operations.",
                "Failures and updates that need review."][tab]
    }
    function columnLabels(tab) {
        return tab === 1 ? ["SERVICE", "MEMORY", "CPU"]
            : tab === 2 ? ["OPERATION", "CPU", "AGE"]
            : tab === 3 ? ["CHECK", "STATE", "SOURCE"]
            : ["ITEM", "STATE", "SCOPE"]
    }

    function jobDisplayName(job) {
        const base = job.name || job.kind || "Operation"
        if (job.project && job.project !== base)
            return base + " · " + job.project
        const identity = String(job.operation_id || job.key || "").split(":")[0]
        const pid = Number(job.root_pid || job.pid || identity || 0)
        return pid > 0 ? base + " · PID " + pid : base
    }

    function inspectorHint(entry) {
        if (!entry) return ""
        if (entry.kind === "overview-failed")
            return "Open Diagnostics to inspect each failed user service."
        if (entry.kind === "job")
            return "This process group is active. Stop it only when its current work is no longer needed."
        if (entry.kind === "history")
            return "This operation is no longer running. Its result is based on the last observed state."
        if (entry.kind === "failed-unit")
            return "Inspect the journal and unit configuration before attempting a restart."
        if (entry.kind === "package" || entry.kind === "aur-package")
            return "Package versions come from the local update check."
        return ""
    }

    function inspectorHeading(entry) {
        if (!entry) return "Selection inspector"
        if (entry.kind === "runtime") return "Service inspector"
        if (entry.kind === "job" || entry.kind === "history") return "Operation inspector"
        if (entry.kind === "failed-unit") return "Unit inspector"
        if (entry.kind === "package" || entry.kind === "aur-package") return "Package inspector"
        if (entry.kind === "attention") return "Signal inspector"
        return "Selection inspector"
    }
    function inspectorStatus(entry) {
        if (!entry) return "Nothing selected"
        if (entry.kind === "runtime") return entry.source.managed_by_arch_remote
            ? "Managed by Arch Remote" : entry.source.status || "Listening"
        if (entry.kind === "job") return "Currently running"
        if (entry.kind === "history") return entry.source.result_label || "Ended"
        if (entry.kind === "failed-unit") return "Service failed"
        if (entry.kind === "package" || entry.kind === "aur-package") return "Update available"
        if (entry.kind === "attention") return entry.source.severity || "Attention"
        return entry.value
    }
    function inspectorFields(entry) {
        if (!entry) return []
        const item = entry.source || ({})
        if (entry.kind === "runtime") return [
            { label: "Scope", value: item.scope || "—" },
            { label: "Endpoint", value: item.bind || "—" },
            { label: "PID", value: String(item.pid || "—") },
            { label: "Uptime", value: item.uptime || "—" },
            { label: "Directory", value: item.cwd || "—" }
        ]
        if (entry.kind === "job" || entry.kind === "history") return [
            { label: "Processes", value: String(item.process_count || 1) },
            { label: entry.kind === "job" ? "Elapsed" : "Finished", value: item.uptime || item.time_label || "—" },
            { label: "Project", value: item.project || "—" }
        ]
        if (entry.kind === "failed-unit") return [
            { label: "Type", value: "User service" },
            { label: "State", value: "Failed" },
            { label: "Other failures", value: String(Math.max(0, (root.systemData.failed_unit_count || 0) - 1)) }
        ]
        if (entry.kind === "package" || entry.kind === "aur-package") return [
            { label: "Source", value: entry.kind === "package" ? "Repository" : "AUR" },
            { label: "Installed", value: item.installed || "—" },
            { label: "Available", value: item.available || "—" }
        ]
        if (entry.kind === "attention") return [
            { label: "Severity", value: item.severity || "Signal" },
            { label: "Source", value: "Operations monitor" }
        ]
        if (entry.kind === "overview-failed") return [
            { label: "Scope", value: "Systemd user" },
            { label: "Units", value: root.countText(root.systemData.failed_unit_count, "failed") },
            { label: "Severity", value: entry.value }
        ]
        return [
            { label: "State", value: entry.value },
            { label: "Scope", value: entry.scope }
        ]
    }
    function inspectorActions(entry) {
        if (!entry) return []
        if (entry.kind === "runtime") {
            const runtime = entry.source
            const actions = []
            if (runtime.managed_by_arch_remote) actions.push({label:"Open Remote", icon:"shield", action:"remote"})
            else {
                if (runtime.url) actions.push({label:"Open", icon:"open_in_new", action:"open"})
                actions.push({label:"Terminal", icon:"terminal", action:"terminal"})
            }
            actions.push({label:runtime.url ? "Copy URL" : "Copy endpoint", icon:"content_copy", action:"copy"})
            if (!runtime.managed_by_arch_remote) {
                actions.push({label:"Files", icon:"folder_open", action:"files"})
                actions.push({label:"Editor", icon:"code", action:"editor"})
            }
            if (runtime.pin_key) actions.push({label:runtime.pinned ? "Unpin service" : "Pin service", icon:"keep", action:"pin"})
            if (!runtime.managed_by_arch_remote && runtime.operations_stop_allowed)
                actions.push({label:root.stopConfirmKey === entry.key ? "Confirm stop" : "Stop process", icon:"stop", action:"stop-runtime", danger:true})
            return actions
        }
        if (entry.kind === "job" && entry.source.root_pid > 0)
            return [{label:root.stopConfirmKey === entry.key ? "Confirm stop" : "Stop job", icon:"stop", action:"stop-job", danger:true}]
        if (entry.kind === "overview-failed") return [
            {label:"Open diagnostics", icon:"error_outline", action:"diagnostics"},
            {label:"Show runtimes", icon:"dns", action:"runtime"}
        ]
        if (entry.kind === "overview-runtime") return [{label:"Show runtimes", icon:"dns", action:"runtime"}]
        if (entry.kind === "overview-jobs" || entry.kind === "overview-history")
            return [{label:"Open jobs", icon:"progress_activity", action:"jobs"}]
        if (entry.kind === "overview-packages") return [{label:"Open diagnostics", icon:"inventory_2", action:"diagnostics"}]
        if (entry.kind === "aur-package") return [{label:"Scan AUR", icon:"refresh", action:"aur"}]
        return [{label:"Refresh checks", icon:"refresh", action:"refresh"}]
    }
    function performInspectorAction(action, entry) {
        if (!entry) return
        const item = entry.source || ({})
        if (action === "diagnostics") { root.switchTab(3); return }
        if (action === "runtime") { root.switchTab(1); return }
        if (action === "jobs") { root.switchTab(2); return }
        if (action === "refresh") { root.refreshAll(); return }
        if (action === "aur") { root.requestAurUpgrades(); return }
        if (action === "remote") { root.openArchRemote(); return }
        if (action === "open") { root.runAction(["open", item.url]); return }
        if (action === "terminal") { root.runAction(["terminal", String(item.pid), String(item.start_ticks || 0)]); return }
        if (action === "copy") {
            root.runAction(["copy-runtime", String(item.pid), String(item.start_ticks || 0), item.url ? "url" : "endpoint"])
            return
        }
        if (action === "files") { root.runAction(["open-folder", String(item.pid), String(item.start_ticks || 0)]); return }
        if (action === "editor") { root.runAction(["open-editor", String(item.pid), String(item.start_ticks || 0)]); return }
        if (action === "pin") { root.runAction(["toggle-pin", item.pin_key]); return }
        if (action === "stop-runtime" || action === "stop-job") {
            if (root.stopConfirmKey !== entry.key) {
                root.stopConfirmKey = entry.key
                stopConfirmation.restart()
                return
            }
            root.stopConfirmKey = ""
            stopConfirmation.stop()
            if (action === "stop-runtime")
                root.runAction(["stop", String(item.pid), String(item.start_ticks || 0), String(item.pin_key || "")])
            else
                root.runAction(["stop-operation", String(item.root_pid), String(item.root_start_ticks || 0)])
        }
    }
    Timer { id: stopConfirmation; interval: 3000; onTriggered: root.stopConfirmKey = "" }

    component WorkbenchAction: RippleButton {
        id: actionButton
        property string label: ""
        property string symbol: ""
        property bool danger: false
        property bool pinAction: false
        property bool plain: false
        property bool leftAligned: false
        implicitHeight: 30
        implicitWidth: Math.max(62, actionText.implicitWidth + (symbol ? 35 : 22))
        buttonRadius: Appearance.radius.control
        colBackground: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.91)
            : pinAction ? ColorUtils.transparentize(Appearance.colors.colSecondary, 0.90) : "transparent"
        colBackgroundHover: danger ? ColorUtils.transparentize(Appearance.colors.colError, 0.82)
            : pinAction ? ColorUtils.transparentize(Appearance.colors.colSecondary, 0.82)
            : Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        background: Rectangle {
            radius: actionButton.buttonRadius
            color: actionButton.buttonColor
            border.width: actionButton.plain ? 0 : 1
            border.color: actionButton.danger
                ? ColorUtils.transparentize(Appearance.colors.colError, 0.58)
                : actionButton.pinAction
                ? ColorUtils.transparentize(Appearance.colors.colSecondary, 0.62)
                : Appearance.colors.colLayer0Border
        }
        Accessible.role: Accessible.Button
        Accessible.name: label
        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: actionButton.leftAligned ? 10 : 0
            anchors.rightMargin: actionButton.leftAligned ? 7 : 0
            spacing: 6
            Item { Layout.fillWidth: !actionButton.leftAligned }
            MaterialSymbol { visible: actionButton.symbol.length > 0; text: actionButton.symbol; iconSize: 14;
                color: actionButton.danger ? Appearance.colors.colError : actionButton.pinAction
                    ? Appearance.colors.colSecondary : actionButton.plain
                    ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0 }
            StyledText { id: actionText; text: actionButton.label; font.pixelSize: 12;
                Layout.maximumWidth: Math.max(0, actionButton.width - 34);
                elide: Text.ElideRight;
                color: actionButton.danger ? Appearance.colors.colError : actionButton.pinAction
                    ? Appearance.colors.colSecondary : actionButton.plain
                    ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0 }
            Item { Layout.fillWidth: true }
        }
    }

    component WorkbenchNavItem: RippleButton {
        id: nav
        required property int tabIndex
        readonly property bool chosen: root.selectedTab === tabIndex
        implicitHeight: 39
        Layout.fillWidth: true
        buttonRadius: Appearance.radius.control
        colBackground: chosen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88) : "transparent"
        colBackgroundHover: chosen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80) : Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        Accessible.role: Accessible.Button
        Accessible.name: root.tabName(tabIndex)
        Accessible.checked: chosen
        onClicked: root.switchTab(tabIndex)
        background: Rectangle {
            radius: nav.buttonRadius
            color: nav.buttonColor
            border.width: nav.chosen ? 1 : 0
            border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
        }
        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.compactWorkbench ? 0 : 12
            anchors.rightMargin: root.compactWorkbench ? 0 : 11
            spacing: 11
            MaterialSymbol {
                Layout.alignment: root.compactWorkbench ? Qt.AlignHCenter : Qt.AlignVCenter
                Layout.preferredWidth: root.compactWorkbench ? nav.width : 17
                horizontalAlignment: Text.AlignHCenter
                text: root.tabIcon(nav.tabIndex)
                iconSize: 17
                color: nav.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                visible: !root.compactWorkbench
                Layout.fillWidth: true
                text: root.tabName(nav.tabIndex)
                font.pixelSize: 13
                color: nav.chosen ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
            }
            StyledText {
                visible: !root.compactWorkbench && nav.tabIndex > 0
                text: nav.tabIndex === 1 ? String(root.runtimeCount())
                    : nav.tabIndex === 2 ? String(root.jobCount()) : String(root.diagnosticCount())
                font.pixelSize: 10
                color: Appearance.colors.colSubtext
            }
        }
    }

    component WorkbenchRow: Rectangle {
        id: resultRow
        required property var entry
        property bool chosen: root.currentSelection && root.currentSelection.key === entry.key
        width: ListView.view ? ListView.view.width : 0
        height: 57
        color: chosen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.90)
            : pointer.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
        Rectangle { anchors.left: parent.left; width: 3; height: parent.height;
            visible: resultRow.chosen; color: Appearance.colors.colPrimary }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1;
            color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.45) }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: centerPane.rowInset
            anchors.rightMargin: centerPane.rowInset
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 12
                MaterialSymbol {
                    text: resultRow.entry.icon
                    iconSize: 17
                    color: resultRow.entry.kind === "failed-unit" || resultRow.entry.kind === "overview-failed"
                        ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    StyledText { Layout.fillWidth: true; text: resultRow.entry.title;
                        color: Appearance.colors.colOnLayer0; font.pixelSize: 13;
                        font.weight: Font.Medium; elide: Text.ElideRight }
                    StyledText { Layout.fillWidth: true; text: resultRow.entry.detail;
                        color: Appearance.colors.colSubtext; font.pixelSize: 11;
                        elide: Text.ElideRight }
                }
            }
            StyledText {
                Layout.preferredWidth: centerPane.valueWidth
                Layout.maximumWidth: centerPane.valueWidth
                horizontalAlignment: Text.AlignLeft
                text: resultRow.entry.value
                color: Appearance.colors.colSubtext
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            StyledText {
                visible: centerPane.showScopeColumn
                Layout.preferredWidth: centerPane.scopeWidth
                Layout.maximumWidth: centerPane.scopeWidth
                text: resultRow.entry.scope
                color: Appearance.colors.colSubtext
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectRow(resultRow.entry)
        }
    }

    component SelectionInspector: Rectangle {
        id: inspector
        property var entry: null
        property bool overlay: false
        readonly property bool healthy: entry && (entry.kind === "runtime" || entry.kind === "job")
        readonly property color statusColor: healthy
            ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Config.options.bar.vertical || Config.options.bar.bottom
                    ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78)
                    : "transparent"
            }
            GradientStop { position: 0.14; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78) }
            GradientStop { position: 0.86; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78) }
            GradientStop {
                position: 1
                color: !Config.options.bar.vertical && Config.options.bar.bottom
                    ? "transparent"
                    : ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78)
            }
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 22
            anchors.bottomMargin: 18
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                StyledText { Layout.fillWidth: true; text: root.inspectorHeading(inspector.entry).toUpperCase();
                    font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2;
                    color: Appearance.colors.colSubtext; elide: Text.ElideRight }
                WorkbenchAction { visible: inspector.overlay; symbol: "close"; label: "Close";
                    onClicked: root.inspectorOpen = false }
            }
            ScrollView {
                id: inspectorScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ColumnLayout {
                    width: inspectorScroll.availableWidth
                    spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        StyledText { Layout.fillWidth: true; text: inspector.entry ? inspector.entry.title : "No selection";
                            font.pixelSize: 17; font.weight: Font.DemiBold;
                            color: Appearance.colors.colOnLayer0; wrapMode: Text.WordWrap }
                        StyledText { Layout.fillWidth: true; text: inspector.entry ? inspector.entry.detail : "Choose an item to inspect.";
                            font.pixelSize: 12; color: Appearance.colors.colSubtext;
                            wrapMode: Text.WordWrap }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 43
                        radius: Appearance.radius.control
                        color: ColorUtils.transparentize(inspector.statusColor, 0.88)
                        border.width: 1
                        border.color: ColorUtils.transparentize(inspector.statusColor, 0.70)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            spacing: 8
                            MaterialSymbol { text: inspector.entry ? inspector.entry.icon : "info";
                                iconSize: 17; color: inspector.statusColor }
                            StyledText { Layout.fillWidth: true; text: root.inspectorStatus(inspector.entry);
                                font.pixelSize: 12; color: inspector.statusColor;
                                elide: Text.ElideRight }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: "DETAILS"; font.pixelSize: 10;
                            font.weight: Font.DemiBold; font.letterSpacing: 1.2;
                            color: Appearance.colors.colSubtext; Layout.bottomMargin: 4 }
                        Repeater {
                            model: root.inspectorFields(inspector.entry)
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 31
                                    spacing: 8
                                    StyledText { Layout.fillWidth: true; text: modelData.label;
                                        font.pixelSize: 12; color: Appearance.colors.colSubtext;
                                        elide: Text.ElideRight }
                                    StyledText { text: modelData.value; font.pixelSize: 12;
                                        font.weight: Font.Medium; color: Appearance.colors.colOnLayer0;
                                        Layout.maximumWidth: inspector.width * 0.52;
                                        elide: Text.ElideMiddle }
                                }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1;
                                    color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.45) }
                            }
                        }
                    }
                    StyledText {
                        visible: root.inspectorHint(inspector.entry).length > 0
                        Layout.fillWidth: true
                        text: root.inspectorHint(inspector.entry)
                        font.pixelSize: 12
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 7
                rowSpacing: 7
                Repeater {
                    model: root.inspectorActions(inspector.entry)
                    delegate: WorkbenchAction {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: (inspector.width - 43) / 2
                        Layout.columnSpan: index === root.inspectorActions(inspector.entry).length - 1
                            && root.inspectorActions(inspector.entry).length % 2 === 1 ? 2 : 1
                        label: modelData.label
                        symbol: modelData.icon
                        danger: modelData.danger === true
                        pinAction: modelData.action === "pin"
                        enabled: !actionProcess.running
                        onClicked: root.performInspectorAction(modelData.action, inspector.entry)
                    }
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            id: navigationPane
            Layout.preferredWidth: root.compactWorkbench ? 62 : root.wideWorkbench ? 202 : 170
            Layout.minimumWidth: Layout.preferredWidth
            Layout.maximumWidth: Layout.preferredWidth
            Layout.fillHeight: true
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Config.options.bar.vertical || Config.options.bar.bottom
                        ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78)
                        : "transparent"
                }
                GradientStop { position: 0.14; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78) }
                GradientStop { position: 0.86; color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78) }
                GradientStop {
                    position: 1
                    color: !Config.options.bar.vertical && Config.options.bar.bottom
                        ? "transparent"
                        : ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78)
                }
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: root.compactWorkbench ? 7 : 11
                anchors.rightMargin: root.compactWorkbench ? 7 : 11
                anchors.topMargin: root.compactWorkbench ? 15 : 22
                anchors.bottomMargin: 15
                spacing: 5
                StyledText { visible: !root.compactWorkbench; text: "WORKSPACE";
                    Layout.leftMargin: 11; Layout.bottomMargin: 7;
                    font.pixelSize: 10; font.letterSpacing: 1.1;
                    color: Appearance.colors.colSubtext }
                Repeater {
                    model: 4
                    delegate: WorkbenchNavItem { required property int index; tabIndex: index }
                }
                StyledText { visible: !root.compactWorkbench; text: "AVAILABLE SOURCES";
                    Layout.leftMargin: 11; Layout.topMargin: 14; Layout.bottomMargin: 3;
                    font.pixelSize: 10; font.letterSpacing: 1.1;
                    color: Appearance.colors.colSubtext }
                Repeater {
                    model: [
                        {name:"This computer", icon:"computer", tab:1},
                        {name:"Arch packages", icon:"inventory_2", tab:3},
                        {name:"Activity archive", icon:"history", tab:2}
                    ]
                    delegate: WorkbenchAction {
                        required property var modelData
                        visible: !root.compactWorkbench
                        Layout.fillWidth: true
                        label: modelData.name
                        symbol: modelData.icon
                        plain: true
                        leftAligned: true
                        onClicked: root.switchTab(modelData.tab)
                    }
                }
                Item { Layout.fillHeight: true }
                Rectangle {
                    visible: !root.compactWorkbench
                    Layout.fillWidth: true
                    implicitHeight: 72
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 5
                        StyledText { text: !root.snapshotReady || !root.systemReady ? "● Checking system"
                                : root.diagnosticCount() > 0 ? "● Needs attention" : "● System clear";
                            color: root.diagnosticCount() > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0;
                            font.pixelSize: 11 }
                        StyledText { Layout.fillWidth: true;
                            text: root.countText(root.systemData.failed_unit_count, "failed unit") + " · "
                                + root.countText(root.attentionCount(), "signal");
                            font.pixelSize: 10; color: Appearance.colors.colSubtext;
                            elide: Text.ElideRight }
                    }
                }
            }
        }
        Item {
            id: centerPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            readonly property int rowInset: width < 500 ? 12 : 24
            readonly property int valueWidth: width < 500 ? 68 : 95
            readonly property int scopeWidth: 80
            readonly property bool showScopeColumn: width >= 440
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                opacity: root.contentShown ? 1 : 0
                Behavior on opacity { MotionAnim { type: MotionAnim.DefaultEffects } }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 76
                    color: "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1;
                        color: Appearance.colors.colLayer0Border }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: centerPane.rowInset
                        anchors.rightMargin: centerPane.rowInset
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText { Layout.fillWidth: true; text: root.headerTitle(root.activeView);
                                font.pixelSize: 19; font.weight: Font.DemiBold;
                                color: Appearance.colors.colOnLayer0; elide: Text.ElideRight }
                            StyledText { Layout.fillWidth: true; text: root.headerDetail(root.activeView);
                                font.pixelSize: 11; color: Appearance.colors.colSubtext;
                                elide: Text.ElideRight }
                        }
                        WorkbenchAction { label: root.compactWorkbench ? "Options" : "View options";
                            symbol: "tune"; onClicked: root.optionsOpen = !root.optionsOpen }
                    }
                }
                Rectangle {
                    visible: root.optionsOpen
                    Layout.fillWidth: true
                    implicitHeight: optionsContent.implicitHeight + 16
                    color: Appearance.colors.colLayer1
                    ColumnLayout {
                        id: optionsContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: centerPane.rowInset
                        anchors.rightMargin: centerPane.rowInset
                        anchors.topMargin: 8
                        spacing: 7
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            TextField {
                                visible: root.activeView === 1 || root.activeView === 2
                                Layout.fillWidth: true
                                implicitHeight: 32
                                text: root.activeView === 1 ? root.runtimeQuery : root.jobQuery
                                placeholderText: root.activeView === 1 ? "Search services…" : "Search jobs and history…"
                                color: Appearance.colors.colOnLayer0
                                placeholderTextColor: Appearance.colors.colSubtext
                                font.pixelSize: 11
                                leftPadding: 10
                                background: Rectangle { radius: Appearance.radius.control;
                                    color: Appearance.colors.colLayer0;
                                    border.width: 1; border.color: Appearance.colors.colLayer0Border }
                                onTextEdited: {
                                    if (root.activeView === 1) root.runtimeQuery = text
                                    else root.jobQuery = text
                                }
                            }
                            WorkbenchAction { label: "Refresh"; symbol: "refresh";
                                onClicked: root.refreshAll() }
                            WorkbenchAction { visible: root.activeView === 3; label: "Scan AUR";
                                symbol: "search"; onClicked: root.requestAurUpgrades() }
                        }
                        RowLayout {
                            visible: root.activeView === 1
                            Layout.fillWidth: true
                            spacing: 3
                            Repeater {
                                model: ["all", "local", "exposed", "pinned"]
                                delegate: WorkbenchAction {
                                    required property var modelData
                                    label: modelData[0].toUpperCase() + modelData.slice(1)
                                    onClicked: root.runtimeFilter = modelData
                                    background: Rectangle { radius: Appearance.radius.control;
                                        color: root.runtimeFilter === modelData
                                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85) : "transparent" }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    visible: root.snapshotError.length > 0 || root.systemError.length > 0
                    Layout.fillWidth: true
                    implicitHeight: errorLabel.implicitHeight + 18
                    color: ColorUtils.transparentize(Appearance.colors.colErrorContainer, 0.52)
                    StyledText {
                        id: errorLabel
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: centerPane.rowInset
                        anchors.rightMargin: centerPane.rowInset
                        text: root.snapshotError || root.systemError
                        color: Appearance.colors.colOnErrorContainer
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.55)
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1;
                        color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, 0.45) }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: centerPane.rowInset
                        anchors.rightMargin: centerPane.rowInset
                        spacing: 10
                        StyledText { Layout.fillWidth: true; text: root.columnLabels(root.activeView)[0];
                            font.pixelSize: 10; font.letterSpacing: 0.7;
                            color: Appearance.colors.colSubtext }
                        StyledText { Layout.preferredWidth: centerPane.valueWidth;
                            text: root.columnLabels(root.activeView)[1];
                            font.pixelSize: 10; font.letterSpacing: 0.7;
                            color: Appearance.colors.colSubtext }
                        StyledText { visible: centerPane.showScopeColumn;
                            Layout.preferredWidth: centerPane.scopeWidth;
                            text: root.columnLabels(root.activeView)[2];
                            font.pixelSize: 10; font.letterSpacing: 0.7;
                            color: Appearance.colors.colSubtext }
                    }
                }
                ListView {
                    id: workbenchList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.currentRows
                    delegate: WorkbenchRow { required property var modelData; entry: modelData }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    StyledText {
                        anchors.centerIn: parent
                        visible: workbenchList.count === 0
                        text: root.loading || root.systemLoading || root.officialUpgradeLoading
                            ? "Checking live system data…"
                            : root.snapshotError || root.systemError
                            ? "Live data is unavailable. Use View options to retry."
                            : root.activeView === 1 ? "No matching services or endpoints."
                            : root.activeView === 2 ? "No current or recent jobs."
                            : "No diagnostics to review."
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 12
                    }
                }
            }
            SelectionInspector {
                visible: !root.wideWorkbench && root.inspectorOpen
                anchors.fill: parent
                z: 5
                overlay: true
                entry: root.currentSelection
            }
        }
        SelectionInspector {
            visible: root.wideWorkbench
            Layout.preferredWidth: root.wideWorkbench ? 265 : 0
            Layout.minimumWidth: Layout.preferredWidth
            Layout.maximumWidth: Layout.preferredWidth
            Layout.fillHeight: true
            entry: root.currentSelection
        }
    }

    Rectangle {
        visible: root.toastMessage.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        z: 20
        implicitHeight: 42
        radius: Appearance.radius.control
        color: root.toastError ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 7
            MaterialSymbol { text: root.toastError ? "error" : "check_circle"; iconSize: 17;
                color: root.toastError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer }
            StyledText { Layout.fillWidth: true; text: root.toastMessage;
                color: root.toastError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer;
                font.pixelSize: 12; elide: Text.ElideRight }
        }
    }
}
