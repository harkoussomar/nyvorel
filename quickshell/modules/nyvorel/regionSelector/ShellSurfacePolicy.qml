pragma Singleton

import qs
import qs.modules.common
import Quickshell

Singleton {
    id: root

    // Centralize shell-specific capture knowledge here. RegionSelection no
    // longer needs to know which components stay mapped in each interface style.
    function namespaceForRegistryId(id) {
        if (!id)
            return ""

        if (id.startsWith("bar:"))
            return "quickshell:bar"

        switch (id) {
        case "appearanceStudio": return "quickshell:appearanceStudio"
        case "archRemote": return "quickshell:archRemote"
        case "backupRecovery": return "quickshell:backupRecovery"
        case "projects": return "quickshell:projectLauncher"
        case "cheatsheet": return "quickshell:cheatsheet"
        case "session": return "quickshell:session"
        case "sidebarLeft": return "quickshell:sidebarLeft"
        case "sidebarRight": return "quickshell:sidebarRight"
        default: return ""
        }
    }

    function registryIdForNamespace(namespace) {
        if (!namespace)
            return ""

        if (namespace === "quickshell:bar")
            return "bar:*"

        switch (namespace) {
        case "quickshell:appearanceStudio": return "appearanceStudio"
        case "quickshell:archRemote": return "archRemote"
        case "quickshell:backupRecovery": return "backupRecovery"
        case "quickshell:projectLauncher": return "projects"
        case "quickshell:cheatsheet": return "cheatsheet"
        case "quickshell:session": return "session"
        case "quickshell:sidebarLeft": return "sidebarLeft"
        case "quickshell:sidebarRight": return "sidebarRight"
        default: return ""
        }
    }

    function logicalVisibleForRegistryId(id) {
        if (!id)
            return true

        if (id.startsWith("bar:"))
            return true

        switch (id) {
        case "appearanceStudio": return GlobalStates.appearanceStudioOpen
        case "archRemote": return GlobalStates.archRemoteOpen
        case "backupRecovery": return GlobalStates.backupRecoveryOpen
        case "projects": return GlobalStates.exclusiveSurfaceActive("projects")
        case "cheatsheet": return GlobalStates.exclusiveSurfaceActive("cheatsheet")
        case "session": return GlobalStates.sessionOpen
        case "sidebarLeft": return GlobalStates.sidebarLeftOpen
        case "sidebarRight": return GlobalStates.sidebarRightOpen
        default: return true
        }
    }

    function layerIsLogicallyVisible(namespace) {
        const id = root.registryIdForNamespace(namespace)
        if (!id)
            return true
        if (id === "bar:*")
            return true
        return root.logicalVisibleForRegistryId(id)
    }

    function radiusForRegistryId(id) {
        if (!id || id.startsWith("bar:"))
            return 0

        if (id === "sidebarLeft") {
            return Math.max(
                0,
                Appearance.rounding.screenRounding
                    - Appearance.sizes.hyprlandGapsOut
                    + 1
            )
        }

        if (id === "sidebarRight") {
            return Appearance.prismMode
                ? Appearance.radius.sidebar
                : (
                    Config.options.appearance.transparency.enable
                        ? Appearance.radius.window
                        : Math.max(
                            0,
                            Appearance.rounding.screenRounding
                                - Appearance.sizes.hyprlandGapsOut
                                + 1
                        )
                  )
        }

        return Appearance.radius.modal
    }

    function shapeForRegistryId(id) {
        return id && !id.startsWith("bar:")
            ? "rounded-rect"
            : "rect"
    }
}
