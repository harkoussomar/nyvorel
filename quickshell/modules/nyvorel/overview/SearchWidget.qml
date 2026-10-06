pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions


Item {
    id: root


    readonly property string xdgConfigHome:
        Directories.config


    readonly property int typingDebounceInterval:
        160


    readonly property int typingResultLimit:
        12


    property string searchingText:
        LauncherSearch.query

    // SEARCH-CLIPBOARD-V2
    property string selectedResultKey: ""


    readonly property bool showResults:
        root.searchingText !== ""


    // OVERVIEW-UI-PRIORITY-V2.4
    // Keep all global modes on one row on the 1920×1080 desktop while
    // preserving the compact command-palette character.
    readonly property real paletteWidth:
        Math.min(
            740,
            Math.max(
                700,
                Appearance.sizes.searchWidth + 260
            )
        )


    readonly property var prefixList: [
        Config.options.search.prefix.action,
        Config.options.search.prefix.app,
        Config.options.search.prefix.clipboard,
        Config.options.search.prefix.emojis,
        Config.options.search.prefix.math,
        Config.options.search.prefix.shellCommand,
        Config.options.search.prefix.webSearch
    ]


    implicitWidth:
        searchWidgetContent.implicitWidth
        + Appearance.sizes.elevationMargin * 2


    implicitHeight:
        searchWidgetContent.implicitHeight
        + Appearance.sizes.elevationMargin * 2


    // ============================================================
    // Search control
    // ============================================================

    function focusFirstItem() {
        if (appResults.count > 0)
            appResults.currentIndex = 0
    }


    function focusSearchInput() {
        searchBar.forceFocus()
    }


    function disableExpandAnimation() {
        // Kept for API compatibility with Overview.qml.
        searchBar.animateWidth = false
    }


    function cancelSearch() {
        searchBar.searchInput.selectAll()

        LauncherSearch.query = ""

        searchBar.searchInput.text = ""

        searchBar.animateWidth = true
    }


    function setSearchingText(text) {
        searchBar.searchInput.text =
            text

        searchBar.searchInput.cursorPosition =
            text.length

        LauncherSearch.query =
            text
    }


    function currentPrefix() {
        return LauncherSearch.prefixForMode(
            LauncherSearch.mode
        )
    }


    function setMode(prefix) {
        LauncherSearch.setModeFromPrefix(prefix)

        root.setSearchingText(
            LauncherSearch.query
        )

        root.focusSearchInput()
        root.selectedResultKey = ""
        root.focusFirstItem()
    }


    function applyResultModel(resetSelection = false) {
        const previousKey =
            resetSelection
                ? ""
                : root.selectedResultKey

        const nextValues =
            (LauncherSearch.results ?? [])
                .slice(0, root.typingResultLimit)

        resultModel.values = nextValues

        let nextIndex = -1

        if (previousKey.length > 0) {
            nextIndex =
                nextValues.findIndex(
                    entry =>
                        (
                            entry
                            && entry.key
                                ? entry.key
                                : ""
                        )
                        === previousKey
                )
        }

        if (nextIndex < 0 && nextValues.length > 0)
            nextIndex = 0

        appResults.currentIndex = nextIndex

        root.selectedResultKey =
            nextIndex >= 0
                ? (
                    nextValues[nextIndex]
                    && nextValues[nextIndex].key
                        ? nextValues[nextIndex].key
                        : ""
                )
                : ""
    }


    // ============================================================
    // Keyboard input
    // ============================================================

    Keys.onPressed: event => {
        if (
            event.key === Qt.Key_Escape
        ) {
            return
        }


        if (
            event.key === Qt.Key_Backspace
        ) {
            if (
                !searchBar.searchInput.activeFocus
            ) {
                root.focusSearchInput()


                if (
                    event.modifiers
                    & Qt.ControlModifier
                ) {
                    let text =
                        searchBar.searchInput.text

                    let pos =
                        searchBar.searchInput.cursorPosition


                    if (pos > 0) {
                        const left =
                            text.slice(
                                0,
                                pos
                            )

                        const match =
                            left.match(
                                /(\s*\S+)\s*$/
                            )

                        const deleteLen =
                            match
                                ? match[0].length
                                : 1


                        searchBar.searchInput.text =
                            text.slice(
                                0,
                                pos - deleteLen
                            )
                            + text.slice(pos)


                        searchBar.searchInput.cursorPosition =
                            pos - deleteLen
                    }
                } else {
                    if (
                        searchBar.searchInput.cursorPosition
                        > 0
                    ) {
                        const pos =
                            searchBar.searchInput.cursorPosition

                        const text =
                            searchBar.searchInput.text


                        searchBar.searchInput.text =
                            text.slice(
                                0,
                                pos - 1
                            )
                            + text.slice(pos)


                        searchBar.searchInput.cursorPosition =
                            pos - 1
                    }
                }


                searchBar.searchInput.cursorPosition =
                    searchBar.searchInput.text.length


                event.accepted =
                    true
            }

            return
        }


        if (
            event.text
            && event.text.length === 1
            && event.key !== Qt.Key_Enter
            && event.key !== Qt.Key_Return
            && event.key !== Qt.Key_Delete
            && event.text.charCodeAt(0) >= 0x20
        ) {
            if (
                !searchBar.searchInput.activeFocus
            ) {
                root.focusSearchInput()


                const pos =
                    searchBar.searchInput.cursorPosition

                const text =
                    searchBar.searchInput.text


                searchBar.searchInput.text =
                    text.slice(0, pos)
                    + event.text
                    + text.slice(pos)


                searchBar.searchInput.cursorPosition =
                    pos + 1


                event.accepted =
                    true


                root.focusFirstItem()
            }
        }
    }


    // ============================================================
    // Mode chip
    // ============================================================

    component ModeChip: Rectangle {
        id: modeChip


        required property string label
        required property string icon
        required property string prefix


        readonly property bool active:
            root.currentPrefix()
                === modeChip.prefix


        implicitWidth:
            chipContent.implicitWidth + 18

        implicitHeight:
            29


        radius:
            Appearance.inlayMode
                ? 0
                : height / 2


        color:
            Appearance.inlayMode
                ? (
                    modeChip.active
                        ? Appearance.inlay.insetFill
                        : chipMouse.containsMouse
                            ? Appearance.colors.colLayer2Hover
                            : "transparent"
                  )
                : modeChip.active
                    ? Appearance.colors.colSecondaryContainer
                    : chipMouse.containsMouse
                        ? Appearance.colors.colLayer2Hover
                        : Appearance.colors.colLayer1


        // Stronger selected-state hierarchy.
        border.width:
            Appearance.inlayMode
                ? Appearance.inlay.borderWidth
                : (modeChip.active ? 1 : 0)

        border.color:
            Appearance.inlayMode
                ? (modeChip.active
                    ? Appearance.colors.colPrimary
                    : Appearance.inlay.borderControl)
                : modeChip.active
                    ? Appearance.colors.colSecondary
                    : "transparent"


        Behavior on color {
            animation:
                Appearance.animation.elementMoveFast
                    .colorAnimation
                    .createObject(this)
        }


        Row {
            id: chipContent

            anchors.centerIn:
                parent

            spacing:
                5


            MaterialSymbol {
                anchors.verticalCenter:
                    parent.verticalCenter

                text:
                    modeChip.icon

                iconSize:
                    15

                color:
                    modeChip.active
                        ? Appearance.m3colors.m3onSecondaryContainer
                        : Appearance.colors.colSubtext
            }


            StyledText {
                anchors.verticalCenter:
                    parent.verticalCenter

                text:
                    modeChip.label

                font {
                    pixelSize:
                        Appearance.font.pixelSize.smaller

                    weight:
                        modeChip.active
                            ? Font.DemiBold
                            : Font.Normal
                }

                color:
                    modeChip.active
                        ? Appearance.m3colors.m3onSecondaryContainer
                        : Appearance.colors.colOnLayer1
            }
        }


        MouseArea {
            id: chipMouse

            anchors.fill:
                parent

            hoverEnabled:
                true

            cursorShape:
                Qt.PointingHandCursor


            onClicked:
                root.setMode(
                    modeChip.prefix
                )
        }
    }


    // ============================================================
    // Clipboard sub-filter chip
    // ============================================================

    component ClipboardFilterChip: Rectangle {
        id: filterChip

        required property string label
        required property string icon
        required property string filterName

        readonly property bool active:
            LauncherSearch.clipboardFilter
            === filterChip.filterName

        implicitWidth:
            filterContent.implicitWidth + 18

        implicitHeight:
            27

        radius:
            Appearance.inlayMode
                ? 0
                : height / 2

        color:
            Appearance.inlayMode
                ? (
                    filterChip.active
                        ? Appearance.inlay.insetFill
                        : filterMouse.containsMouse
                            ? Appearance.colors.colLayer2Hover
                            : "transparent"
                  )
                : filterChip.active
                    ? Appearance.colors.colPrimaryContainer
                    : filterMouse.containsMouse
                        ? Appearance.colors.colLayer2Hover
                        : Appearance.colors.colLayer1

        border.width:
            Appearance.inlayMode
                ? Appearance.inlay.borderWidth
                : (filterChip.active ? 1 : 0)

        border.color:
            Appearance.inlayMode
                ? (filterChip.active
                    ? Appearance.colors.colPrimary
                    : Appearance.inlay.borderControl)
                : filterChip.active
                    ? Appearance.colors.colPrimary
                    : "transparent"

        Row {
            id: filterContent
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: filterChip.icon
                iconSize: 14
                color:
                    filterChip.active
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: filterChip.label
                font {
                    pixelSize:
                        Appearance.font.pixelSize.smaller
                    weight:
                        filterChip.active
                            ? Font.DemiBold
                            : Font.Normal
                }
                color:
                    filterChip.active
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer1
            }
        }

        MouseArea {
            id: filterMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                LauncherSearch.setClipboardFilter(
                    filterChip.filterName
                )
                root.focusSearchInput()
            }
        }
    }


    // ============================================================
    // Surface
    // ============================================================

    StyledRectangularShadow {
        visible:
            !Appearance.prismMode && !Appearance.inlayMode

        target:
            searchWidgetContent
    }

    // prism-v2-phase5: search is the focused command surface above overview.
    PrismSurface {
        visible:
            Appearance.prismMode

        anchors.fill:
            searchWidgetContent

        depth:
            Appearance.prism.depthModal

        surfaceRadius:
            Appearance.prism.radiusModal

        elevated:
            true

        borderWidth:
            1
    }


    Rectangle {
        id: searchWidgetContent


        anchors {
            top:
                parent.top

            horizontalCenter:
                parent.horizontalCenter

            topMargin:
                Appearance.sizes.elevationMargin
        }


        clip:
            true


        implicitWidth:
            root.paletteWidth


        implicitHeight:
            columnLayout.implicitHeight


        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusModal
                    : Appearance.rounding.large


        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.inlayMode
                    ? Appearance.inlay.surfaceFill
                    : Appearance.colors.colBackgroundSurfaceContainer

        border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
        border.color: Appearance.inlayMode ? Appearance.inlay.borderControl : "transparent"


        Behavior on implicitHeight {
            enabled:
                GlobalStates.overviewOpen

            animation:
                Appearance.animation.elementMove
                    .numberAnimation
                    .createObject(this)
        }


        ColumnLayout {
            id: columnLayout


            width:
                parent.width


            spacing:
                0


            // ====================================================
            // Search bar
            // ====================================================

            SearchBar {
                id: searchBar


                property real verticalPadding:
                    5


                Layout.fillWidth:
                    true

                Layout.leftMargin:
                    8

                Layout.rightMargin:
                    8

                Layout.topMargin:
                    verticalPadding

                Layout.bottomMargin:
                    verticalPadding


                Synchronizer on searchingText {
                    property alias source:
                        root.searchingText
                }
            }


            // ====================================================
            // Search modes
            //
            // Prefixes remain available for keyboard users, but are
            // now also discoverable in the UI.
            // ====================================================

            Item {
                visible:
                    GlobalStates.overviewOpen

                Layout.fillWidth:
                    true

                implicitHeight:
                    Math.max(
                        38,
                        modeFlow.implicitHeight + 10
                    )


                Flow {
                    id: modeFlow

                    anchors {
                        left:
                            parent.left

                        right:
                            parent.right

                        top:
                            parent.top

                        leftMargin:
                            10

                        rightMargin:
                            10

                        topMargin:
                            5
                    }

                    spacing:
                        6


                    ModeChip {
                        label:
                            "All"

                        icon:
                            "search"

                        prefix:
                            ""
                    }


                    ModeChip {
                        label:
                            "Apps"

                        icon:
                            "apps"

                        prefix:
                            Config.options.search.prefix.app
                    }


                    ModeChip {
                        label:
                            "Clipboard"

                        icon:
                            "content_paste"

                        prefix:
                            Config.options.search.prefix.clipboard
                    }


                    ModeChip {
                        label:
                            "Actions"

                        icon:
                            "bolt"

                        prefix:
                            Config.options.search.prefix.action
                    }


                    ModeChip {
                        label:
                            "Emoji"

                        icon:
                            "emoji_emotions"

                        prefix:
                            Config.options.search.prefix.emojis
                    }


                    ModeChip {
                        label:
                            "Math"

                        icon:
                            "calculate"

                        prefix:
                            Config.options.search.prefix.math
                    }


                    ModeChip {
                        label:
                            "Web"

                        icon:
                            "travel_explore"

                        prefix:
                            Config.options.search.prefix.webSearch
                    }


                    ModeChip {
                        label:
                            "Shell"

                        icon:
                            "terminal"

                        prefix:
                            Config.options.search.prefix.shellCommand
                    }
                }
            }


            // CLIPBOARD-FILTERS-V2.2
            Item {
                visible:
                    LauncherSearch.mode
                    === "clipboard"

                Layout.fillWidth:
                    true

                implicitHeight:
                    visible ? 35 : 0

                Row {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                    }

                    spacing: 6

                    ClipboardFilterChip {
                        label: "All"
                        icon: "select_all"
                        filterName: "all"
                    }

                    ClipboardFilterChip {
                        label: "Text"
                        icon: "notes"
                        filterName: "text"
                    }

                    ClipboardFilterChip {
                        label: "Images"
                        icon: "image"
                        filterName: "image"
                    }

                    ClipboardFilterChip {
                        label: "Links"
                        icon: "link"
                        filterName: "link"
                    }
                }
            }


            // ====================================================
            // Separator
            // ====================================================

            Rectangle {
                visible:
                    root.showResults

                Layout.fillWidth:
                    true

                height:
                    1

                color:
                    Appearance.colors.colOutlineVariant
            }


            // ====================================================
            // Results
            // ====================================================

            ListView {
                id: appResults


                visible:
                    root.showResults


                Layout.fillWidth:
                    true


                implicitHeight:
                    Math.min(
                        520,
                        appResults.contentHeight
                        + topMargin
                        + bottomMargin
                    )


                clip:
                    true


                topMargin:
                    8

                bottomMargin:
                    8

                spacing:
                    2


                boundsBehavior:
                    Flickable.StopAtBounds


                KeyNavigation.up:
                    searchBar


                highlightMoveDuration:
                    90


                ScrollBar.vertical:
                    ScrollBar {
                        policy:
                            ScrollBar.AsNeeded
                    }


                onFocusChanged: {
                    if (
                        focus
                        && appResults.count > 0
                    ) {
                        appResults.currentIndex = 0
                    }
                }


                onCurrentIndexChanged: {
                    const current =
                        appResults.currentItem

                    root.selectedResultKey =
                        current
                        && current.modelData
                        && current.modelData.key
                            ? current.modelData.key
                            : ""
                }


                Connections {
                    target:
                        root


                    function onSearchingTextChanged() {
                        root.selectedResultKey = ""
                    }
                }


                Connections {
                    target:
                        LauncherSearch


                    function onResultsChanged() {
                        root.applyResultModel(false)
                    }
                }


                // SEARCH-CLIPBOARD-V2.1-FINAL-REPAIR
                model:
                    ScriptModel {
                        id: resultModel

                        objectProp:
                            "key"
                    }


                delegate:
                    SearchItem {
                        id: searchItem


                        required property var modelData


                        anchors.left:
                            parent?.left

                        anchors.right:
                            parent?.right


                        entry:
                            modelData


                        query:
                            StringUtils.cleanOnePrefix(
                                root.searchingText,
                                root.prefixList
                            )


                        Keys.onPressed: event => {
                            if (
                                event.key !== Qt.Key_Tab
                            ) {
                                return
                            }


                            if (
                                LauncherSearch.results.length
                                === 0
                            ) {
                                return
                            }


                            const tabbedText =
                                searchItem.modelData.name


                            LauncherSearch.completeText(
                                tabbedText
                            )


                            searchBar.searchInput.text =
                                LauncherSearch.query


                            searchBar.searchInput.cursorPosition =
                                tabbedText.length


                            event.accepted =
                                true


                            root.focusSearchInput()
                        }
                    }
            }
        }
    }
}