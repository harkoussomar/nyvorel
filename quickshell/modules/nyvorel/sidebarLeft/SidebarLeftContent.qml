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
    property bool loading: false
    property bool systemLoading: false
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
        root.showToast(
            `Operations backend/UI mismatch (schema ${schema}, contract ${contract})`,
            true
        )
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
                    root.pruneExpandedRuntimeKeys(payload.runtimes || [])
                } catch (error) {
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
                    root.requestSnapshot()
                } catch (error) {
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

    component HeaderIconButton: RippleButton {
        id: headerButton

        property string iconName: ""
        property string tooltipText: ""
        property bool active: false

        implicitWidth: 32
        implicitHeight: 32
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: tooltipText

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control
        colBackground:
            active
                ? (Appearance.colors.colSecondaryContainer)
                : "transparent"
        colBackgroundHover:
              (active
                 ? Appearance.colors.colSecondaryContainerHover
                 : Appearance.colors.colLayer2Hover)
        colRipple:
             (active
                ? Appearance.colors.colSecondaryContainerActive
                : Appearance.colors.colLayer2Active)

        background: Rectangle {
            radius: headerButton.buttonRadius
            color: headerButton.buttonColor
            border.width: (headerButton.tabbedTo? 2 : 0)
            border.color:
                 Appearance.colors.colSecondary
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: headerButton.iconName
            iconSize: 17
            fill: headerButton.active ? 1 : 0
            color:
                false && headerButton.active
                    ? Appearance.colors.colPrimary
                    : headerButton.active
                        ? Appearance.colors.colOnSecondaryContainer
                        : headerButton.hovered
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
        }

        StyledToolTip {
            extraVisibleCondition:
                parent.hovered === true
            delay: 450
            text: headerButton.tooltipText
        }
    }

    component AtlasSurface: Rectangle {
        Layout.fillWidth: true
        radius: 13
        color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.62)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    component OpsKicker: StyledText {
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.letterSpacing: 1.15
        font.weight: Font.DemiBold
    }

    // Compact Operations: shared sections remain theme-aware in all four styles.
    component SectionTitle: RowLayout {
        id: section

        property string title: ""
        property string detail: ""
        property string iconName: ""

        Layout.fillWidth: true
        spacing: 7
        implicitHeight: 30

        MaterialSymbol {
            visible: section.iconName.length > 0
            text: section.iconName
            iconSize: 16
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            text: section.title
            color:
                 Appearance.colors.colSubtext
            font {
                pixelSize: Appearance.font.pixelSize.small
                weight: Font.DemiBold
            }
        }

        StyledText {
            visible: section.detail.length > 0
            text: section.detail
            color: Appearance.colors.colSubtext
            font.pixelSize:
                Appearance.font.pixelSize.smallest
        }
    }

    component MetricTile: Rectangle {
        id: metric

        property string iconName: ""
        property string value: "0"
        property string label: ""
        property bool attention: false

        Layout.fillWidth: true
        implicitHeight: 98

        radius: 12
        color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.72)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                MaterialSymbol {
                    text: metric.iconName
                    iconSize: 15
                    color: metric.attention ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: metric.value
                    color: Appearance.colors.colOnLayer1
                    font {
                        pixelSize: 28
                        weight: Font.DemiBold
                    }
                    horizontalAlignment: Text.AlignLeft
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: metric.label
                color: Appearance.colors.colSubtext
                font.pixelSize:
                    Appearance.font.pixelSize.smallest
                elide: Text.ElideRight
            }
        }
    }

    component SearchField: TextField {
        id: searchField

        property string iconName: "search"

        Layout.fillWidth: true
        implicitHeight: 34
        leftPadding: 34
        rightPadding: 12
        topPadding: 0
        bottomPadding: 0
        color: Appearance.colors.colOnLayer1
        placeholderTextColor: Appearance.colors.colSubtext
        selectionColor: Appearance.colors.colPrimary
        selectedTextColor: Appearance.colors.colOnPrimary
        font.pixelSize: Appearance.font.pixelSize.small
        activeFocusOnTab: true
        Accessible.role: Accessible.EditableText
        Accessible.name: placeholderText

        background: Rectangle {
            radius: Appearance.radius.control
            color:
                searchField.activeFocus
                    ? Appearance.colors.colLayer2
                    : Appearance.colors.colLayer1
            border.width: searchField.activeFocus ? 1 : 0
            border.color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.left: parent.left
                anchors.leftMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                text: searchField.iconName
                iconSize: 16
                color:
                    searchField.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
            }
        }
    }

    component FilterChip: RippleButton {
        id: chip

        property string label: ""
        property bool active: false

        implicitHeight: 27
        implicitWidth: chipText.implicitWidth + 20
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.checked: active

        buttonRadius: Appearance.radius.full
        buttonRadiusPressed: Appearance.radius.full
        colBackground:
            active
                ? Appearance.colors.colSecondaryContainer
                : Appearance.colors.colLayer1
        colBackgroundHover:
            active
                ? Appearance.colors.colSecondaryContainerHover
                : Appearance.colors.colLayer2Hover
        colRipple:
            active
                ? Appearance.colors.colSecondaryContainerActive
                : Appearance.colors.colLayer2Active

        contentItem: StyledText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color:
                chip.active
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colSubtext
            font {
                pixelSize: Appearance.font.pixelSize.smallest
                weight: chip.active ? Font.DemiBold : Font.Medium
            }
        }
    }

    component SmallAction: RippleButton {
        id: action

        property string iconName: ""
        property string label: ""
        property bool danger: false

        implicitHeight: 32
        implicitWidth:
            Math.max(
                62,
                actionText.implicitWidth + 34
            )

        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed:
            Appearance.radius.control

        colBackground:
            danger
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colLayer2
        colBackgroundHover:
            danger
                ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colLayer2Hover
        colRipple:
            danger
                ? Appearance.colors.colErrorContainerActive
                : Appearance.colors.colLayer2Active

        contentItem: Row {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter:
                    parent.verticalCenter
                text: action.iconName
                iconSize: 15
                color:
                    action.danger
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnLayer1
            }

            StyledText {
                id: actionText
                anchors.verticalCenter:
                    parent.verticalCenter
                text: action.label
                color:
                    action.danger
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnLayer1
                font {
                    pixelSize:
                        Appearance.font.pixelSize.smallest
                    weight: Font.DemiBold
                }
            }
        }
    }

    component RuntimeCard: Rectangle {
        id: runtimeCard

        required property var runtime
        property bool expanded: false
        property bool stopArmed: false

        signal openRequested()
        signal terminalRequested()
        signal stopRequested()
        signal pinRequested()
        signal expansionToggleRequested()
        signal remoteRequested()
        signal copyRequested(string mode)
        signal folderRequested()
        signal editorRequested()

        Layout.fillWidth: true
        implicitHeight: expanded ? 224 : 122

        radius: 11
        color: runtime.pinned
            ? ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer1, 0.55)
            : ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: runtime.pinned ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        clip: true

        Behavior on implicitHeight {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }

        Timer {
            interval: 3000
            running: runtimeCard.stopArmed
            repeat: false
            onTriggered: runtimeCard.stopArmed = false
        }

        ColumnLayout {
            anchors {
                fill: parent
                margins: 9
            }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Appearance.radius.control
                    color:
                        runtime.managed_by_arch_remote
                            ? Appearance.colors.colLayer2
                            : runtime.exposed
                                ? Appearance.colors.colSecondaryContainer
                                : Appearance.colors.colLayer2

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text:
                            runtime.icon && runtime.icon.length > 0
                                ? runtime.icon
                                : runtime.managed_by_arch_remote
                                    ? runtime.managed_icon
                                    : runtime.exposed
                                        ? "public"
                                        : "dns"
                        iconSize: 18
                        color:
                            runtime.exposed && !runtime.managed_by_arch_remote
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: runtime.name
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                        font {
                            pixelSize: Appearance.font.pixelSize.small
                            weight: Font.DemiBold
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text:
                            runtime.managed_by_arch_remote
                                ? `${runtime.bind} · managed by Arch Remote`
                                : `${runtime.kind} · ${runtime.scope} · :${runtime.port}`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideMiddle
                    }
                }

                Rectangle {
                    implicitWidth: runtimeStatusText.implicitWidth + 14
                    implicitHeight: 22
                    radius: Appearance.radius.full
                    color:
                        runtime.managed_by_arch_remote
                            ? Appearance.colors.colLayer2
                            : runtime.exposed
                                ? Appearance.colors.colSecondaryContainer
                                : Appearance.colors.colLayer2

                    StyledText {
                        id: runtimeStatusText
                        anchors.centerIn: parent
                        text:
                            runtime.managed_by_arch_remote
                                ? "Remote"
                                : runtime.exposed
                                    ? runtime.scope
                                    : runtime.status
                        color:
                            runtime.exposed && !runtime.managed_by_arch_remote
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colSubtext
                        font {
                            pixelSize: Appearance.font.pixelSize.smallest
                            weight: Font.DemiBold
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: `${runtime.cpu}% CPU · ${runtime.memory} · ${runtime.uptime}`
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
                opacity: 0.72
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                SmallAction {
                    visible: runtime.managed_by_arch_remote
                    iconName: "shield"
                    label: "Open Remote"
                    onClicked: runtimeCard.remoteRequested()
                }

                SmallAction {
                    visible: !runtime.managed_by_arch_remote && runtime.url.length > 0
                    iconName: "open_in_new"
                    label: "Open"
                    onClicked: runtimeCard.openRequested()
                }

                SmallAction {
                    visible: !runtime.managed_by_arch_remote
                    iconName: "terminal"
                    label: "Terminal"
                    onClicked: runtimeCard.terminalRequested()
                }

                Item { Layout.fillWidth: true }

                HeaderIconButton {
                    iconName: "keep"
                    tooltipText: runtime.pinned ? "Unpin runtime" : "Pin runtime"
                    active: runtime.pinned
                    onClicked: runtimeCard.pinRequested()
                }

                HeaderIconButton {
                    iconName: runtimeCard.expanded ? "expand_less" : "expand_more"
                    tooltipText: runtimeCard.expanded ? "Hide details" : "Show details"
                    onClicked: runtimeCard.expansionToggleRequested()
                }

                SmallAction {
                    visible: !runtime.managed_by_arch_remote && runtime.operations_stop_allowed
                    iconName: "stop"
                    label: runtimeCard.stopArmed ? "Confirm" : "Stop"
                    danger: runtimeCard.stopArmed
                    onClicked: {
                        if (!runtimeCard.stopArmed) {
                            runtimeCard.stopArmed = true
                            return
                        }
                        runtimeCard.stopArmed = false
                        runtimeCard.stopRequested()
                    }
                }
            }

            ColumnLayout {
                visible: runtimeCard.expanded
                Layout.fillWidth: true
                spacing: 3

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `PID ${runtime.pid} · ${runtime.protocol || "tcp"} · ${runtime.bind} · ${runtime.scope}`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: runtime.cwd.length > 0 ? runtime.cwd : "Working directory unavailable"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideMiddle
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SmallAction {
                        iconName: "content_copy"
                        label: runtime.url.length > 0 ? "Copy URL" : "Copy endpoint"
                        onClicked:
                            runtimeCard.copyRequested(
                                runtime.url.length > 0 ? "url" : "endpoint"
                            )
                    }

                    SmallAction {
                        visible: !runtime.managed_by_arch_remote
                        iconName: "folder_open"
                        label: "Files"
                        onClicked: runtimeCard.folderRequested()
                    }

                    SmallAction {
                        visible: !runtime.managed_by_arch_remote
                        iconName: "code"
                        label: "Editor"
                        onClicked: runtimeCard.editorRequested()
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    component JobGroupRow: Rectangle {
        id: jobGroupRow

        required property var job
        property bool historical: false
        property bool stopArmed: false

        signal stopRequested()

        Layout.fillWidth: true
        implicitHeight: historical ? 43 : 59
        radius: 10
        color: historical ? "transparent"
            : Appearance.colors.colLayer1
        border.width: historical ? 0 : 1
        border.color: Appearance.colors.colLayer0Border

        Timer {
            interval: 3000
            running: jobGroupRow.stopArmed
            repeat: false
            onTriggered: jobGroupRow.stopArmed = false
        }

        RowLayout {
            anchors {
                fill: parent
                margins: historical ? 6 : 9
            }
            spacing: 8

            MaterialSymbol {
                text: historical ? "history" : "progress_activity"
                iconSize: 16
                color: historical ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text:
                        job.project && job.project.length > 0
                            ? `${job.name} · ${job.project}`
                            : job.name
                    color: Appearance.colors.colOnLayer1
                    font {
                        pixelSize: Appearance.font.pixelSize.small
                        weight: historical ? Font.Normal : Font.DemiBold
                    }
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text:
                        historical
                            ? `${job.time_label || "Ended"} · ${job.result_label || "Result unknown"}`
                            : `${job.process_count || 1} ${(job.process_count || 1) === 1 ? "process" : "processes"} · ${job.cpu}% CPU · ${job.memory} · ${job.uptime}`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideMiddle
                }
            }

            SmallAction {
                visible: !historical && job.root_pid > 0
                iconName: "stop"
                label: jobGroupRow.stopArmed ? "Confirm" : "Stop"
                danger: jobGroupRow.stopArmed
                onClicked: {
                    if (!jobGroupRow.stopArmed) {
                        jobGroupRow.stopArmed = true
                        return
                    }
                    jobGroupRow.stopArmed = false
                    jobGroupRow.stopRequested()
                }
            }
        }
    }

    component AttentionRow: Rectangle {
        id: attentionRow

        required property var issue

        Layout.fillWidth: true
        implicitHeight: 59
        radius: 10
        color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        RowLayout {
            anchors {
                fill: parent
                margins: 9
            }
            spacing: 9

            MaterialSymbol {
                text: issue.icon
                iconSize: 17
                color:
                    issue.severity === "critical"
                        ? Appearance.colors.colOnErrorContainer
                        : issue.severity === "warning"
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: issue.title
                    color: Appearance.colors.colOnLayer1
                    font {
                        pixelSize: Appearance.font.pixelSize.small
                        weight: Font.DemiBold
                    }
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: issue.detail
                    color: Appearance.colors.colSubtext
                    opacity: 1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }
        }
    }

    component OverviewLink: RippleButton {
        id: overviewLink
        property string iconName: ""
        property string title: ""
        property string value: ""
        property string subtitle: ""
        property int tabIndex: 0

        Layout.fillWidth: true
        implicitHeight: 58
        activeFocusOnTab: true
        buttonRadius: Appearance.radius.card
        buttonRadiusPressed: Appearance.radius.card
        colBackground:
             Appearance.colors.colLayer1
        colBackgroundHover:
             Appearance.colors.colLayer1Hover
        colRipple:
             Appearance.colors.colLayer1Active

        onClicked: root.switchTab(tabIndex)

        contentItem: RowLayout {
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: Appearance.radius.control
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: overviewLink.iconName
                    iconSize: 15
                    color: Appearance.colors.colPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: overviewLink.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    text: overviewLink.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }

            StyledText {
                text: overviewLink.value
                color: Appearance.colors.colOnLayer1
                font.weight: Font.DemiBold
            }

            MaterialSymbol {
                text: "chevron_right"
                iconSize: 17
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Workbench row: opens the already available Runtime tab, without new
    // shell commands or an unsafe URL open side effect.
    // Lightweight, read-only data rows: never execute package installs.
    component DiagnosticPackageRow: Rectangle {
        id: packageRow
        required property var packageInfo
        property bool aur: false
        Layout.fillWidth: true
        implicitHeight: 55
        radius: 10
        color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        RowLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 9
            MaterialSymbol {
                text: packageRow.aur ? "deployed_code" : "inventory_2"
                iconSize: 17
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: packageRow.packageInfo.name
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }
                StyledText {
                    Layout.fillWidth: true
                    text: packageRow.packageInfo.installed + "  →  " + packageRow.packageInfo.available
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideMiddle
                }
            }
            StyledText {
                text: packageRow.aur ? "AUR" : "REPO"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    component DiagnosticServiceRow: Rectangle {
        id: failedRow
        required property string unitName
        Layout.fillWidth: true
        implicitHeight: 40
        radius: 10
        color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        RowLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 9
            MaterialSymbol {
                text: "error_outline"
                iconSize: 17
                color: Appearance.colors.colError
            }
            StyledText {
                Layout.fillWidth: true
                text: failedRow.unitName
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideMiddle
            }
            StyledText {
                text: "FAILED"
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
            }
        }
    }

    component WorkbenchPinnedRow: Rectangle {
        id: pinnedRow
        required property var runtime
        Layout.fillWidth: true
        implicitHeight: 54
        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8
            MaterialSymbol {
                text: "push_pin"
                iconSize: 17
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: pinnedRow.runtime.name || "Pinned endpoint"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: pinnedRow.runtime.url || pinnedRow.runtime.bind || "Local endpoint"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideMiddle
                }
            }
            SmallAction {
                visible: pinnedRow.runtime.url && pinnedRow.runtime.url.length > 0
                iconName: "open_in_new"
                label: "Open"
                onClicked: root.runAction(["open", String(pinnedRow.runtime.url)])
            }
            SmallAction {
                iconName: "arrow_forward"
                label: "View"
                onClicked: {
                    root.runtimeFilter = "pinned"
                    root.runtimeQuery = ""
                    root.switchTab(1)
                }
            }
        }
    }

    component WorkbenchEventRow: Rectangle {
        id: eventRow
        required property var entry
        property bool running: false
        Layout.fillWidth: true
        implicitHeight: 50
        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 9
            MaterialSymbol {
                text: eventRow.running ? "progress_activity" : "history"
                iconSize: 16
                color: eventRow.running
                    ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: eventRow.entry.name || eventRow.entry.kind || "Operation"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: eventRow.running
                        ? `${eventRow.entry.process_count || 1} process(es) · ${eventRow.entry.uptime || "active"}`
                        : `${eventRow.entry.time_label || "Finished"} · ${eventRow.entry.result_label || "Outcome unknown"}`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
            StyledText {
                text: eventRow.running ? "LIVE" : "ENDED"
                color: eventRow.running ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
            }
        }
    }

    component EmptyState: Item {
        id: emptyState

        property string iconName: "check_circle"
        property string title: ""
        property string subtitle: ""

        Layout.fillWidth: true
        implicitHeight: 98

        Column {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                anchors.horizontalCenter:
                    parent.horizontalCenter
                text: emptyState.iconName
                iconSize: 24
                color: Appearance.colors.colSubtext
            }

            StyledText {
                anchors.horizontalCenter:
                    parent.horizontalCenter
                text: emptyState.title
                color: Appearance.colors.colOnLayer0
                font.weight: Font.DemiBold
            }

            StyledText {
                anchors.horizontalCenter:
                    parent.horizontalCenter
                text: emptyState.subtitle
                color: Appearance.colors.colSubtext
                font.pixelSize:
                    Appearance.font.pixelSize.smallest
            }
        }
    }

    component TabButton: RippleButton {
        id: tab
        required property int tabIndex
        readonly property bool selected: root.selectedTab === tab.tabIndex
        Layout.preferredWidth: 145
        implicitHeight: 43
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.tabName(tab.tabIndex)
        Accessible.checked: tab.selected
        buttonRadius: Appearance.radius.control
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        background: Item {
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 2
                radius: 1
                visible: tab.selected
                color: Appearance.colors.colPrimary
            }
        }
        onClicked: root.switchTab(tab.tabIndex)
        contentItem: RowLayout {
            anchors.centerIn: parent
            spacing: 7
            MaterialSymbol {
                text: root.tabIcon(tab.tabIndex)
                iconSize: 16
                color: tab.selected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                text: root.tabName(tab.tabIndex)
                color: tab.selected ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: tab.selected ? Font.DemiBold : Font.Normal
            }
        }
    }

    component RunwayMetric: Rectangle {
        id: metric
        required property string title
        required property string value
        required property string detail
        required property int targetTab
        property bool hovered: pointer.containsMouse
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: hovered ? Appearance.colors.colLayer1Hover
            : ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 3
            StyledText {
                text: metric.title.toUpperCase()
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.letterSpacing: 1
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: metric.value
                font.pixelSize: 26
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: metric.detail
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
                MaterialSymbol {
                    text: "arrow_forward"
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }
            }
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.switchTab(metric.targetTab)
        }
    }

    component RunwayEvent: Rectangle {
        id: eventRow
        required property var entry
        Layout.fillWidth: true
        implicitHeight: 54
        radius: 9
        color: pointer.containsMouse ? Appearance.colors.colLayer1Hover
            : ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 10
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 4
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: eventRow.entry.name || eventRow.entry.kind || "Operation"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: `${eventRow.entry.process_count || 1} processes · ${eventRow.entry.memory || "—"}`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
            StyledText {
                text: "RUNNING"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colPrimary
            }
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.switchTab(2)
        }
    }

    component RunwayIssue: Rectangle {
        id: issueRow
        required property var issue
        Layout.fillWidth: true
        implicitHeight: 63
        radius: 9
        color: pointer.containsMouse ? Appearance.colors.colLayer1Hover
            : ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 10
            MaterialSymbol {
                text: issueRow.issue.icon || "warning"
                iconSize: 20
                color: root.severityColor(issueRow.issue.severity)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: issueRow.issue.title || "Attention"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: issueRow.issue.detail || "Review diagnostics"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.switchTab(3)
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: operationsRail
            Layout.preferredWidth: root.width < 760 ? 58 : 183
            Layout.minimumWidth: Layout.preferredWidth
            Layout.maximumWidth: Layout.preferredWidth
            Layout.fillHeight: true
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Config.options.bar.vertical || Config.options.bar.bottom
                        ? Qt.rgba(0, 0, 0, 0.17) : "transparent"
                }
                GradientStop { position: 0.14; color: Qt.rgba(0, 0, 0, 0.17) }
                GradientStop { position: 0.86; color: Qt.rgba(0, 0, 0, 0.17) }
                GradientStop {
                    position: 1
                    color: !Config.options.bar.vertical && Config.options.bar.bottom
                        ? "transparent" : Qt.rgba(0, 0, 0, 0.17)
                }
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: operationsRail.width < 70 ? 8 : 12
                anchors.rightMargin: operationsRail.width < 70 ? 8 : 12
                anchors.topMargin: 18
                anchors.bottomMargin: 15
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 16
                    spacing: 9
                    Rectangle {
                        implicitWidth: 35
                        implicitHeight: 35
                        radius: 9
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.87)
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "monitoring"
                            iconSize: 19
                            color: Appearance.colors.colPrimary
                        }
                    }
                    ColumnLayout {
                        visible: operationsRail.width >= 70
                        spacing: 1
                        StyledText {
                            text: "Operations"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: "Work and system health"
                            font.pixelSize: 10
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                    Layout.bottomMargin: 18
                }
                StyledText {
                    visible: operationsRail.width >= 70
                    text: "WORKSPACE"
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.15
                    color: Appearance.colors.colSubtext
                    Layout.leftMargin: 10
                    Layout.bottomMargin: 8
                }
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        implicitHeight: 40
                        radius: 9
                        color: root.selectedTab === index
                            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88) : "transparent"
                        border.width: root.selectedTab === index ? 1 : 0
                        border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: operationsRail.width < 70 ? 0 : 11
                            spacing: 10
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: operationsRail.width < 70 ? 8 : 0
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter
                                text: root.tabIcon(index)
                                iconSize: 17
                                color: root.selectedTab === index
                                    ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            StyledText {
                                visible: operationsRail.width >= 70
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                text: root.tabName(index)
                                font.pixelSize: 11
                                color: root.selectedTab === index
                                    ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.switchTab(index)
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Rectangle {
                    visible: operationsRail.width >= 70
                    Layout.fillWidth: true
                    implicitHeight: 104
                    radius: 13
                    color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill,
                                          Appearance.colors.colLayer1, 0.62)
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 5
                        StyledText {
                            text: root.attentionCount() > 0 ? "● Needs a look" : "● All clear"
                            font.pixelSize: 11
                            color: root.attentionCount() > 0
                                ? Appearance.colors.colPrimary : "#9acaad"
                        }
                        StyledText {
                            text: root.jobCount() + " active · " + root.runtimeCount() + " listening"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: root.attentionCount() + " signal" + (root.attentionCount() === 1 ? "" : "s")
                            font.pixelSize: 10
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
                GridLayout {
                    columns: operationsRail.width < 70 ? 1 : 2
                    Layout.fillWidth: true
                    Layout.topMargin: 9
                    HeaderIconButton {
                        iconName: "refresh"
                        tooltipText: "Refresh · Ctrl+R"
                        onClicked: root.refreshAll()
                    }
                    HeaderIconButton {
                        iconName: "close"
                        tooltipText: "Close Operations"
                        onClicked: GlobalStates.sidebarLeftOpen = false
                    }
                }
            }
        }

        Item {
            id: contentViewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: operationsRail.width < 70 ? 13 : 22
            Layout.rightMargin: operationsRail.width < 70 ? 13 : 21
            Layout.topMargin: 18
            Layout.bottomMargin: 12
            clip: true
            Item {
                id: contentStage
                anchors.fill: parent
                opacity: root.contentShown ? 1 : 0
                transform: Translate {
                    x: root.contentShift
                    Behavior on x { MotionAnim { type: MotionAnim.FastSpatial } }
                }
                Behavior on opacity { MotionAnim { type: MotionAnim.DefaultEffects } }
                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    sourceComponent: root.activeView === 0 ? overviewPage
                        : root.activeView === 1 ? runtimePage
                        : root.activeView === 2 ? jobsPage : diagnosticsPage
                }
            }
        }
    }

    Rectangle {
        visible:
            root.toastMessage.length > 0
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 18
            rightMargin: 18
            bottomMargin: 18
        }
        implicitHeight: 42
        z: 20

        radius: Appearance.radius.control
        color:
            root.toastError
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colSecondaryContainer
        border.width: 0

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 11
                rightMargin: 11
            }
            spacing: 7

            MaterialSymbol {
                text:
                    root.toastError
                        ? "error"
                        : "check_circle"
                iconSize: 17
                color:
                    root.toastError
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnSecondaryContainer
            }

            StyledText {
                Layout.fillWidth: true
                text: root.toastMessage
                color:
                    root.toastError
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnSecondaryContainer
                font.pixelSize:
                    Appearance.font.pixelSize.small
                elide: Text.ElideRight
            }
        }
    }

    // Network Atlas rhythm: two primary surfaces, one compact route, two detail surfaces.
    Component {
        id: overviewPage
        ScrollView {
            id: overviewScroll
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ColumnLayout {
                width: overviewScroll.availableWidth
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 148
                    spacing: 12
                    AtlasSurface {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 510
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 17
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                OpsKicker { Layout.fillWidth: true; text: "CURRENT FLIGHT" }
                                StyledText {
                                    text: root.loading ? "REFRESHING" : "●  LIVE"
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }
                            Item { Layout.fillHeight: true }
                            StyledText {
                                text: String(root.jobCount()).padStart(2, "0")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: 38
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "Active operations"
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: root.countText(root.trackedProcessCount(), "tracked process")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                    AtlasSurface {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 385
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 17
                            spacing: 5
                            OpsKicker { text: "SYSTEM SIGNALS" }
                            Item { Layout.fillHeight: true }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                MaterialSymbol {
                                    text: root.attentionCount() > 0 ? "error_outline" : "check_circle"
                                    iconSize: 29
                                    color: root.attentionCount() > 0 ? Appearance.colors.colPrimary : "#9acaad"
                                }
                                StyledText {
                                    text: String(root.attentionCount()).padStart(2, "0")
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: 34
                                    font.weight: Font.DemiBold
                                }
                            }
                            StyledText {
                                text: root.attentionCount() > 0 ? "Needs a look" : "All clear"
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: root.systemData.failed_unit_count + " failed services · " + root.systemData.disk.percent + "% disk used"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                AtlasSurface {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 158
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 9
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "Work surfaces"
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                            OpsKicker { text: "LOCAL · LIVE" }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 9
                            RunwayMetric {
                                title: "Endpoints"
                                value: String(root.localRuntimeCount()).padStart(2, "0")
                                detail: "Listening locally"
                                targetTab: 1
                            }
                            RunwayMetric {
                                title: "Upgrades"
                                value: root.updateCount() === "—" ? "—" : root.updateCount().padStart(2, "0")
                                detail: "Pending review"
                                targetTab: 3
                            }
                            RunwayMetric {
                                title: "Incidents"
                                value: String(root.attentionCount()).padStart(2, "0")
                                detail: "Open diagnostics"
                                targetTab: 3
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 237
                    spacing: 12
                    AtlasSurface {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 535
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 5
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Execution lane"
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                }
                                SmallAction { iconName: "arrow_forward"; label: "All jobs"; onClicked: root.switchTab(2) }
                            }
                            Repeater {
                                model: root.runningWorkbenchJobs()
                                delegate: RunwayEvent { required property var modelData; entry: modelData }
                            }
                            StyledText {
                                visible: root.runningWorkbenchJobs().length === 0
                                Layout.fillWidth: true
                                text: "No tracked operations are running."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                    AtlasSurface {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 375
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 7
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Needs a look"
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                }
                                OpsKicker { text: root.countText(root.attentionCount(), "signal") }
                            }
                            Repeater {
                                model: root.urgentWorkbenchIssues().slice(0, 2)
                                delegate: RunwayIssue { required property var modelData; issue: modelData }
                            }
                            StyledText {
                                visible: root.urgentWorkbenchIssues().length === 0
                                Layout.fillWidth: true
                                text: "No urgent signals."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            Item { Layout.fillHeight: true }
                            SmallAction { iconName: "arrow_forward"; label: "Open diagnostics"; onClicked: root.switchTab(3) }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 7
                    MaterialSymbol { text: "circle"; iconSize: 8; color: Appearance.colors.colPrimary }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.countText(root.localRuntimeCount(), "local service") + " listening"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                    SmallAction { iconName: "arrow_forward"; label: "Explore connections"; onClicked: root.openArchRemote() }
                }
            }
        }
    }

    Component {
        id: runtimePage

        ScrollView {
            id: runtimeScroll
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: runtimeScroll.availableWidth
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 118
                    spacing: 11
                    AtlasSurface {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 540
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 3
                            OpsKicker { text: "RUNTIME / LOCAL" }
                            Item { Layout.fillHeight: true }
                            StyledText {
                                text: root.countText(root.localRuntimes().length, "service")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: 25
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "Listening on this device"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                    AtlasSurface {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 370
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 3
                            OpsKicker { text: "REMOTE-MANAGED" }
                            Item { Layout.fillHeight: true }
                            StyledText {
                                text: root.countText(root.remoteManagedRuntimes().length, "service")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: 25
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "Lifecycle handled by Arch Remote"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                }

                SectionTitle {
                    title: "Local services"
                    detail: `${root.localRuntimes().length} listening`
                    iconName: "dns"
                }

                Repeater {
                    model: root.localRuntimes()
                    delegate: RuntimeCard {
                        required property var modelData
                        runtime: modelData
                        expanded: root.runtimeExpanded(modelData)
                        onExpansionToggleRequested: root.toggleRuntimeExpanded(modelData)
                        onOpenRequested: root.runAction(["open", modelData.url])
                        onTerminalRequested: root.runAction(["terminal", String(modelData.pid), String(modelData.start_ticks || 0)])
                        onStopRequested: root.runAction(["stop", String(modelData.pid), String(modelData.start_ticks || 0), String(modelData.pin_key || "")])
                        onPinRequested: root.runAction(["toggle-pin", modelData.pin_key])
                        onRemoteRequested: root.openArchRemote()
                        onCopyRequested: mode => root.runAction(["copy-runtime", String(modelData.pid), String(modelData.start_ticks || 0), mode])
                        onFolderRequested: root.runAction(["open-folder", String(modelData.pid), String(modelData.start_ticks || 0)])
                        onEditorRequested: root.runAction(["open-editor", String(modelData.pid), String(modelData.start_ticks || 0)])
                    }
                }

                EmptyState {
                    visible: root.localRuntimes().length === 0
                    iconName: "dns"
                    title: "No local listeners"
                    subtitle:
                        "Local development services will appear here automatically."
                }

                SectionTitle {
                    visible: root.remoteManagedRuntimes().length > 0
                    title: "Remote-managed"
                    detail: `${root.remoteManagedRuntimes().length} managed`
                    iconName: "shield"
                }

                StyledText {
                    visible: root.remoteManagedRuntimes().length > 0
                    Layout.fillWidth: true
                    text: "Operations observes resource usage; Arch Remote owns remote lifecycle, reachability and security."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: root.remoteManagedRuntimes()
                    delegate: RuntimeCard {
                        required property var modelData
                        runtime: modelData
                        expanded: root.runtimeExpanded(modelData)
                        onExpansionToggleRequested: root.toggleRuntimeExpanded(modelData)
                        onOpenRequested: root.runAction(["open", modelData.url])
                        onTerminalRequested: root.runAction(["terminal", String(modelData.pid), String(modelData.start_ticks || 0)])
                        onStopRequested: root.runAction(["stop", String(modelData.pid), String(modelData.start_ticks || 0), String(modelData.pin_key || "")])
                        onPinRequested: root.runAction(["toggle-pin", modelData.pin_key])
                        onRemoteRequested: root.openArchRemote()
                        onCopyRequested: mode => root.runAction(["copy-runtime", String(modelData.pid), String(modelData.start_ticks || 0), mode])
                        onFolderRequested: root.runAction(["open-folder", String(modelData.pid), String(modelData.start_ticks || 0)])
                        onEditorRequested: root.runAction(["open-editor", String(modelData.pid), String(modelData.start_ticks || 0)])
                    }
                }

                Item { Layout.preferredHeight: 6 }
            }
        }
    }

    Component {
        id: jobsPage

        ScrollView {
            id: jobsScroll
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: jobsScroll.availableWidth
                spacing: 8

                AtlasSurface {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 115
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 20
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            OpsKicker { text: "ACTIVE OPERATIONS" }
                            Item { Layout.fillHeight: true }
                            StyledText {
                                text: root.countText(root.jobCount(), "operation")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: 25
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "Builds, tests, transfers, and agents"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Appearance.colors.colLayer0Border }
                        ColumnLayout {
                            Layout.preferredWidth: 175
                            spacing: 3
                            OpsKicker { text: "TRACKED PROCESSES" }
                            Item { Layout.fillHeight: true }
                            StyledText {
                                text: String(root.trackedProcessCount())
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: 25
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "Across current work"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                }

                SearchField {
                    placeholderText: "Search jobs, projects, activity…"
                    text: root.jobQuery
                    onTextChanged: root.jobQuery = text
                }

                SectionTitle {
                    title: "Running operations"
                    detail:
                        `${root.countText(root.jobCount(), "operation")} · ${root.countText(root.trackedProcessCount(), "process")}`
                    iconName: "progress_activity"
                }

                Repeater {
                    model: root.filteredJobGroups()
                    delegate: JobGroupRow {
                        required property var modelData
                        job: modelData
                        onStopRequested:
                            root.runAction([
                                "stop-operation",
                                String(modelData.root_pid),
                                String(modelData.root_start_ticks || 0)
                            ])
                    }
                }

                EmptyState {
                    visible: root.filteredJobGroups().length === 0
                    iconName: root.snapshotData.job_groups.length === 0 ? "check_circle" : "search_off"
                    title: root.snapshotData.job_groups.length === 0 ? "No tracked operations running" : "No matching operations"
                    subtitle: root.snapshotData.job_groups.length === 0 ? "Builds, tests, transfers, media tasks, agents and package work appear here." : "Change the search query."
                }

                SectionTitle {
                    visible: root.filteredJobHistory().length > 0
                    title: "Recent activity"
                    detail:
                        root.countText(root.filteredJobHistory().length, "operation")
                    iconName: "history"
                }

                Rectangle {
                    visible: root.filteredJobHistory().length > 0
                    Layout.fillWidth: true
                    implicitHeight: recentHistoryColumn.implicitHeight + 10
                    radius: 13
                    color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.62)
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    ColumnLayout {
                        id: recentHistoryColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 5
                        }
                        spacing: 1

                        Repeater {
                            model: root.filteredJobHistory()
                            delegate: JobGroupRow {
                                required property var modelData
                                job: modelData
                                historical: true
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }
            }
        }
    }

    // System Diagnostics: actionable issues, not a duplicate resource monitor.
    Component {
        id: diagnosticsPage
        ScrollView {
            id: diagnosticsScroll
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: diagnosticsScroll.availableWidth
                spacing: 9

                AtlasSurface {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 99
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 15
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            OpsKicker { text: "SYSTEM / DIAGNOSTICS" }
                            StyledText {
                                text: "Actionable signals"
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: 23
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "Failed services and available upgrades"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                        SmallAction { iconName: "refresh"; label: "Check"; onClicked: root.refreshAll() }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MetricTile {
                        iconName: "error_outline"
                        value: root.systemLoading ? "…" : String(root.systemData.failed_unit_count || 0)
                        label: "Failed units"
                        attention: root.systemData.failed_unit_count > 0
                    }
                    MetricTile {
                        iconName: "system_update"
                        value: root.updateCount()
                        label: "Upgrades"
                        attention: root.systemData.updates.total > 0
                    }
                    MetricTile {
                        iconName: "warning_amber"
                        value: String(root.attentionCount())
                        label: "Signals"
                        attention: root.attentionCount() > 0
                    }
                }

                SectionTitle {
                    title: "Failed user services"
                    detail: root.systemLoading ? "Checking…"
                        : root.countText(root.systemData.failed_unit_count, "unit")
                    iconName: "error_outline"
                }
                Repeater {
                    model: root.systemData.failed_units || []
                    delegate: DiagnosticServiceRow {
                        required property var modelData
                        unitName: String(modelData)
                    }
                }
                StyledText {
                    visible: !root.systemLoading && (root.systemData.failed_units || []).length === 0
                    Layout.fillWidth: true
                    text: "No failed user services reported."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }

                SectionTitle {
                    title: "Repository upgrades"
                    detail: root.officialUpgradeLoading ? "Checking…"
                        : root.officialUpgradeChecked
                            ? root.countText(root.officialUpgradeRows.length, "package")
                            : "Not checked"
                    iconName: "inventory_2"
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Installed packages with upgrades in your local pacman sync databases."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.officialUpgradeRows
                    delegate: DiagnosticPackageRow {
                        required property var modelData
                        packageInfo: modelData
                    }
                }
                StyledText {
                    visible: root.officialUpgradeChecked && root.officialUpgradeRows.length === 0
                    Layout.fillWidth: true
                    text: root.systemData.updates.official_count > 0
                        ? "No local pacman upgrade rows. The cached update count may use fresher metadata."
                        : "No repository upgrades listed by pacman -Qu."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    SectionTitle {
                        title: "AUR upgrades"
                        iconName: "deployed_code"
                        detail: root.aurUpgradeLoading ? "Checking…"
                            : root.aurUpgradeChecked
                                ? root.countText(root.aurUpgradeRows.length, "package")
                                : "Optional"
                    }
                    SmallAction {
                        iconName: "search"
                        label: "Scan AUR"
                        onClicked: root.requestAurUpgrades()
                    }
                }
                StyledText {
                    visible: !root.aurUpgradeChecked
                    Layout.fillWidth: true
                    text: "On-demand check with yay or paru; may require a network connection."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: root.aurUpgradeRows
                    delegate: DiagnosticPackageRow {
                        required property var modelData
                        packageInfo: modelData
                        aur: true
                    }
                }
                StyledText {
                    visible: root.aurUpgradeChecked && root.aurUpgradeRows.length === 0
                    Layout.fillWidth: true
                    text: root.aurUpgradeNote.length > 0
                        ? root.aurUpgradeNote : "No AUR upgrades returned by the helper."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
                }

                SectionTitle {
                    title: "Attention signals"
                    detail: root.countText(root.attentionCount(), "signal")
                    iconName: "notification_important"
                }
                Repeater {
                    model: (root.snapshotData.attention || []).filter(
                        item => item.severity === "critical" || item.severity === "warning"
                    )
                    delegate: AttentionRow {
                        required property var modelData
                        issue: modelData
                    }
                }
                StyledText {
                    visible: root.attentionCount() === 0
                    Layout.fillWidth: true
                    text: "No attention signals in the current snapshot."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
                Item { Layout.preferredHeight: 6 }
            }
        }
    }


}

