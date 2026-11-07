import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    // The Operations window is owned by the navbar popup. This Scope keeps
    // IPC and shortcuts available even while the popup is unloaded.
    IpcHandler {
        target: "operationsCenter"
        function ping() {}
    }
    IpcHandler {
        target: "sidebarLeft"
        function toggle(): void { GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen }
        function close(): void { GlobalStates.sidebarLeftOpen = false }
        function open(): void { GlobalStates.sidebarLeftOpen = true }
    }
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen)
                GlobalStates.sidebarRightOpen = false
        }
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen)
                GlobalStates.sidebarLeftOpen = false
        }
    }
    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggle Operations"
        onPressed: GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
    }
    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Open Operations"
        onPressed: GlobalStates.sidebarLeftOpen = true
    }
    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Close Operations"
        onPressed: GlobalStates.sidebarLeftOpen = false
    }
    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Open Operations"
        onPressed: GlobalStates.sidebarLeftOpen = true
    }
}
