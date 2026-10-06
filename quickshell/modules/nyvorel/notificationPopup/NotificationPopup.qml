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
                    === Hyprland
                        .focusedMonitor
                        ?.name
            )
            ?? null


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
                    Appearance.inlayMode
                        ? Appearance.sizes.hyprlandGapsOut
                        : Appearance.prismMode
                            ? Appearance.prism.screenInset
                            : 8

                topMargin:
                    Appearance.inlayMode
                        ? Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
                        : Appearance.prismMode
                            ? Appearance.sizes.barHeight + Appearance.prism.islandGap
                            : 8
            }


            implicitWidth:
                parent.width
                - Appearance
                    .sizes
                    .elevationMargin
                    * 2


            clip:
                !Appearance.prismMode && !Appearance.inlayMode
        }
    }
}