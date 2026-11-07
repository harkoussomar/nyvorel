import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool presentationClosing: false
    property bool placementPending: false
    property string targetScreenName: ""

    function focusedScreenName() {
        const name = Hyprland.focusedMonitor?.name ?? ""
        return Quickshell.screens.find(screen => screen.name === name)?.name
            ?? Quickshell.screens[0]?.name
            ?? ""
    }

    function screenAtCursor(position) {
        const x = Number(position?.x)
        const y = Number(position?.y)
        if (!Number.isFinite(x) || !Number.isFinite(y))
            return ""

        for (const monitor of HyprlandData.monitors) {
            const scale = Number(monitor.scale)
            const rotation = Number(monitor.transform) % 2 === 1
            const width = Number(rotation ? monitor.height : monitor.width) / scale
            const height = Number(rotation ? monitor.width : monitor.height) / scale
            const left = Number(monitor.x)
            const top = Number(monitor.y)
            if (!Number.isFinite(width) || !Number.isFinite(height)
                    || !Number.isFinite(left) || !Number.isFinite(top)
                    || width <= 0 || height <= 0)
                continue
            if (x >= left && x < left + width && y >= top && y < top + height
                    && Quickshell.screens.some(screen => screen.name === monitor.name))
                return monitor.name
        }
        return ""
    }

    function finishPlacement(screenName) {
        if (!root.placementPending)
            return
        root.placementPending = false
        placementFallbackTimer.stop()
        root.targetScreenName = screenName || root.focusedScreenName()
        root.presentationClosing = false
        GlobalStates.archRemoteOpen = true
    }

    function openCenter() {
        presentationCloseTimer.stop()
        root.presentationClosing = false
        root.placementPending = true
        placementFallbackTimer.restart()
        if (!cursorPositionProc.running) {
            cursorPositionProc.command = ["hyprctl", "-j", "cursorpos"]
            cursorPositionProc.running = true
        }
    }

    function closeCenter() {
        root.placementPending = false
        placementFallbackTimer.stop()
        if (!GlobalStates.archRemoteOpen)
            return
        root.presentationClosing = true
        GlobalStates.archRemoteOpen = false
        presentationCloseTimer.restart()
    }

    function toggleCenter() {
        if (GlobalStates.archRemoteOpen || root.placementPending)
            root.closeCenter()
        else
            root.openCenter()
    }

    Process {
        id: cursorPositionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.finishPlacement(root.screenAtCursor(JSON.parse(this.text)))
                } catch (error) {
                    root.finishPlacement("")
                }
            }
        }
    }

    Timer {
        id: placementFallbackTimer
        interval: 350
        repeat: false
        onTriggered: root.finishPlacement("")
    }

    Timer {
        id: presentationCloseTimer
        interval: 260 // motion-calibrated-v1
        repeat: false
        onTriggered: root.presentationClosing = false
    }

    IpcHandler {
        target: "archRemote"
        function toggle() { root.toggleCenter() }
        function open() { root.openCenter() }
        function close() { root.closeCenter() }
        function ping() { return "ready" }
        function uiVersion() { return "2.4.1" }
    }

    // Internal runtime-proof target for installer validation.
    // The previous Arch Remote version does not expose this target.
    IpcHandler {
        target: "archRemoteV24"
        function ping() {}
    }

    IpcHandler {
        target: "archRemoteV241"
        function ping() {}
    }

    GlobalShortcut {
        name: "archRemoteToggle"
        description: "Toggle Arch Remote Control Center"
        onPressed: root.toggleCenter()
    }

    LazyLoader {
        // modal-material-stability-v1
        // Glass keeps only the native host mapped; the visual content
        // remains logically gated by archRemoteOpen.
        active:
            Config.options.appearance.transparency.enable
                ? true
                : (
                    GlobalStates.archRemoteOpen
                    || root.presentationClosing
                )

        component: PanelWindow {
            visible: true
            id: panelWindow
            screen: Quickshell.screens.find(screen => screen.name === root.targetScreenName)
                ?? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name)
                ?? null
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "quickshell:archRemote"
            mask: Region {
                item:
                    GlobalStates.archRemoteOpen
                        ? archRemoteContentLoader.item
                        : null
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus:
                GlobalStates.archRemoteOpen
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None

            Loader {
                id: archRemoteContentLoader
                anchors.fill: parent
                active:
                    GlobalStates.archRemoteOpen
                    || root.presentationClosing

                sourceComponent: Component {
                ArchRemoteContent {
                    anchors.fill: parent
                    screenName:
                        panelWindow.screen !== null
                            ? panelWindow.screen.name
                            : ""
                    onCloseRequested: root.closeCenter()
                }
                }
            }
        }
    }
}
