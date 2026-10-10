import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland


Scope {
    id: root

    // More compact than the original Appearance.sizes.sidebarWidth.
    // 420px is still wide enough for the calendar and Android toggles.
    property int sidebarWidth: 420



    // memory-lazy-surfaces-v2
    // Keep the existing module controller resident, but not its native window.
    property bool sidebarRightRetained: false

    Timer {
        id: sidebarRightUnloadTimer
        interval: 300
        repeat: false

        onTriggered: {
            if (!GlobalStates.sidebarRightOpen)
                root.sidebarRightRetained = false
        }
    }

    Connections {
        target: GlobalStates

        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                sidebarRightUnloadTimer.stop()
                root.sidebarRightRetained = true
            } else if (root.sidebarRightRetained) {
                sidebarRightUnloadTimer.restart()
            }
        }
    }

    LazyLoader {
        id: sidebarRightWindowLoader

        active:
            GlobalStates.sidebarRightOpen
            || root.sidebarRightRetained
            || Config?.options.sidebar.keepRightSidebarLoaded

        component: PanelWindow {
            id: panelWindow
    
            // sidebar-material-stability-v2
            // Keep the native host mapped in Glass; the material Loader moves
            // off-canvas while logically closed.
            // phase3c-motion-hardening-v1
            // Fluid and Prism keep the native host mapped; QML owns the material
            // plane motion. Other styles keep their existing map/unmap behavior.
            visible:
                Config.options.appearance.transparency.enable
                || Appearance.prismMode
                || GlobalStates.sidebarRightOpen
    
            implicitWidth:
                root.sidebarWidth
    
            exclusiveZone:
                0
    
            color:
                "transparent"
    
            // glass-system-v2.3b-shape
            Region {
                id: glassSidebarRightVisibleMask
                item: sidebarContentLoader.item
            }
            HyprlandWindow.visibleMask:
                Config.options.appearance.transparency.enable
                    ? glassSidebarRightVisibleMask
                    : null
    
            WlrLayershell.namespace:
                "quickshell:sidebarRight"
    
            mask: Region {
                item:
                    GlobalStates.sidebarRightOpen
                        ? sidebarContentLoader.item
                        : null
            }
    
            WlrLayershell.keyboardFocus:
                GlobalStates.sidebarRightOpen
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None
    
    
            anchors {
                top: true
                right: true
                bottom: true
            }
    
    
            function hide() {
                GlobalStates.sidebarRightOpen = false
            }
    
            // >>> SNIP-TARGETING-V3 sidebarRight >>>
            function syncShellCaptureRegion(): void {
                if (
                    !GlobalStates.regionSelectorOpen
                    ||
                    !GlobalStates.sidebarRightOpen
                    || !panelWindow.screen
                    || !sidebarContentLoader.item
                    || sidebarContentLoader.width <= 0
                    || sidebarContentLoader.height <= 0
                ) {
                    GlobalStates.clearCaptureRegion("sidebarRight")
                    return
                }
    
                const monitor =
                    Hyprland.monitorFor(panelWindow.screen)
                const monitorLayers =
                    HyprlandData.layers[monitor?.name]
                const topLayers =
                    monitorLayers?.levels["2"] ?? []
                const host =
                    topLayers.find(
                        layer =>
                            layer.namespace
                            === "quickshell:sidebarRight"
                    )
    
                if (!host) {
                    GlobalStates.clearCaptureRegion("sidebarRight")
                    return
                }
    
                const monitorX = monitor?.x ?? 0
                const monitorY = monitor?.y ?? 0
    
                GlobalStates.registerCaptureRegion(
                    "sidebarRight",
                    panelWindow.screen.name,
                    host.x - monitorX + sidebarContentLoader.x,
                    host.y - monitorY + sidebarContentLoader.y,
                    sidebarContentLoader.width,
                    sidebarContentLoader.height,
                    165,
                    "Right Sidebar",
                    0
                )
            }
            // <<< SNIP-TARGETING-V3 sidebarRight >>>
    
    
            // ========================================================
            // Global focus / dismiss behavior
            // ========================================================
    
            function syncDismissable(): void {
                if (GlobalStates.sidebarRightOpen && visible)
                    GlobalFocusGrab.addDismissable(panelWindow)
                else
                    GlobalFocusGrab.removeDismissable(panelWindow)
            }
    
            onVisibleChanged: {
                panelWindow.syncDismissable()
                Qt.callLater(
                    () => panelWindow.syncShellCaptureRegion()
                )
            }
    
            Connections {
                target: GlobalStates

                function onRegionSelectorOpenChanged() {
                    panelWindow.syncShellCaptureRegion()
                }
    
                function onSidebarRightOpenChanged() {
                    panelWindow.syncDismissable()
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                }
            }
    
    
            Connections {
                target: GlobalFocusGrab
    
                function onDismissed() {
                    // Keep the sidebar visible while Region Selector is active.
                    // Normal outside-click dismissal resumes after it closes.
                    if (GlobalStates.regionSelectorOpen)
                        return
    
                    panelWindow.hide()
                }
            }
    
    
            // ========================================================
            // Sidebar content
            // ========================================================
    
            Loader {
                id: sidebarContentLoader
    
                property real glassSlideOffset:
                    (
                        Config.options.appearance.transparency.enable
                        || Appearance.prismMode
                    )
                        ? (
                            GlobalStates.sidebarRightOpen
                                ? 0
                                : root.sidebarWidth
                                  + Appearance.sizes.elevationMargin
                          )
                        : 0
    
                Behavior on glassSlideOffset {
                    MotionExpressiveAnim {
                        phase:
                            GlobalStates.sidebarRightOpen
                                ? MotionExpressiveAnim.Enter
                                : MotionExpressiveAnim.Exit
    
                        standardEnterDuration: 500
                        standardExitDuration: 240
                        expressiveEnterDuration: Appearance.prism.enterDuration
                        expressiveExitDuration: Appearance.prism.exitDuration
    
                        standardEnterCurve:
                            Appearance.animationCurves.expressiveDefaultSpatial
    
                        standardExitCurve:
                            Appearance.animationCurves.expressiveFastSpatial
    
                        overshootAmount: 1.025
                    }
                }
    
                active:
                    Config.options.appearance.transparency.enable
                    || Appearance.prismMode
                    || GlobalStates.sidebarRightOpen
                    || Config?.options.sidebar.keepRightSidebarLoaded
    
                focus:
                    GlobalStates.sidebarRightOpen
    
                onGlassSlideOffsetChanged:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                onXChanged:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                onYChanged:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                onWidthChanged:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                onHeightChanged:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                onItemChanged:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
    
                Component.onCompleted:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
    
    
                // prism-v2-phase3a: keep the interactive panel detached by the
                // same semantic negative-space rhythm used by the persistent shell.
                anchors {
                    top: parent.top
                    right: parent.right
                    bottom: parent.bottom
                    left: parent.left
    
                    topMargin:
                        Appearance.prismMode
                            ? Appearance.prism.screenInset + Appearance.prism.islandGap
                            : Appearance.sizes.hyprlandGapsOut
    
                    rightMargin:
                        (Appearance.prismMode
                            ? Appearance.prism.screenInset + Appearance.prism.islandGap
                            : Appearance.sizes.hyprlandGapsOut)
                        - sidebarContentLoader.glassSlideOffset
    
                    bottomMargin:
                        Appearance.prismMode
                            ? Appearance.prism.screenInset + Appearance.prism.islandGap
                            : Appearance.sizes.hyprlandGapsOut
    
                    // Extra left room for the sidebar shadow.
                    leftMargin:
                        Appearance.sizes.elevationMargin
                        + sidebarContentLoader.glassSlideOffset
                }
    
    
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide()
                    }
                }
    
    
                sourceComponent:
                    SidebarRightContent {}
            }
        }
    }


    // ============================================================
    // IPC
    // ============================================================

    IpcHandler {
        target:
            "sidebarRight"


        function toggle(): void {
            GlobalStates.sidebarRightOpen =
                !GlobalStates.sidebarRightOpen
        }


        function close(): void {
            GlobalStates.sidebarRightOpen = false
        }


        function open(): void {
            GlobalStates.sidebarRightOpen = true
        }
    }


    // ============================================================
    // Shortcuts
    // ============================================================

    GlobalShortcut {
        name:
            "sidebarRightToggle"

        description:
            "Toggles right sidebar on press"


        onPressed: {
            GlobalStates.sidebarRightOpen =
                !GlobalStates.sidebarRightOpen
        }
    }


    GlobalShortcut {
        name:
            "sidebarRightOpen"

        description:
            "Opens right sidebar on press"


        onPressed: {
            GlobalStates.sidebarRightOpen = true
        }
    }


    GlobalShortcut {
        name:
            "sidebarRightClose"

        description:
            "Closes right sidebar on press"


        onPressed: {
            GlobalStates.sidebarRightOpen = false
        }
    }
}
