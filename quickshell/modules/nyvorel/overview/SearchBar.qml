pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions


RowLayout {
    id: root

    spacing: 7

    property bool animateWidth: false
    property alias searchInput: searchInput
    property string searchingText


    function forceFocus() {
        searchInput.forceActiveFocus()
    }


    enum SearchPrefixType {
        Action,
        App,
        Clipboard,
        Emojis,
        Math,
        ShellCommand,
        WebSearch,
        DefaultSearch
    }


    // SEARCH-CLIPBOARD-V2
    readonly property int searchPrefixType: {
        switch (LauncherSearch.mode) {
        case "action":
            return SearchBar.SearchPrefixType.Action
        case "app":
            return SearchBar.SearchPrefixType.App
        case "clipboard":
            return SearchBar.SearchPrefixType.Clipboard
        case "emoji":
            return SearchBar.SearchPrefixType.Emojis
        case "math":
            return SearchBar.SearchPrefixType.Math
        case "shell":
            return SearchBar.SearchPrefixType.ShellCommand
        case "web":
            return SearchBar.SearchPrefixType.WebSearch
        default:
            return SearchBar.SearchPrefixType.DefaultSearch
        }
    }


    readonly property string modeIcon: {
        switch (root.searchPrefixType) {
        case SearchBar.SearchPrefixType.Action:
            return "settings_suggest"

        case SearchBar.SearchPrefixType.App:
            return "apps"

        case SearchBar.SearchPrefixType.Clipboard:
            return "content_paste"

        case SearchBar.SearchPrefixType.Emojis:
            return "add_reaction"

        case SearchBar.SearchPrefixType.Math:
            return "calculate"

        case SearchBar.SearchPrefixType.ShellCommand:
            return "terminal"

        case SearchBar.SearchPrefixType.WebSearch:
            return "travel_explore"

        default:
            return "search"
        }
    }


    readonly property string modeLabel: {
        switch (root.searchPrefixType) {
        case SearchBar.SearchPrefixType.Action:
            return "Actions"

        case SearchBar.SearchPrefixType.App:
            return "Apps"

        case SearchBar.SearchPrefixType.Clipboard:
            return "Clipboard"

        case SearchBar.SearchPrefixType.Emojis:
            return "Emoji"

        case SearchBar.SearchPrefixType.Math:
            return "Math"

        case SearchBar.SearchPrefixType.ShellCommand:
            return "Shell"

        case SearchBar.SearchPrefixType.WebSearch:
            return "Web"

        default:
            return "Search"
        }
    }


    readonly property string modePlaceholder: {
        switch (root.searchPrefixType) {
        case SearchBar.SearchPrefixType.Action:
            return "Search actions…"

        case SearchBar.SearchPrefixType.App:
            return "Search applications…"

        case SearchBar.SearchPrefixType.Clipboard:
            return "Search clipboard history…"

        case SearchBar.SearchPrefixType.Emojis:
            return "Search emojis…"

        case SearchBar.SearchPrefixType.Math:
            return "Calculate…"

        case SearchBar.SearchPrefixType.ShellCommand:
            return "Run a shell command…"

        case SearchBar.SearchPrefixType.WebSearch:
            return "Search the web…"

        default:
            return "Search apps, commands or the web…"
        }
    }


    // ============================================================
    // Current mode
    //
    // Fixed width deliberately keeps the overall palette geometry
    // stable when switching between modes.
    // ============================================================

    Rectangle {
        Layout.alignment:
            Qt.AlignVCenter

        Layout.preferredWidth:
            108

        implicitHeight:
            40

        radius:
            Appearance.inlayMode
                ? 0
                : height / 2


        color:
            Appearance.inlayMode
                ? (
                    root.searchPrefixType
                        === SearchBar.SearchPrefixType.DefaultSearch
                            ? "transparent"
                            : Appearance.inlay.insetFill
                  )
                : root.searchPrefixType
                    === SearchBar.SearchPrefixType.DefaultSearch
                        ? Appearance.colors.colSurfaceContainerHigh
                        : Appearance.colors.colSecondaryContainer

        border.width:
            Appearance.inlayMode
                ? Appearance.inlay.borderWidth
                : 0

        border.color:
            Appearance.inlayMode
                ? (
                    root.searchPrefixType
                        === SearchBar.SearchPrefixType.DefaultSearch
                            ? Appearance.inlay.borderControl
                            : Appearance.colors.colPrimary
                  )
                : "transparent"


        Behavior on color {
            animation:
                Appearance.animation.elementMoveFast
                    .colorAnimation
                    .createObject(this)
        }


        Row {
            anchors.centerIn:
                parent

            spacing:
                6


            MaterialSymbol {
                anchors.verticalCenter:
                    parent.verticalCenter

                text:
                    root.modeIcon

                iconSize:
                    18

                color:
                    root.searchPrefixType
                        === SearchBar.SearchPrefixType.DefaultSearch
                            ? Appearance.colors.colOnSurfaceVariant
                            : Appearance.m3colors.m3onSecondaryContainer
            }


            StyledText {
                anchors.verticalCenter:
                    parent.verticalCenter

                text:
                    root.modeLabel

                font {
                    pixelSize:
                        Appearance.font.pixelSize.smaller

                    weight:
                        Font.DemiBold
                }

                color:
                    root.searchPrefixType
                        === SearchBar.SearchPrefixType.DefaultSearch
                            ? Appearance.colors.colOnSurfaceVariant
                            : Appearance.m3colors.m3onSecondaryContainer
            }
        }
    }


    // ============================================================
    // Search input
    // ============================================================

    ToolbarTextField {
        id: searchInput

        Layout.fillWidth:
            true

        Layout.topMargin:
            4

        Layout.bottomMargin:
            4


        implicitHeight:
            40


        focus:
            GlobalStates.overviewOpen


        font.pixelSize:
            Appearance.font.pixelSize.small


        placeholderText:
            root.modePlaceholder


        onTextChanged:
            LauncherSearch.query = text


        onAccepted: {
            if (appResults.count <= 0)
                return

            const firstItem =
                appResults.itemAtIndex(0)

            if (
                firstItem
                && firstItem.clicked
            ) {
                firstItem.clicked()
            }
        }


        Keys.onPressed: event => {
            if (event.key !== Qt.Key_Tab)
                return

            if (
                LauncherSearch.results.length
                === 0
            ) {
                return
            }


            const tabbedText =
                LauncherSearch.results[0].name


            LauncherSearch.completeText(
                tabbedText
            )

            searchInput.text =
                LauncherSearch.query

            searchInput.cursorPosition =
                searchInput.text.length


            event.accepted =
                true
        }
    }


    // ============================================================
    // Image search
    // ============================================================

    IconToolbarButton {
        Layout.topMargin:
            4

        Layout.bottomMargin:
            4


        implicitWidth:
            36

        implicitHeight:
            36


        onClicked: {
            GlobalStates.overviewOpen =
                false

            Quickshell.execDetached([
                "qs",
                "-p",
                Quickshell.shellPath(""),
                "ipc",
                "call",
                "region",
                "search"
            ])
        }


        text:
            "image_search"


        StyledToolTip {
            text:
                Translation.tr("Google Lens")
        }
    }


    // ============================================================
    // Music recognition
    // ============================================================

    IconToolbarButton {
        id: songRecButton

        Layout.topMargin:
            4

        Layout.bottomMargin:
            4

        Layout.rightMargin:
            2


        implicitWidth:
            36

        implicitHeight:
            36


        toggled:
            SongRec.running


        onClicked:
            SongRec.toggleRunning()


        text:
            "music_cast"


        StyledToolTip {
            text:
                Translation.tr("Recognize music")
        }


        colText:
            toggled
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnSurfaceVariant


        background:
            MaterialShape {
                RotationAnimation on rotation {
                    running:
                        songRecButton.toggled

                    duration:
                        12000

                    easing.type:
                        Easing.Linear

                    loops:
                        Animation.Infinite

                    from:
                        0

                    to:
                        360
                }


                shape:
                    songRecButton.toggled
                        ? MaterialShape.Shape.SoftBurst
                        : MaterialShape.Shape.Circle


                color: {
                    if (songRecButton.toggled) {
                        return songRecButton.hovered
                            ? Appearance.colors.colPrimaryHover
                            : Appearance.colors.colPrimary
                    }

                    return songRecButton.hovered
                        ? Appearance.colors.colSurfaceContainerHigh
                        : ColorUtils.transparentize(
                            Appearance.colors.colSurfaceContainerHigh
                        )
                }


                Behavior on color {
                    animation:
                        Appearance.animation.elementMoveFast
                            .colorAnimation
                            .createObject(this)
                }
            }
    }
}