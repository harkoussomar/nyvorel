import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    IpcHandler {
        target: "sidebarRight"
        function toggle(): void { GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen }
        function close(): void { GlobalStates.sidebarRightOpen = false }
        function open(): void { GlobalStates.sidebarRightOpen = true }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles the control center"
        onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens the control center"
        onPressed: GlobalStates.sidebarRightOpen = true
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes the control center"
        onPressed: GlobalStates.sidebarRightOpen = false
    }
}
