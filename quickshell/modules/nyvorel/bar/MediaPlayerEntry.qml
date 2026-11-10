import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

ColumnLayout {
    id: entry

    required property MprisPlayer player
    property bool separated: false

    spacing: 10

    function seekAt(x, width) {
        if (!player?.canSeek || !(player?.length > 0)) return
        player.position = Math.max(0, Math.min(1, x / width)) * player.length
    }

    function sourceName() {
        const bus = String(player?.dbusName ?? "")
        const source = bus.replace(/^org\.mpris\.MediaPlayer2\./, "")
            .split(".")[0].replace(/[-_]/g, " ")
        return source.length > 0
            ? source.charAt(0).toUpperCase() + source.slice(1)
            : Translation.tr("Media player")
    }

    component TransportButton: Rectangle {
        id: button
        property string symbol: ""
        property bool primary: false
        signal invoked()

        implicitWidth: primary ? 42 : 32
        implicitHeight: primary ? 42 : 32
        radius: width / 2
        color: primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        opacity: enabled ? 1 : 0.42

        MaterialSymbol {
            anchors.centerIn: parent
            text: button.symbol
            iconSize: button.primary ? 22 : 19
            fill: 1
            color: button.primary
                ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }

        MouseArea {
            anchors.fill: parent
            enabled: button.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.invoked()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: entry.separated ? 1 : 0
        visible: entry.separated
        color: Appearance.colors.colLayer0Border
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 80
            Layout.preferredHeight: 80
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            clip: true

            Image {
                id: artImage
                anchors.fill: parent
                source: entry.player?.trackArtUrl ?? ""
                sourceSize: Qt.size(160, 160)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready
                text: "music_note"
                iconSize: 32
                color: Appearance.colors.colPrimary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            StyledText {
                Layout.fillWidth: true
                text: entry.sourceName()
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: StringUtils.cleanMusicTitle(entry.player?.trackTitle)
                    || Translation.tr("Unknown title")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
            StyledText {
                Layout.fillWidth: true
                text: entry.player?.trackArtist || Translation.tr("Unknown artist")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    Rectangle {
        id: seekTrack
        Layout.fillWidth: true
        implicitHeight: 6
        radius: height / 2
        color: Appearance.colors.colLayer1

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1,
                entry.player?.length > 0
                    ? entry.player.position / entry.player.length : 0))
            height: parent.height
            radius: height / 2
            color: Appearance.colors.colPrimary
        }
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -8
            anchors.bottomMargin: -8
            enabled: entry.player?.canSeek ?? false
            cursorShape: Qt.PointingHandCursor
            onPressed: event => entry.seekAt(event.x, seekTrack.width)
            onPositionChanged: event => {
                if (pressed) entry.seekAt(event.x, seekTrack.width)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        StyledText {
            text: StringUtils.friendlyTimeForSeconds(entry.player?.position)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: StringUtils.friendlyTimeForSeconds(entry.player?.length)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 14

        TransportButton {
            symbol: "skip_previous"
            enabled: entry.player?.canGoPrevious ?? false
            onInvoked: entry.player?.previous()
        }
        TransportButton {
            primary: true
            symbol: entry.player?.isPlaying ? "pause" : "play_arrow"
            enabled: entry.player?.canTogglePlaying ?? false
            onInvoked: entry.player?.togglePlaying()
        }
        TransportButton {
            symbol: "skip_next"
            enabled: entry.player?.canGoNext ?? false
            onInvoked: entry.player?.next()
        }
    }

    property var positionTimer: Timer {
        running: entry.visible && entry.player?.isPlaying
        interval: 1000
        repeat: true
        onTriggered: entry.player?.positionChanged()
    }
}
