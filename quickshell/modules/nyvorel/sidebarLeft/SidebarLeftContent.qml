import qs
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Quickshell
import Quickshell.Io

Item {
    id: root

    required property var scopeRoot

    readonly property int expectedSchemaVersion: 5
    readonly property string expectedUiContract: "1.1.0"

    property string helperPath:
        Quickshell.shellPath(
            "scripts/operations-center/operations.py"
        )

    property int selectedTab: 0
    property int activeView: 0
    property int previousTab: 0
    property real contentShift: 0
    property bool contentShown: true
    property bool entered: false
    property bool loading: false
    property bool systemLoading: false
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
    opacity: root.entered ? 1 : 0

    transform: Translate {
        x: root.entered ? 0 : -8

        Behavior on x {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }
    }

    Behavior on opacity {
        MotionAnim {
            type: MotionAnim.DefaultEffects
        }
    }

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
        return "System"
    }

    function tabIcon(index) {
        if (index === 0)
            return "space_dashboard"
        if (index === 1)
            return "dns"
        if (index === 2)
            return "work_history"
        return "computer"
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

        if (next === 3)
            root.requestSystem(false)
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

    function requestSnapshot() {
        if (snapshotProcess.running)
            return

        root.loading = true
        snapshotProcess.command = [
            "python3",
            root.helperPath,
            "snapshot"
        ]
        snapshotProcess.running = true
    }

    function requestSystem(force) {
        if (systemProcess.running)
            return

        root.systemLoading = true

        const command = [
            "python3",
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

        actionProcess.command = [
            "python3",
            root.helperPath
        ].concat(args)
        actionProcess.running = true
    }

    function refreshAll() {
        root.requestSnapshot()

        if (root.selectedTab === 3)
            root.requestSystem(true)
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

    function localRuntimeCount() {
        return root.snapshotData.summary.local_runtime_count || 0
    }

    function remoteManagedCount() {
        return root.snapshotData.summary.remote_managed_count || 0
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

        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false

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
        id: actionProcess

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

                actionRefreshTimer.restart()
            }
        }
    }

    Timer {
        id: actionRefreshTimer
        interval: 350
        repeat: false
        onTriggered: root.requestSnapshot()
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

        implicitWidth: 36
        implicitHeight: 36
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: tooltipText

        buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
        buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.radius.control
        colBackground:
            active
                ? (Appearance.inlayMode
                    ? Appearance.inlay.selectedFill
                    : Appearance.prismMode
                        ? Appearance.prism.persistentFill
                        : Appearance.colors.colSecondaryContainer)
                : Appearance.inlayMode
                    ? Appearance.inlay.insetFill
                    : "transparent"
        colBackgroundHover:
            Appearance.inlayMode
                ? (active
                    ? Appearance.inlay.hoverFill
                    : Appearance.inlay.controlFill)
                : Appearance.prismMode
                    ? Appearance.prism.persistentFill
                    : (active
                        ? Appearance.colors.colSecondaryContainerHover
                        : Appearance.colors.colLayer2Hover)
        colRipple:
            Appearance.prismMode
                ? Appearance.colors.colLayer2Active
                : (active
                    ? Appearance.colors.colSecondaryContainerActive
                    : Appearance.colors.colLayer2Active)

        background: Rectangle {
            radius: headerButton.radius
            color: headerButton.buttonColor
            border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : (headerButton.tabbedTo ? 2 : 0)
            border.color:
                Appearance.inlayMode
                    ? (headerButton.active ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                    : Appearance.colors.colSecondary
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: headerButton.iconName
            iconSize: 18
            fill: headerButton.active ? 1 : 0
            color:
                Appearance.prismMode && headerButton.active
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

    component SectionTitle: RowLayout {
        id: section

        property string title: ""
        property string detail: ""
        property string iconName: ""

        Layout.fillWidth: true
        spacing: 7

        MaterialSymbol {
            visible: section.iconName.length > 0
            text: section.iconName
            iconSize: 16
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: section.title
            color:
                Appearance.prismMode
                    ? Appearance.colors.colOnLayer0
                    : Appearance.colors.colSubtext
            font {
                pixelSize:
                    Appearance.prismMode
                        ? Appearance.font.pixelSize.small
                        : Appearance.font.pixelSize.smallest
                weight: Font.DemiBold
                capitalization:
                    Appearance.prismMode
                        ? Font.MixedCase
                        : Font.AllUppercase
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
        implicitHeight: 62

        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusCard
                    : Appearance.radius.card
        color:
            Appearance.inlayMode
                ? (attention
                    ? Appearance.inlay.selectedFill
                    : Appearance.inlay.insetFill)
                : Appearance.prismMode
                    ? Appearance.prism.persistentFill
                    : (attention
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer1)
        border.width:
            (Appearance.prismMode || Appearance.inlayMode) ? 1 : 0
        border.color:
            Appearance.inlayMode
                ? (attention
                    ? Appearance.inlay.borderFocus
                    : Appearance.inlay.borderSection)
                : Appearance.prismMode
                    ? (attention
                        ? Appearance.prism.focusBorder
                        : Appearance.prism.borderSubtle)
                    : "transparent"

        ColumnLayout {
            anchors {
                fill: parent
                margins: 9
            }
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                MaterialSymbol {
                    text: metric.iconName
                    iconSize: 15
                    color:
                        Appearance.prismMode
                            ? (metric.attention
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext)
                            : (metric.attention
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colSubtext)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: metric.value
                    color:
                        Appearance.prismMode
                            ? Appearance.colors.colOnLayer0
                            : (metric.attention
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer1)
                    font {
                        pixelSize:
                            Appearance.font.pixelSize.normal
                        weight: Font.DemiBold
                    }
                    horizontalAlignment:
                        Text.AlignRight
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: metric.label
                color:
                    Appearance.prismMode
                        ? Appearance.colors.colSubtext
                        : (metric.attention
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colSubtext)
                opacity:
                    Appearance.prismMode
                        ? 1
                        : (metric.attention ? 0.82 : 1)
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
        implicitHeight: 38
        leftPadding: 36
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

        implicitHeight: 30
        implicitWidth: chipText.implicitWidth + 22
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
        implicitHeight: expanded ? 216 : 118

        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusCard
                    : Appearance.radius.card
        color:
            Appearance.inlayMode
                ? (runtime.pinned
                    ? Appearance.inlay.selectedFill
                    : Appearance.inlay.controlFill)
                : Appearance.prismMode
                    ? Appearance.prism.persistentFill
                    : (runtime.pinned
                        ? Appearance.colors.colSecondaryContainer
                        : Appearance.colors.colLayer1)
        border.width:
            (Appearance.prismMode || Appearance.inlayMode) ? 1 : 0
        border.color:
            Appearance.inlayMode
                ? (runtime.pinned
                    ? Appearance.inlay.borderFocus
                    : Appearance.inlay.borderSection)
                : Appearance.prismMode
                    ? (runtime.pinned
                        ? Appearance.prism.focusBorder
                        : Appearance.prism.borderSubtle)
                    : "transparent"
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
                margins: 10
            }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
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
                    implicitHeight: 24
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
        implicitHeight: historical ? 58 : 78
        radius: Appearance.radius.control
        color:
            historical
                ? "transparent"
                : (Appearance.prismMode
                    ? Appearance.prism.persistentFill
                    : Appearance.colors.colLayer1)
        border.width:
            Appearance.prismMode && !historical ? 1 : 0
        border.color:
            Appearance.prismMode && !historical
                ? Appearance.prism.borderSubtle
                : "transparent"

        Timer {
            interval: 3000
            running: jobGroupRow.stopArmed
            repeat: false
            onTriggered: jobGroupRow.stopArmed = false
        }

        RowLayout {
            anchors {
                fill: parent
                margins: historical ? 7 : 10
            }
            spacing: 9

            MaterialSymbol {
                text: historical ? "history" : "progress_activity"
                iconSize: 17
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
        implicitHeight: 62
        radius: Appearance.radius.control
        color:
            issue.severity === "critical"
                ? Appearance.colors.colErrorContainer
                : (Appearance.prismMode
                    ? Appearance.prism.persistentFill
                    : Appearance.colors.colLayer1)
        border.width:
            Appearance.prismMode && issue.severity !== "critical" ? 1 : 0
        border.color:
            Appearance.prismMode && issue.severity !== "critical"
                ? (issue.severity === "warning"
                    ? Appearance.prism.focusBorder
                    : Appearance.prism.borderSubtle)
                : "transparent"

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
                    color:
                        issue.severity === "critical"
                            ? Appearance.colors.colOnErrorContainer
                            : Appearance.colors.colOnLayer1
                    font {
                        pixelSize: Appearance.font.pixelSize.small
                        weight: Font.DemiBold
                    }
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: issue.detail
                    color:
                        issue.severity === "critical"
                            ? Appearance.colors.colOnErrorContainer
                            : Appearance.colors.colSubtext
                    opacity: issue.severity === "critical" ? 0.86 : 1
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
        implicitHeight: 72
        activeFocusOnTab: true
        buttonRadius: Appearance.radius.card
        buttonRadiusPressed: Appearance.radius.card
        colBackground:
            Appearance.prismMode
                ? "transparent"
                : Appearance.colors.colLayer1
        colBackgroundHover:
            Appearance.prismMode
                ? Appearance.prism.persistentFill
                : Appearance.colors.colLayer1Hover
        colRipple:
            Appearance.prismMode
                ? Appearance.colors.colLayer2Active
                : Appearance.colors.colLayer1Active

        onClicked: root.switchTab(tabIndex)

        contentItem: RowLayout {
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: Appearance.radius.control
                color: Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: overviewLink.iconName
                    iconSize: 17
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

    component EmptyState: Item {
        id: emptyState

        property string iconName: "check_circle"
        property string title: ""
        property string subtitle: ""

        Layout.fillWidth: true
        implicitHeight: 110

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

        Layout.fillWidth: true
        implicitHeight: 38
        activeFocusOnTab: true

        readonly property bool selected:
            root.selectedTab === tab.tabIndex

        Accessible.role: Accessible.Button
        Accessible.name: root.tabName(tab.tabIndex)

        buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
        buttonRadiusPressed:
            Appearance.inlayMode ? 0 : Appearance.radius.control

        colBackground:
            selected
                ? (Appearance.inlayMode
                    ? Appearance.inlay.selectedFill
                    : Appearance.prismMode
                        ? Appearance.prism.persistentFill
                        : Appearance.colors.colPrimary)
                : Appearance.inlayMode
                    ? Appearance.inlay.insetFill
                    : "transparent"
        colBackgroundHover:
            Appearance.inlayMode
                ? (selected
                    ? Appearance.inlay.hoverFill
                    : Appearance.inlay.controlFill)
                : Appearance.prismMode
                    ? Appearance.prism.persistentFill
                    : (selected
                        ? Appearance.colors.colPrimaryHover
                        : Appearance.colors.colLayer2Hover)
        colRipple:
            Appearance.prismMode
                ? Appearance.colors.colLayer2Active
                : (selected
                    ? Appearance.colors.colPrimaryActive
                    : Appearance.colors.colLayer2Active)

        background: Rectangle {
            radius: tab.radius
            color: tab.buttonColor
            border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : (tab.tabbedTo ? 2 : 0)
            border.color:
                Appearance.inlayMode
                    ? (tab.selected ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                    : Appearance.colors.colSecondary
        }

        onClicked:
            root.switchTab(tab.tabIndex)

        contentItem: Row {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter:
                    parent.verticalCenter
                text:
                    root.tabIcon(tab.tabIndex)
                iconSize: 15
                fill: tab.selected ? 1 : 0
                color:
                    tab.selected
                        ? (Appearance.inlayMode
                            ? Appearance.colors.colOnLayer1
                            : Appearance.prismMode
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnPrimary)
                        : Appearance.colors.colSubtext
            }

            StyledText {
                anchors.verticalCenter:
                    parent.verticalCenter
                text:
                    root.tabName(tab.tabIndex)
                color:
                    tab.selected
                        ? (Appearance.inlayMode
                            ? Appearance.colors.colOnLayer1
                            : Appearance.prismMode
                                ? Appearance.colors.colOnLayer0
                                : Appearance.colors.colOnPrimary)
                        : Appearance.colors.colOnLayer0
                font {
                    pixelSize:
                        Appearance.font.pixelSize.smallest
                    weight:
                        tab.selected
                            ? Font.DemiBold
                            : Font.Normal
                }
            }
        }
    }

    anchors.fill: parent

    ColumnLayout {
        anchors {
            fill: parent
            margins:
                Appearance.prismMode
                    ? Appearance.prism.panelPadding
                    : 10
        }

        spacing:
            Appearance.prismMode
                ? Appearance.spacing.md
                : 10

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            Layout.topMargin: 4
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Appearance.inlayMode ? 0 : 18
                color:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colLayer1
                border.width: 0
                border.color: "transparent"

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 11
                        rightMargin: 11
                    }
                    spacing: 9

                    MaterialSymbol {
                        text: "monitoring"
                        iconSize: 20
                        fill: 1
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: "Operations"
                            color: Appearance.colors.colOnLayer0
                            font {
                                family: Appearance.font.family.title
                                pixelSize: Appearance.font.pixelSize.small
                                weight: Font.DemiBold
                            }
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text:
                                root.loading
                                    ? "Refreshing runtime state…"
                                    : "Local runtime, jobs & system"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 116
                Layout.preferredHeight: 40
                radius: Appearance.inlayMode ? 0 : 18
                color:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colLayer1
                border.width: 0
                border.color: "transparent"

                RowLayout {
                    anchors {
                        fill: parent
                        margins: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 2
                    }
                    spacing: 0

                    HeaderIconButton {
                        iconName: "refresh"
                        tooltipText: "Refresh · Ctrl+R"
                        onClicked: root.refreshAll()
                    }

                    HeaderIconButton {
                        iconName: "push_pin"
                        tooltipText:
                            root.scopeRoot.pin
                                ? "Unpin sidebar"
                                : "Pin sidebar"
                        active: root.scopeRoot.pin
                        onClicked: root.scopeRoot.togglePin()
                    }

                    HeaderIconButton {
                        iconName: "open_in_new"
                        tooltipText: "Detach sidebar"
                        onClicked: root.scopeRoot.toggleDetach()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44

            radius: Appearance.inlayMode ? 0 : Appearance.radius.card
            color:
                (Appearance.prismMode || Appearance.inlayMode)
                    ? "transparent"
                    : Appearance.colors.colLayer1
            border.width: 0
            border.color: "transparent"

            RowLayout {
                anchors {
                    fill: parent
                    margins: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 3
                }
                spacing: 3

                TabButton {
                    tabIndex: 0
                }

                TabButton {
                    tabIndex: 1
                }

                TabButton {
                    tabIndex: 2
                }

                TabButton {
                    tabIndex: 3
                }
            }
        }

        Item {
            id: contentViewport

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Item {
                id: contentStage

                anchors.fill: parent
                opacity:
                    root.contentShown
                        ? 1
                        : 0

                transform: Translate {
                    x: root.contentShift

                    Behavior on x {
                        MotionAnim {
                            type: MotionAnim.FastSpatial
                        }
                    }
                }

                Behavior on opacity {
                    MotionAnim {
                        type: MotionAnim.DefaultEffects
                    }
                }

                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    sourceComponent:
                        root.activeView === 0
                            ? overviewPage
                            : root.activeView === 1
                                ? runtimePage
                                : root.activeView === 2
                                    ? jobsPage
                                    : systemPage
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

    Component {
        id: overviewPage

        ScrollView {
            id: overviewScroll
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: overviewScroll.availableWidth
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    MetricTile {
                        iconName: "dns"
                        value: String(root.localRuntimeCount())
                        label: "Local services"
                    }
                    MetricTile {
                        iconName: "work_history"
                        value: String(root.jobCount())
                        label: "Active operations"
                    }
                    MetricTile {
                        iconName: "warning"
                        value: String(root.attentionCount())
                        label: "Issues"
                        attention: root.attentionCount() > 0
                    }
                    MetricTile {
                        iconName: "system_update"
                        value: root.updateCount()
                        label: "Updates"
                    }
                }

                SectionTitle {
                    visible: root.snapshotData.attention.length > 0
                    title: root.attentionCount() > 0 ? "Attention" : "Maintenance"
                    detail:
                        root.attentionCount() > 0
                            ? root.countText(root.attentionCount(), "issue")
                            : root.countText(root.maintenanceCount(), "item")
                    iconName: root.attentionCount() > 0 ? "warning" : "build"
                }

                Repeater {
                    model:
                        root.snapshotData.attention.filter(
                            item => item.severity === "critical" || item.severity === "warning"
                        ).slice(0, 2)
                    delegate: AttentionRow {
                        required property var modelData
                        issue: modelData
                    }
                }

                Repeater {
                    visible: root.attentionCount() === 0
                    model:
                        root.snapshotData.attention.filter(
                            item => item.severity === "maintenance"
                        ).slice(0, 1)
                    delegate: AttentionRow {
                        required property var modelData
                        issue: modelData
                    }
                }

                SectionTitle {
                    title: "Active now"
                    detail:
                        `${root.localRuntimeCount()} local · ${root.countText(root.jobCount(), "operation")}`
                    iconName: "monitoring"
                }

                OverviewLink {
                    iconName: "dns"
                    title: "Runtime"
                    value: String(root.localRuntimeCount())
                    subtitle:
                        root.remoteManagedCount() > 0
                            ? `${root.countText(root.localRuntimeCount(), "local listener")} · ${root.countText(root.remoteManagedCount(), "service")} managed by Arch Remote`
                            : root.countText(root.localRuntimeCount(), "local listener")
                    tabIndex: 1
                }

                OverviewLink {
                    iconName: "work_history"
                    title: "Operations"
                    value: String(root.jobCount())
                    subtitle:
                        `${root.countText(root.trackedProcessCount(), "tracked process")} · builds, tests, media, agents and package work`
                    tabIndex: 2
                }

                OverviewLink {
                    iconName: "computer"
                    title: "System"
                    value:
                        root.systemData.failed_unit_count > 0
                            ? `${root.systemData.failed_unit_count} failed`
                            : "OK"
                    subtitle:
                        `${root.systemData.memory.percent}% memory · ${root.systemData.disk.percent}% disk · ${root.updateCount()} updates`
                    tabIndex: 3
                }

                Item { Layout.preferredHeight: 6 }
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

                SearchField {
                    placeholderText: "Search runtimes, projects, ports…"
                    text: root.runtimeQuery
                    onTextChanged: root.runtimeQuery = text
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    FilterChip {
                        label: "All"
                        active: root.runtimeFilter === "all"
                        onClicked: root.runtimeFilter = "all"
                    }
                    FilterChip {
                        label: "Local"
                        active: root.runtimeFilter === "local"
                        onClicked: root.runtimeFilter = "local"
                    }
                    FilterChip {
                        label: "Exposed"
                        active: root.runtimeFilter === "exposed"
                        onClicked: root.runtimeFilter = "exposed"
                    }
                    FilterChip {
                        label: "Pinned"
                        active: root.runtimeFilter === "pinned"
                        onClicked: root.runtimeFilter = "pinned"
                    }
                    Item { Layout.fillWidth: true }
                }

                SectionTitle {
                    title: "Local services"
                    detail: `${root.filteredLocalRuntimes().length} shown · ${root.localRuntimes().length} listening`
                    iconName: "dns"
                }

                Repeater {
                    model: root.filteredLocalRuntimes()
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
                    visible: root.filteredLocalRuntimes().length === 0
                    iconName: root.localRuntimes().length === 0 ? "dns" : "search_off"
                    title: root.localRuntimes().length === 0 ? "No local listeners" : "No matching runtimes"
                    subtitle:
                        root.localRuntimes().length === 0
                            ? "Local development services will appear here automatically."
                            : "Change the search or runtime filter."
                }

                SectionTitle {
                    visible: root.filteredRemoteManagedRuntimes().length > 0
                    title: "Remote-managed"
                    detail: `${root.filteredRemoteManagedRuntimes().length} shown`
                    iconName: "shield"
                }

                StyledText {
                    visible: root.filteredRemoteManagedRuntimes().length > 0
                    Layout.fillWidth: true
                    text: "Operations observes resource usage; Arch Remote owns remote lifecycle, reachability and security."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: root.filteredRemoteManagedRuntimes()
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
                    radius: Appearance.radius.card
                    color:
                        Appearance.prismMode
                            ? "transparent"
                            : Appearance.colors.colLayer1
                    border.width: 0

                    ColumnLayout {
                        id: recentHistoryColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: Appearance.prismMode ? 0 : 5
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

    Component {
        id: systemPage

        ScrollView {
            id: systemScroll
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: systemScroll.availableWidth
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    MetricTile {
                        iconName: "system_update"
                        value:
                            root.systemData.updates.total < 0
                                ? "—"
                                : String(root.systemData.updates.total)
                        label: "Updates"
                        attention: root.systemData.updates.total > 0
                    }
                    MetricTile {
                        iconName: "memory"
                        value: `${root.systemData.memory.percent}%`
                        label: "Memory"
                    }
                    MetricTile {
                        iconName: "storage"
                        value: `${root.systemData.disk.percent}%`
                        label: "Disk"
                        attention: root.systemData.disk.percent >= 80
                    }
                }

                SectionTitle {
                    title: "System health"
                    detail: root.systemData.hostname
                    iconName: "computer"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 130
                    radius: Appearance.radius.card
                    color:
                        Appearance.prismMode
                            ? "transparent"
                            : Appearance.colors.colLayer1
                    border.width: 0

                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: Appearance.prismMode ? 2 : 10
                        }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "Memory"
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: `${root.systemData.memory.used} / ${root.systemData.memory.total}`
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "Root disk"
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: `${root.systemData.disk.free} free`
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "Load · 1 / 5 / 15 min"
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: root.systemData.load
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "User services"
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text:
                                    root.systemData.failed_unit_count === 0
                                        ? "No failures"
                                        : `${root.systemData.failed_unit_count} failed`
                                color:
                                    root.systemData.failed_unit_count === 0
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.m3colors.m3error
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                SectionTitle {
                    title: "Packages"
                    detail: root.systemLoading ? "Refreshing…" : "Arch repositories"
                    iconName: "system_update"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 88
                    radius: Appearance.radius.card
                    color:
                        Appearance.prismMode
                            ? "transparent"
                            : Appearance.colors.colLayer1
                    border.width: 0

                    RowLayout {
                        anchors {
                            fill: parent
                            margins: Appearance.prismMode ? 2 : 10
                        }
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                text: `${root.systemData.updates.official_count} official · ${root.systemData.updates.aur_count} AUR`
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text:
                                    root.systemData.updates.total > 0
                                        ? `${root.systemData.updates.total} update(s) available`
                                        : "Package state is current"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }

                        SmallAction {
                            iconName: "refresh"
                            label: "Refresh"
                            onClicked: root.requestSystem(true)
                        }
                    }
                }

                Rectangle {
                    visible: root.systemData.failed_unit_count > 0
                    Layout.fillWidth: true
                    implicitHeight: failedUnitsColumnV2.implicitHeight + 18
                    radius: Appearance.radius.card
                    color: Appearance.colors.colErrorContainer
                    border.width: 0

                    ColumnLayout {
                        id: failedUnitsColumnV2
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 9
                        }
                        spacing: 3
                        StyledText {
                            text: "Failed user services"
                            color: Appearance.colors.colOnErrorContainer
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: root.systemData.failed_units
                            delegate: StyledText {
                                required property var modelData
                                Layout.fillWidth: true
                                text: `✕ ${modelData}`
                                color: Appearance.colors.colOnErrorContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 6 }
            }
        }
    }

}

