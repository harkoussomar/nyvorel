import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool presentationClosing: false

    function openCenter() {
        presentationCloseTimer.stop()
        root.presentationClosing = false
        GlobalStates.archRemoteOpen = true
    }

    function closeCenter() {
        if (!GlobalStates.archRemoteOpen)
            return
        root.presentationClosing = true
        GlobalStates.archRemoteOpen = false
        presentationCloseTimer.restart()
    }

    function toggleCenter() {
        if (GlobalStates.archRemoteOpen)
            root.closeCenter()
        else
            root.openCenter()
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
