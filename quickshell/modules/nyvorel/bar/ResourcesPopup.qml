import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Io

StyledPopup {
    id: root

    popupColor:
        Appearance.colors.colLayer0
    popupRadius:
        Appearance.radius.popup

    dismissOnOutsideClick: true

    signal closeRequested()

    onDismissRequested:
        root.closeRequested()

    property string diskUsedText: "—"
    property string diskTotalText: "—"
    property real diskPercent: 0

    property string networkName: "—"
    property string networkType: "—"
    property string networkDevice: "—"

    property real load1: 0
    property real load5: 0
    property real load15: 0
    property int logicalCpuCount: 1

    property string topProcessName: "—"
    property string topProcessCpu: "—"
    property string topProcessMemory: "—"

    readonly property real memoryPercent:
        root.clamp(ResourceUsage.memoryUsedPercentage)
    readonly property real cpuPercent:
        root.clamp(ResourceUsage.cpuUsage)
    readonly property real swapPercent:
        root.clamp(ResourceUsage.swapUsedPercentage)

    readonly property int memoryThreshold:
        Config.options.bar.resources.memoryWarningThreshold
    readonly property int cpuThreshold:
        Config.options.bar.resources.cpuWarningThreshold
    readonly property int swapThreshold:
        Config.options.bar.resources.swapWarningThreshold

    readonly property bool memoryCritical:
        memoryPercent * 100 >= memoryThreshold
    readonly property bool cpuCritical:
        cpuPercent * 100 >= cpuThreshold
    readonly property bool swapCritical:
        swapPercent * 100 >= swapThreshold
    readonly property bool diskCritical:
        diskPercent >= 0.90

    readonly property bool memoryElevated:
        !memoryCritical
        && memoryPercent * 100 >= Math.max(80, memoryThreshold - 10)

    readonly property string healthText: {
        if (memoryCritical)
            return Translation.tr("Memory critical")
        if (cpuCritical)
            return Translation.tr("CPU critical")
        if (swapCritical)
            return Translation.tr("Swap critical")
        if (diskCritical)
            return Translation.tr("Disk almost full")
        if (memoryElevated)
            return Translation.tr("Memory high")
        return Translation.tr("Normal")
    }

    readonly property color healthAccent:
        (
            memoryCritical
            || cpuCritical
            || swapCritical
            || diskCritical
        )
            ? Appearance.colors.colError
            : Appearance.colors.colPrimary

    readonly property real loadPerCpu:
        logicalCpuCount > 0
            ? load1 / logicalCpuCount
            : 0

    function clamp(value) {
        return Math.max(0, Math.min(1, value))
    }

    function formatKB(kb) {
        if (!kb || kb <= 0)
            return "0 GB"

        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    function compactGB(kb) {
        if (!kb || kb <= 0)
            return "0"

        return (kb / (1024 * 1024)).toFixed(1)
    }

    function trendText(values) {
        if (!values || values.length < 2)
            return Translation.tr("warming up")

        const newest = Number(values[values.length - 1])
        const lookbackIndex = Math.max(0, values.length - 6)
        const previous = Number(values[lookbackIndex])
        const delta = Math.round((newest - previous) * 100)

        if (Math.abs(delta) < 2)
            return Translation.tr("steady")
        if (delta > 0)
            return "↑ " + delta + "%"

        return "↓ " + Math.abs(delta) + "%"
    }

    function networkTypeLabel(type) {
        if (
            type === "wireless"
            || type === "wifi"
            || type === "802-11-wireless"
        )
            return Translation.tr("Wi-Fi")

        if (
            type === "ethernet"
            || type === "802-3-ethernet"
        )
            return Translation.tr("Ethernet")

        return type.length > 0
            ? type
            : Translation.tr("Network")
    }

    function refreshSystemProbe() {
        if (systemProbe.running)
            return

        systemProbe.running = true
    }

    property var systemProbe: Process {
        command: [
            "sh",
            "-lc",
            "disk=\"$(df -Pk / | awk 'NR==2 {print $3 \"|\" $2 \"|\" $5}')\"; "
            + "network=\"$(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null "
            + "| awk -F: '$2 ~ /wireless|wifi|ethernet|802-11-wireless|802-3-ethernet/ "
            + "{print $1 \"|\" $2 \"|\" $3; exit}')\"; "
            + "load=\"$(awk '{print $1 \"|\" $2 \"|\" $3}' /proc/loadavg)\"; "
            + "cpus=\"$(nproc 2>/dev/null || printf 1)\"; "
            + "topproc=\"$(ps -eo comm=,%cpu=,%mem= --sort=-%cpu 2>/dev/null "
            + "| awk 'NR==1 {printf \"%s|%s|%s\", $1, $2, $3}')\"; "
            + "printf 'DISK=%s\\nNETWORK=%s\\nLOAD=%s\\nCPUS=%s\\nTOP=%s\\n' "
            + "\"$disk\" \"$network\" \"$load\" \"$cpus\" \"$topproc\""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n")

                for (const line of lines) {
                    if (line.startsWith("DISK=")) {
                        const fields =
                            line.substring(5).split("|")

                        if (fields.length >= 3) {
                            root.diskUsedText =
                                root.formatKB(Number(fields[0]))
                            root.diskTotalText =
                                root.formatKB(Number(fields[1]))
                            root.diskPercent =
                                Number(
                                    fields[2].replace("%", "")
                                ) / 100
                        }
                    } else if (line.startsWith("NETWORK=")) {
                        const fields =
                            line.substring(8).split("|")

                        root.networkName =
                            fields.length > 0
                            && fields[0].length > 0
                                ? fields[0]
                                : Translation.tr("Disconnected")

                        root.networkType =
                            fields.length > 1
                                ? fields[1]
                                : ""

                        root.networkDevice =
                            fields.length > 2
                                ? fields[2]
                                : ""
                    } else if (line.startsWith("LOAD=")) {
                        const fields =
                            line.substring(5).split("|")

                        if (fields.length >= 3) {
                            root.load1 =
                                Number(fields[0]) || 0
                            root.load5 =
                                Number(fields[1]) || 0
                            root.load15 =
                                Number(fields[2]) || 0
                        }
                    } else if (line.startsWith("CPUS=")) {
                        root.logicalCpuCount =
                            Math.max(
                                1,
                                Number(line.substring(5)) || 1
                            )
                    } else if (line.startsWith("TOP=")) {
                        const fields =
                            line.substring(4).split("|")

                        root.topProcessName =
                            fields.length > 0
                            && fields[0].length > 0
                                ? fields[0]
                                : "—"

                        root.topProcessCpu =
                            fields.length > 1
                                ? fields[1]
                                : "—"

                        root.topProcessMemory =
                            fields.length > 2
                                ? fields[2]
                                : "—"
                    }
                }
            }
        }
    }

    property var systemProbeTimer: Timer {
        interval: 10000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered:
            root.refreshSystemProbe()
    }

    Item {
        id: contentFrame

        anchors.centerIn:
            parent

        implicitWidth: 382
        implicitHeight:
            content.implicitHeight

        ColumnLayout {
            id: content

            anchors {
                left:
                    parent.left
                right:
                    parent.right
                top:
                    parent.top
            }

            spacing: 9

            // ====================================================
            // Header / overall health
            // ====================================================
            RowLayout {
                Layout.fillWidth:
                    true

                spacing: 9

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius:
                        Appearance.radius.control

                    color:
                        Appearance.colors.colLayer1

                    MaterialSymbol {
                        anchors.centerIn:
                            parent

                        text: "monitoring"
                        fill: 1
                        iconSize: 21
                        color:
                            root.healthAccent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth:
                        true

                    spacing: 0

                    StyledText {
                        text:
                            Translation.tr("System")

                        font.pixelSize:
                            Appearance.font.pixelSize.normal
                        font.weight:
                            Font.DemiBold

                        color:
                            Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        text:
                            Translation.tr("Live health overview")

                        font.pixelSize:
                            Appearance.font.pixelSize.smaller

                        color:
                            Appearance.colors.colSubtext
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitWidth: 0
                }

                Rectangle {
                    Layout.alignment:
                        Qt.AlignRight | Qt.AlignVCenter

                    implicitWidth:
                        healthLabel.implicitWidth + 16
                    implicitHeight: 26

                    radius:
                        height / 2

                    color:
                        Appearance.colors.colLayer1

                    border.width: 1
                    border.color:
                        root.healthAccent

                    RowLayout {
                        anchors.centerIn:
                            parent

                        spacing: 5

                        Rectangle {
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: 3
                            color:
                                root.healthAccent
                        }

                        StyledText {
                            id: healthLabel

                            text:
                                root.healthText

                            font.pixelSize:
                                Appearance.font.pixelSize.smallest
                            font.weight:
                                Font.DemiBold

                            color:
                                root.healthAccent
                        }
                    }
                }
            }

            // ====================================================
            // Primary resources
            // ====================================================
            GridLayout {
                Layout.fillWidth:
                    true

                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                MetricCard {
                    Layout.fillWidth: true

                    icon: "memory"
                    title:
                        Translation.tr("Memory")
                    valueText:
                        `${Math.round(root.memoryPercent * 100)}%`
                    detailText:
                        `${root.compactGB(ResourceUsage.memoryUsed)} / `
                        + `${root.compactGB(ResourceUsage.memoryTotal)} GB`
                    trend:
                        root.trendText(
                            ResourceUsage.memoryUsageHistory
                        )
                    progress:
                        root.memoryPercent
                    critical:
                        root.memoryCritical
                }

                MetricCard {
                    Layout.fillWidth: true

                    icon: "developer_board"
                    title:
                        Translation.tr("CPU")
                    valueText:
                        `${Math.round(root.cpuPercent * 100)}%`
                    detailText:
                        Translation.tr("%1 logical CPUs")
                            .arg(root.logicalCpuCount)
                    trend:
                        root.trendText(
                            ResourceUsage.cpuUsageHistory
                        )
                    progress:
                        root.cpuPercent
                    critical:
                        root.cpuCritical
                }

                MetricCard {
                    Layout.fillWidth: true

                    icon: "swap_horiz"
                    title:
                        Translation.tr("Swap")
                    valueText:
                        `${Math.round(root.swapPercent * 100)}%`
                    detailText:
                        `${root.compactGB(ResourceUsage.swapUsed)} / `
                        + `${root.compactGB(ResourceUsage.swapTotal)} GB`
                    trend:
                        root.trendText(
                            ResourceUsage.swapUsageHistory
                        )
                    progress:
                        root.swapPercent
                    critical:
                        root.swapCritical
                }

                MetricCard {
                    Layout.fillWidth: true

                    icon: "hard_drive"
                    title:
                        Translation.tr("Disk")
                    valueText:
                        `${Math.round(root.diskPercent * 100)}%`
                    detailText:
                        `${root.diskUsedText} / ${root.diskTotalText}`
                    trend:
                        Translation.tr("root filesystem")
                    progress:
                        root.clamp(root.diskPercent)
                    critical:
                        root.diskCritical
                }
            }

            // ====================================================
            // Network + load
            // ====================================================
            InfoSection {
                icon: "wifi"
                title:
                    root.networkName
                detail:
                    root.networkTypeLabel(
                        root.networkType
                    )
                    + (
                        root.networkDevice.length > 0
                            ? " · " + root.networkDevice
                            : ""
                    )
                trailing:
                    Translation.tr("Connected")
            }

            InfoSection {
                icon: "speed"
                title:
                    Translation.tr("Load average")
                detail:
                    root.load1.toFixed(2)
                    + " · "
                    + root.load5.toFixed(2)
                    + " · "
                    + root.load15.toFixed(2)
                trailing:
                    root.loadPerCpu.toFixed(2)
                    + " / CPU"
            }

            // ====================================================
            // Top CPU process
            // ====================================================
            Rectangle {
                Layout.fillWidth:
                    true

                implicitHeight: 58
                radius:
                    Appearance.radius.card

                color:
                    Appearance.colors.colLayer1

                border.width: 1
                border.color:
                    Appearance.colors.colLayer0Border

                RowLayout {
                    anchors {
                        fill:
                            parent
                        leftMargin: 10
                        rightMargin: 11
                    }

                    spacing: 9

                    Rectangle {
                        implicitWidth: 30
                        implicitHeight: 30
                        radius:
                            Appearance.radius.control

                        color:
                            Appearance.colors.colLayer2

                        MaterialSymbol {
                            anchors.centerIn:
                                parent

                            text: "memory_alt"
                            iconSize: 17
                            fill: 1

                            color:
                                Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth:
                            true

                        spacing: 0

                        StyledText {
                            Layout.fillWidth:
                                true

                            text:
                                Translation.tr("Top CPU process")

                            font.pixelSize:
                                Appearance.font.pixelSize.smallest

                            color:
                                Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth:
                                true

                            text:
                                root.topProcessName

                            font.pixelSize:
                                Appearance.font.pixelSize.small
                            font.weight:
                                Font.DemiBold

                            color:
                                Appearance.colors.colOnLayer1

                            elide:
                                Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        spacing: 0

                        StyledText {
                            Layout.alignment:
                                Qt.AlignRight

                            text:
                                root.topProcessCpu === "—"
                                    ? "—"
                                    : root.topProcessCpu + "% CPU"

                            font.pixelSize:
                                Appearance.font.pixelSize.small
                            font.weight:
                                Font.DemiBold

                            color:
                                Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.alignment:
                                Qt.AlignRight

                            text:
                                root.topProcessMemory === "—"
                                    ? ""
                                    : root.topProcessMemory + "% RAM"

                            font.pixelSize:
                                Appearance.font.pixelSize.smallest

                            color:
                                Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // ====================================================
            // Compact footer: uptime only. Battery is intentionally
            // omitted because it has its own dedicated bar popup.
            // ====================================================
            RowLayout {
                Layout.fillWidth:
                    true

                spacing: 5

                MaterialSymbol {
                    text: "schedule"
                    iconSize: 14

                    color:
                        Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth:
                        true

                    text:
                        Translation.tr("Uptime")
                        + " · "
                        + DateTime.uptime

                    font.pixelSize:
                        Appearance.font.pixelSize.smallest

                    color:
                        Appearance.colors.colSubtext
                }

                StyledText {
                    text:
                        Translation.tr("updates every 10s")

                    font.pixelSize:
                        Appearance.font.pixelSize.smallest

                    color:
                        Appearance.colors.colSubtext
                }
            }
        }
    }

    component MetricCard: Rectangle {
        id: card

        required property string icon
        required property string title
        required property string valueText
        required property string detailText
        required property string trend
        required property real progress

        property bool critical: false

        readonly property color accent:
            critical
                ? Appearance.colors.colError
                : Appearance.colors.colPrimary

        implicitHeight: 92

        radius:
            Appearance.radius.card

        color:
            Appearance.colors.colLayer1

        border.width: 1
        border.color:
            Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors {
                fill:
                    parent
                margins: 10
            }

            spacing: 6

            RowLayout {
                Layout.fillWidth:
                    true

                spacing: 7

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28

                    radius:
                        Appearance.radius.control

                    color:
                        Appearance.colors.colLayer2

                    MaterialSymbol {
                        anchors.centerIn:
                            parent

                        text:
                            card.icon
                        iconSize: 16
                        fill: 1
                        color:
                            card.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth:
                        true

                    spacing: 0

                    StyledText {
                        Layout.fillWidth:
                            true

                        text:
                            card.title

                        font.pixelSize:
                            Appearance.font.pixelSize.small
                        font.weight:
                            Font.DemiBold

                        color:
                            Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth:
                            true

                        text:
                            card.detailText

                        font.pixelSize:
                            Appearance.font.pixelSize.smallest

                        color:
                            Appearance.colors.colSubtext

                        elide:
                            Text.ElideRight
                    }
                }

                StyledText {
                    text:
                        card.valueText

                    font.pixelSize:
                        Appearance.font.pixelSize.small
                    font.weight:
                        Font.DemiBold

                    color:
                        card.accent
                }
            }

            RowLayout {
                Layout.fillWidth:
                    true

                spacing: 7

                Rectangle {
                    Layout.fillWidth:
                        true

                    implicitHeight: 5
                    radius:
                        height / 2

                    color:
                        Appearance.colors.colLayer3

                    clip: true

                    Rectangle {
                        anchors {
                            left:
                                parent.left
                            top:
                                parent.top
                            bottom:
                                parent.bottom
                        }

                        width:
                            parent.width
                            * root.clamp(card.progress)

                        radius:
                            parent.radius

                        color:
                            card.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: 160
                                easing.type:
                                    Easing.OutCubic
                            }
                        }
                    }
                }

                StyledText {
                    text:
                        card.trend

                    font.pixelSize:
                        Appearance.font.pixelSize.smallest

                    color:
                        card.critical
                            ? Appearance.colors.colError
                            : Appearance.colors.colSubtext
                }
            }
        }
    }

    component InfoSection: Rectangle {
        id: info

        required property string icon
        required property string title
        required property string detail
        required property string trailing

        Layout.fillWidth:
            true

        implicitHeight: 52

        radius:
            Appearance.radius.card

        color:
            Appearance.colors.colLayer1

        border.width: 1
        border.color:
            Appearance.colors.colLayer0Border

        RowLayout {
            anchors {
                fill:
                    parent
                leftMargin: 10
                rightMargin: 11
            }

            spacing: 9

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius:
                    Appearance.radius.control

                color:
                    Appearance.colors.colLayer2

                MaterialSymbol {
                    anchors.centerIn:
                        parent

                    text:
                        info.icon
                    iconSize: 16
                    fill: 1

                    color:
                        Appearance.colors.colPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth:
                    true

                spacing: 0

                StyledText {
                    Layout.fillWidth:
                        true

                    text:
                        info.title

                    font.pixelSize:
                        Appearance.font.pixelSize.small
                    font.weight:
                        Font.Medium

                    color:
                        Appearance.colors.colOnLayer1

                    elide:
                        Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth:
                        true

                    text:
                        info.detail

                    font.pixelSize:
                        Appearance.font.pixelSize.smallest

                    color:
                        Appearance.colors.colSubtext

                    elide:
                        Text.ElideRight
                }
            }

            StyledText {
                Layout.maximumWidth: 110

                text:
                    info.trailing

                horizontalAlignment:
                    Text.AlignRight

                font.pixelSize:
                    Appearance.font.pixelSize.smallest
                font.weight:
                    Font.Medium

                color:
                    Appearance.colors.colSubtext

                elide:
                    Text.ElideRight
            }
        }
    }
}
