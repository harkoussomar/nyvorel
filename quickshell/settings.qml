//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Shapes
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.nyvorel.settingsControlRail
import "modules/settings"
import "modules/nyvorel/settingsControlRail/SettingsSearchIndex.js" as SettingsIndex

ApplicationWindow {
    id: root

    function focusSettings(): void {
        if (root.closing)
            return
        root.raise()
        root.requestActivate()
    }

    IpcHandler {
        target: "settings"

        function open(): void { root.focusSettings() }
        function toggle(): void { root.requestClose() }
    }

    Shortcut {
        sequence: "Ctrl+K"
        context: Qt.WindowShortcut
        onActivated: root.focusInlineSearch()
    }

    property string firstRunFilePath:
        CF.FileUtils.trimFileProtocol(
            `${Directories.state}/user/first_run.txt`
        )
    property string firstRunFileContent:
        "This file is just here to confirm you've been greeted :>"

    // -------------------------------------------------------------------------
    // Frame state
    // -------------------------------------------------------------------------

    property real contentPadding: width < 820 ? 8 : 10
    property var pageScrollPositions: ({})
    property int previousPage: 0
    property bool showNextTime: false

    readonly property bool navigationExpanded: width >= 900
    readonly property real navigationWidth:
        navigationExpanded ? 210 : 58

    readonly property real preferredScreenMargin: 64
    readonly property real preferredWindowWidth: 1100
    readonly property real preferredWindowHeight: 750

    property bool closing: false
    property bool allowImmediateClose: false

    property var pages: [
        {
            name: Translation.tr("Appearance"),
            description: Translation.tr("Themes, surfaces, motion and saved looks"),
            group: Translation.tr("Make it yours"),
            icon: "palette",
            sections: [Translation.tr("Theme"), Translation.tr("Surfaces & motion"), Translation.tr("Corners"), Translation.tr("App theming"), Translation.tr("Saved looks")],
            component: ""
        },
        {
            name: Translation.tr("Bar & workspaces"),
            description: Translation.tr("Layout, indicators and workspace display"),
            group: Translation.tr("Make it yours"),
            icon: "view_agenda",
            sections: [Translation.tr("Bar layout"), Translation.tr("Bar content"), Translation.tr("System tray"), Translation.tr("Workspaces")],
            component: "modules/settings/BarConfig.qml"
        },
        {
            name: Translation.tr("Desktop"),
            description: Translation.tr("Wallpaper motion, clock and weather"),
            group: Translation.tr("Make it yours"),
            icon: "wallpaper",
            sections: [Translation.tr("Wallpaper motion"), Translation.tr("Desktop clock"), Translation.tr("Desktop weather")],
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Windows & controls"),
            description: Translation.tr("Dock, sidebars, capture tools and lock screen"),
            group: Translation.tr("Everyday use"),
            icon: "dashboard_customize",
            sections: [Translation.tr("Shell surfaces"), Translation.tr("Lock & feedback"), Translation.tr("Capture tools"), Translation.tr("Navigation & sidebars"), Translation.tr("Typography")],
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            name: Translation.tr("System & language"),
            description: Translation.tr("Sound, power, input and language"),
            group: Translation.tr("Everyday use"),
            icon: "tune",
            sections: [Translation.tr("System"), Translation.tr("Touchpad"), Translation.tr("Locale & time"), Translation.tr("Feedback"), Translation.tr("Privacy & content")],
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            name: Translation.tr("Services"),
            description: Translation.tr("Search, weather, storage and optional tools"),
            group: Translation.tr("Everyday use"),
            icon: "cloud",
            sections: [Translation.tr("AI & recognition"), Translation.tr("Search & web"), Translation.tr("Weather"), Translation.tr("Storage & performance"), Translation.tr("Optional tools")],
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("About"),
            description: Translation.tr("Version, diagnostics and project links"),
            icon: "info",
            sections: [Translation.tr("Overview"), Translation.tr("Runtime"), Translation.tr("System & project")],
            component: "modules/settings/About.qml"
        }
    ]

    property int currentPage: 0
    property var settingsSectionSelections: ({})
    property var pendingAppearanceSearch: null
    readonly property var appearanceEditor: appearancePageLoader.item
    readonly property var currentPageItem:
        root.currentPage === 0 ? root.appearanceEditor : pageLoader.item

    function openWallpaperPicker(): void {
        Quickshell.execDetached(["qs", "ipc", "-c", "nyvorel", "call", "wallpaperPicker", "open"])
    }

    function openConfigFile(): void {
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/system/nyvorel-app-launch"),
            "--open", CF.FileUtils.trimFileProtocol(Config.filePath)
        ])
    }

    function prepareSearchPage(entry): void {
        if (!entry)
            return

        if (entry.pageSection) {
            root.settingsSectionSelections[entry.pageIndex] = entry.pageSection
            if (root.currentPage === entry.pageIndex && pageLoader.item?.currentSection !== undefined)
                pageLoader.item.currentSection = entry.pageSection
        }
        if (entry.appearanceTab === undefined)
            return
        if (!root.appearanceEditor) {
            root.pendingAppearanceSearch = entry
            return
        }
        root.appearanceEditor.currentPage = entry.appearanceTab
        if (entry.appearanceSection)
            root.appearanceEditor.interfaceFineTuneSection = entry.appearanceSection
        if (entry.appearanceTab === 3 && entry.path === "Terminal appearance")
            root.appearanceEditor.expandTerminalTuning()
    }

    Timer {
        id: finishAppearanceEdits
        interval: 120
        onTriggered: root.requestClose()
    }


    // -------------------------------------------------------------------------
    // Settings Control Rail search navigation
    // -------------------------------------------------------------------------

    property string pendingSearchLabel: ""
    property string pendingSettingsGroup: ""
    property int searchTargetAttempts: 0
    property bool searchHighlightVisible: false
    property real searchHighlightX: 0
    property real searchHighlightY: 0
    property real searchHighlightWidth: 0
    property real searchHighlightHeight: 0

    function normalizedSearchText(value) {
        return String(value === undefined || value === null ? "" : value).toLowerCase().trim()
    }

    function findSearchTextNode(node, needle) {
        if (!node || !node.visible || needle.length === 0)
            return null

        try {
            if (
                node.text !== undefined
                && root.normalizedSearchText(node.text)
                    .indexOf(needle) >= 0
            ) {
                return node
            }
        } catch (error) {
        }

        let children = []

        try {
            children = node.children ? node.children : []
        } catch (error) {
            children = []
        }

        for (let i = 0; i < children.length; ++i) {
            const result =
                root.findSearchTextNode(children[i], needle)

            if (result)
                return result
        }

        return null
    }

    function searchAncestorFlickable(node) {
        let current = node && node.parent ? node.parent : null

        while (current) {
            try {
                if (
                    current.contentY !== undefined
                    && current.contentHeight !== undefined
                    && current.height !== undefined
                ) {
                    return current
                }
            } catch (error) {
            }

            current = current.parent ? current.parent : null
        }

        return null
    }

    function highlightSearchNode(node) {
        if (!node)
            return

        try {
            const point = node.mapToItem(contentPane, 0, 0)
            root.searchHighlightX = Math.max(4, point.x - 8)
            root.searchHighlightY = Math.max(4, point.y - 6)
            root.searchHighlightWidth =
                Math.min(
                    contentPane.width - root.searchHighlightX - 4,
                    Math.max(80, node.width + 16)
                )
            root.searchHighlightHeight =
                Math.max(30, node.height + 12)
            root.searchHighlightVisible = true
            searchHighlightHideTimer.restart()
        } catch (error) {
            root.searchHighlightVisible = false
        }
    }

    function revealPendingSearchTarget() {
        const needle =
            root.normalizedSearchText(Translation.tr(root.pendingSearchLabel))

        if (needle.length === 0 || !root.currentPageItem)
            return

        if (root.currentPage === 0 && !root.appearanceEditor.currentTabReady)
            return

        if (root.pendingSettingsGroup.length && root.currentPageItem.revealSetting)
            root.currentPageItem.revealSetting(root.pendingSettingsGroup)

        const target =
            root.findSearchTextNode(root.currentPageItem, needle)

        if (!target) {
            root.searchTargetAttempts += 1

            if (root.searchTargetAttempts < 5)
                searchTargetTimer.restart()

            return
        }

        const flickable =
            root.searchAncestorFlickable(target)

        if (flickable) {
            try {
                const point =
                    target.mapToItem(
                        flickable.contentItem
                            ? flickable.contentItem
                            : flickable,
                        0,
                        0
                    )

                const maxY =
                    Math.max(
                        0,
                        flickable.contentHeight
                            - flickable.height
                    )

                flickable.contentY =
                    Math.max(
                        0,
                        Math.min(maxY, point.y - 84)
                    )
            } catch (error) {
            }
        }

        Qt.callLater(() => {
            root.highlightSearchNode(target)
            let control = target
            while (control && control !== root.currentPageItem) {
                const name = root.normalizedSearchText(control.Accessible?.name)
                if (control.activeFocusOnTab && control.enabled && name === needle) {
                    control.forceActiveFocus(Qt.TabFocusReason)
                    break
                }
                const interactive = control.children?.find(child =>
                    child.visible && child.enabled && child.activeFocusOnTab
                    && root.normalizedSearchText(child.Accessible?.name) === needle)
                if (interactive) {
                    interactive.forceActiveFocus(Qt.TabFocusReason)
                    break
                }
                control = control.parent
            }
        })

        root.pendingSearchLabel = ""
        root.pendingSettingsGroup = ""
        root.searchTargetAttempts = 0
    }

    function jumpToSection(label: string): void {
        root.pendingSettingsGroup = ""
        root.pendingSearchLabel = label
        root.searchTargetAttempts = 0
        root.revealPendingSearchTarget()
    }

    // Inline global search: reuse the same generated settings index as the
    // original search surface, without opening a second search dialog.
    property var inlineSearchMatches: []
    property int inlineSearchSelected: 0

    function focusInlineSearch() {
        headerSearchInput.forceActiveFocus()
        headerSearchInput.selectAll()
        if (headerSearchInput.text.trim().length > 0)
            root.refreshInlineSearch()
    }

    function refreshInlineSearch() {
        const query = root.normalizedSearchText(headerSearchInput.text)
        if (!query.length) {
            root.inlineSearchMatches = []
            root.inlineSearchSelected = 0
            headerSearchResults.close()
            return
        }

        const terms = query.split(/\s+/).filter(t => t.length > 0)
        const entries = SettingsIndex.entries || []
        const candidates = []
        for (let i = 0; i < entries.length; ++i) {
            const entry = entries[i]
            if (!entry || !entry.label || (entry.pageIndex === undefined && entry.action !== "open-config"))
                continue

            const label = root.normalizedSearchText(entry.label)
            const path = root.normalizedSearchText(entry.page + " " + (entry.path || ""))
            const keywords = root.normalizedSearchText(entry.keywords || "")
            const allText = label + " " + path + " " + keywords
            if (!terms.every(term => allText.indexOf(term) !== -1))
                continue

            let score = 0
            if (label === query) score += 100
            if (label.startsWith(query)) score += 50
            if (label.indexOf(query) >= 0) score += 35
            if (path.indexOf(query) >= 0) score += 12
            if ((entry.path || "") === "Page") score += 4
            if (keywords.indexOf(query) >= 0) score += 2
            candidates.push({ entry: entry, score: score, order: i })
        }
        candidates.sort((a, b) => (b.score - a.score) || (a.order - b.order))
        root.inlineSearchMatches = candidates.slice(0, 9).map(match => match.entry)
        root.inlineSearchSelected = 0
        if (!headerSearchResults.opened)
            headerSearchResults.open()
    }

    function navigateInlineSearch(entry) {
        if (!entry)
            return
        headerSearchResults.close()
        headerSearchInput.clear()
        if (entry.action === "open-config") {
            root.openConfigFile()
            frameFocus.forceActiveFocus()
            return
        }
        if (entry.pageIndex === undefined)
            return
        const pageIndex = Number(entry.pageIndex)
        if (pageIndex < 0 || pageIndex >= root.pages.length)
            return
        root.pendingAppearanceSearch = null
        root.pendingSettingsGroup = entry.settingsGroup ?? ""
        if ((entry.path || "") !== "Page") {
            root.pendingSearchLabel = String(entry.searchLabel ?? entry.label ?? "")
            root.searchTargetAttempts = 0
        } else {
            root.pendingSearchLabel = ""
        }
        root.prepareSearchPage(entry)
        root.switchToPage(pageIndex)
        if (root.pendingSearchLabel.length)
            searchTargetTimer.restart()
        else
            frameFocus.forceActiveFocus()
    }

    property bool keyboardNavigationActive: false
    property bool keyboardFocusRingVisible: false
    property real keyboardFocusX: 0
    property real keyboardFocusY: 0
    property real keyboardFocusWidth: 0
    property real keyboardFocusHeight: 0

    function revealKeyboardFocusItem(item) {
        if (!item)
            return

        let current = item.parent

        while (current) {
            try {
                const hasVerticalScroll =
                    current.contentY !== undefined
                    && current.contentHeight !== undefined
                    && current.height !== undefined
                    && current.contentHeight > current.height

                const hasHorizontalScroll =
                    current.contentX !== undefined
                    && current.contentWidth !== undefined
                    && current.width !== undefined
                    && current.contentWidth > current.width

                if (hasVerticalScroll || hasHorizontalScroll) {
                    const targetParent =
                        current.contentItem
                            ? current.contentItem
                            : current

                    const point =
                        item.mapToItem(targetParent, 0, 0)

                    if (hasVerticalScroll) {
                        const maxY =
                            Math.max(
                                0,
                                current.contentHeight
                                    - current.height
                            )

                        if (point.y < current.contentY + 18) {
                            current.contentY =
                                Math.max(0, point.y - 18)
                        } else if (
                            point.y + item.height
                            > current.contentY
                                + current.height
                                - 18
                        ) {
                            current.contentY =
                                Math.min(
                                    maxY,
                                    point.y
                                        + item.height
                                        - current.height
                                        + 18
                                )
                        }
                    }

                    if (hasHorizontalScroll) {
                        const maxX =
                            Math.max(
                                0,
                                current.contentWidth
                                    - current.width
                            )

                        if (point.x < current.contentX + 18) {
                            current.contentX =
                                Math.max(0, point.x - 18)
                        } else if (
                            point.x + item.width
                            > current.contentX
                                + current.width
                                - 18
                        ) {
                            current.contentX =
                                Math.min(
                                    maxX,
                                    point.x
                                        + item.width
                                        - current.width
                                        + 18
                                )
                        }
                    }
                }
            } catch (error) {
            }

            current = current.parent
        }
    }

    function showKeyboardFocus(item) {
        if (!item || !frameSurface) {
            root.keyboardFocusRingVisible = false
            return
        }

        try {
            const point =
                item.mapToItem(frameSurface, 0, 0)

            root.keyboardFocusX =
                Math.max(0, point.x - 3)
            root.keyboardFocusY =
                Math.max(0, point.y - 3)
            root.keyboardFocusWidth =
                Math.max(24, item.width + 6)
            root.keyboardFocusHeight =
                Math.max(24, item.height + 6)
            root.keyboardFocusRingVisible = true
        } catch (error) {
            root.keyboardFocusRingVisible = false
        }
    }

    function moveSettingsKeyboardFocus(forward) {
        let current = root.activeFocusItem

        if (!current)
            current = frameFocus

        let next = null

        try {
            next = current.nextItemInFocusChain(forward)
        } catch (error) {
            next = null
        }

        if (!next || next === current)
            return false

        try {
            next.forceActiveFocus(Qt.TabFocusReason)
        } catch (error) {
            return false
        }

        root.keyboardNavigationActive = true
        root.revealKeyboardFocusItem(next)
        Qt.callLater(() => root.showKeyboardFocus(next))
        return true
    }

    Timer {
        id: searchTargetTimer
        interval: 120
        repeat: false
        onTriggered: root.revealPendingSearchTarget()
    }

    Timer {
        id: searchHighlightHideTimer
        interval: 1400
        repeat: false
        onTriggered: root.searchHighlightVisible = false
    }

    // -------------------------------------------------------------------------
    // Native window
    // -------------------------------------------------------------------------

    visible: true
    title: "Nyvorel Settings"
    color: "transparent"

    minimumWidth: 680
    minimumHeight: 500
    width: preferredWindowWidth
    height: preferredWindowHeight

    function fitInitialSizeToScreen(): void {
        if (!root.screen)
            return

        const geometry = root.screen.availableGeometry
            ?? root.screen.geometry
        if (!geometry)
            return
        const availableWidth = Math.max(
            root.minimumWidth,
            geometry.width - root.preferredScreenMargin
        )
        const availableHeight = Math.max(
            root.minimumHeight,
            geometry.height - root.preferredScreenMargin
        )

        root.width = Math.min(root.preferredWindowWidth, availableWidth)
        root.height = Math.min(root.preferredWindowHeight, availableHeight)
    }

    function requestClose(): void {
        if (root.closing || root.allowImmediateClose)
            return

        if (root.appearanceEditor && !root.appearanceEditor.canClose) {
            root.appearanceEditor.prepareToClose()
            finishAppearanceEdits.restart()
            return
        }

        root.closing = true
        closeAnimation.restart()
    }

    function switchToPage(index: int): void {
        if (index < 0 || index >= root.pages.length)
            return
        if (index === root.currentPage)
            return

        if (pageLoader.item && pageLoader.item.contentY !== undefined)
            root.pageScrollPositions[root.currentPage] = pageLoader.item.contentY
        root.currentPage = index
    }

    onClosing: closeEvent => {
        if (root.allowImmediateClose) {
            closeEvent.accepted = true
            return
        }

        closeEvent.accepted = false
        root.requestClose()
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0

        // Size once at startup so normal user/compositor resizing remains
        // authoritative afterwards.
        root.fitInitialSizeToScreen()

        Qt.callLater(() => frameFocus.forceActiveFocus())
    }

    // -------------------------------------------------------------------------
    // Presentation lifecycle
    // -------------------------------------------------------------------------

    Rectangle {
        id: frameSurface

        // Hyprland owns the outer window border, rounding and shadow.
        anchors.fill: parent
        color: Appearance.colors.colLayer0Base
        enabled: !root.closing

        MotionAnim {
            id: closeAnimation
            target: frameSurface
            property: "opacity"
            to: 0
            type: MotionAnim.FastEffects

            onFinished: {
                root.allowImmediateClose = true
                // Quickshell's CLI terminates this dedicated Settings
                // instance without deleting QML objects inside a handler.
                Quickshell.execDetached([
                    "qs", "-p", Quickshell.shellPath("settings.qml"), "kill"
                ])
            }
        }

        Shape {
            id: settingsSidebarSurface
            width: root.navigationWidth + root.contentPadding
            height: frameSurface.height

            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 0
                    x2: settingsSidebarSurface.width * 0.6
                    y2: settingsSidebarSurface.height

                    // Very soft, theme-aware milky material, with gentle depth.
                    // A dark theme lightens; a light theme subtly darkens.
                    GradientStop {
                        position: 0
                        color: Qt.rgba(
                            Appearance.colors.colOnLayer0.r,
                            Appearance.colors.colOnLayer0.g,
                            Appearance.colors.colOnLayer0.b, 0.065)
                    }
                    GradientStop {
                        position: 0.52
                        color: Qt.rgba(
                            Appearance.colors.colOnLayer0.r,
                            Appearance.colors.colOnLayer0.g,
                            Appearance.colors.colOnLayer0.b, 0.042)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.rgba(
                            Appearance.colors.colOnLayer0.r,
                            Appearance.colors.colOnLayer0.g,
                            Appearance.colors.colOnLayer0.b, 0.055)
                    }
                }

                startX: 0
                startY: 0
                PathLine { x: settingsSidebarSurface.width; y: 0 }
                PathLine { x: settingsSidebarSurface.width; y: settingsSidebarSurface.height }
                PathLine { x: 0; y: settingsSidebarSurface.height }
                PathLine { x: 0; y: 0 }
            }
        }

        // ---------------------------------------------------------------------
        // Local shell controls
        // ---------------------------------------------------------------------

        component SidebarUtilityButton: RippleButton {
            id: utilityButton

            required property string iconName
            required property string label

            property string description: ""
            property bool expanded: true

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 40

            buttonRadius: Appearance.radius.control
            buttonRadiusPressed: Appearance.radius.control

            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active

            activeFocusOnTab: true

            Accessible.role: Accessible.Button
            Accessible.name: label
            Accessible.description: description

            contentItem: Item {
                anchors.fill: parent

                MaterialSymbol {
                    id: utilityIcon

                    anchors {
                        verticalCenter: parent.verticalCenter
                        horizontalCenter:
                            utilityButton.expanded
                                ? undefined
                                : parent.horizontalCenter
                        left:
                            utilityButton.expanded
                                ? parent.left
                                : undefined
                        leftMargin: utilityButton.expanded ? 11 : 0
                    }

                    text: utilityButton.iconName
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    visible: utilityButton.expanded

                    anchors {
                        left: utilityIcon.right
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 8
                    }

                    text: utilityButton.label
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                }
            }

            StyledToolTip {
                text:
                    utilityButton.description.length > 0
                        ? utilityButton.description
                        : utilityButton.label
            }
        }

        FocusScope {
            id: frameFocus

            anchors.fill: parent
            focus: true

            // Handle global Settings shortcuts after focused child controls
            // get the first chance to consume the event.
            Keys.priority: Keys.AfterItem
            Keys.onPressed: event => {
                if (
                    event.key === Qt.Key_Escape
                    && event.modifiers === Qt.NoModifier
                ) {
                    root.requestClose()
                    event.accepted = true
                    return
                }

                const ctrl =
                    (event.modifiers & Qt.ControlModifier)
                    === Qt.ControlModifier

                if (
                    !ctrl
                    && event.modifiers === Qt.NoModifier
                    && (
                        event.key === Qt.Key_Up
                        || event.key === Qt.Key_Down
                        || event.key === Qt.Key_Left
                        || event.key === Qt.Key_Right
                    )
                ) {
                    const forward =
                        event.key === Qt.Key_Down
                        || event.key === Qt.Key_Right

                    if (root.moveSettingsKeyboardFocus(forward))
                        event.accepted = true

                    return
                }

                if (!ctrl)
                    return

                if (event.key === Qt.Key_K) {
                    root.focusInlineSearch()
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_PageDown) {
                    root.switchToPage(
                        Math.min(
                            root.currentPage + 1,
                            root.pages.length - 1
                        )
                    )
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    root.switchToPage(
                        Math.max(root.currentPage - 1, 0)
                    )
                    event.accepted = true
                } else if (event.key === Qt.Key_Tab) {
                    root.switchToPage(
                        (root.currentPage + 1) % root.pages.length
                    )
                    event.accepted = true
                } else if (event.key === Qt.Key_Backtab) {
                    root.switchToPage(
                        (
                            root.currentPage
                            - 1
                            + root.pages.length
                        ) % root.pages.length
                    )
                    event.accepted = true
                }
            }

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: root.contentPadding
                }

                spacing: 4

                // -------------------------------------------------------------
                // Fixed header
                // -------------------------------------------------------------

                Item {
                    id: titleBar

                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: 44

                    // nyvorel-settings-responsive-rail-v1
                    // The title is part of the navigation rail's visual column.
                    // On compact windows, use an icon rather than clipped text.
                    Item {
                        id: settingsRailHeading
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        width: root.navigationWidth
                        height: parent.height
                        visible: Config.options?.windows.showTitlebar

                        StyledText {
                            id: titleText
                            anchors.centerIn: parent
                            visible: root.navigationExpanded && Config.options?.windows.showTitlebar
                            color: Appearance.colors.colOnLayer0
                            text: Translation.tr("Settings")
                            font {
                                family: Appearance.font.family.title
                                pixelSize: Appearance.font.pixelSize.title
                                variableAxes: Appearance.font.variableAxes.title
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !root.navigationExpanded
                            text: "settings"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer0
                            Accessible.name: Translation.tr("Settings")
                        }
                    }

                    // One native search field. Results appear immediately below
                    // this field; no second dialog or duplicated search input.
                    Rectangle {
                        id: headerSearch
                        readonly property real contentInset: settingsRailHeading.width + bodyRow.spacing

                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            horizontalCenterOffset: headerSearch.contentInset / 2
                            verticalCenter: parent.verticalCenter
                        }
                        width: Math.min(520, titleBar.width - contentInset
                            - 2 * (closeButton.width + bodyRow.spacing))
                        height: 36
                        radius: Appearance.radius.control
                        color: headerSearchInput.activeFocus
                            ? Appearance.colors.colLayer1Hover
                            : Appearance.colors.colLayer1
                        border.width: 1
                        border.color: headerSearchInput.activeFocus
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer0Border

                        MaterialSymbol {
                            id: headerSearchIcon
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            text: "search"
                            iconSize: 18
                            color: Appearance.colors.colSubtext
                        }

                        TextField {
                            id: headerSearchInput
                            anchors {
                                left: headerSearchIcon.right
                                leftMargin: 10
                                right: headerSearchHint.left
                                rightMargin: 8
                                top: parent.top
                                bottom: parent.bottom
                            }
                            background: Item {}
                            leftPadding: 0
                            rightPadding: 0
                            topPadding: 0
                            bottomPadding: 0
                            color: Appearance.colors.colOnLayer0
                            selectionColor: Appearance.colors.colPrimary
                            selectedTextColor: Appearance.colors.colOnPrimary
                            font.family: Appearance.font.family.title
                            font.pixelSize: Appearance.font.pixelSize.small
                            placeholderText: Translation.tr("Search settings")
                            placeholderTextColor: Appearance.colors.colSubtext
                            verticalAlignment: TextInput.AlignVCenter
                            selectByMouse: true
                            activeFocusOnTab: true
                            Accessible.name: Translation.tr("Search settings")
                            Accessible.description: Translation.tr("Search every settings page. Ctrl+K to focus")

                            onTextChanged: root.refreshInlineSearch()
                            onActiveFocusChanged: {
                                if (activeFocus && text.trim().length > 0)
                                    root.refreshInlineSearch()
                            }
                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    if (headerSearchResults.opened || text.length > 0) {
                                        headerSearchResults.close()
                                        clear()
                                        event.accepted = true
                                    }
                                } else if (headerSearchResults.opened &&
                                           event.key === Qt.Key_Down &&
                                           root.inlineSearchMatches.length > 0) {
                                    root.inlineSearchSelected = Math.min(
                                        root.inlineSearchMatches.length - 1,
                                        root.inlineSearchSelected + 1)
                                    inlineResultList.positionViewAtIndex(root.inlineSearchSelected, ListView.Contain)
                                    event.accepted = true
                                } else if (headerSearchResults.opened &&
                                           event.key === Qt.Key_Up &&
                                           root.inlineSearchMatches.length > 0) {
                                    root.inlineSearchSelected = Math.max(0, root.inlineSearchSelected - 1)
                                    inlineResultList.positionViewAtIndex(root.inlineSearchSelected, ListView.Contain)
                                    event.accepted = true
                                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                           && text.trim().length > 0) {
                                    if (root.inlineSearchMatches.length > 0)
                                        root.navigateInlineSearch(root.inlineSearchMatches[root.inlineSearchSelected])
                                    event.accepted = true
                                }
                            }
                        }

                        StyledText {
                            id: headerSearchHint
                            anchors {
                                right: parent.right
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            visible: headerSearchInput.text.length === 0 && headerSearch.width >= 340
                            text: "Ctrl+K"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                        MaterialSymbol {
                            id: clearSearchIcon
                            anchors {
                                right: parent.right
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            visible: headerSearchInput.text.length > 0
                            text: "close"
                            iconSize: 17
                            color: Appearance.colors.colSubtext

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    headerSearchInput.clear()
                                    headerSearchInput.forceActiveFocus()
                                }
                            }
                        }

                        Popup {
                            id: headerSearchResults
                            x: 0
                            y: headerSearch.height + 7
                            width: headerSearch.width
                            height: Math.min(440,
                                             Math.max(90, root.height - 110),
                                             root.inlineSearchMatches.length === 0
                                                 ? 66
                                                 : root.inlineSearchMatches.length * 57 + 12)
                            padding: 6
                            z: 125
                            modal: false
                            focus: false
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                            background: Rectangle {
                                color: Appearance.colors.colLayer0
                                border.color: Appearance.colors.colLayer0Border
                                border.width: 1
                                radius: Appearance.radius.control
                            }

                            contentItem: Item {
                                ListView {
                                    id: inlineResultList
                                    anchors.fill: parent
                                    visible: root.inlineSearchMatches.length > 0
                                    model: root.inlineSearchMatches
                                    clip: true
                                    spacing: 2
                                    boundsBehavior: Flickable.StopAtBounds

                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: inlineResultList.width
                                        height: 55
                                        radius: Appearance.radius.control
                                        color: root.inlineSearchSelected === index || resultHover.containsMouse
                                            ? Appearance.colors.colLayer2Hover
                                            : "transparent"

                                        Column {
                                            anchors {
                                                left: parent.left
                                                right: parent.right
                                                leftMargin: 12
                                                rightMargin: 12
                                                verticalCenter: parent.verticalCenter
                                            }
                                            spacing: 3

                                            StyledText {
                                                width: parent.width
                                                text: String(modelData.label || "")
                                                color: Appearance.colors.colOnLayer0
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                width: parent.width
                                                text: String(modelData.page || "") +
                                                    ((modelData.path || "") === "Page" ? "" : "  ›  " + String(modelData.path || ""))
                                                color: Appearance.colors.colSubtext
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: resultHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: root.inlineSearchSelected = index
                                            onClicked: root.navigateInlineSearch(modelData)
                                        }
                                    }
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: root.inlineSearchMatches.length === 0
                                    text: Translation.tr("No matching settings")
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                    }

                    // Normalized to the Battery dialog action-button DNA.
                    Rectangle {
                        id: closeButton

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }

                        implicitWidth: 34
                        implicitHeight: 34
                        radius: height / 2

                        activeFocusOnTab: true

                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Close settings")
                        Accessible.focusable: true
                        Accessible.focused: closeButton.activeFocus
                        Accessible.onPressAction: root.requestClose()

                        Keys.onPressed: event => {
                            if (
                                event.key === Qt.Key_Space
                                || event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter
                            ) {
                                root.requestClose()
                                event.accepted = true
                            }
                        }

                        color:
                            closeArea.containsMouse || closeButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Qt.rgba(
                                    Appearance.colors.colOnSurfaceVariant.r,
                                    Appearance.colors.colOnSurfaceVariant.g,
                                    Appearance.colors.colOnSurfaceVariant.b,
                                    0.07
                                )

                        border.width: 1
                        border.color:
                            closeArea.containsMouse || closeButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 19
                            color:
                                closeArea.containsMouse || closeButton.activeFocus
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnSurfaceVariant
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestClose()
                        }

                        StyledToolTip {
                            extraVisibleCondition: closeArea.containsMouse
                            text: Translation.tr("Close settings")
                        }
                    }


                }

                // -------------------------------------------------------------
                // Fixed sidebar + scroll-owning page
                // -------------------------------------------------------------

                RowLayout {
                    id: bodyRow

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    SettingsControlRail {
                        id: navRailWrapper

                        Layout.fillHeight: true
                        Layout.preferredWidth: root.navigationWidth
                        Layout.minimumWidth: root.navigationWidth
                        Layout.maximumWidth: root.navigationWidth

                        pages: root.pages
                        currentPage: root.currentPage
                        expanded: root.navigationExpanded

                        onPageRequested: index => root.switchToPage(index)
                        onConfigRequested: root.openConfigFile()
                    }

                    Item {
                        id: contentPane

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Rectangle {
                            id: searchTargetHighlight

                            x: root.searchHighlightX
                            y: root.searchHighlightY
                            width: root.searchHighlightWidth
                            height: root.searchHighlightHeight
                            z: 20

                            visible:
                                root.searchHighlightVisible
                                || opacity > 0.01

                            opacity:
                                root.searchHighlightVisible
                                    ? 1
                                    : 0

                            radius: Appearance.radius.control
                            color: "transparent"
                            border.width: 2
                            border.color: Appearance.colors.colPrimary

                            Behavior on opacity {
                                MotionAnim {
                                    type: MotionAnim.FastEffects
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4

                            RowLayout {
                                id: appearanceFeedback
                                readonly property string feedback: root.appearanceEditor?.feedback
                                    ?? (appearancePageLoader.status === Loader.Error
                                        ? Translation.tr("Could not load Appearance")
                                        : root.currentPage === 0 ? Translation.tr("Loading appearance…") : "")

                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 12
                                visible: (root.appearanceEditor?.previewToken.length ?? 0) > 0
                                    || (root.currentPage <= 2 && feedback.length > 0)

                                StyledText {
                                    Layout.fillWidth: true
                                    text: (root.appearanceEditor?.previewToken.length ?? 0) > 0
                                        ? Translation.tr("Live preview · %1 seconds left").arg(root.appearanceEditor.previewSeconds)
                                        : appearanceFeedback.feedback
                                    color: root.appearanceEditor?.actionFailed
                                        ? Appearance.m3colors.m3error
                                        : Appearance.colors.colOnLayer1
                                    wrapMode: Text.Wrap
                                }

                                RippleButtonWithIcon {
                                    visible: (root.appearanceEditor?.previewToken.length ?? 0) > 0
                                    enabled: root.appearanceEditor ? !root.appearanceEditor.pending : false
                                    implicitHeight: 36
                                    materialIcon: "undo"
                                    mainText: Translation.tr("Revert")
                                    onClicked: root.appearanceEditor.revertPreview()
                                }

                                RippleButtonWithIcon {
                                    visible: (root.appearanceEditor?.previewToken.length ?? 0) > 0
                                    enabled: root.appearanceEditor ? !root.appearanceEditor.pending : false
                                    implicitHeight: 36
                                    materialIcon: "check"
                                    mainText: Translation.tr("Keep")
                                    onClicked: root.appearanceEditor.keepPreview()
                                }
                            }

                            Loader {
                                id: appearancePageLoader
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.currentPage === 0
                                asynchronous: true
                                active: false
                                source: Qt.resolvedUrl("modules/settings/AppearanceConfig.qml")
                                Component.onCompleted: Qt.callLater(() => appearancePageLoader.active = true)
                                onLoaded: {
                                    root.prepareSearchPage(root.pendingAppearanceSearch)
                                    root.pendingAppearanceSearch = null
                                    if (root.currentPage === 0 && root.pendingSearchLabel.length)
                                        searchTargetTimer.restart()
                                    if (pageLoader.item && pageLoader.item.appearanceEditor !== undefined)
                                        pageLoader.item.appearanceEditor = item
                                }

                                Connections {
                                    target: appearancePageLoader.item
                                    function onWallpaperRequested() { root.openWallpaperPicker() }
                                    function onCurrentTabReadyChanged() {
                                        if (root.currentPage === 0 && target.currentTabReady && root.pendingSearchLabel.length)
                                            searchTargetTimer.restart()
                                    }
                                }
                            }

                            Loader {
                                id: pageLoader

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                opacity: 1

                                visible: root.currentPage !== 0
                                active: Config.ready && visible
                                source: root.pages[root.currentPage].component

                                Connections {
                                    target: pageLoader.item?.currentSection !== undefined
                                        ? pageLoader.item : null
                                    function onCurrentSectionChanged() {
                                        root.settingsSectionSelections[root.currentPage] = target.currentSection
                                    }
                                }

                                onLoaded: {
                                    const section = root.settingsSectionSelections[root.currentPage]
                                    if (section && item?.currentSection !== undefined)
                                        item.currentSection = section
                                    if (item && item.appearanceEditor !== undefined)
                                        item.appearanceEditor = root.appearanceEditor
                                    if (
                                        item
                                        && item.contentY !== undefined
                                    ) {
                                        item.contentY =
                                            root.pageScrollPositions[
                                                root.currentPage
                                            ] ?? 0
                                    }
                                }


                            }
                        }
                    }
                }
            }
        }
    
        Rectangle {
            id: keyboardFocusRing

            x: root.keyboardFocusX
            y: root.keyboardFocusY
            width: root.keyboardFocusWidth
            height: root.keyboardFocusHeight
            z: 90

            visible:
                root.keyboardNavigationActive
                && root.keyboardFocusRingVisible
                && opacity > 0.01

            opacity:
                root.keyboardNavigationActive
                && root.keyboardFocusRingVisible
                    ? 1
                    : 0

            radius: Appearance.radius.control
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary

            Behavior on opacity {
                MotionAnim {
                    type: MotionAnim.FastEffects
                }
            }

            Behavior on x {
                MotionAnim {
                    type: MotionAnim.FastSpatial
                }
            }

            Behavior on y {
                MotionAnim {
                    type: MotionAnim.FastSpatial
                }
            }
        }

        Loader {
            id: settingsControlLoader
            anchors.fill: parent
            z: 100
            asynchronous: true
            property bool started: false
            active: started || appearancePageLoader.status === Loader.Error
                || (appearancePageLoader.status === Loader.Ready
                    && (root.currentPage !== 0 || root.appearanceEditor.currentTabReady || root.appearanceEditor.actionFailed))
            source: Qt.resolvedUrl("modules/nyvorel/settingsControlRail/SettingsControlSurface.qml")

            onLoaded: {
                started = true
                item.pages = Qt.binding(() => root.pages)
                item.currentPage = Qt.binding(() => root.currentPage)
            }

            Connections {
                target: settingsControlLoader.item
                function onNavigateRequested(pageIndex, label) {
                    const entry = SettingsIndex.entries.find(
                        candidate => candidate.pageIndex === pageIndex && candidate.label === label)
                    root.pendingAppearanceSearch = null
                    root.pendingSettingsGroup = entry?.settingsGroup ?? ""
                    root.pendingSearchLabel = entry?.searchLabel ?? label
                    root.searchTargetAttempts = 0
                    root.prepareSearchPage(entry)
                    root.switchToPage(pageIndex)
                    searchTargetTimer.restart()
                }
            }
        }


}
}
