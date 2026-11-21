import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    readonly property bool toastLogicalVisible:
        Notifications.popupList.length > 0 && !GlobalStates.screenLocked
    property bool retainingExit: false
    property string targetScreenName: ""
    readonly property ShellScreen presentedScreen: {
        if (GlobalStates.screenLocked || (!toastLogicalVisible && !retainingExit))
            return null
        return Quickshell.screens.find(screen => screen.name === targetScreenName)
            ?? Quickshell.screens[0]
            ?? null
    }

    function syncPresentation(): void {
        if (GlobalStates.screenLocked) {
            exitTimer.stop()
            retainingExit = false
        } else if (toastLogicalVisible) {
            if (!retainingExit)
                targetScreenName = Hyprland.focusedMonitor?.name ?? ""
            exitTimer.stop()
            retainingExit = true
        } else if (retainingExit) {
            exitTimer.restart()
        }
    }

    onToastLogicalVisibleChanged: syncPresentation()
    Component.onCompleted: syncPresentation()

    Timer {
        id: exitTimer
        interval: Appearance.reducedMotion ? 16
            : Math.ceil(Math.max(Appearance.animationCurves.expressiveFastSpatialDuration,
                Appearance.animationCurves.expressiveFastEffectsDuration) * Appearance.motionScale) + 32
        onTriggered: notificationPopup.retainingExit = false
    }

    Variants {
        model: notificationPopup.presentedScreen ? [notificationPopup.presentedScreen] : []

        PanelWindow {
            id: root
            required property ShellScreen modelData
            screen: modelData

            readonly property bool barOnThisScreen: GlobalStates.barOpen && !GlobalStates.screenLocked
                && (Config.options.bar.screenList.length === 0
                    || Config.options.bar.screenList.includes(modelData.name))

            HyprlandWindow.visibleMask: Config.options.appearance.transparency.enable
                ? glassNotificationVisibleMask : null
            Region {
                id: glassNotificationVisibleMask
                item: listview.contentItem
            }

            WlrLayershell.namespace: "quickshell:notificationPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusiveZone: 0
            anchors {
                top: true
                right: true
                bottom: true
            }
            margins {
                top: root.barOnThisScreen && !Config.options.bar.vertical && !Config.options.bar.bottom
                    ? Appearance.sizes.barHeight + 8 : 0
                right: root.barOnThisScreen && Config.options.bar.vertical && Config.options.bar.bottom
                    ? Appearance.sizes.verticalBarWidth + 8 : 0
            }
            mask: Region {
                item: notificationPopup.toastLogicalVisible ? listview.contentItem : null
            }
            color: "transparent"
            implicitWidth: Appearance.sizes.notificationPopupWidth

            NotificationToastList {
                id: listview
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                    rightMargin: 8
                    topMargin: 8
                }
                implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
                clip: true
                populate: add
            }
        }
    }
}
