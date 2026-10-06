//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "modules/appearanceStudio"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Stuff for every panel family
    ReloadPopup {}

    // memory-lazy-surfaces-v2
    property bool appearanceStudioRetained: false

    Timer {
        id: appearanceStudioUnloadTimer
        interval: 340
        repeat: false

        onTriggered: {
            if (!GlobalStates.appearanceStudioOpen)
                root.appearanceStudioRetained = false
        }
    }

    Connections {
        target: GlobalStates

        function onAppearanceStudioOpenChanged() {
            if (GlobalStates.appearanceStudioOpen) {
                appearanceStudioUnloadTimer.stop()
                root.appearanceStudioRetained = true
            } else if (root.appearanceStudioRetained) {
                appearanceStudioUnloadTimer.restart()
            }
        }
    }

    LazyLoader {
        id: appearanceStudioLoader

        active:
            GlobalStates.appearanceStudioOpen
            || root.appearanceStudioRetained

        component: AppearanceStudio {}
    }

    IpcHandler {
        target: "appearanceStudio"

        function toggle(): void {
            GlobalStates.appearanceStudioOpen =
                !GlobalStates.appearanceStudioOpen
        }

        function open(): void {
            GlobalStates.appearanceStudioOpen = true
        }

        function close(): void {
            GlobalStates.appearanceStudioOpen = false
        }
    }

    GlobalShortcut {
        name: "appearanceStudioToggle"
        description: "Toggle Appearance Studio"

        onPressed:
            GlobalStates.appearanceStudioOpen =
                !GlobalStates.appearanceStudioOpen
    }


    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
    }


    // Panel families
    // DYNAMIC-SELECTED-FAMILY-V1
    property list<string> families: ["ii", "waffle"]

    property url selectedPanelFamilySource: {
        if (!Config.ready)
            return ""

        if (Config.options.panelFamily === "nyvorel")
            return Qt.resolvedUrl(
                "panelFamilies/NyvorelFamily.qml"
            )

        if (Config.options.panelFamily === "waffle")
            return Qt.resolvedUrl(
                "panelFamilies/WaffleFamily.qml"
            )

        return ""
    }

    function cyclePanelFamily() {
        const currentIndex =
            families.indexOf(Config.options.panelFamily)
        const nextIndex =
            (currentIndex + 1) % families.length
        Config.options.panelFamily =
            families[nextIndex]
    }

    Loader {
        id: selectedPanelFamilyLoader

        active:
            Config.ready
            && root.selectedPanelFamilySource.toString().length > 0

        source:
            root.selectedPanelFamilySource

        onLoaded:
            console.info(
                "DYNAMIC-FAMILY-V1 loaded",
                Config.options.panelFamily
            )

        onStatusChanged: {
            if (status === Loader.Error) {
                console.error(
                    "DYNAMIC-FAMILY-V1 load error",
                    source
                )
            }
        }
    }

    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}

