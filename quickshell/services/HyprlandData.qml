pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    property bool desktopPending: false
    property bool layersPending: false

    function scheduleRefresh(desktop, layerGeometry) {
        root.desktopPending = root.desktopPending || desktop
        root.layersPending = root.layersPending || layerGeometry
        if ((root.desktopPending || root.layersPending)
                && !refreshTimer.running && !refreshProcess.running)
            refreshTimer.start()
    }

    function handleCompositorEvent(name) {
        if (name === "screencast")
            return
        const layerEvent = name === "openlayer" || name === "closelayer"
        root.scheduleRefresh(!layerEvent, GlobalStates.regionSelectorOpen)
    }

    function flushRefresh() {
        const queries = root.desktopPending ? ["clients", "monitors", "workspaces", "activeworkspace"] : []
        if (root.layersPending && GlobalStates.regionSelectorOpen)
            queries.push("layers")
        root.desktopPending = false
        root.layersPending = false
        if (queries.length) {
            refreshProcess.queries = queries
            refreshProcess.exec(["hyprctl", "-j", "--batch", queries.join(" ; ")])
        }
    }

    function applyReplies(queries, output) {
        let replies
        try {
            // hyprctl prints one JSON document per query, separated by newlines.
            const documents = output.trim().replace(/([\]}])[ \t]*(?:\r?\n[ \t]*)+([\[{])/g, "$1,$2")
            replies = JSON.parse("[" + documents + "]")
        } catch (_) {
            return
        }
        if (queries.length !== replies.length)
            return

        for (let i = 0; i < queries.length; ++i) {
            const data = replies[i]
            switch (queries[i]) {
            case "clients":
                if (Array.isArray(data)) {
                    const byAddress = {}
                    for (const win of data)
                        byAddress[win.address] = win
                    root.windowByAddress = byAddress
                    root.addresses = data.map(win => win.address)
                    root.windowList = data
                }
                break
            case "monitors":
                if (Array.isArray(data))
                    root.monitors = data
                break
            case "workspaces":
                if (Array.isArray(data)) {
                    // Exclude special workspaces and temporary lock-screen workspaces.
                    const workspaces = data.filter(ws => ws.id >= 1 && ws.id <= 100)
                    const byId = {}
                    for (const workspace of workspaces)
                        byId[workspace.id] = workspace
                    root.workspaceById = byId
                    root.workspaceIds = workspaces.map(ws => ws.id)
                    root.workspaces = workspaces
                }
                break
            case "activeworkspace":
                if (data && typeof data === "object" && !Array.isArray(data))
                    root.activeWorkspace = data
                break
            case "layers":
                if (GlobalStates.regionSelectorOpen && data && typeof data === "object" && !Array.isArray(data))
                    root.layers = data
                break
            }
        }
    }

    Component.onCompleted: root.scheduleRefresh(true, GlobalStates.regionSelectorOpen)

    Connections {
        target: Hyprland
        function onRawEvent(event) { root.handleCompositorEvent(event.name) }
    }

    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen) {
                root.scheduleRefresh(true, true)
            } else {
                root.layersPending = false
                root.layers = ({})
            }
        }
    }

    Timer {
        id: refreshTimer
        // Start once per burst so continuous events still get regular updates.
        interval: 25
        onTriggered: root.flushRefresh()
    }

    Process {
        id: refreshProcess
        property list<string> queries
        stdout: StdioCollector {
            onStreamFinished: root.applyReplies(refreshProcess.queries, text)
        }
        onExited: Qt.callLater(() => root.scheduleRefresh(false, false))
    }
}
