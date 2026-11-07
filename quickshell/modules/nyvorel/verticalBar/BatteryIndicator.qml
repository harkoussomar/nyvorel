import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.nyvorel.bar as Bar

MouseArea {
    id: root
    property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""
    property bool borderless: Config.options.bar.borderless
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property bool popupPinned: GlobalStates.isBarPopupOpen("battery", root.barScreenName)

    implicitHeight: Appearance.barLayout.axiomComponents ? 38 : batteryProgress.implicitHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: GlobalStates.toggleBarPopup("battery", root.barScreenName)

    ClippedProgressBar {
        id: batteryProgress
        visible: !Appearance.barLayout.axiomComponents
        anchors.centerIn: parent
        vertical: true
        valueBarWidth: 21
        valueBarHeight: 40
        value: percentage
        highlightColor: (isLow && !isCharging) ? Appearance.m3colors.m3error : Appearance.colors.colOnSecondaryContainer

        font {
            pixelSize: text.length > 2 ? 11 : 13
            weight: text.length > 2 ? Font.Medium : Font.DemiBold
        }

        textMask: Item {
            anchors.centerIn: parent
            width: batteryProgress.valueBarWidth
            height: batteryProgress.valueBarHeight

            StyledText {
                anchors.centerIn: parent
                font: batteryProgress.font
                text: batteryProgress.text
            }
        }
    }

    // Axiom vertical energy readout. The original popup and Battery service
    // remain on the same MouseArea; no new popup path or window is added.
    Item {
        id: axiomBattery
        visible: Appearance.barLayout.axiomComponents
        width: Appearance.sizes.verticalBarWidth
        height: 38
        anchors.centerIn: parent
        Rectangle {
            id: axiomBatteryRail
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: 4
            height: 20
            radius: 1
            color: Appearance.barVisual.axiomBatteryTrack
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.height * Math.max(0, Math.min(1, root.percentage))
                radius: 1
                color: root.isLow && !root.isCharging
                    ? Appearance.colors.colError : Appearance.barVisual.axiomBatteryAccent
            }
        }
        StyledText {
            anchors.top: axiomBatteryRail.bottom
            anchors.topMargin: 3
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.barVisual.axiomTextSize - 2
            color: Appearance.barVisual.axiomValue
            text: Math.round(Math.max(0, Math.min(1, root.percentage)) * 100) + "%"
        }
    }

    Bar.BatteryPopup {
        id: batteryPopup
        hoverTarget: root
        showOnHover: false
        forceActive: root.popupPinned
        onCloseRequested: GlobalStates.closeBarPopup("battery", root.barScreenName)
    }
}
