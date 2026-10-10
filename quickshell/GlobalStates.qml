import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool appearanceStudioOpen: false
    property bool archRemoteOpen: false
    property bool backupRecoveryOpen: false

    // Arch Remote is a full-screen layer-shell surface, but region snipping
    // should see only the centered visible modal card.
    property string archRemoteScreenName: ""
    property real archRemoteRegionX: 0
    property real archRemoteRegionY: 0
    property real archRemoteRegionWidth: 0
    property real archRemoteRegionHeight: 0

    // Appearance Studio is a layer-shell surface rather than a normal
    // Hyprland client. Publish the visible card rectangle so region snipping
    // can treat it as a window-like target.
    property string appearanceStudioScreenName: ""
    property real appearanceStudioRegionX: 0
    property real appearanceStudioRegionY: 0
    property real appearanceStudioRegionWidth: 0
    property real appearanceStudioRegionHeight: 0
    property bool workspaceShowNumbers: false

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }

    // >>> SHELL-SURFACE-MANAGER-V1 >>>
    //
    // One source of truth for major user-facing shell surfaces.
    // Settings is a native ApplicationWindow and is intentionally excluded.
    // Polkit is a system-blocking surface and is intentionally excluded.
    readonly property var exclusiveSurfaceIds: [
        "appearanceStudio",
        "archRemote",
        "backupRecovery",
        "projects",
        "cheatsheet",
        "overview",
        "session"
    ]

    property string activeExclusiveSurface: ""
    property bool exclusiveSurfaceSyncing: false

    // Exact monitor-local rectangles exported by shell-owned surfaces.
    property var captureRegions: ({})

    function exclusiveSurfaceActive(id) {
        return root.activeExclusiveSurface === id
    }

    function exclusiveSurfaceLabel(id) {
        switch (id) {
        case "appearanceStudio": return "Appearance Studio"
        case "archRemote": return "Arch Remote"
        case "backupRecovery": return "Backup & Recovery"
        case "projects": return "Project Launcher"
        case "cheatsheet": return "Cheatsheet"
        case "overview": return "Overview / Search"
        case "session": return "Session"
        default: return id
        }
    }

    function hasExclusiveBoolean(id) {
        return [
            "appearanceStudio",
            "archRemote",
            "backupRecovery",
            "overview",
            "session"
        ].includes(id)
    }

    function setExclusiveBoolean(id, value) {
        switch (id) {
        case "appearanceStudio":
            root.appearanceStudioOpen = value
            break
        case "archRemote":
            root.archRemoteOpen = value
            break
        case "backupRecovery":
            root.backupRecoveryOpen = value
            break
        case "overview":
            root.overviewOpen = value
            break
        case "session":
            root.sessionOpen = value
            break
        }
    }

    function openExclusiveSurface(id) {
        if (!root.exclusiveSurfaceIds.includes(id))
            return

        root.exclusiveSurfaceSyncing = true

        for (const candidate of root.exclusiveSurfaceIds) {
            if (
                candidate !== id
                && root.hasExclusiveBoolean(candidate)
            ) {
                root.setExclusiveBoolean(candidate, false)
            }
        }

        root.activeExclusiveSurface = id

        if (root.hasExclusiveBoolean(id))
            root.setExclusiveBoolean(id, true)

        root.exclusiveSurfaceSyncing = false
    }

    function closeExclusiveSurface(id, force) {
        const forced = force === true

        // Region Selector is a capture overlay, not a competing primary
        // surface. Keep the current modal rendered during capture.
        if (
            !forced
            && root.regionSelectorOpen
            && root.activeExclusiveSurface === id
        ) {
            return
        }

        root.exclusiveSurfaceSyncing = true

        if (root.hasExclusiveBoolean(id))
            root.setExclusiveBoolean(id, false)

        if (root.activeExclusiveSurface === id)
            root.activeExclusiveSurface = ""

        root.exclusiveSurfaceSyncing = false
        root.clearCaptureRegion(id)
    }

    function toggleExclusiveSurface(id) {
        if (root.activeExclusiveSurface === id)
            root.closeExclusiveSurface(id, false)
        else
            root.openExclusiveSurface(id)
    }

    function closeAllExclusiveSurfaces(force) {
        root.exclusiveSurfaceSyncing = true

        for (const candidate of root.exclusiveSurfaceIds) {
            if (root.hasExclusiveBoolean(candidate))
                root.setExclusiveBoolean(candidate, false)
        }

        root.activeExclusiveSurface = ""
        root.exclusiveSurfaceSyncing = false

        if (force === true)
            root.captureRegions = ({})
    }

    function handleExclusiveBooleanChanged(id, value) {
        if (root.exclusiveSurfaceSyncing)
            return

        // Focus can move to Region Selector while the source modal is still
        // supposed to be captured. Undo focus-loss closes during that window.
        if (
            !value
            && root.regionSelectorOpen
            && root.activeExclusiveSurface === id
        ) {
            root.exclusiveSurfaceSyncing = true
            root.setExclusiveBoolean(id, true)
            root.exclusiveSurfaceSyncing = false
            return
        }

        if (value) {
            root.openExclusiveSurface(id)
            return
        }

        if (root.activeExclusiveSurface === id)
            root.activeExclusiveSurface = ""

        root.clearCaptureRegion(id)
    }

    // >>> SNIP-GEOMETRY-V2.3-LIVE >>>
    function registerCaptureRegion(
        id,
        screenName,
        x,
        y,
        width,
        height,
        priority,
        label,
        captureOutset
    ) {
        if (
            !screenName
            || width <= 0
            || height <= 0
        ) {
            root.clearCaptureRegion(id)
            return
        }

        const previous = root.captureRegions[id]
        if (
            previous
            && previous.screenName === screenName
            && previous.x === x
            && previous.y === y
            && previous.width === width
            && previous.height === height
            && previous.priority === (priority ?? 100)
            && previous.label === (label || root.exclusiveSurfaceLabel(id))
            && previous.captureOutset === Math.max(0, captureOutset ?? 0)
        ) return

        const next = ({})

        for (const key in root.captureRegions)
            next[key] = root.captureRegions[key]

        next[id] = {
            id: id,
            screenName: screenName,
            x: x,
            y: y,
            width: width,
            height: height,
            priority: priority ?? 100,
            label: label || root.exclusiveSurfaceLabel(id),
            captureOutset: Math.max(0, captureOutset ?? 0)
        }

        root.captureRegions = next
    }

    function clearCaptureRegion(id) {
        if (!root.captureRegions[id])
            return

        const next = ({})

        for (const key in root.captureRegions) {
            if (key !== id)
                next[key] = root.captureRegions[key]
        }

        root.captureRegions = next
    }

    function syncAppearanceStudioCaptureRegion() {
        if (
            root.appearanceStudioOpen
            && root.appearanceStudioScreenName.length > 0
            && root.appearanceStudioRegionWidth > 0
            && root.appearanceStudioRegionHeight > 0
        ) {
            root.registerCaptureRegion(
                "appearanceStudio",
                root.appearanceStudioScreenName,
                root.appearanceStudioRegionX,
                root.appearanceStudioRegionY,
                root.appearanceStudioRegionWidth,
                root.appearanceStudioRegionHeight,
                160,
                "Appearance Studio",
                4
            )
        } else {
            root.clearCaptureRegion("appearanceStudio")
        }
    }

    function syncArchRemoteCaptureRegion() {
        if (
            root.archRemoteOpen
            && root.archRemoteScreenName.length > 0
            && root.archRemoteRegionWidth > 0
            && root.archRemoteRegionHeight > 0
        ) {
            root.registerCaptureRegion(
                "archRemote",
                root.archRemoteScreenName,
                root.archRemoteRegionX,
                root.archRemoteRegionY,
                root.archRemoteRegionWidth,
                root.archRemoteRegionHeight,
                160,
                "Arch Remote",
                4
            )
        } else {
            root.clearCaptureRegion("archRemote")
        }
    }

    onAppearanceStudioOpenChanged: {
        root.handleExclusiveBooleanChanged(
            "appearanceStudio",
            root.appearanceStudioOpen
        )
        root.syncAppearanceStudioCaptureRegion()
    }

    onArchRemoteOpenChanged: {
        root.handleExclusiveBooleanChanged(
            "archRemote",
            root.archRemoteOpen
        )
        root.syncArchRemoteCaptureRegion()
    }

    onBackupRecoveryOpenChanged:
        root.handleExclusiveBooleanChanged(
            "backupRecovery",
            root.backupRecoveryOpen
        )


    onOverviewOpenChanged:
        root.handleExclusiveBooleanChanged(
            "overview",
            root.overviewOpen
        )

    onSessionOpenChanged:
        root.handleExclusiveBooleanChanged(
            "session",
            root.sessionOpen
        )

    onAppearanceStudioScreenNameChanged:
        root.syncAppearanceStudioCaptureRegion()
    onAppearanceStudioRegionXChanged:
        root.syncAppearanceStudioCaptureRegion()
    onAppearanceStudioRegionYChanged:
        root.syncAppearanceStudioCaptureRegion()
    onAppearanceStudioRegionWidthChanged:
        root.syncAppearanceStudioCaptureRegion()
    onAppearanceStudioRegionHeightChanged:
        root.syncAppearanceStudioCaptureRegion()

    onArchRemoteScreenNameChanged:
        root.syncArchRemoteCaptureRegion()
    onArchRemoteRegionXChanged:
        root.syncArchRemoteCaptureRegion()
    onArchRemoteRegionYChanged:
        root.syncArchRemoteCaptureRegion()
    onArchRemoteRegionWidthChanged:
        root.syncArchRemoteCaptureRegion()
    onArchRemoteRegionHeightChanged:
        root.syncArchRemoteCaptureRegion()

    IpcHandler {
        target: "shellSurfaceManagerV1"

        function ping(): void {}

        function closeAll(): void {
            root.closeAllExclusiveSurfaces(true)
        }
    }
    // <<< SHELL-SURFACE-MANAGER-V1 <<<

}
