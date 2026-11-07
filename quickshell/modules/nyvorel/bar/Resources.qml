import qs
import qs.modules.common
import qs.services

import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""

    property bool borderless:
        Config.options.bar.borderless

    property bool alwaysShowAllResources: false
    property bool axiomMode: false
    readonly property bool popupPinned: GlobalStates.isBarPopupOpen("resources", root.barScreenName)

    readonly property bool swapWarning:
        ResourceUsage.swapUsedPercentage * 100
        >= Config.options.bar.resources.swapWarningThreshold

    implicitWidth:
        resourceRow.implicitWidth

    // nyvorel-phase3b-component-plane: stay level with clock/media/workspaces.
    implicitHeight:
        Appearance.barLayout.persistentHeight

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    onClicked:
        GlobalStates.toggleBarPopup("resources", root.barScreenName)

    RowLayout {
        id: resourceRow

        anchors.centerIn:
            parent

        spacing:
            root.axiomMode ? 8 : Appearance.fluidMode ? 6 : 2

        Resource {
            axiomMode: root.axiomMode
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

        Rectangle {
            visible: root.axiomMode
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 1
            implicitHeight: 20
            color: Appearance.barVisual.axiomDivider
        }

        Resource {
            axiomMode: root.axiomMode
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

        Rectangle {
            visible: root.axiomMode && root.swapWarning
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.swapWarning ? 1 : 0
            implicitHeight: 20
            color: Appearance.barVisual.axiomDivider
        }

        Resource {
            axiomMode: root.axiomMode
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
            GlobalStates.closeBarPopup("resources", root.barScreenName)
    }
}
