import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io

StyledPopup {
    id: root
    irisAnimation: Appearance.barLayout.axiomComponents
    popupRadius: Appearance.radius.popup
    popupColor: root.surface
    contentMargin: 13
    dismissOnOutsideClick: true
    onDismissRequested: root.closeRequested()
    signal closeRequested()

    readonly property real screenWidth: root.QsWindow?.window?.screen?.width ?? 900
    readonly property real screenHeight: root.QsWindow?.window?.screen?.height ?? 900
    readonly property real panelWidth: Math.min(536, Math.max(292, screenWidth - 56))
    readonly property real panelMaxHeight: Math.max(280, screenHeight
        - (Config.options.bar.vertical ? 52 : Appearance.sizes.barHeight) - 64)
    readonly property int diagnosticColumns: panelWidth >= 440 ? 2 : 1
    readonly property color surface: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill,
        Appearance.colors.colLayer1, 0.62)
    readonly property color inset: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill,
        Appearance.colors.colLayer1, 0.82)
    readonly property color stroke: Appearance.colors.colLayer0Border
    readonly property color ink: Appearance.colors.colOnLayer0
    readonly property color muted: Appearance.colors.colSubtext
    readonly property color accent: Appearance.colors.colPrimary

    readonly property real memoryPercent: clamp(ResourceUsage.memoryUsedPercentage)
    readonly property real cpuPercent: clamp(ResourceUsage.cpuUsage)
    readonly property real swapPercent: clamp(ResourceUsage.swapUsedPercentage)
    readonly property bool memoryCritical: memoryPercent * 100 >= Config.options.bar.resources.memoryWarningThreshold
    readonly property bool cpuCritical: cpuPercent * 100 >= Config.options.bar.resources.cpuWarningThreshold
    readonly property bool swapCritical: swapPercent * 100 >= Config.options.bar.resources.swapWarningThreshold
    readonly property bool diskCritical: diskPercent >= 90

    property string diskUsedText: "—"
    property string diskTotalText: "—"
    property real diskPercent: 0
    property int logicalCpuCount: 1
    property var loadValues: []
    property string cpuClock: "—"
    property string cpuTemperature: "—"
    property string cachedMemory: "—"
    property string cpuPressure: "—"
    property string memoryPressure: "—"
    property string ioPressure: "—"
    property string rootInodes: "—"
    property string processCount: "—"
    property string topProcessName: "—"
    property string topProcessCpu: "—"
    property string topProcessMemory: "—"
    property bool hasProbeSample: false
    property bool probeFailed: false

    function clamp(value) { return Math.max(0, Math.min(1, value)) }
    function compactGB(kib) { return kib > 0 ? (kib / 1048576).toFixed(1) : "0" }
    function loadText() {
        return loadValues.length >= 3
            ? loadValues.map(value => Number(value).toFixed(2)).join(" · ") : "—"
    }
    function refreshSystemProbe() {
        if (!systemProbe.running) systemProbe.running = true
    }

    property var systemProbe: Process {
        command: [Quickshell.shellPath("scripts/system/nyvorel-operations"), "system-overview"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(this.text)
                    if (result.error) throw new Error(result.message || "System probe failed")
                    root.diskUsedText = result.disk?.used ?? "—"
                    root.diskTotalText = result.disk?.total ?? "—"
                    root.diskPercent = Number(result.disk?.percent ?? 0)
                    root.logicalCpuCount = Math.max(1, Number(result.logicalCpuCount ?? 1))
                    root.loadValues = Array.isArray(result.load) ? result.load : []
                    root.cpuClock = result.cpuClock ?? "—"
                    root.cpuTemperature = result.cpuTemperature ?? "—"
                    root.cachedMemory = result.cachedMemory ?? "—"
                    root.cpuPressure = result.cpuPressure ?? "—"
                    root.memoryPressure = result.memoryPressure ?? "—"
                    root.ioPressure = result.ioPressure ?? "—"
                    root.rootInodes = result.rootInodes ?? "—"
                    root.processCount = String(result.processCount ?? "—")
                    root.topProcessName = result.topProcessName ?? "—"
                    root.topProcessCpu = result.topProcessCpu ?? "—"
                    root.topProcessMemory = result.topProcessMemory ?? "—"
                    root.hasProbeSample = true
                    root.probeFailed = false
                } catch (error) {
                    root.probeFailed = true
                    console.warn("System overview probe:", error)
                }
            }
        }
    }
    property var systemProbeTimer: Timer {
        interval: 10000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.refreshSystemProbe()
    }

    component Kicker: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        font.letterSpacing: 1.05
        color: root.muted
    }
    component CardSurface: Rectangle {
        radius: 12
        color: root.surface
        border.width: 1
        border.color: root.stroke
    }
    component VitalCard: CardSurface {
        id: vital
        required property string label
        required property string value
        required property string detail
        required property string symbol
        required property real progress
        property bool critical: false
        readonly property color tone: critical ? Appearance.colors.colError : root.accent
        implicitHeight: 128
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 5
            Kicker { text: vital.label.toUpperCase() }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    StyledText {
                        text: vital.value
                        font.pixelSize: 27
                        font.weight: Font.DemiBold
                        color: vital.tone
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: vital.detail
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.muted
                        elide: Text.ElideRight
                    }
                }
                CircularProgress {
                    implicitSize: 58
                    value: vital.progress
                    lineWidth: 4
                    gapAngle: 0
                    enableAnimation: false
                    colPrimary: vital.tone
                    colSecondary: Appearance.colors.colLayer3
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: vital.symbol
                        iconSize: 19
                        color: vital.tone
                    }
                }
            }
        }
    }
    component StorageMeter: Rectangle {
        id: compact
        required property string label
        required property string detail
        required property string value
        required property real progress
        property bool critical: false
        readonly property color tone: critical ? Appearance.colors.colError : root.accent
        implicitHeight: 82
        radius: 12
        color: root.surface
        border.width: 1
        border.color: root.stroke
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                StyledText { text: compact.label; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold; color: root.ink }
                Item { Layout.fillWidth: true }
                StyledText { text: compact.value; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold; color: compact.tone }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Appearance.colors.colLayer3
                clip: true
                Rectangle {
                    height: parent.height
                    width: parent.width * root.clamp(compact.progress)
                    radius: parent.radius
                    color: compact.tone
                }
            }
            StyledText { Layout.fillWidth: true; text: compact.detail; font.pixelSize: Appearance.font.pixelSize.smallest; color: root.muted; elide: Text.ElideRight }
        }
    }
    component SignalCell: Item {
        id: signalCell
        required property string label
        required property string value
        implicitHeight: 38
        Layout.fillWidth: true
        RowLayout {
            anchors.fill: parent
            spacing: 7
            StyledText { Layout.fillWidth: true; text: signalCell.label; font.pixelSize: Appearance.font.pixelSize.smaller; color: root.muted; elide: Text.ElideRight }
            StyledText { text: signalCell.value; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold; color: root.ink }
        }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.stroke }
    }

    Controls.ScrollView {
        id: contentFrame
        anchors.centerIn: parent
        implicitWidth: root.panelWidth
        implicitHeight: Math.min(content.implicitHeight, root.panelMaxHeight)
        contentWidth: availableWidth
        clip: content.implicitHeight > root.panelMaxHeight
        padding: 0
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        Controls.ScrollBar.vertical.policy: content.implicitHeight > root.panelMaxHeight
            ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff

        ColumnLayout {
            id: content
            width: contentFrame.availableWidth
            spacing: 11

            GridLayout {
                Layout.fillWidth: true
                columns: root.panelWidth >= 390 ? 2 : 1
                columnSpacing: 9
                rowSpacing: 9
                VitalCard {
                    Layout.fillWidth: true
                    label: Translation.tr("Memory")
                    value: `${Math.round(root.memoryPercent * 100)}%`
                    detail: `${root.compactGB(ResourceUsage.memoryUsed)} / ${root.compactGB(ResourceUsage.memoryTotal)} GB`
                    symbol: "memory"
                    progress: root.memoryPercent
                    critical: root.memoryCritical
                }
                VitalCard {
                    Layout.fillWidth: true
                    label: Translation.tr("CPU")
                    value: `${Math.round(root.cpuPercent * 100)}%`
                    detail: Translation.tr("%1 logical CPUs").arg(root.logicalCpuCount)
                    symbol: "developer_board"
                    progress: root.cpuPercent
                    critical: root.cpuCritical
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.panelWidth >= 390 ? 2 : 1
                columnSpacing: 9
                rowSpacing: 9
                StorageMeter {
                    Layout.fillWidth: true
                    label: Translation.tr("Swap")
                    value: `${Math.round(root.swapPercent * 100)}%`
                    detail: `${root.compactGB(ResourceUsage.swapUsed)} / ${root.compactGB(ResourceUsage.swapTotal)} GB`
                    progress: root.swapPercent
                    critical: root.swapCritical
                }
                StorageMeter {
                    Layout.fillWidth: true
                    label: Translation.tr("Root disk")
                    value: root.hasProbeSample ? `${Math.round(root.diskPercent)}%` : "—"
                    detail: `${root.diskUsedText} / ${root.diskTotalText}`
                    progress: root.diskPercent / 100
                    critical: root.diskCritical
                }
            }

            CardSurface {
                Layout.fillWidth: true
                implicitHeight: signalsContent.implicitHeight + 26
                ColumnLayout {
                    id: signalsContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 13
                    spacing: 7
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { text: Translation.tr("Health signals"); font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold; color: root.ink }
                        Item { Layout.fillWidth: true }
                        Kicker { text: root.hasProbeSample ? Translation.tr("10S SAMPLE") : Translation.tr("WAITING") }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.diagnosticColumns
                        columnSpacing: 18
                        rowSpacing: 0
                        SignalCell { label: Translation.tr("CPU clock"); value: root.cpuClock }
                        SignalCell { label: Translation.tr("CPU temperature"); value: root.cpuTemperature }
                        SignalCell { label: Translation.tr("Cached memory"); value: root.cachedMemory }
                        SignalCell { label: Translation.tr("Memory pressure"); value: root.memoryPressure }
                        SignalCell { label: Translation.tr("CPU pressure"); value: root.cpuPressure }
                        SignalCell { label: Translation.tr("I/O pressure"); value: root.ioPressure }
                        SignalCell { label: Translation.tr("Processes"); value: root.processCount }
                        SignalCell { label: Translation.tr("Root inodes"); value: root.rootInodes }
                    }
                }
            }

            CardSurface {
                Layout.fillWidth: true
                implicitHeight: 72
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 13
                    spacing: 11
                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 9
                        color: root.inset
                        MaterialSymbol { anchors.centerIn: parent; text: "memory_alt"; iconSize: 19; color: root.accent }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Kicker { text: Translation.tr("TOP CPU PROCESS") }
                        StyledText { Layout.fillWidth: true; text: root.topProcessName; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold; color: root.ink; elide: Text.ElideRight }
                    }
                    ColumnLayout {
                        spacing: 2
                        StyledText { text: root.topProcessCpu === "—" ? "—" : root.topProcessCpu + "% CPU"; font.pixelSize: Appearance.font.pixelSize.small; color: root.ink }
                        StyledText { text: root.topProcessMemory === "—" ? "" : root.topProcessMemory + "% RAM"; font.pixelSize: Appearance.font.pixelSize.smallest; color: root.muted }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                MaterialSymbol { text: "schedule"; iconSize: 14; color: root.muted }
                StyledText { Layout.fillWidth: true; text: Translation.tr("Uptime") + " · " + DateTime.uptime; font.pixelSize: Appearance.font.pixelSize.smallest; color: root.muted }
                StyledText { text: Translation.tr("Updates every 10s while open"); font.pixelSize: Appearance.font.pixelSize.smallest; color: root.muted }
            }
        }
    }
}
