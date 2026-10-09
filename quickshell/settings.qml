//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.nyvorel.settingsControlRail
import Quickshell.Hyprland

ApplicationWindow {
    id: root

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

    property bool navigationCollapsedByUser: false
    readonly property bool navigationCanExpand: width >= 880
    readonly property bool navigationExpanded:
        navigationCanExpand && !navigationCollapsedByUser
    readonly property real navigationExpandedWidth:
        width >= 1040 ? 166 : 150
    readonly property real navigationCollapsedWidth: 58
    readonly property real navigationWidth:
        navigationExpanded
            ? navigationExpandedWidth
            : navigationCollapsedWidth

    readonly property real preferredScreenMargin: 64
    readonly property real preferredWindowWidth: 1100
    readonly property real preferredWindowHeight: 750

    property bool closing: false
    property bool allowImmediateClose: false

    readonly property bool pageScrolled:
        pageLoader.item
        && pageLoader.item.contentY !== undefined
        && pageLoader.item.contentY > 1

    property var pages: [
        {
            name: Translation.tr("Quick"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            name: Translation.tr("General"),
            icon: "browse",
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            name: Translation.tr("Background"),
            icon: "texture",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Interface"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("Advanced"),
            icon: "construction",
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]

    property int currentPage: 0


    // -------------------------------------------------------------------------
    // Settings Control Rail search navigation
    // -------------------------------------------------------------------------

    property string pendingSearchLabel: ""
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
        if (!node || needle.length === 0)
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
            root.normalizedSearchText(root.pendingSearchLabel)

        if (
            needle.length === 0
            || !pageLoader.item
        ) {
            return
        }

        const target =
            root.findSearchTextNode(pageLoader.item, needle)

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

        Qt.callLater(
            () => root.highlightSearchNode(target)
        )

        root.pendingSearchLabel = ""
        root.searchTargetAttempts = 0
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

    // glass-system-v2.4-settings-ready-mask
    Region {
        id: glassSettingsReadyMask
        item: Config.ready ? settingsModalShell : null
    }
    HyprlandWindow.visibleMask:
        Config.options.appearance.transparency.enable
            ? glassSettingsReadyMask
            : null

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

        root.closing = true

        if (openAnimation.running)
            openAnimation.stop()

        closeAnimation.restart()
    }

    function switchToPage(index: int): void {
        if (index < 0 || index >= root.pages.length)
            return
        if (index === root.currentPage)
            return

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

        Qt.callLater(() => {
            frameFocus.forceActiveFocus()
            openAnimation.restart()
        })
    }

    // Keep the existing Hyprland decoration workaround. The QML shell owns
    // its visible semantic modal radius and outline.
    Timer {
        id: settingsDecorationFixTimer
        interval: 80
        repeat: false
        running: true

        onTriggered: Quickshell.execDetached([
            "bash",
            "-lc",
            "~/.local/libexec/nyvorel-settings-modal-decoration-fix-v3"
        ])
    }

    // -------------------------------------------------------------------------
    // Presentation lifecycle
    // -------------------------------------------------------------------------

    Item {
        id: frameSurface

        anchors.fill: parent
        transformOrigin: Item.Center

        // Stable visible state. Opening motion must never be required for
        // Settings to become visible.
        opacity: 1
        scale: 1
        enabled: !root.closing

        transform: Translate {
            id: frameTranslate
            y: 0
        }

        ParallelAnimation {
            id: openAnimation

            MotionAnim {
                target: frameSurface
                property: "opacity"
                from: frameSurface.opacity
                to: 1
                type: MotionAnim.DefaultEffects
            }

            MotionAnim {
                target: frameSurface
                property: "scale"
                from: frameSurface.scale
                to: 1
                type: MotionAnim.FastSpatial
            }

            MotionAnim {
                target: frameTranslate
                property: "y"
                from: frameTranslate.y
                to: 0
                type: MotionAnim.FastSpatial
            }

            onFinished: frameFocus.forceActiveFocus()
        }

        ParallelAnimation {
            id: closeAnimation

            MotionAnim {
                target: frameSurface
                property: "opacity"
                to: 0
                type: MotionAnim.FastEffects
            }

            MotionAnim {
                target: frameSurface
                property: "scale"
                to: 0.985
                type: MotionAnim.FastEffects
            }

            MotionAnim {
                target: frameTranslate
                property: "y"
                to: 6
                type: MotionAnim.FastEffects
            }

            onFinished: {
                root.allowImmediateClose = true
                root.close()
            }
        }

        Rectangle {
            id: settingsModalShell

            anchors.fill: parent

            radius: Appearance.radius.modal
            antialiasing: true
            color: Appearance.colors.colLayer0Base

            border.width: 1
            border.color:
                Appearance.fluidMode
                    ? Appearance.colors.fluidBorderStrong
                    : Appearance.colors.colLayer0Border

            // fluid-refinement-v1.2
            Behavior on radius {
                MotionAnim {
                    type: MotionAnim.DefaultEffects
                }
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
                    settingsControlSurface.open("search")
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

                spacing: 8

                // -------------------------------------------------------------
                // Fixed header
                // -------------------------------------------------------------

                Item {
                    id: titleBar

                    visible: Config.options?.windows.showTitlebar
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight:
                        Math.max(
                            40,
                            titleText.implicitHeight,
                            closeButton.implicitHeight
                        )

                    // Header title tracks the actual content pane rather than
                    // the whole window, so it remains optically centered when
                    // the sidebar is expanded.
                    Item {
                        id: headerContentRegion

                        x: navRailWrapper.width + bodyRow.spacing
                        width: Math.max(0, parent.width - x)
                        height: parent.height
                    }

                    StyledText {
                        id: titleText

                        anchors {
                            left:
                                Config.options.windows.centerTitle
                                    ? undefined
                                    : headerContentRegion.left
                            horizontalCenter:
                                Config.options.windows.centerTitle
                                    ? headerContentRegion.horizontalCenter
                                    : undefined
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                        }

                        color: Appearance.colors.colOnLayer0
                        text: Translation.tr("Settings")

                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes:
                                Appearance.font.variableAxes.title
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

                    Rectangle {
                        anchors {
                            left: headerContentRegion.left
                            right: parent.right
                            bottom: parent.bottom
                        }

                        height: 1
                        color: Appearance.colors.colLayer0Border
                        opacity: root.pageScrolled ? 1 : 0

                        Behavior on opacity {
                            MotionAnim {
                                type: MotionAnim.FastEffects
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // Fixed sidebar + scroll-owning page
                // -------------------------------------------------------------

                SettingsPageTabs {
                    id: settingsPageTabs

                    Layout.fillWidth: true
                    Layout.leftMargin:
                        navRailWrapper.width + bodyRow.spacing

                    pages: root.pages
                    currentPage: root.currentPage

                    onPageRequested:
                        index => root.switchToPage(index)
                }

                RowLayout {
                    id: bodyRow

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    SettingsControlRail {
                        id: navRailWrapper

                        Layout.fillHeight: true
                        Layout.preferredWidth: 58
                        Layout.minimumWidth: 58
                        Layout.maximumWidth: 58

                        favoriteCount:
                            settingsControlSurface.favoriteCount
                        historyCount:
                            settingsControlSurface.historyCount
                        canUndo:
                            settingsControlSurface.canUndo
                        diagnosticsOk:
                            settingsControlSurface.diagnosticsOk
                        diagnosticsWarning:
                            settingsControlSurface.diagnosticsWarning

                        onSearchRequested:
                            settingsControlSurface.open("search")

                        onFavoritesRequested:
                            settingsControlSurface.open("favorites")

                        onRecentRequested:
                            settingsControlSurface.open("recent")

                        onContextRequested:
                            settingsControlSurface.open("context")

                        onAppearanceRequested: {
                            Quickshell.execDetached([
                                "qs",
                                "-c",
                                "ii",
                                "ipc",
                                "call",
                                "appearanceStudio",
                                "open"
                            ])
                            root.requestClose()
                        }

                        onUndoRequested:
                            settingsControlSurface.undoLast()

                        onDiagnosticsRequested:
                            settingsControlSurface.open("diagnostics")

                        onConfigRequested: {
                            Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", `${Directories.config}/nyvorel/config.json`])
                        }
                    }

                    Rectangle {
                        id: contentPane

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        color: Appearance.colors.colLayer1
                        radius: Appearance.radius.card
                        border.width: 1
                        border.color:
                            Appearance.colors.colLayer0Border
                        clip: true

                        Behavior on radius {
                            MotionAnim {
                                type: MotionAnim.DefaultEffects
                            }
                        }

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

                        Loader {
                            id: pageLoader

                            anchors.fill: parent
                            opacity: 1

                            active: Config.ready

                            Component.onCompleted: {
                                source =
                                    root.pages[root.currentPage].component
                            }

                            onLoaded: {
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

                            Connections {
                                target: root

                                function onCurrentPageChanged() {
                                    if (
                                        pageLoader.item
                                        && pageLoader.item.contentY
                                            !== undefined
                                    ) {
                                        root.pageScrollPositions[
                                            root.previousPage
                                        ] = pageLoader.item.contentY
                                    }

                                    root.previousPage =
                                        root.currentPage

                                    pageSwitchAnimation.complete()
                                    pageSwitchAnimation.restart()
                                }
                            }

                            // Desktop settings navigation should feel immediate,
                            // not like a horizontally sliding mobile carousel.
                            SequentialAnimation {
                                id: pageSwitchAnimation

                                NumberAnimation {
                                    target: pageLoader
                                    property: "opacity"
                                    from: 1
                                    to: 0
                                    duration:
                                        Math.round(
                                            Appearance.animation
                                                .elementMoveFast.duration
                                            * 0.4
                                        )
                                    easing.type:
                                        Appearance.animation
                                            .elementMoveExit.type
                                    easing.bezierCurve:
                                        Appearance.animation
                                            .elementMoveExit.bezierCurve
                                }

                                PropertyAction {
                                    target: pageLoader
                                    property: "source"
                                    value:
                                        root.pages[
                                            root.currentPage
                                        ].component
                                }

                                NumberAnimation {
                                    target: pageLoader
                                    property: "opacity"
                                    from: 0
                                    to: 1
                                    duration:
                                        Math.round(
                                            Appearance.animation
                                                .elementMoveFast.duration
                                            * 0.55
                                        )
                                    easing.type:
                                        Appearance.animation
                                            .elementMoveEnter.type
                                    easing.bezierCurve:
                                        Appearance.animation
                                            .elementMoveEnter.bezierCurve
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

        SettingsControlSurface {
            id: settingsControlSurface

            anchors.fill: parent
            z: 100

            pages: root.pages
            currentPage: root.currentPage

            helperPath:
                `${Directories.config}/quickshell/nyvorel/scripts/settings-control/settings_control.py`

            onNavigateRequested: (pageIndex, label) => {
                root.pendingSearchLabel = label
                root.searchTargetAttempts = 0
                root.switchToPage(pageIndex)
                searchTargetTimer.restart()
            }
        }

}
}
