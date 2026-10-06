import qs.modules.common
import qs.services

import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root

    property bool borderless:
        Config.options.bar.borderless

    property bool alwaysShowAllResources: false
    property bool popupPinned: false

    readonly property bool swapWarning:
        ResourceUsage.swapUsedPercentage * 100
        >= Config.options.bar.resources.swapWarningThreshold

    implicitWidth:
        resourceRow.implicitWidth

    implicitHeight:
        Appearance.sizes.baseBarHeight

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    onClicked:
        root.popupPinned = !root.popupPinned

    RowLayout {
        id: resourceRow

        anchors.centerIn:
            parent

        spacing:
            Appearance.inlayMode
                ? Appearance.spacing.sm
                : Appearance.fluidMode
                    ? 6
                    : 2

        Resource {
            iconName: "memory"
            label: "RAM"
            percentage:
                ResourceUsage.memoryUsedPercentage

            warningThreshold:
                Config.options
                    .bar
                    .resources
                    .memoryWarningThreshold
        }

        Resource {
            iconName: "developer_board"
            label: "CPU"
            percentage:
                ResourceUsage.cpuUsage

            warningThreshold:
                Config.options
                    .bar
                    .resources
                    .cpuWarningThreshold
        }

        Resource {
            iconName: "swap_horiz"
            label: "SWP"
            percentage:
                ResourceUsage.swapUsedPercentage

            shown:
                (
                    root.alwaysShowAllResources
                    && ResourceUsage.swapTotal > 0
                )
                || root.swapWarning

            warningThreshold:
                Config.options
                    .bar
                    .resources
                    .swapWarningThreshold
        }
    }

    ResourcesPopup {
        hoverTarget: root

        // Deliberate interaction: this is an information panel,
        // not a tooltip.
        showOnHover: false
        forceActive: root.popupPinned

        onCloseRequested:
            root.popupPinned = false
    }
}
