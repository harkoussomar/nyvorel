import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs.modules.common
import qs.modules.nyvorel.background
import qs.modules.nyvorel.bar
import qs.modules.nyvorel.dock
import qs.modules.nyvorel.lock
import qs.modules.nyvorel.mediaControls
import qs.modules.nyvorel.notificationPopup
import qs.modules.nyvorel.onScreenDisplay
import qs.modules.nyvorel.onScreenKeyboard
import qs.modules.nyvorel.overview
import qs.modules.nyvorel.projectLauncher
import qs.modules.nyvorel.archRemote
import qs.modules.nyvorel.backupRecovery
import qs.modules.nyvorel.polkit
import qs.modules.nyvorel.regionSelector
import qs.modules.nyvorel.screenCorners
import qs.modules.nyvorel.sessionScreen
import qs.modules.nyvorel.sidebarLeft
import qs.modules.nyvorel.sidebarRight
import qs.modules.nyvorel.overlay
import qs.modules.nyvorel.verticalBar

Scope {
    id: root
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: ProjectLauncher {} }
    PanelLoader { component: ArchRemote {} }
    PanelLoader { component: BackupRecovery {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }


    // CHEATSHEET-DYNAMIC-V3
    property var cheatsheetDynamicComponent: null
    property var cheatsheetDynamicInstance: null

    function loadCheatsheetDynamic(): void {
        if (root.cheatsheetDynamicInstance)
            return

        const component = Qt.createComponent(
            Qt.resolvedUrl("../modules/nyvorel/cheatsheet/Cheatsheet.qml")
        )

        if (component.status !== Component.Ready) {
            console.error(
                "Cheatsheet dynamic load failed:",
                component.errorString()
            )
            component.destroy()
            return
        }

        const instance = component.createObject(root)

        if (!instance) {
            console.error(
                "Cheatsheet dynamic createObject failed:",
                component.errorString()
            )
            component.destroy()
            return
        }

        root.cheatsheetDynamicComponent = component
        root.cheatsheetDynamicInstance = instance
    }

    function unloadCheatsheetDynamic(): void {
        if (root.cheatsheetDynamicInstance) {
            root.cheatsheetDynamicInstance.destroy()
            root.cheatsheetDynamicInstance = null
        }

        if (root.cheatsheetDynamicComponent) {
            root.cheatsheetDynamicComponent.destroy()
            root.cheatsheetDynamicComponent = null
        }
    }

    Connections {
        target: GlobalStates

        function onActiveExclusiveSurfaceChanged() {
            if (GlobalStates.exclusiveSurfaceActive("cheatsheet"))
                root.loadCheatsheetDynamic()
            else
                root.unloadCheatsheetDynamic()
        }
    }

    Component.onCompleted: {
        if (GlobalStates.exclusiveSurfaceActive("cheatsheet"))
            root.loadCheatsheetDynamic()
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            GlobalStates.toggleExclusiveSurface("cheatsheet")
        }

        function open(): void {
            GlobalStates.openExclusiveSurface("cheatsheet")
        }

        function close(): void {
            GlobalStates.closeExclusiveSurface("cheatsheet", false)
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"
        onPressed:
            GlobalStates.toggleExclusiveSurface("cheatsheet")
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"
        onPressed:
            GlobalStates.openExclusiveSurface("cheatsheet")
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"
        onPressed:
            GlobalStates.closeExclusiveSurface("cheatsheet", false)
    }

}
