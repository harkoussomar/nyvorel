pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RowLayout {
    id: root

    property alias searchInput: input
    required property color surfaceColor
    required property color hoverColor
    required property color activeColor
    required property color activeOutline
    property color outline: Appearance.m3colors.m3outlineVariant
    readonly property color focusOutline: Appearance.colors.colPrimary
    signal inputKeyPressed(var event)

    spacing: 7

    function forceFocus() {
        input.forceActiveFocus()
    }

    function openLens() {
        GlobalStates.overviewOpen = false
        GlobalStates.superReleaseMightTrigger = false
        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"])
    }

    Shortcut {
        sequence: "Alt+L"
        enabled: root.visible
        onActivated: root.openLens()
    }

    Shortcut {
        sequence: "Alt+M"
        enabled: root.visible
        onActivated: SongRec.toggleRunning()
    }

    Controls.TextField {
        id: input

        Layout.fillWidth: true
        Layout.preferredHeight: 48
        leftPadding: 16
        rightPadding: 16
        selectByMouse: true
        color: Appearance.m3colors.m3onSurface
        placeholderTextColor: Appearance.m3colors.m3onSurfaceVariant
        selectionColor: root.activeColor
        selectedTextColor: color
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.normal
        Accessible.name: Translation.tr("Search")
        placeholderText: {
            switch (LauncherSearch.mode) {
            case "clipboard": return Translation.tr("Search clipboard history…")
            case "emoji": return Translation.tr("Find an emoji…")
            case "app": return Translation.tr("Find an application…")
            case "action": return Translation.tr("Find an action…")
            case "math": return Translation.tr("Enter a calculation…")
            case "shell": return Translation.tr("Enter a shell command…")
            case "web": return Translation.tr("Search the web…")
            default: return Translation.tr("Find apps, actions, and answers…")
            }
        }

        Keys.onPressed: event => root.inputKeyPressed(event)

        background: Rectangle {
            radius: Appearance.radius.control
            color: root.surfaceColor
            border.color: input.activeFocus ? root.focusOutline : root.outline
        }
    }

    IconToolbarButton {
        id: lensButton

        Layout.preferredWidth: 44
        Layout.preferredHeight: 48
        buttonRadius: Appearance.radius.control
        rippleEnabled: false
        colText: Appearance.m3colors.m3onSurface
        readonly property string label: Translation.tr("Search a screen region with Google Lens")
        text: "image_search"
        Accessible.name: label
        onClicked: root.openLens()

        background: Rectangle {
            radius: lensButton.buttonRadius
            color: lensButton.down ? root.activeColor : lensButton.hovered ? root.hoverColor : root.surfaceColor
            border.width: lensButton.visualFocus ? 2 : 1
            border.color: lensButton.visualFocus ? root.focusOutline : root.outline
        }

        StyledToolTip { text: lensButton.label + " · Alt+L" }
    }

    IconToolbarButton {
        id: musicButton

        Layout.preferredWidth: 44
        Layout.preferredHeight: 48
        buttonRadius: Appearance.radius.control
        rippleEnabled: false
        colText: Appearance.m3colors.m3onSurface
        readonly property string label: SongRec.running ? Translation.tr("Stop music recognition") : Translation.tr("Recognize music")
        text: SongRec.running ? "stop_circle" : "music_note"
        toggled: SongRec.running
        Accessible.name: label
        onClicked: {
            SongRec.toggleRunning()
            root.forceFocus()
        }

        background: Rectangle {
            radius: musicButton.buttonRadius
            color: musicButton.toggled || musicButton.down ? root.activeColor
                : musicButton.hovered ? root.hoverColor : root.surfaceColor
            border.width: musicButton.visualFocus ? 2 : 1
            border.color: musicButton.visualFocus ? root.focusOutline
                : musicButton.toggled ? root.activeOutline : root.outline
        }

        StyledToolTip { text: musicButton.label + " · Alt+M" }
    }
}
