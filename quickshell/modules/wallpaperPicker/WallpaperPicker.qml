import QtCore as QtSettings
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Scope {
    id: root

    readonly property bool opened: GlobalStates.wallpaperPickerOpen
    readonly property bool retained: opened || closing || busy || undoTimer.running
    readonly property bool busy: backend.running || operation.length > 0 || finishing
    readonly property string backendPath: FileUtils.trimFileProtocol(
        Quickshell.shellPath("scripts/system/nyvorel-appearance-studio"))
    readonly property string errorColor: Appearance.m3colors.m3error
    property string monitorName: ""
    property var monitor: Quickshell.screens.find(screen => screen.name === monitorName) ?? null
    readonly property bool waffle: Config.options.panelFamily === "waffle"
    readonly property bool verticalBar: !waffle && Config.options.bar.vertical
    readonly property bool bottomBar: !verticalBar && (waffle
        ? Config.options.waffles.bar.bottom : Config.options.bar.bottom)
    readonly property int floatingBottomMargin: (GlobalStates.barOpen && bottomBar
        ? (waffle ? 48 : Appearance.sizes.barHeight + Appearance.rounding.screenRounding) : 0) + 22
    onFloatingBottomMarginChanged: Qt.callLater(updateRegion)
    property bool ready: false
    property bool finishing: false
    property bool closing: false
    property bool comparing: false
    property bool recentOnly: false
    property bool folderToolsOpen: false
    property string returnFolder: ""
    readonly property url libraryUrl: prefs.libraryFolder || Wallpapers.defaultFolder
    readonly property string libraryPath: decodeURIComponent(FileUtils.trimFileProtocol(libraryUrl.toString()))
    readonly property bool canGoUp: libraryPath.startsWith("/") && libraryPath !== "/"
    // The Qt folder model treats escaped URL characters as filesystem text.
    readonly property bool needsFolderFallback: /[#?%]/.test(libraryPath)
    readonly property bool folderLoading: needsFolderFallback ? loadedFolder !== libraryPath
        : library.status === FolderListModel.Loading
    property string loadedFolder: ""
    property var folderEntries: []
    property bool folderError: false
    onLibraryPathChanged: {
        folderEntries = []
        folderError = false
        loadedFolder = ""
        Qt.callLater(loadFolderFallback)
    }
    property string selection: ""
    property var generatedLook: null
    property var shownLook: null
    property string previewRequest: ""
    property int previewSession: 0
    property int requestSession: 0
    property string previewError: ""
    property bool keepPreviewOnClose: false
    readonly property var liveLook: (opened || closing && keepPreviewOnClose)
        && !GlobalStates.screenLocked && !comparing && selection !== original ? shownLook : null
    readonly property bool canCompare: !!shownLook && selection !== original && !busy
    readonly property bool canApply: !busy && !comparing && selection !== original
        && shownLook?.path === selection && !!shownLook.paletteReady && !previewError
    readonly property bool buildingPreview: selection !== original && !previewError
        && (shownLook?.path !== selection || !shownLook?.paletteReady)

    Binding {
        target: MaterialThemeLoader
        property: "previewColors"
        value: root.liveLook?.colors ?? null
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: GlobalStates
        property: "wallpaperPreviewPath"
        value: root.liveLook?.path ?? ""
        restoreMode: Binding.RestoreBindingOrValue
    }
    property string original: ""
    readonly property string comparisonWallpaper: /\.(mp4|webm|mkv|avi|mov)$/i.test(original)
        ? Config.options.background.thumbnailPath : original
    property string operation: ""
    property string output: ""
    property string message: ""
    property var beforeSwitch: null
    property var committedLook: null
    property var recent: []
    property var galleryImages: ({})

    function duration(milliseconds: int): int {
        return Appearance.reducedMotion ? 0 : Math.round(milliseconds * Appearance.motionScale)
    }

    function imageUrl(path: string): url {
        return path.length ? FileUtils.localFileUrl(path) : ""
    }

    function baseName(path: string): string {
        return path.slice(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "")
    }

    function begin(): void {
        previewSession++
        closingTimer.stop()
        undoTimer.stop()
        closing = false
        monitorName = Hyprland.focusedMonitor?.name ?? ""
        if (!monitorName && Quickshell.screens.length)
            monitorName = Quickshell.screens[0].name
        comparing = false
        galleryImages = ({})
        folderToolsOpen = false
        returnFolder = ""
        if (needsFolderFallback) {
            loadedFolder = ""
            folderError = false
            folderEntries = []
        }
        keepPreviewOnClose = false
        generatedLook = null
        shownLook = null
        previewError = ""
        message = ""
        beforeSwitch = null
        committedLook = null
        try {
            recent = JSON.parse(prefs.recentJson)
        } catch (error) {
            recent = []
        }
        original = Config.options.background.wallpaperPath ?? ""
        if (!prefs.libraryFolder.length && original.length)
            prefs.libraryFolder = imageUrl(FileUtils.parentDirectory(original)).toString()
        choose(original)
        Qt.callLater(restoreCarousel)
        Qt.callLater(loadFolderFallback)
        Qt.callLater(updateRegion)
        requestStatus("open-status")
        Qt.callLater(keys.forceActiveFocus)
    }

    function validatePreview(): void {
        if (!opened || !selection || selection === original || imageProbe.wallpaperPath !== selection)
            return
        if (imageProbe.failed) {
            previewError = "Could not display this image. Choose another wallpaper."
        } else if (imageProbe.status === Image.Ready) {
            if (generatedLook?.path === selection)
                shownLook = generatedLook
            else if (shownLook?.path !== selection)
                shownLook = { path: selection, colors: null, paletteReady: false }
        }
    }

    function choose(path: string): void {
        if (busy && operation !== "open-status" && !finishing)
            return
        if (selection !== path) {
            message = ""
            previewError = ""
        } else if (previewError && !imageProbe.failed) {
            previewError = ""
        }
        selection = path
        Qt.callLater(validatePreview)
        if (path === original) {
            generatedLook = null
            shownLook = null
        }
        previewDebounce.restart()
    }

    function generatePreview(): void {
        if (!opened || busy || paletteProcess.running || !selection || imageProbe.failed
                || selection === original || selection === generatedLook?.path)
            return
        previewRequest = selection
        requestSession = previewSession
        paletteProcess.exec([backendPath, "wallpaper-preview", "--wallpaper", previewRequest])
    }

    function acceptPreview(exitCode: int): void {
        if (!opened)
            return
        if (requestSession !== previewSession || previewRequest !== selection) {
            previewDebounce.restart()
            return
        }
        let result
        try {
            result = JSON.parse(paletteOutput.text)
        } catch (error) {}
        if (exitCode !== 0 || result?.ok !== true) {
            previewError = result?.error || "Could not generate a preview for this wallpaper."
            return
        }
        generatedLook = { path: previewRequest, colors: result.colors, paletteReady: true }
        validatePreview()
    }

    function loadFolderFallback(): void {
        if (!opened || !needsFolderFallback || folderScanner.running || loadedFolder === libraryPath)
            return
        folderScanner.requestedPath = libraryPath
        folderScanner.exec([
            FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/system/nyvorel-wallpaper-folder")),
            libraryPath
        ])
    }

    function galleryPath(index: int): string {
        if (recentOnly)
            return recent[index] ?? ""
        return needsFolderFallback ? folderEntries[index]?.path ?? "" : library.get(index, "filePath") ?? ""
    }

    function galleryFolder(index: int): bool {
        if (recentOnly || index < 0)
            return false
        return needsFolderFallback ? !!folderEntries[index]?.directory : !!library.get(index, "fileIsDir")
    }

    function loadGalleryImages(): void {
        if (!opened || !gallery.count || (!recentOnly && folderLoading) || galleryLoader.running)
            return
        const center = Math.max(0, gallery.currentIndex)
        const nearby = [0, -1, 1, -2, 2, -3, 3].map(offset => center + offset)
        const paths = nearby.filter(index => index >= 0 && index < gallery.count && !galleryFolder(index))
            .map(index => galleryPath(index))
            .filter(path => path.length > 0 && galleryImages[path] === undefined)
        if (!paths.length)
            return
        galleryLoader.paths = paths
        galleryLoader.session = previewSession
        galleryLoader.exec([
            FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/system/nyvorel-wallpaper-image")),
            "--gallery", "512", ...paths
        ])
    }

    function centerCard(animated: bool): void {
        if (!opened || gallery.currentIndex < 0 || gallery.stride <= 0)
            return
        glide.stop()
        const target = gallery.originX + gallery.currentIndex * gallery.stride - gallery.leftMargin
        if (!animated || Appearance.reducedMotion || Math.abs(gallery.contentX - target) < 1) {
            gallery.contentX = target
            return
        }
        glide.from = gallery.contentX
        glide.to = target
        glide.start()
    }

    function restoreCarousel(): void {
        if (!opened || !gallery.count || (!recentOnly && folderLoading))
            return
        let index = recentOnly ? prefs.recentIndex : prefs.libraryIndex
        const target = !recentOnly && returnFolder ? returnFolder : selection
        if (target) {
            for (let i = 0; i < gallery.count; i++) {
                if (galleryPath(i) === target) {
                    index = i
                    break
                }
            }
        }
        gallery.currentIndex = Math.max(0, Math.min(index, gallery.count - 1))
        if (!recentOnly) {
            prefs.libraryIndex = gallery.currentIndex
            returnFolder = ""
        }
        centerCard(false)
        galleryDebounce.restart()
    }

    function toggleRecent(): void {
        recentOnly = !recentOnly
        folderToolsOpen = false
        Qt.callLater(restoreCarousel)
    }

    function toggleFolderTools(): void {
        if (recentOnly) {
            recentOnly = false
            folderToolsOpen = true
            Qt.callLater(restoreCarousel)
        } else {
            folderToolsOpen = !folderToolsOpen
        }
    }

    function browseFolder(folder: url): void {
        returnFolder = ""
        folderToolsOpen = true
        recentOnly = false
        prefs.libraryFolder = folder.toString()
        prefs.libraryIndex = 0
        Qt.callLater(restoreCarousel)
    }

    function goUp(): void {
        if (!canGoUp || busy)
            return
        const child = libraryPath
        browseFolder(imageUrl(FileUtils.parentDirectory(libraryPath.replace(/\/+$/, "")) || "/"))
        returnFolder = child
    }

    function setWallpaper(): void {
        if (!canApply)
            return
        comparing = false
        message = ""
        requestStatus("set-status")
    }

    function requestStatus(action: string): void {
        operation = action
        output = ""
        backend.exec([backendPath, "status"])
    }

    function applyWallpaper(active, path: string, action: string): void {
        const palette = active.customPalette
        const seed = palette?.primary && palette?.secondary && palette?.tertiary && palette?.neutral
            ? "ii4:" + [palette.primary, palette.secondary, palette.tertiary, palette.neutral].join("|")
            : (active.seed ?? "")
        operation = action
        output = ""
        backend.exec([backendPath, "apply",
            "--source", active.source ?? "wallpaper", "--mode", active.mode ?? "dark",
            "--scheme", active.scheme ?? "auto", "--preset", active.preset ?? "",
            "--seed", seed, "--wallpaper", path])
    }

    function fail(text: string): void {
        message = text
        if (!opened)
            undoTimer.restart()
    }

    function finish(exitCode: int): void {
        finishing = true
        handleResult(exitCode)
        finishing = false
    }

    function handleResult(exitCode: int): void {
        const action = operation
        operation = ""
        let data = ({})
        try {
            data = JSON.parse(output)
        } catch (error) {}
        if (exitCode !== 0 || data.ok !== true) {
            fail(data.error ?? "The wallpaper could not be updated.")
            return
        }
        if (action === "open-status") {
            const wallpaper = data.committedWallpaper || data.wallpaper || original
            if (selection === original)
                choose(wallpaper)
            original = wallpaper
            if (!prefs.libraryFolder.length && original.length)
                prefs.libraryFolder = imageUrl(FileUtils.parentDirectory(original)).toString()
            previewDebounce.restart()
            Qt.callLater(restoreCarousel)
            updateRegion()
        } else if (action === "set-status") {
            if (!opened)
                return
            if (data.preview) {
                fail("Keep or revert the appearance preview in Settings first.")
                return
            }
            beforeSwitch = {active: data.active, path: data.committedWallpaper || data.wallpaper || original}
            applyWallpaper(data.active, selection, "set")
        } else if (action === "set") {
            committedLook = data.active
            if (data.warnings?.length)
                message = `Wallpaper updated · ${data.warnings.length} theme integration warning(s)`
            recent = [selection, beforeSwitch.path, ...recent].filter((path, index, paths) =>
                path && paths.indexOf(path) === index).slice(0, 24)
            prefs.recentJson = JSON.stringify(recent)
            keepPreviewOnClose = true
            closing = opened
            if (closing)
                closingTimer.restart()
            undoTimer.restart()
            GlobalStates.closeExclusiveSurface("wallpaperPicker")
        } else if (action === "undo-status") {
            const active = data.active
            if (data.preview || !committedLook || !active
                    || ["wallpaper", "source", "mode", "scheme", "preset", "seed"].some(
                        key => committedLook[key] !== active[key])
                    || JSON.stringify(committedLook.customPalette) !== JSON.stringify(active.customPalette)) {
                beforeSwitch = null
                fail("Appearance changed since the switch. Undo is unavailable.")
                return
            }
            applyWallpaper(beforeSwitch.active, beforeSwitch.path, "undo")
        } else if (action === "undo") {
            beforeSwitch = null
            message = "Previous wallpaper restored"
            undoTimer.restart()
        }
    }

    function pickAt(index: int): void {
        if (!gallery.count || (busy && operation !== "open-status"))
            return
        gallery.currentIndex = Math.max(0, Math.min(index, gallery.count - 1))
        centerCard(true)
        if (recentOnly)
            prefs.recentIndex = gallery.currentIndex
        else
            prefs.libraryIndex = gallery.currentIndex
        if (!galleryFolder(gallery.currentIndex))
            choose(galleryPath(gallery.currentIndex))
    }

    function step(direction: int): void {
        gallery.cancelFlick()
        pickAt(gallery.currentIndex < 0 ? 0 : gallery.currentIndex + direction)
    }

    function handleKeyPress(event): void {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.closeExclusiveSurface("wallpaperPicker")
        } else if (folderToolsOpen && (event.key === Qt.Key_Backspace
                || (event.key === Qt.Key_Up && (event.modifiers & Qt.AltModifier)))) {
            root.goUp()
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            const direction = event.key === Qt.Key_Right ? 1 : -1
            keys.forceActiveFocus()
            root.step(direction)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const index = gallery.currentIndex
            if (keys.activeFocus && galleryFolder(index))
                root.browseFolder(root.imageUrl(galleryPath(index)))
            else
                root.setWallpaper()
        } else {
            return
        }
        event.accepted = true
    }

    function compareOnPress(event): void {
        root.comparing = root.canCompare
        event.accepted = true
    }

    function handleKeyRelease(event): void {
        if (event.key === Qt.Key_Space && !event.isAutoRepeat) {
            root.comparing = false
            event.accepted = true
        }
    }

    function updateRegion(): void {
        if (!opened || !monitor)
            return
        GlobalStates.wallpaperPickerScreenName = monitorName
        GlobalStates.wallpaperPickerRegionX = Math.round((monitor.width - preview.width) / 2)
        GlobalStates.wallpaperPickerRegionY = monitor.height - preview.height - floatingBottomMargin
        GlobalStates.wallpaperPickerRegionWidth = preview.width
        GlobalStates.wallpaperPickerRegionHeight = preview.height
    }

    onOpenedChanged: {
        if (ready && opened && !busy) {
            begin()
        } else if (ready && opened) {
            closingTimer.stop()
            closing = false
            Qt.callLater(restoreCarousel)
            Qt.callLater(keys.forceActiveFocus)
        } else if (!opened) {
            comparing = false
            previewDebounce.stop()
            galleryDebounce.stop()
            galleryLoader.running = false
            if (ready && monitor && preview.visible && !closing) {
                closing = true
                closingTimer.restart()
            }
        }
    }

    Component.onCompleted: {
        ready = true
        if (opened)
            begin()
    }

    QtSettings.Settings {
        id: prefs
        location: Qt.resolvedUrl(Directories.config + "/nyvorel/wallpaper-picker.ini")
        category: "Library"
        property int libraryIndex: 0
        property int recentIndex: 0
        property string libraryFolder: ""
        property string recentJson: "[]"
    }

    FolderListModel {
        id: library
        folder: root.needsFolderFallback ? "" : root.libraryUrl
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif", "*.bmp", "*.svg"]
        showDirs: true
        showDotAndDotDot: false
        showDirsFirst: true
        showOnlyReadable: true
        caseSensitive: false
        sortField: FolderListModel.Name
        onStatusChanged: {
            if (status === FolderListModel.Ready && !root.recentOnly && !root.needsFolderFallback)
                Qt.callLater(root.restoreCarousel)
        }
    }

    Process {
        id: folderScanner
        property string requestedPath: ""
        stdout: StdioCollector { id: folderOutput }

        onExited: exitCode => {
            if (!root.opened || requestedPath !== root.libraryPath) {
                Qt.callLater(root.loadFolderFallback)
                return
            }
            root.loadedFolder = requestedPath
            if (exitCode === 0) {
                try {
                    root.folderEntries = JSON.parse(folderOutput.text)
                } catch (error) {
                    root.folderError = true
                }
            } else {
                root.folderError = true
            }
            Qt.callLater(root.restoreCarousel)
        }
    }

    Timer {
        id: previewDebounce
        interval: 115
        onTriggered: root.generatePreview()
    }

    Timer {
        id: galleryDebounce
        interval: 45
        onTriggered: root.loadGalleryImages()
    }

    Process {
        id: galleryLoader
        property var paths: []
        property int session: 0
        stdout: SplitParser {
            onRead: line => {
                if (!root.opened || galleryLoader.session !== root.previewSession)
                    return
                try {
                    const item = JSON.parse(line)
                    if (galleryLoader.paths.includes(item.path))
                        root.galleryImages = Object.assign({}, root.galleryImages, {[item.path]: item.image})
                } catch (error) {}
            }
        }
        onExited: {
            if (!root.opened || session !== root.previewSession) {
                galleryDebounce.restart()
                return
            }
            const images = Object.assign({}, root.galleryImages)
            for (const path of paths) {
                if (images[path] === undefined)
                    images[path] = ""
            }
            root.galleryImages = images
            galleryDebounce.restart()
        }
    }

    Timer {
        id: closingTimer
        interval: Math.max(1, root.duration(250))
        onTriggered: root.closing = false
    }

    Timer {
        id: undoTimer
        interval: 10000
    }

    Process {
        id: backend
        stdout: StdioCollector {
            onStreamFinished: root.output = text
        }
        onExited: exitCode => root.finish(exitCode)
    }

    Process {
        id: paletteProcess
        stdout: StdioCollector { id: paletteOutput }
        onExited: exitCode => root.acceptPreview(exitCode)
    }

    WallpaperImage {
        id: imageProbe
        visible: false
        wallpaperPath: root.selection !== root.original ? root.selection : ""
        sourceSize: Qt.size(320, 240)
        onFailedChanged: Qt.callLater(root.validatePreview)
        Connections {
            target: imageProbe
            function onStatusChanged() { Qt.callLater(root.validatePreview) }
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Choose wallpaper folder"
        parentWindow: keys.Window.window
        options: FolderDialog.DontUseNativeDialog
        currentFolder: root.libraryUrl
        onAccepted: {
            root.browseFolder(selectedFolder)
            keys.forceActiveFocus()
        }
        onRejected: keys.forceActiveFocus()
    }

    FileDialog {
        id: fileDialog
        title: "Choose wallpaper"
        parentWindow: keys.Window.window
        options: FileDialog.DontUseNativeDialog
        currentFolder: root.libraryUrl
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp *.avif *.bmp *.svg)"]
        onAccepted: {
            // QUrl.toString preserves the file URL. Decode once for the native backend.
            const path = decodeURIComponent(FileUtils.trimFileProtocol(selectedFile.toString()))
            root.choose(path)
            keys.forceActiveFocus()
        }
        onRejected: keys.forceActiveFocus()
    }

    PanelWindow {
        id: preview

        visible: (root.opened || root.closing) && root.monitor !== null
        screen: root.monitor
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:wallpaperPicker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened && !GlobalStates.regionSelectorOpen
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors.bottom: true
        margins.bottom: root.floatingBottomMargin
        implicitWidth: Math.min(864, Math.max(1, (root.monitor?.width ?? 864)
            - (root.verticalBar && GlobalStates.barOpen ? 2 * Appearance.sizes.verticalBarWidth + 24 : 32)))
        implicitHeight: carousel.height + toolbar.height + 17

        onWidthChanged: root.updateRegion()
        onHeightChanged: root.updateRegion()
        onVisibleChanged: root.updateRegion()
        onScreenChanged: root.updateRegion()

        mask: Region {
            item: root.opened && !GlobalStates.regionSelectorOpen ? keys : null
        }

        HyprlandFocusGrab {
            windows: [preview]
            active: root.opened && preview.visible && !!Hyprland.focusedMonitor
                && !GlobalStates.regionSelectorOpen && !fileDialog.visible && !folderDialog.visible
            onCleared: {
                if (root.opened && !GlobalStates.regionSelectorOpen
                        && !fileDialog.visible && !folderDialog.visible)
                    GlobalStates.closeExclusiveSurface("wallpaperPicker")
            }
        }

        FocusScope {
            id: keys
            property real reveal: root.opened ? 1 : 0

            anchors.fill: parent
            focus: true
            enabled: root.opened && !GlobalStates.regionSelectorOpen
            opacity: reveal
            transform: Translate { y: Appearance.reducedMotion ? 0 : 17 * (1 - keys.reveal) }

            Behavior on reveal {
                NumberAnimation { duration: root.duration(215); easing.type: Easing.OutCubic }
            }
            Component.onCompleted: {
                if (root.opened && !Appearance.reducedMotion) {
                    reveal = 0
                    Qt.callLater(() => reveal = Qt.binding(() => root.opened ? 1 : 0))
                }
            }

            onActiveFocusChanged: {
                if (!activeFocus)
                    root.comparing = false
            }
            Keys.priority: Keys.BeforeItem
            Keys.onSpacePressed: event => root.compareOnPress(event)
            Keys.onPressed: event => root.handleKeyPress(event)
            Keys.onReleased: event => root.handleKeyRelease(event)

            Shortcut {
                sequence: "Space"
                context: Qt.WindowShortcut
                enabled: root.opened && !fileDialog.visible && !folderDialog.visible
                    && (keys.Window.window?.activeFocusItem === keys || gallery.activeFocus)
                autoRepeat: false
                onActivated: root.comparing = root.canCompare
            }

            Item {
                id: carousel
                width: parent.width
                height: gallery.cardHeight + 24

                ListView {
                    id: gallery
                    readonly property real cardWidth: Math.min(330, Math.round(width * 0.55))
                    readonly property real cardHeight: Math.round(Math.min(cardWidth * 0.62,
                        (root.monitor?.height ?? 720) * 0.33))
                    readonly property real stride: cardWidth + spacing

                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: -Math.round(cardWidth * 0.135)
                    leftMargin: (width - cardWidth) / 2
                    rightMargin: leftMargin
                    boundsBehavior: Flickable.StopAtBounds
                    highlightFollowsCurrentItem: false
                    keyNavigationEnabled: false
                    model: root.recentOnly ? root.recent : root.needsFolderFallback ? root.folderEntries : library
                    reuseItems: true
                    cacheBuffer: Math.max(0, stride * 2)
                    clip: true
                    Accessible.name: root.recentOnly ? "Recent wallpapers" : "Wallpaper library"

                    onDraggingChanged: {
                        if (dragging)
                            glide.stop()
                    }
                    onMovementEnded: {
                        const centered = Math.round((contentX + leftMargin - originX) / stride)
                        root.pickAt(centered)
                    }
                    onWidthChanged: Qt.callLater(root.centerCard, false)
                    onCountChanged: Qt.callLater(root.restoreCarousel)
                    onCurrentIndexChanged: galleryDebounce.restart()

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: event => {
                            if (event.angleDelta.y === 0 || event.angleDelta.x !== 0)
                                return
                            root.step(event.angleDelta.y < 0 ? 1 : -1)
                            event.accepted = true
                        }
                    }

                    delegate: Item {
                        id: slot
                        required property int index
                        readonly property string path: root.galleryPath(index)
                        readonly property bool isFolder: root.galleryFolder(index)
                        readonly property real progress: Math.max(-2, Math.min(2,
                            (x + width / 2 - gallery.contentX - gallery.width / 2) / gallery.stride))
                        readonly property real distance: Math.min(1, Math.abs(progress))

                        width: gallery.cardWidth
                        height: gallery.height
                        z: 3 - Math.abs(progress)

                        Button {
                            id: card
                            readonly property bool selected: gallery.currentIndex === slot.index
                            readonly property bool current: !slot.isFolder && slot.path === root.original

                            width: parent.width
                            height: gallery.cardHeight
                            y: 7 + 10 * slot.distance
                            padding: 4
                            scale: (1 - 0.17 * slot.distance) * (down ? 0.982 : 1)
                            rotation: Appearance.reducedMotion ? 0 : 3 * Math.max(-1, Math.min(1, slot.progress))
                            opacity: 1 - 0.20 * slot.distance
                            activeFocusOnTab: false
                            enabled: !root.busy || root.operation === "open-status"

                            readonly property bool showComparison: selected && !slot.isFolder && root.comparing
                            readonly property string title: showComparison ? "Current wallpaper" : slot.isFolder
                                ? FileUtils.fileNameForPath(slot.path) : root.baseName(slot.path)
                            Accessible.name: title + (current ? ", current wallpaper" : "")
                            onClicked: {
                                keys.forceActiveFocus()
                                if (slot.isFolder)
                                    root.browseFolder(root.imageUrl(slot.path))
                                else
                                    root.pickAt(slot.index)
                            }

                            background: Rectangle {
                                radius: Appearance.radius.card
                                color: card.hovered ? Appearance.m3colors.m3surfaceContainerHigh
                                    : Appearance.m3colors.m3surfaceContainer
                                border.width: card.selected ? 2 : 1
                                border.color: card.selected ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer0Border
                            }

                            contentItem: Item {
                                Item {
                                    anchors.fill: parent
                                    anchors.bottomMargin: 24
                                    clip: true

                                    Image {
                                        id: galleryPhoto
                                        readonly property string path: slot.isFolder ? "" : slot.path
                                        readonly property var thumbnail: root.galleryImages[path]
                                        property bool useOriginal: false
                                        anchors.fill: parent
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(512, 512)
                                        source: path && thumbnail !== undefined
                                            ? root.imageUrl(!useOriginal && thumbnail ? thumbnail : path) : ""
                                        opacity: status === Image.Ready ? 1 : 0
                                        onPathChanged: useOriginal = false
                                        onStatusChanged: {
                                            if (status === Image.Error && thumbnail && !useOriginal)
                                                useOriginal = true
                                        }
                                        Behavior on opacity {
                                            NumberAnimation { duration: root.duration(140) }
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: !slot.isFolder && !card.showComparison && galleryPhoto.status !== Image.Ready
                                        text: galleryPhoto.status === Image.Error ? "broken_image" : "image"
                                        iconSize: 32
                                        color: Appearance.colors.colSubtext
                                    }

                                    WallpaperPreviewPhoto {
                                        wallpaperPath: card.selected && !slot.isFolder && root.canCompare
                                            ? root.comparisonWallpaper : ""
                                        opacity: card.showComparison && status === Image.Ready ? 1 : 0
                                        Behavior on opacity {
                                            NumberAnimation { duration: root.duration(135) }
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: slot.isFolder
                                        text: "folder"
                                        iconSize: 40
                                        color: Appearance.colors.colSecondary
                                    }
                                }

                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 7
                                    anchors.rightMargin: 7
                                    height: 23
                                    spacing: 5

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: card.title
                                        elide: Text.ElideRight
                                        font.pixelSize: 12
                                        color: Appearance.colors.colOnLayer0
                                    }
                                    MaterialSymbol {
                                        visible: card.current
                                        text: "check_circle"
                                        iconSize: 15
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                        }
                    }
                }

                NumberAnimation {
                    id: glide
                    target: gallery
                    property: "contentX"
                    duration: root.duration(245)
                    easing.type: Easing.OutCubic
                }

                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: emptyText.implicitWidth + 28
                    implicitHeight: emptyText.implicitHeight + 18
                    radius: Appearance.radius.card
                    color: Appearance.m3colors.m3surfaceContainerLow
                    visible: gallery.count === 0

                    StyledText {
                        id: emptyText
                        anchors.centerIn: parent
                        text: !root.recentOnly && root.folderLoading ? "Loading wallpapers…"
                            : !root.recentOnly && root.folderError ? "Could not open this folder" : "No wallpapers in this view"
                        color: Appearance.colors.colOnLayer0
                    }
                }

                WallpaperPickerButton {
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    materialIcon: "chevron_left"
                    label: "Previous wallpaper"
                    iconOnly: true
                    visible: gallery.currentIndex > 0
                    onClicked: { root.step(-1); keys.forceActiveFocus() }
                }

                WallpaperPickerButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    materialIcon: "chevron_right"
                    label: "Next wallpaper"
                    iconOnly: true
                    visible: gallery.currentIndex + 1 < gallery.count
                    onClicked: { root.step(1); keys.forceActiveFocus() }
                }
            }

            Rectangle {
                id: toolbar
                readonly property bool compact: width < 500
                readonly property bool narrow: width < 360

                anchors.top: carousel.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 674)
                height: root.folderToolsOpen ? 96 : 55
                radius: Appearance.radius.modal
                color: Appearance.m3colors.m3surfaceContainerLow
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 55
                    anchors.leftMargin: toolbar.compact ? 8 : 13
                    anchors.rightMargin: toolbar.compact ? 6 : 10
                    spacing: toolbar.compact ? 3 : 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (root.previewError)
                                    return "Preview unavailable"
                                if (root.message)
                                    return "Wallpaper picker"
                                if (root.comparing)
                                    return "Current desktop"
                                if (root.operation === "set-status" || root.operation === "set")
                                    return "Applying wallpaper…"
                                if (root.buildingPreview)
                                    return root.liveLook?.path === root.selection ? "Generating theme…" : "Loading wallpaper…"
                                if (root.liveLook)
                                    return root.liveLook.colors ? "Wallpaper and theme preview" : "Wallpaper preview"
                                return root.original ? "Current wallpaper" : "Wallpaper library"
                            }
                            elide: Text.ElideRight
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (root.previewError || root.message)
                                    return root.previewError || root.message
                                if (root.comparing)
                                    return "Release to return to preview"
                                if (root.canApply)
                                    return "Space Compare · Enter Apply"
                                if (gallery.count <= 0)
                                    return "Browse a folder or choose a file"
                                if (root.folderToolsOpen)
                                    return "← → Browse · Backspace Go up"
                                return "← → Browse · Esc Close"
                            }
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: root.previewError || root.message ? root.errorColor : Appearance.colors.colSubtext
                        }
                    }

                    Row {
                        spacing: 3
                        visible: !!root.liveLook?.colors && !toolbar.compact

                        Repeater {
                            model: [Appearance.colors.colPrimary, Appearance.colors.colSecondary,
                                    Appearance.colors.colTertiary]
                            Rectangle {
                                required property color modelData
                                width: 10
                                height: 10
                                radius: width / 2
                                color: modelData
                            }
                        }
                    }

                    WallpaperPickerButton {
                        materialIcon: root.recentOnly ? "collections" : "history"
                        label: root.recentOnly ? "Library" : "Recent wallpapers"
                        iconOnly: true
                        visible: root.recent.length > 0
                        enabled: !root.busy
                        onClicked: root.toggleRecent()
                    }
                    WallpaperPickerButton {
                        materialIcon: "folder_open"
                        label: root.folderToolsOpen ? "Hide folder navigation" : "Browse folders"
                        iconOnly: true
                        toggled: root.folderToolsOpen
                        colBackgroundToggled: Appearance.colors.colLayer3
                        colBackgroundToggledHover: Appearance.colors.colLayer3Hover
                        enabled: !root.busy
                        onClicked: { root.toggleFolderTools(); keys.forceActiveFocus() }
                    }
                    WallpaperPickerButton {
                        materialIcon: "image_search"
                        label: "Choose file"
                        iconOnly: true
                        enabled: !root.busy
                        onClicked: fileDialog.open()
                    }
                    WallpaperPickerButton {
                        materialIcon: "compare"
                        label: "Hold to compare"
                        iconOnly: true
                        visible: !toolbar.narrow
                        enabled: root.canCompare
                        onDownChanged: root.comparing = down && enabled
                        onClicked: keys.forceActiveFocus()
                        onEnabledChanged: {
                            if (!enabled)
                                root.comparing = false
                        }
                    }
                    WallpaperPickerButton {
                        materialIcon: "wallpaper"
                        label: "Apply"
                        iconOnly: toolbar.narrow
                        filled: true
                        enabled: root.canApply
                        onClicked: root.setWallpaper()
                    }
                    WallpaperPickerButton {
                        materialIcon: "close"
                        label: "Close"
                        iconOnly: true
                        onClicked: GlobalStates.closeExclusiveSurface("wallpaperPicker")
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: folderTools.top
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    height: 1
                    visible: folderTools.visible
                    color: Appearance.colors.colLayer0Border
                }

                RowLayout {
                    id: folderTools
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: toolbar.compact ? 8 : 13
                    anchors.rightMargin: toolbar.compact ? 6 : 10
                    height: 41
                    spacing: toolbar.compact ? 3 : 6
                    visible: root.folderToolsOpen

                    WallpaperPickerButton {
                        materialIcon: "arrow_upward"
                        label: "Go up to parent folder"
                        iconOnly: true
                        enabled: root.canGoUp && !root.busy
                        onClicked: { root.goUp(); keys.forceActiveFocus() }
                    }

                    StyledText {
                        id: folderLocation
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.libraryPath === Directories.home ? "~"
                            : root.libraryPath.startsWith(Directories.home + "/")
                                ? "~" + root.libraryPath.slice(Directories.home.length)
                                : root.libraryPath
                        elide: Text.ElideMiddle
                        font.pixelSize: 12
                        color: Appearance.colors.colOnLayer0
                        ToolTip.visible: pathHover.hovered
                        ToolTip.text: root.libraryPath
                        ToolTip.delay: 400
                        HoverHandler { id: pathHover }
                    }

                    WallpaperPickerButton {
                        materialIcon: "photo_library"
                        label: "Pictures"
                        iconOnly: toolbar.compact
                        enabled: !root.busy
                        onClicked: { root.browseFolder(root.imageUrl(Directories.pictures)); keys.forceActiveFocus() }
                    }

                    WallpaperPickerButton {
                        materialIcon: "folder_managed"
                        label: "Open folder dialog"
                        iconOnly: true
                        enabled: !root.busy
                        onClicked: folderDialog.open()
                    }
                }
            }
        }
    }

    PanelWindow {
        visible: !root.opened && !root.closing && root.monitor !== null && (undoTimer.running || root.busy)
        screen: root.monitor
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:wallpaperPickerUndo"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors.bottom: true
        margins.bottom: root.floatingBottomMargin
        implicitWidth: undoRow.implicitWidth + 24
        implicitHeight: undoRow.implicitHeight + 16

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0Base
            radius: Appearance.radius.control
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            RowLayout {
                id: undoRow
                anchors.centerIn: parent
                spacing: 12

                StyledText {
                    text: root.message || (root.busy ? "Updating wallpaper…" : "Wallpaper updated")
                    color: Appearance.colors.colOnLayer0
                }
                RippleButtonWithIcon {
                    buttonRadius: Appearance.radius.control
                    materialIcon: "undo"
                    mainText: "Undo"
                    visible: root.beforeSwitch && root.beforeSwitch.path.length > 0
                    enabled: !root.busy
                    onClicked: root.requestStatus("undo-status")
                }
            }
        }
    }
}
