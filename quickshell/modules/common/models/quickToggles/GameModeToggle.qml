import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: toggled
    icon: "gamepad"

    mainAction: () => {
        root.toggled = !root.toggled
        if (root.toggled) {
            HyprNative.enableGameMode()
        } else {
            Quickshell.execDetached(["hyprctl", "reload"])
        }
    }
    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption animations.enabled -j | jq 'if .bool == null then .int else (if .bool then 1 else 0 end) end')" -ne 0`]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode !== 0 // Inverted because enabled = nonzero exit
        }
    }
    tooltipText: Translation.tr("Game mode")
}
