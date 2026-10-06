import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.modules.nyvorel.bar as Bar

MouseArea {
    id: root

    property bool borderless: Config.options.bar.borderless

    property bool popupPinned: false

    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow:
        percentage <= Config.options.battery.low / 100

    readonly property int percentValue:
        Math.round(percentage * 100)

    readonly property string valueText:
        Appearance.inlayMode
            ? `${percentValue}%`
            : percentValue.toString()

    readonly property string inlayBatteryIcon:
        isCharging || isPluggedIn
            ? "battery_charging_full"
            : percentValue >= 90
                ? "battery_full"
                : percentValue >= 75
                    ? "battery_6_bar"
                    : percentValue >= 60
                        ? "battery_5_bar"
                        : percentValue >= 45
                            ? "battery_4_bar"
                            : percentValue >= 30
                                ? "battery_3_bar"
                                : percentValue >= 15
                                    ? "battery_2_bar"
                                    : "battery_1_bar"

    readonly property string powerProfileIcon:
        PowerProfiles.profile === PowerProfile.PowerSaver
            ? "energy_savings_leaf"
            : PowerProfiles.profile === PowerProfile.Performance
                ? "local_fire_department"
                : "airwave"

    readonly property int powerProfileFill:
        PowerProfiles.profile === PowerProfile.Balanced ? 0 : 1

    readonly property string displayIcon:
        Appearance.inlayMode
            ? inlayBatteryIcon
            : isPluggedIn
                ? "bolt"
                : powerProfileIcon

    readonly property int displayIconFill:
        Appearance.inlayMode
            ? 1
            : isPluggedIn
                ? 1
                : powerProfileFill

    readonly property color accentColor:
        isLow && !isPluggedIn
            ? Appearance.m3colors.m3error
            : (Appearance.prismMode || Appearance.inlayMode)
                ? Appearance.colors.colOnLayer1
                : Appearance.colors.colOnSecondaryContainer

    implicitWidth: batteryChip.implicitWidth
    implicitHeight: batteryChip.implicitHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    onClicked: {
        root.popupPinned = !root.popupPinned

        if (root.popupPinned)
            Battery.refreshPowerSettings()
    }

    Rectangle {
        id: batteryChip

        anchors.centerIn: parent

        implicitWidth:
            Appearance.inlayMode
                ? valueBubble.implicitWidth + iconBubble.width + 2
                : Appearance.prismMode
                    ? valueBubble.implicitWidth + iconBubble.width + 8
                    : Math.max(
                        72,
                        valueBubble.implicitWidth + iconBubble.width + 12
                    )
        implicitHeight: 23
        radius: Appearance.inlayMode ? 0 : (Appearance.prismMode ? Appearance.prism.radiusControl : height / 2)

        color:
            (Appearance.prismMode || Appearance.inlayMode)
                ? "transparent"
                : Appearance.colors.colLayer0
        border.width:
            (Appearance.prismMode || Appearance.inlayMode)
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
            visible: !Appearance.prismMode && !Appearance.inlayMode

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

            x: Appearance.inlayMode ? 0 : 2
            y: Appearance.inlayMode ? Math.round((parent.height - height) / 2) : 2
            width:
                Appearance.inlayMode
                    ? 18
                    : parent.height - 4
            height: width
            radius: Appearance.inlayMode ? 0 : height / 2

            color: (Appearance.prismMode || Appearance.inlayMode) ? "transparent" : Appearance.colors.colLayer0
            border.width: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 1
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
                    Appearance.inlayMode
                        ? Appearance.font.pixelSize.larger
                        : 14
                animateChange: true
            }
        }

        Rectangle {
            id: valueBubble

            anchors {
                right: parent.right
                rightMargin: Appearance.inlayMode ? 0 : 2
                verticalCenter: parent.verticalCenter
            }

            implicitWidth:
                (Appearance.inlayMode
                    ? inlayValueText.implicitWidth
                    : valueTextItem.implicitWidth)
                + (Appearance.inlayMode
                    ? 2
                    : Appearance.prismMode
                        ? 4
                        : 12)
            height:
                Appearance.inlayMode
                    ? parent.height
                    : parent.height - 4
            radius: Appearance.inlayMode ? 0 : (Appearance.prismMode ? Appearance.prism.radiusControl : height / 2)

            // Prism and Inlay integrate battery into their owning system region
            // instead of nesting another pill/card.
            color: (Appearance.prismMode || Appearance.inlayMode) ? "transparent" : Appearance.colors.colLayer0
            border.width: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 1
            border.color: Qt.rgba(
                root.accentColor.r,
                root.accentColor.g,
                root.accentColor.b,
                0.78
            )
            antialiasing: true

            Text {
                id: valueTextItem
                visible: !Appearance.inlayMode

                anchors.centerIn: parent

                text: root.valueText
                color: Appearance.prismMode ? root.accentColor : "#F7FFF9"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            StyledText {
                id: inlayValueText
                visible: Appearance.inlayMode

                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1

                text: root.valueText
                color: root.accentColor
                font.pixelSize: Appearance.font.pixelSize.small
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
            root.popupPinned = false
    }
}
