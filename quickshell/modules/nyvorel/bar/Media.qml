import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root
    property bool vertical: false

    readonly property var playablePlayers: MprisController.players.filter(player =>
        player && player.trackTitle
            && player.playbackState !== MprisPlaybackState.Stopped)
    readonly property MprisPlayer activePlayer:
        MprisController.activePlayer
            && MprisController.activePlayer.playbackState !== MprisPlaybackState.Stopped
            ? MprisController.activePlayer : (playablePlayers[0] ?? null)
    readonly property bool hasMedia: playablePlayers.length > 0
    readonly property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""
    readonly property bool popupOpen:
        GlobalStates.isBarPopupOpen("media", root.barScreenName)

    visible: hasMedia
    Layout.fillHeight: !vertical
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : 28
    implicitHeight: vertical ? 34 : Appearance.barLayout.persistentHeight

    onHasMediaChanged: {
        if (!hasMedia && popupOpen)
            GlobalStates.mediaControlsOpen = false
    }

    Timer {
        running: root.hasMedia
            && root.activePlayer?.playbackState === MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.activePlayer?.positionChanged()
    }

    Rectangle {
        id: mediaSurface
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: Appearance.rounding.verysmall
        color: root.popupOpen || mediaButton.containsMouse
            ? Appearance.colors.colLayer1Hover : "transparent"

        Rectangle {
            visible: root.playablePlayers.length > 1
            x: 8
            y: 5
            width: 17
            height: 17
            radius: 4
            color: Appearance.colors.colPrimary
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        Rectangle {
            id: coverTile
            x: root.playablePlayers.length > 1 ? 3 : 4
            y: 2
            width: 18
            height: 18
            radius: 4
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            Image {
                id: coverImage
                anchors.fill: parent
                source: root.activePlayer?.trackArtUrl ?? ""
                sourceSize: Qt.size(48, 48)
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: coverImage.status !== Image.Ready
                text: "music_note"
                iconSize: 15
                fill: 1
                color: Appearance.colors.colOnLayer1
            }

            Rectangle {
                anchors.fill: parent
                visible: !root.activePlayer?.isPlaying
                    && coverImage.status === Image.Ready
                color: Qt.rgba(0, 0, 0, 0.38)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    iconSize: 14
                    fill: 1
                    color: "white"
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            width: 16
            height: 2
            radius: 1
            color: Appearance.colors.colLayer1

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1,
                    root.activePlayer?.length > 0
                        ? root.activePlayer.position / root.activePlayer.length : 0))
                height: parent.height
                radius: 1
                color: Appearance.colors.colPrimary
            }
        }
    }

    MouseArea {
        id: mediaButton
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            | Qt.BackButton | Qt.ForwardButton

        onClicked: event => {
            if (!root.activePlayer) return
            if (event.button === Qt.MiddleButton)
                root.activePlayer.togglePlaying()
            else if (event.button === Qt.BackButton)
                root.activePlayer.previous()
            else if (event.button === Qt.ForwardButton)
                root.activePlayer.next()
            else {
                if (root.popupOpen) {
                    GlobalStates.mediaControlsOpen = false
                } else {
                    GlobalStates.mediaControlsScreenName = root.barScreenName
                    if (GlobalStates.mediaControlsOpen)
                        GlobalStates.openBarPopup("media", root.barScreenName)
                    else
                        GlobalStates.mediaControlsOpen = true
                }
            }
        }
    }

    MediaPopup {
        hoverTarget: mediaButton
        forceActive: root.popupOpen
    }
}
