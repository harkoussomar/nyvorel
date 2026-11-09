import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import QtQuick.Controls

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    // notification-toast-material-stability-v1
    readonly property bool toastLogicalVisible:
        Notifications.popupList.length > 0
        && !GlobalStates.screenLocked
    property string targetScreenName: Hyprland.focusedMonitor?.name ?? ""

    onToastLogicalVisibleChanged: {
        if (toastLogicalVisible)
            targetScreenName = Hyprland.focusedMonitor?.name ?? ""
    }


    PanelWindow {
        id: root


        visible:
            Config.options.appearance.transparency.enable
                ? true
                : notificationPopup.toastLogicalVisible

        screen:
            Quickshell.screens.find(
                (screen) =>
                    screen.name
                    === notificationPopup.targetScreenName
            )
            ?? Quickshell.screens[0]
            ?? null

        readonly property bool barOnThisScreen:
            GlobalStates.barOpen
            && !GlobalStates.screenLocked
            && (
                Config.options.bar.screenList.length === 0
                || Config.options.bar.screenList.includes(root.screen?.name)
            )


        // glass-system-v2.3b-shape
        Region {
            id: glassNotificationVisibleMask
            item:
                notificationPopup.toastLogicalVisible
                    ? listview.contentItem
                    : null
        }
        HyprlandWindow.visibleMask:
            Config.options.appearance.transparency.enable
                ? glassNotificationVisibleMask
                : null

        WlrLayershell.namespace:
            "quickshell:notificationPopup"


        WlrLayershell.layer:
            WlrLayer.Overlay


        exclusiveZone:
            0


        anchors {
            top:
                true

            right:
                true

            bottom:
                true
        }

        margins {
            top: root.barOnThisScreen && !Config.options.bar.vertical && !Config.options.bar.bottom
                ? Appearance.sizes.barHeight + 8 : 0
            right: root.barOnThisScreen && Config.options.bar.vertical && Config.options.bar.bottom
                ? Appearance.sizes.verticalBarWidth + 8 : 0
        }


        mask:
            Region {
                item:
                    notificationPopup.toastLogicalVisible
                        ? listview.contentItem
                        : null
            }


        color:
            "transparent"


        implicitWidth:
            Appearance
                .sizes
                .notificationPopupWidth


        // notification-architecture-v2
        // Popup presentation is deliberately flat: one delegate per
        // notification. App grouping remains a notification-center concern.
        NotificationToastList {
            id: listview


            anchors {
                top:
                    parent.top

                bottom:
                    parent.bottom

                right:
                    parent.right

                rightMargin:
                      8

                topMargin:
                      8
            }


            implicitWidth:
                parent.width
                - Appearance
                    .sizes
                    .elevationMargin
                    * 2


            clip:
                true
        }
    }
}
