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
        GlobalStates.backupRecoveryOpen = true
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
        if (!GlobalStates.backupRecoveryOpen)
            return
        root.presentationClosing = true
        GlobalStates.backupRecoveryOpen = false
        presentationCloseTimer.restart()
    }

    function toggleCenter() {
        if (GlobalStates.backupRecoveryOpen || root.placementPending)
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
        target: "backupRecovery"
        function toggle() { root.toggleCenter() }
        function open() { root.openCenter() }
        function close() { root.closeCenter() }
        function ping() { return "ready" }
        function uiVersion() { return "1.6.0" }
    }

    // Runtime-proof endpoint. qs ipc call does not print QML return values, so
    // a version-specific target proves this exact wrapper generation is live.
    IpcHandler {
        target: "backupRecoveryV160"
        function ping() {}
    }

    GlobalShortcut {
        name: "backupRecoveryToggle"
        description: "Toggle Backup & Recovery Center"
        onPressed: root.toggleCenter()
    }

    LazyLoader {
        // Create the native host only after the target screen is known.
        // A mapped layer-shell window cannot reliably move to another output.
        active: GlobalStates.backupRecoveryOpen || root.presentationClosing

        component: PanelWindow {
            visible: true
            id: backupRecoveryWindow
            screen: Quickshell.screens.find(screen => screen.name === root.targetScreenName)
                ?? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name)
                ?? null
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:backupRecovery"
            mask: Region {
                item:
                    GlobalStates.backupRecoveryOpen
                        ? backupRecoveryContentLoader.item
                        : null
            }

            WlrLayershell.layer: WlrLayer.Overlay
            // backup-recovery-snip-focus-v1
            //
            // Backup Recovery normally owns keyboard focus, but Region Selector
            // must temporarily receive the seat while the modal remains visible
            // underneath for capture.
            // backup-recovery-persistent-host-v1 focus
            WlrLayershell.keyboardFocus:
                GlobalStates.regionSelectorOpen
                    ? WlrKeyboardFocus.None
                    : (
                        GlobalStates.backupRecoveryOpen
                            ? WlrKeyboardFocus.OnDemand
                            : WlrKeyboardFocus.None
                    )

            // backup-recovery-persistent-host-loader-fix-v1
            // BackupRecoveryContent is visual, so use QtQuick Loader.
            Loader {
                id: backupRecoveryContentLoader
                anchors.fill: parent
                active:
                    GlobalStates.backupRecoveryOpen
                    || root.presentationClosing

                sourceComponent: Component {
                    BackupRecoveryContent {
                    anchors.fill: parent
                    captureScreenName:
                        backupRecoveryWindow.screen
                            ? backupRecoveryWindow.screen.name
                            : ""
                    onCloseRequested: root.closeCenter()
                    }
                }
            }
        }
    }
}
