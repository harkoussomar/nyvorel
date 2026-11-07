import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property string iconName
    required property double percentage
    property int warningThreshold: 100
    implicitHeight: Appearance.barLayout.axiomComponents ? 45 : resourceProgress.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    property bool warning: percentage * 100 >= warningThreshold

    ClippedFilledCircularProgress {
        id: resourceProgress
        anchors.centerIn: parent
        visible: !Appearance.barLayout.axiomComponents
        value: percentage
        enableAnimation: false
        colPrimary: root.warning ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
        accountForLightBleeding: !root.warning

        MaterialSymbol {
            font.weight: Font.Medium
            fill: 1
            text: root.iconName
            iconSize: 13
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    // The same theme-driven 24px utilization rings as horizontal Axiom,
    // with values below them for a narrow vertical rail.
    CircularProgress {
        id: axiomProgress
        visible: Appearance.barLayout.axiomComponents
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        implicitSize: Appearance.barVisual.axiomRingSize
        lineWidth: 2
        gapAngle: 0
        value: root.percentage
        enableAnimation: false
        colPrimary: root.warning ? Appearance.colors.colError
            : root.iconName === "memory" ? Appearance.barVisual.axiomRamAccent
            : Appearance.barVisual.axiomCpuAccent
        colSecondary: Appearance.barVisual.axiomBatteryTrack
        MaterialSymbol {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1
            text: root.iconName
            fill: 0
            iconSize: Appearance.barVisual.axiomIconSize - 2
            color: axiomProgress.colPrimary
        }
    }
    StyledText {
        visible: Appearance.barLayout.axiomComponents
        anchors.top: axiomProgress.bottom
        anchors.topMargin: 3
        anchors.horizontalCenter: parent.horizontalCenter
        text: Math.round(Math.max(0, Math.min(1, root.percentage)) * 100) + "%"
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.barVisual.axiomTextSize - 2
        color: root.warning ? Appearance.colors.colError : Appearance.barVisual.axiomValue
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        enabled: root.visible
    }
}
