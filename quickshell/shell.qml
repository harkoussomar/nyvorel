//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "modules/wallpaperPicker"
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

    property bool wallpaperPickerRetained: false

    LazyLoader {
        active: GlobalStates.wallpaperPickerOpen || root.wallpaperPickerRetained
        component: WallpaperPicker {
            onRetainedChanged: {
                const keep = retained
                Qt.callLater(() => root.wallpaperPickerRetained = keep)
            }
            Component.onCompleted: root.wallpaperPickerRetained = retained
        }
    }

    IpcHandler {
        target: "wallpaperPicker"

        function open(): void { GlobalStates.openExclusiveSurface("wallpaperPicker") }
        function close(): void { GlobalStates.closeExclusiveSurface("wallpaperPicker") }
        function toggle(): void { GlobalStates.toggleExclusiveSurface("wallpaperPicker") }
    }

    GlobalShortcut {
        name: "wallpaperSelectorToggle"
        description: "Change wallpaper"
        onPressed: GlobalStates.toggleExclusiveSurface("wallpaperPicker")
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        KeyboardLayout.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
    }


    // Panel families
    // DYNAMIC-SELECTED-FAMILY-V1
    property list<string> families: ["nyvorel", "waffle"]

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

