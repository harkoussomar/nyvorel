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

    readonly property ShellScreen presentedScreen: {
        if (!GlobalStates.archRemoteOpen && !root.presentationClosing)
            return null
        return Quickshell.screens.find(screen => screen.name === root.targetScreenName)
            ?? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name)
            ?? Quickshell.screens[0]
            ?? null
    }

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
        GlobalStates.archRemoteOpen = true
        presentationCloseTimer.stop()
        root.presentationClosing = false
    }

    function openCenter() {
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
        // Keep the surface through the opacity fade and the scaled spatial exit.
        interval: Appearance.reducedMotion
            ? 200 : Math.max(200, Math.round(260 * Appearance.motionScale))
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

    Variants {
        // Tie the native surface to its output for the life of the presentation.
        model: root.presentedScreen ? [root.presentedScreen] : []

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "quickshell:archRemote"
            mask: Region {
                item:
                    GlobalStates.archRemoteOpen
                        ? archRemoteContent
                        : null
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus:
                GlobalStates.archRemoteOpen
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None

            ArchRemoteContent {
                id: archRemoteContent
                anchors.fill: parent
                screenName: modelData.name
                onCloseRequested: root.closeCenter()
            }
        }
    }
}
