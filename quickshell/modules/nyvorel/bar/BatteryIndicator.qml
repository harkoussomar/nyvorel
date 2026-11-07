import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.modules.nyvorel.bar as Bar

MouseArea {
    id: root
    property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""

    property bool borderless: Config.options.bar.borderless
    // Only the horizontal Fluid navbar enables this; all other users are unchanged.
    property bool axiomMode: false

    readonly property bool popupPinned: GlobalStates.isBarPopupOpen("battery", root.barScreenName)

    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow:
        percentage <= Config.options.battery.low / 100

    readonly property int percentValue:
        Math.round(percentage * 100)

    readonly property string valueText:
         percentValue.toString()

    readonly property string powerProfileIcon:
        PowerProfiles.profile === PowerProfile.PowerSaver
            ? "energy_savings_leaf"
            : PowerProfiles.profile === PowerProfile.Performance
                ? "local_fire_department"
                : "airwave"

    readonly property int powerProfileFill:
        PowerProfiles.profile === PowerProfile.Balanced ? 0 : 1

    readonly property string displayIcon:
         isPluggedIn
            ? "bolt"
            : powerProfileIcon

    readonly property int displayIconFill:
         isPluggedIn
            ? 1
            : powerProfileFill

    readonly property color accentColor:
        isLow && !isPluggedIn
            ? Appearance.m3colors.m3error
            : (false)
                ? Appearance.colors.colOnLayer1
                : Appearance.colors.colOnSecondaryContainer

    implicitWidth: root.axiomMode ? axiomBatteryRow.implicitWidth : batteryChip.implicitWidth
    implicitHeight: root.axiomMode ? 24 : batteryChip.implicitHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    onClicked: {
        GlobalStates.toggleBarPopup("battery", root.barScreenName)

        if (root.popupPinned)
            Battery.refreshPowerSettings()
    }

    // Exact Axiom shape: optional charging bolt + 28x4 rail + 11px mono %.
    Row {
        id: axiomBatteryRow
        visible: root.axiomMode
        anchors.centerIn: parent
        spacing: 7

        MaterialSymbol {
            visible: root.isCharging || root.isPluggedIn
            text: "bolt"
            iconSize: Appearance.barVisual.axiomIconSize
            color: root.isLow && !root.isPluggedIn
                ? Appearance.colors.colError : Appearance.barVisual.axiomBatteryAccent
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            width: 28
            height: 4
            radius: 1
            color: Appearance.barVisual.axiomBatteryTrack
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            Rectangle {
                width: parent.width * root.percentage
                height: parent.height
                radius: 1
                color: root.isLow && !root.isPluggedIn
                    ? Appearance.colors.colError : Appearance.barVisual.axiomBatteryAccent
                Behavior on width {
                    enabled: Appearance.barMotion.allowSpatial
                    NumberAnimation { duration: Appearance.barMotion.statusDuration }
                }
            }
        }
        Text {
            text: root.percentValue + "%"
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.barVisual.axiomTextSize
            font.weight: Font.DemiBold
            color: root.isLow && !root.isPluggedIn
                ? Appearance.colors.colError : Appearance.barVisual.axiomValue
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        id: batteryChip
        visible: !root.axiomMode

        anchors.centerIn: parent

        implicitWidth:
              Math.max(
                 72,
                 valueBubble.implicitWidth + iconBubble.width + 12
             )
        implicitHeight: 23
        radius: (height / 2)

        color:
            (false)
                ? "transparent"
                : Appearance.colors.colLayer0
        border.width:
            (false)
                ? 0
                : 1
        border.color:
            Qt.rgba(
                root.accentColor.r,
                root.accentColor.g,
                root.accentColor.b,
                0.78
            )
        antialiasing: true

        Rectangle {
            id: fillPill
            visible: true

            x: 1
            y: 1
            height: parent.height - 2
            width: Math.max(
                iconBubble.x + iconBubble.width + 7,
                Math.round((parent.width - 2) * root.percentage)
            )
            radius: height / 2

            color: root.accentColor
            opacity: 0.9
            antialiasing: true
        }

        Rectangle {
            id: iconBubble

            x: 2
            y: 2
            width:
                 parent.height - 4
            height: width
            radius: height / 2

            color: (false) ? "transparent" : Appearance.colors.colLayer0
            border.width: (false) ? 0 : 1
            border.color: Qt.rgba(
                root.accentColor.r,
                root.accentColor.g,
                root.accentColor.b,
                0.88
            )
            antialiasing: true

            MaterialSymbol {
                anchors.centerIn: parent

                text: root.displayIcon
                fill: root.displayIconFill
                iconSize:
                     14
                animateChange: true
            }
        }

        Rectangle {
            id: valueBubble

            anchors {
                right: parent.right
                rightMargin: 2
                verticalCenter: parent.verticalCenter
            }

            implicitWidth:
                (valueTextItem.implicitWidth)
                + (12)
            height:
                 parent.height - 4
            radius: (height / 2)

            // instead of nesting another pill/card.
            color: (false) ? "transparent" : Appearance.colors.colLayer0
            border.width: (false) ? 0 : 1
            border.color: Qt.rgba(
                root.accentColor.r,
                root.accentColor.g,
                root.accentColor.b,
                0.78
            )
            antialiasing: true

            Text {
                id: valueTextItem
                visible: !false

                anchors.centerIn: parent

                text: root.valueText
                color: "#F7FFF9"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

        }
    }

    Bar.BatteryPopup {
        id: batteryPopup

        hoverTarget: root

        // Click-only popup. Hovering never opens it.
        showOnHover: false

        // Keep the popup alive after the mouse leaves.
        forceActive: root.popupPinned

        onCloseRequested:
            GlobalStates.closeBarPopup("battery", root.barScreenName)
    }
}
