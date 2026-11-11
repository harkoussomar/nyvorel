import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.nyvorel.bar as Bar
import qs.modules.nyvorel.bar.weather as BarWeather
import qs.modules.nyvorel.sidebarLeft
import qs.modules.nyvorel.sidebarRight

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    // Match the horizontal bar's information order from top to bottom.
    readonly property bool axiomOrientation: Appearance.barLayout.axiomComponents
    readonly property bool showResources: Config.options.bar.visibility.resources && root.height >= 900
    readonly property bool showClock: Config.options.bar.visibility.clock
    readonly property bool showTray: root.height >= 700
        && ((TrayService.pinnedItems?.length ?? 0) > 0
            || (TrayService.unpinnedItems?.length ?? 0) > 0)
    readonly property bool hasOtherUtilityActions:
        Config.options.bar.utilButtons.showScreenSnip
        || Config.options.bar.utilButtons.showScreenRecord
        || Config.options.bar.utilButtons.showColorPicker
        || Config.options.bar.utilButtons.showMicToggle
        || Config.options.bar.utilButtons.showDarkModeToggle
        || Config.options.bar.utilButtons.showKeepAwakeToggle
        || Config.options.bar.utilButtons.showNightLightToggle

    component HorizontalBarSeparator: Rectangle {
        Layout.leftMargin: Appearance.sizes.baseBarHeight / 3
        Layout.rightMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.barLayout.axiomComponents ? Appearance.barVisual.axiomDivider : Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: Config.options.bar.showBackground ? Appearance.barVisual.attachedSurfaceFill : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.radius.bar : 0
        border.width: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        Rectangle {
            visible: Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 1
            color: Appearance.colors.colLayer0Border
            width: 1
            height: parent.height - (Config.options.bar.cornerStyle === 0
                ? Appearance.rounding.screenRounding * 2 : 0)
            y: Config.options.bar.cornerStyle === 0
                ? Appearance.rounding.screenRounding : 0
            anchors.left: Config.options.bar.bottom ? parent.left : undefined
            anchors.right: Config.options.bar.bottom ? undefined : parent.right
        }
    }

    FocusedScrollMouseArea { // Top section | scroll to change brightness
        id: barTopSectionMouseArea
        anchors.top: parent.top
        implicitHeight: topSectionColumnLayout.implicitHeight
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        height: (root.height - middleSection.height) / 2
        width: Appearance.sizes.verticalBarWidth

        onScrollDown: {
            if (root.brightnessMonitor?.ready)
                root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness - 0.05)
        }
        onScrollUp: {
            if (root.brightnessMonitor?.ready)
                root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness + 0.05)
        }
        onMovedAway: GlobalStates.osdBrightnessOpen = false

        ColumnLayout { // Content
            id: topSectionColumnLayout
            anchors.fill: parent
            spacing: 10

            Bar.LeftSidebarButton { // Left sidebar button
                id: leftSidebarButton
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: (Appearance.sizes.baseVerticalBarWidth - implicitWidth) / 2 + Appearance.sizes.hyprlandGapsOut
                colBackground: barTopSectionMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
            }

            HorizontalBarSeparator {
                visible: Config.options.bar.utilButtons.showKeyboardLayout
                    || Config.options.bar.utilButtons.showKeyboardToggle
                    || root.hasOtherUtilityActions
                color: Appearance.colors.colOnLayer0
                opacity: 0.32
            }

            Bar.KeyboardLayoutButton {
                visible: Config.options.bar.utilButtons.showKeyboardLayout
                    || Config.options.bar.utilButtons.showKeyboardToggle
                Layout.alignment: Qt.AlignHCenter
            }

            RippleButton {
                id: utilityLauncher
                visible: root.hasOtherUtilityActions
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.radius.control
                toggled: GlobalStates.isBarPopupOpen("utilities", root.screen?.name)
                colBackground: "transparent"
                colBackgroundToggled: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colBackgroundToggledHover: Appearance.colors.colLayer1Hover
                onClicked: GlobalStates.toggleBarPopup("utilities", root.screen?.name)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "tune"
                    iconSize: Appearance.barVisual.axiomIconSize
                    color: Appearance.colors.colOnLayer0
                }
            }

            HorizontalBarSeparator {
                visible: mediaWidget.hasMedia
                    && (Config.options.bar.utilButtons.showKeyboardLayout
                        || Config.options.bar.utilButtons.showKeyboardToggle
                        || root.hasOtherUtilityActions)
                color: Appearance.colors.colOnLayer0
                opacity: 0.32
            }

            VerticalMedia {
                id: mediaWidget
                Layout.alignment: Qt.AlignHCenter
            }

            Item { Layout.fillHeight: true }
        }
    }

    Bar.StyledPopup {
        hoverTarget: leftSidebarButton
        showOnHover: false
        forceActive: GlobalStates.isBarPopupOpen("operations", root.screen?.name)
        irisAnimation: true
        dismissOnOutsideClick: true
        popupRadius: Appearance.radius.bar
        contentMargin: 0
        onDismissRequested: GlobalStates.closeBarPopup("operations", root.screen?.name)
        SidebarLeftContent {}
    }

    Bar.StyledPopup {
        hoverTarget: utilityLauncher
        showOnHover: false
        forceActive: GlobalStates.isBarPopupOpen("utilities", root.screen?.name)
        irisAnimation: true
        dismissOnOutsideClick: true
        popupRadius: Appearance.radius.bar
        contentMargin: 10
        onDismissRequested: GlobalStates.closeBarPopup("utilities", root.screen?.name)
        Bar.UtilButtons { showKeyboardLayoutAction: false }
    }

    Column { // Middle section
        id: middleSection
        anchors.centerIn: parent
        spacing: 4

        Bar.BarGroup {
            id: middleCenterGroup
            vertical: true
            quiet: root.axiomOrientation
            padding: root.axiomOrientation ? 3 : 6

            Bar.Workspaces {
                id: workspacesWidget
                vertical: true
                MouseArea {
                    // Right-click to toggle overview
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton

                    onPressed: event => {
                        if (event.button === Qt.RightButton) {
                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                        }
                    }
                }
            }
        }
    }

    Bar.StyledPopup {
        hoverTarget: rightSidebarButton
        showOnHover: false
        forceActive: GlobalStates.isBarPopupOpen("controls", root.screen?.name)
        irisAnimation: true
        dismissOnOutsideClick: true
        popupRadius: Appearance.radius.bar
        contentMargin: 0
        onDismissRequested: GlobalStates.closeBarPopup("controls", root.screen?.name)
        SidebarRightContent {}
    }

    Bar.NetworkOperationsPopup {
        barScreenName: root.screen?.name
        hoverTarget: networkButton
    }


    FocusedScrollMouseArea { // Bottom section | scroll to change volume
        id: barBottomSectionMouseArea

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        implicitHeight: bottomSectionColumnLayout.implicitHeight
        
        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;

        ColumnLayout {
            id: bottomSectionColumnLayout
            anchors.fill: parent
            spacing: 4

            Item { 
                Layout.fillWidth: true
                Layout.fillHeight: true 
            }

            Bar.BarGroup {
                vertical: true
                Layout.alignment: Qt.AlignHCenter
                quiet: root.axiomOrientation
                padding: root.axiomOrientation ? 3 : 8
                verticalRowSpacing: root.axiomOrientation ? 4 : 8
                visible: root.showResources || root.showClock || root.showTray || Battery.available

                Resources {

                    barScreenName: root.screen?.name
                    visible: root.showResources
                    Layout.fillWidth: true
                }

                HorizontalBarSeparator {
                    visible: root.axiomOrientation && root.showResources && root.showClock
                }

                VerticalClockWidget {

                    barScreenName: root.screen?.name
                    visible: root.showClock
                    Layout.fillWidth: true
                }

                VerticalDateWidget {
                    visible: !root.axiomOrientation && root.showClock
                    Layout.fillWidth: true
                }

                HorizontalBarSeparator {
                    visible: root.axiomOrientation && root.showClock && root.showTray
                }

                Bar.SysTray {

                    barScreenName: root.screen?.name
                    vertical: true
                    axiomMode: root.axiomOrientation
                    showSeparator: !root.axiomOrientation
                    visible: root.showTray
                    Layout.fillWidth: true
                    invertSide: Config?.options.bar.bottom
                }

                HorizontalBarSeparator {
                    visible: root.axiomOrientation && root.showTray && Battery.available
                }

                BatteryIndicator {

                    barScreenName: root.screen?.name
                    visible: Battery.available
                    Layout.fillWidth: true
                }
            }

            HorizontalBarSeparator {
                visible: root.axiomOrientation && Battery.available
            }

            RippleButton {
                id: networkButton
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.small
                toggled: GlobalStates.isBarPopupOpen("network", root.screen?.name)
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colBackgroundToggled: "transparent"
                colBackgroundToggledHover: "transparent"
                colRipple: Appearance.colors.colLayer1Active
                onClicked: GlobalStates.toggleBarPopup("network", root.screen?.name)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: Network.barSymbol
                    iconSize: root.axiomOrientation ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }
            }

            BarWeather.WeatherBar {
                vertical: true
                visible: Config.options.bar.weather.enable
                Layout.alignment: Qt.AlignHCenter
            }

            RippleButton { // Right sidebar button
                id: rightSidebarButton

                Layout.alignment: Qt.AlignBottom | Qt.AlignHCenter
                Layout.bottomMargin: Appearance.rounding.screenRounding
                Layout.fillHeight: false

                implicitHeight: indicatorsColumnLayout.implicitHeight + 4 * 2
                implicitWidth: indicatorsColumnLayout.implicitWidth + 6 * 2

                buttonRadius: root.axiomOrientation ? Appearance.rounding.small : Appearance.rounding.full
                colBackground: barBottomSectionMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                colBackgroundToggled: "transparent"
                colBackgroundToggledHover: "transparent"
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                toggled: GlobalStates.isBarPopupOpen("controls", root.screen?.name)
                property color colText: Appearance.colors.colOnLayer0

                Behavior on colText {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                // nyvorel-phase1b-ripple-click-contract
                onClicked: {
                    GlobalStates.toggleBarPopup("controls", root.screen?.name);
                }

                ColumnLayout {
                    id: indicatorsColumnLayout
                    anchors.centerIn: parent
                    property real realSpacing: root.axiomOrientation ? 4 : 6
                    spacing: 0

                    Revealer {
                        vertical: true
                        reveal: Audio.sink?.audio?.muted ?? false
                        Layout.fillWidth: true
                        Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
                        Behavior on Layout.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "volume_off"
                            iconSize: root.axiomOrientation ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    Revealer {
                        vertical: true
                        reveal: Audio.source?.audio?.muted ?? false
                        Layout.fillWidth: true
                        Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
                        Behavior on Layout.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "mic_off"
                            iconSize: root.axiomOrientation ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    Bar.HyprlandXkbIndicator {
                        vertical: true
                        visible: active
                            && !Config.options.bar.utilButtons.showKeyboardLayout
                            && !Config.options.bar.utilButtons.showKeyboardToggle
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: indicatorsColumnLayout.realSpacing
                        color: rightSidebarButton.colText
                    }
                    Revealer {
                        vertical: true
                        reveal: root.axiomOrientation || Notifications.silent || Notifications.unread > 0
                        Layout.fillWidth: true
                        implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
                        implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
                        Bar.NotificationUnreadCount {
                            id: notificationUnreadCount
                        }
                    }
                    MaterialSymbol {
                        visible: BluetoothStatus.available && BluetoothStatus.enabled
                        Layout.topMargin: visible ? indicatorsColumnLayout.realSpacing : 0
                        text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
                        iconSize: root.axiomOrientation ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                    }
                }
            }
        }
    }
}
