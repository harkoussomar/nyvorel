pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property var bindings: []
    property bool loaded: false
    property bool failed: false
    property bool refreshPending: false
    property bool customized: false
    property bool captureWanted: false
    property bool captureActive: false
    readonly property bool captureBusy: capture.running || captureActive
    readonly property bool saving: mutation.running
    readonly property string editorPath: Quickshell.shellPath("scripts/hyprland/keybind_editor.py")
    signal editFinished(bool succeeded, string message)
    signal captureFailed(string message)

    function setCapture(wanted): void {
        captureWanted = wanted
        syncCapture()
    }

    function syncCapture(): void {
        if (capture.running || captureWanted === captureActive)
            return
        capture.starting = captureWanted
        capture.command = ["python3", root.editorPath, capture.starting ? "capture-start" : "capture-stop"]
        capture.running = true
    }

    function apply(args): void {
        if (mutation.running)
            return
        mutation.command = ["python3", root.editorPath, ...args]
        mutation.running = true
    }

    function refresh(): void {
        if (query.running)
            refreshPending = true
        else
            query.running = true
    }

    Component.onCompleted: refresh()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.refresh()
        }
    }

    Process {
        id: query
        command: ["python3", root.editorPath, "list"]
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            try {
                const result = code === 0 && status === 0 ? JSON.parse(output.text) : null
                if (!result?.ok || !Array.isArray(result.bindings))
                    throw new Error("Expected a list of active bindings")
                root.bindings = result.bindings
                root.customized = !!result.customized
                root.failed = false
            } catch (error) {
                root.bindings = []
                root.failed = true
            }
            root.loaded = true
            if (root.refreshPending) {
                root.refreshPending = false
                Qt.callLater(root.refresh)
            }
        }
    }

    Process {
        id: capture
        property bool starting: false
        stdout: StdioCollector { id: captureOutput }
        onExited: (code, status) => {
            let result
            try {
                result = code === 0 && status === 0 ? JSON.parse(captureOutput.text) : null
            } catch (error) {}
            if (!result?.ok) {
                root.captureActive = false
                root.captureWanted = false
                root.captureFailed(result?.message || "Could not change shortcut recording mode.")
                return
            }
            root.captureActive = capture.starting
            Qt.callLater(root.syncCapture)
        }
    }

    Process {
        id: mutation
        stdout: StdioCollector { id: mutationOutput }
        onExited: (code, status) => {
            let result
            try {
                result = code === 0 && status === 0 ? JSON.parse(mutationOutput.text) : null
            } catch (error) {}
            root.refresh()
            root.editFinished(!!result?.ok, result?.message || "")
        }
    }
}
