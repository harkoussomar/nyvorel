import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool detach: false
    property bool pin: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent

    function toggleDetach() {
        root.detach = !root.detach;
    }

    function togglePin() {
        root.pin = !root.pin
    }

    // memory-lazy-surfaces-v2
    // Keep the native host/controller behavior, but create the expensive
    // SidebarLeftContent object only when it is actually needed.
    function attachSidebarContent(): void {
        if (!root.sidebarContent)
            return

        if (root.detach) {
            if (detachedSidebarLoader.item?.contentParent)
                detachedSidebarLoader.item.contentParent.children =
                    [root.sidebarContent]
        } else {
            if (sidebarLoader.item?.contentParent)
                sidebarLoader.item.contentParent.children =
                    [root.sidebarContent]
        }
    }

    function ensureSidebarContent(): void {
        if (!root.sidebarContent) {
            root.sidebarContent =
                contentComponent.createObject(
                    null,
                    { "scopeRoot": root }
                )
        }

        Qt.callLater(root.attachSidebarContent)
    }

    function releaseSidebarContent(): void {
        if (
            !root.sidebarContent
            || GlobalStates.sidebarLeftOpen
            || root.pin
            || root.detach
        )
            return

        root.sidebarContent.parent = null
        root.sidebarContent.destroy()
        root.sidebarContent = null
    }

    Timer {
        id: sidebarContentUnloadTimer
        interval: 380
        repeat: false
        onTriggered: root.releaseSidebarContent()
    }

    Connections {
        target: GlobalStates

        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                sidebarContentUnloadTimer.stop()
                Qt.callLater(root.ensureSidebarContent)
            } else if (!root.pin && !root.detach) {
                sidebarContentUnloadTimer.restart()
            }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.sidebarLeftOpen)
            Qt.callLater(root.ensureSidebarContent)
    }

onDetachChanged: {

    root.ensureSidebarContent()
        if (root.detach) {
            GlobalFocusGrab.removeDismissable(sidebarLoader.item) // Remove sidebar from the focus grab system
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            detachedSidebarLoader.item.contentParent.children = [sidebarContent];
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarLoader.item.contentParent.children = [sidebarContent];
        }
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: panelWindow
            // sidebar-material-stability-v2
            // In Glass, keep only the native host mapped. The actual
            // material plane moves off-canvas while logically closed.
            // phase3c-motion-hardening-v1
            // Keep the host mapped in Fluid and Prism so QML owns the toggle
            // choreography. Mica/default keep their existing map/unmap path.
            visible:
                Config.options.appearance.transparency.enable
                || Appearance.prismMode
                || GlobalStates.sidebarLeftOpen
            
            property bool extend: false
            property real sidebarWidth:
                panelWindow.extend
                    ? Appearance.sizes.sidebarWidthExtended
                    : Math.min(
                        460,
                        Math.max(
                            350,
                            panelWindow.screen
                                ? panelWindow.screen.width * 0.30
                                : 420
                        )
                    )
            property var contentParent: sidebarLeftBackground

            function syncShellCaptureRegion(): void {
                if (
                    !GlobalStates.sidebarLeftOpen
                    || !panelWindow.screen
                    || sidebarLeftBackground.width <= 0
                    || sidebarLeftBackground.height <= 0
                ) {
                    GlobalStates.clearCaptureRegion(
                        "sidebarLeft"
                    )
                    return
                }

                // sidebar-snip-global-geometry-v3
                //
                // sidebarLeftBackground.x/y are local to the layer-shell
                // surface. The surface itself begins after reserved edges
                // such as the top navbar, so convert to monitor-local coords.
                const monitor =
                    Hyprland.monitorFor(panelWindow.screen)
                const monitorData =
                    HyprlandData.monitors.find(
                        entry => entry.id === monitor?.id
                    )
                const reserved =
                    monitorData?.reserved ?? [0, 0, 0, 0]
                const surfaceX = reserved[0] ?? 0
                const surfaceY = reserved[1] ?? 0

                GlobalStates.registerCaptureRegion(
                    "sidebarLeft",
                    panelWindow.screen.name,
                    surfaceX + sidebarLeftBackground.x,
                    surfaceY + sidebarLeftBackground.y,
                    sidebarLeftBackground.width,
                    sidebarLeftBackground.height,
                    165,
                    "Left Sidebar"
                )
            }

            Connections {
                target: GlobalStates

                function onSidebarLeftOpenChanged() {
                    panelWindow.syncDismissable()
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                }
            }

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone:
                root.pin && GlobalStates.sidebarLeftOpen
                    ? sidebarWidth
                    : 0
            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
            // glass-system-v2.3b-shape
            Region {
                id: glassSidebarLeftVisibleMask
                item: sidebarLeftBackground
            }
            HyprlandWindow.visibleMask:
                Config.options.appearance.transparency.enable
                    ? glassSidebarLeftVisibleMask
                    : null

            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            // left-sidebar-snip-v1
            WlrLayershell.keyboardFocus:
                GlobalStates.regionSelectorOpen
                    ? WlrKeyboardFocus.None
                    : (
                        GlobalStates.sidebarLeftOpen
                            ? WlrKeyboardFocus.OnDemand
                            : WlrKeyboardFocus.None
                    )
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            mask: Region {
                item:
                    GlobalStates.sidebarLeftOpen
                        ? sidebarLeftBackground
                        : null
            }

            function syncDismissable(): void {
                if (GlobalStates.sidebarLeftOpen && visible)
                    GlobalFocusGrab.addDismissable(panelWindow)
                else
                    GlobalFocusGrab.removeDismissable(panelWindow)
            }

            onVisibleChanged: panelWindow.syncDismissable()
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    // Region Selector temporarily takes focus for snipping.
                    // Keep the sidebar rendered underneath it.
                    if (GlobalStates.regionSelectorOpen)
                        return

                    panelWindow.hide();
                }
            }

            // Content
            StyledRectangularShadow {
                visible: !Appearance.prismMode && !Appearance.inlayMode
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
            }

            PrismSurface {
                visible: Appearance.prismMode
                x: sidebarLeftBackground.x
                y: sidebarLeftBackground.y
                width: sidebarLeftBackground.width
                height: sidebarLeftBackground.height
                depth: Appearance.prism.depthInteractive
                surfaceRadius: Appearance.prism.radiusInteractive
            }

            Rectangle {
                id: sidebarLeftBackground

                property real glassSlideOffset:
                    (
                        Config.options.appearance.transparency.enable
                        || Appearance.prismMode
                    )
                        ? (
                            GlobalStates.sidebarLeftOpen
                                ? 0
                                : -panelWindow.sidebarWidth
                                  - Appearance.sizes.elevationMargin
                          )
                        : 0

                Behavior on glassSlideOffset {
                    MotionExpressiveAnim {
                        phase:
                            GlobalStates.sidebarLeftOpen
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

                onXChanged:
                    panelWindow.syncShellCaptureRegion()
                onYChanged:
                    panelWindow.syncShellCaptureRegion()
                onWidthChanged:
                    panelWindow.syncShellCaptureRegion()
                onHeightChanged:
                    panelWindow.syncShellCaptureRegion()

                Component.onCompleted:
                    Qt.callLater(
                        () => panelWindow.syncShellCaptureRegion()
                    )
                anchors.top: parent.top
                anchors.left: parent.left
                // prism-v2-phase3a: interactive sidebars use the Prism spatial
                // geometry contract instead of duplicating magic offsets.
                anchors.topMargin:
                    Appearance.prismMode
                        ? Appearance.prism.screenInset + Appearance.prism.islandGap
                        : Appearance.sizes.hyprlandGapsOut
                anchors.leftMargin:
                    (Appearance.prismMode
                        ? Appearance.prism.screenInset + Appearance.prism.islandGap
                        : Appearance.sizes.hyprlandGapsOut)
                    + sidebarLeftBackground.glassSlideOffset
                width:
                    panelWindow.sidebarWidth
                    - Appearance.sizes.hyprlandGapsOut
                    - Appearance.sizes.elevationMargin
                    - (Appearance.prismMode ? Appearance.prism.islandGap : 0)
                height:
                    parent.height
                    - Appearance.sizes.hyprlandGapsOut * 2
                    - (Appearance.prismMode ? Appearance.prism.islandGap * 2 : 0)

                color:
                    Appearance.prismMode
                        ? "transparent"
                        : Appearance.inlayMode
                            ? Appearance.inlay.surfaceFill
                            : Appearance.colors.colLayer0
                border.width:
                    Appearance.prismMode
                        ? 0
                        : Appearance.inlayMode
                            ? Appearance.inlay.borderWidth
                            : 1
                border.color:
                    Appearance.inlayMode
                        ? Appearance.inlay.borderSubtle
                        : Appearance.fluidMode
                            ? Appearance.colors.fluidBorderStrong
                            : Appearance.colors.colLayer0Border

                property real prismBaseSidebarRadius: Appearance.radius.window
                radius:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.prismMode
                            ? Appearance.prism.radiusInteractive
                            : prismBaseSidebarRadius
                Behavior on width {
                    MotionAnim {
                        type: MotionAnim.DefaultSpatial
                        duration: 420
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O) {
                            panelWindow.extend = !panelWindow.extend;
                        } else if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        } else if (event.key === Qt.Key_P) {
                            root.togglePin();
                        }
                        event.accepted = true;
                    }
                }

}
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            onVisibleChanged: {
                if (!visible) GlobalStates.sidebarLeftOpen = false;
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color:
                    Appearance.prismMode
                        ? Appearance.prism.interactiveFill
                        : Appearance.inlayMode
                            ? Appearance.inlay.surfaceFill
                            : Appearance.colors.colLayer0
                radius:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.prismMode
                            ? Appearance.prism.radiusInteractive
                            : 0
                border.width:
                    (Appearance.prismMode || Appearance.inlayMode) ? 1 : 0
                border.color:
                    Appearance.prismMode
                        ? Appearance.prism.borderStrong
                        : Appearance.inlayMode
                            ? Appearance.inlay.borderSubtle
                            : "transparent"

                Keys.onPressed: (event) => {
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_D) {
                            root.toggleDetach();
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    // Stable always-on Operations Center IPC proof. This lives in the host
    // Scope so lazy SidebarLeftContent does not control IPC availability.
    IpcHandler {
        target: "operationsCenter"
        function ping() {}
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.detach = !root.detach;
        }
    }

}
