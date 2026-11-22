pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

FocusScope {
    id: root

    property real availableWidth: 720
    property real availableHeight: 680
    property bool attachedToBar: false
    readonly property string searchingText: searchBar.searchInput.text
    readonly property bool emojiMode: LauncherSearch.mode === "emoji"
    readonly property var activeView: emojiMode ? emojiResults : appResults
    property var resultValues: []
    property string selectedResultKey: ""
    property bool navigatingEmoji: false
    property bool selectionMoved: false
    // Use the Workbench side-pane tint over the actual bar surface.
    readonly property color resultsBackground: attachedToBar
        ? ColorUtils.transparentize(Appearance.m3colors.m3background, 0.78)
        : ColorUtils.applyAlpha(Appearance.m3colors.m3surfaceContainer, 1)
    readonly property color surfaceOutline: attachedToBar
        ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.86)
        : Appearance.m3colors.m3outlineVariant
    readonly property color resultHighlight: attachedToBar
        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
        : ColorUtils.mix(resultsBackground, Appearance.colors.colPrimary, 0.78)
    readonly property color resultOutline: attachedToBar
        ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.66)
        : ColorUtils.mix(resultsBackground, Appearance.colors.colPrimary, 0.40)
    readonly property color resultHover: attachedToBar
        ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.93)
        : ColorUtils.mix(resultsBackground, Appearance.m3colors.m3onSurface, 0.91)

    implicitWidth: Math.min(720, Math.max(1, availableWidth - 32))
    implicitHeight: content.implicitHeight + 16
    focus: true

    function focusFirstItem() {
        selectIndex(0, false)
    }

    function focusSearchInput() {
        searchBar.forceFocus()
    }

    function cancelSearch() {
        setSearchingText("")
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text
        searchBar.searchInput.cursorPosition = text.length
        LauncherSearch.query = text
    }

    function selectIndex(index, scroll) {
        const count = resultValues.length
        const next = count ? Math.min(Math.max(index, 0), count - 1) : -1
        activeView.currentIndex = next
        selectedResultKey = resultValues[next]?.key ?? ""
        if (scroll && next >= 0)
            activeView.positionViewAtIndex(next, ListView.Contain)
    }

    function syncResults() {
        // A refresh of the same query (clipboard update, math answer, etc.)
        // should preserve the user's selection by identity.
        const previous = selectionMoved ? selectedResultKey : ""
        resultValues = LauncherSearch.results
        const index = previous ? resultValues.findIndex(entry => entry.key === previous) : -1
        selectIndex(index === -1 ? 0 : index, index !== -1)
    }

    function activate(index) {
        const entry = resultValues[index]
        if (!entry)
            return
        GlobalStates.overviewOpen = false
        entry.execute()
    }

    function handleKey(event) {
        const count = resultValues.length
        if (!count)
            return
        const index = activeView.currentIndex
        const rowSize = emojiMode ? emojiResults.columns : 1
        const pageRows = Math.max(1, Math.floor(activeView.height / (emojiMode ? emojiResults.cellHeight : 52)) - 1)
        let next = index
        if (event.key === Qt.Key_Down)
            next = index + rowSize
        else if (event.key === Qt.Key_Up)
            next = index - rowSize
        else if (event.key === Qt.Key_PageDown)
            next = index + rowSize * pageRows
        else if (event.key === Qt.Key_PageUp)
            next = index - rowSize * pageRows
        else if (emojiMode && (navigatingEmoji || !LauncherSearch.queryText)
                && event.modifiers === Qt.NoModifier && (event.key === Qt.Key_Left || event.key === Qt.Key_Right))
            next = index + (event.key === Qt.Key_Right ? 1 : -1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true
            activate(index)
            return
        } else if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier
                && LauncherSearch.mode === "clipboard") {
            event.accepted = true
            const raw = resultValues[index]?.rawValue
            if (raw)
                Cliphist.deleteEntry(raw)
            return
        } else {
            return
        }
        event.accepted = true
        navigatingEmoji = emojiMode
        selectionMoved = true
        selectIndex(next, true)
    }

    onSearchingTextChanged: {
        selectedResultKey = ""
        navigatingEmoji = false
        selectionMoved = false
        LauncherSearch.query = searchingText
    }

    onVisibleChanged: {
        if (visible)
            Qt.callLater(focusSearchInput)
    }

    Connections {
        target: LauncherSearch
        function onResultsChanged() { root.syncResults() }
        function onQueryChanged() {
            if (root.searchingText !== LauncherSearch.query)
                root.setSearchingText(LauncherSearch.query)
        }
    }

    Component.onCompleted: {
        setSearchingText(LauncherSearch.query)
        syncResults()
    }

    Column {
        id: content

        width: parent.width
        y: 12
        spacing: 6

        SearchBar {
            id: searchBar

            width: content.width
            surfaceColor: root.resultsBackground
            hoverColor: root.resultHover
            activeColor: root.resultHighlight
            activeOutline: root.resultOutline
            outline: root.surfaceOutline
            onInputKeyPressed: event => root.handleKey(event)
        }

        Rectangle {
            id: resultSurface

            visible: root.searchingText.length > 0
            width: content.width
            height: Math.min(Math.max(64, root.availableHeight - 100), Math.min(540,
                root.resultValues.length === 0 ? 48 : root.activeView.contentHeight + 12))
            radius: Appearance.radius.card
            color: root.resultsBackground
            border.color: root.surfaceOutline

            StyledText {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                visible: root.resultValues.length === 0
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                color: Appearance.colors.colSubtext
                text: LauncherSearch.emptyMessage
            }

            ListView {
                id: appResults

                anchors.fill: parent
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                visible: !root.emojiMode && count > 0
                model: root.emojiMode ? null : root.resultValues
                clip: true
                spacing: 1
                cacheBuffer: 120
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                keyNavigationWraps: false
                highlightMoveDuration: 0

                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AsNeeded
                }

                delegate: SearchItem {
                    required property var modelData

                    width: appResults.width - 6
                    focusPolicy: Qt.NoFocus
                    entry: modelData
                    query: LauncherSearch.queryText
                    selectionFill: root.resultHighlight
                    selectionBorder: root.resultOutline
                    hoverFill: root.resultHover
                }
            }

            GridView {
                id: emojiResults

                property int columns: Math.max(1, Math.floor(width / 54))

                anchors.fill: parent
                anchors.margins: 6
                visible: root.emojiMode && count > 0
                model: root.emojiMode ? root.resultValues : null
                cellWidth: width / columns
                cellHeight: 50
                clip: true
                cacheBuffer: 120
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                keyNavigationWraps: false

                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AsNeeded
                }

                delegate: Item {
                    id: cell

                    required property int index
                    required property var modelData
                    readonly property bool selected: GridView.isCurrentItem

                    width: emojiResults.cellWidth
                    height: emojiResults.cellHeight

                    RippleButton {
                        id: glyphButton

                        anchors.fill: parent
                        anchors.margins: 2
                        focusPolicy: Qt.NoFocus
                        buttonRadius: Appearance.radius.control
                        toggled: cell.selected
                        colBackgroundHover: root.resultHover
                        colBackgroundToggled: "transparent"
                        colBackgroundToggledHover: "transparent"
                        colRippleToggled: root.resultOutline
                        Accessible.name: cell.modelData.name
                        Accessible.description: Translation.tr("Copy emoji")
                        onClicked: root.activate(cell.index)

                        contentItem: StyledText {
                            text: cell.modelData.iconName
                            font.pixelSize: 25
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Rectangle {
                        anchors.fill: glyphButton
                        z: -1
                        radius: glyphButton.buttonRadius
                        visible: cell.selected
                        color: root.resultHighlight
                        border.color: root.resultOutline
                    }
                }
            }
        }
    }
}
