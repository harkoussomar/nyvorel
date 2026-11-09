import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    readonly property MprisPlayer activePlayer:
        MprisController.activePlayer

    readonly property string cleanedTitle:
        StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || ""

    readonly property bool hasMedia:
        activePlayer !== null
        && cleanedTitle.length > 0
        && activePlayer?.playbackState !== MprisPlaybackState.Stopped

    visible: hasMedia

    Layout.fillHeight: true

    implicitWidth: hasMedia
        ? Math.min(content.implicitWidth, 190)
        : 0

    // nyvorel-phase3a-content-height: match the persistent navbar plane.
    implicitHeight: Appearance.barLayout.persistentHeight

    Timer {
        running:
            root.hasMedia
            && activePlayer?.playbackState === MprisPlaybackState.Playing

        interval: Config.options.resources.updateInterval
        repeat: true

        onTriggered: activePlayer?.positionChanged()
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent

        acceptedButtons:
            Qt.LeftButton
            | Qt.MiddleButton
            | Qt.RightButton
            | Qt.BackButton
            | Qt.ForwardButton

        onPressed: event => {
            if (!root.activePlayer)
                return

            if (event.button === Qt.MiddleButton) {
                root.activePlayer.togglePlaying()
            } else if (event.button === Qt.BackButton) {
                root.activePlayer.previous()
            } else if (
                event.button === Qt.ForwardButton
                || event.button === Qt.RightButton
            ) {
                root.activePlayer.next()
            } else if (event.button === Qt.LeftButton) {
                if (!GlobalStates.mediaControlsOpen)
                    GlobalStates.mediaControlsScreenName = root.QsWindow?.window?.screen?.name ?? ""
                GlobalStates.mediaControlsOpen =
                    !GlobalStates.mediaControlsOpen
            }
        }
    }

    RowLayout {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }

        spacing: Appearance.barLayout.axiomComponents ? Appearance.spacing.xs : 6

        ClippedFilledCircularProgress {
            id: mediaProgress

            Layout.alignment: Qt.AlignVCenter

            implicitSize: Appearance.barLayout.axiomComponents ? 20 : 20

            lineWidth: Appearance.rounding.unsharpen

            value: {
                const length = root.activePlayer?.length ?? 0
                const position = root.activePlayer?.position ?? 0

                return length > 0
                    ? position / length
                    : 0
            }

            colPrimary:
                Appearance.barLayout.axiomComponents ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnSecondaryContainer

            enableAnimation: false

            Item {
                anchors.centerIn: parent

                width: mediaProgress.implicitSize
                height: mediaProgress.implicitSize

                MaterialSymbol {
                    anchors.centerIn: parent

                    text:
                        root.activePlayer?.isPlaying
                        ? "pause"
                        : "music_note"

                    fill: 1

                    iconSize:
                        Appearance.font.pixelSize.normal

                    color:
                        Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true

            font {
                family: Appearance.barLayout.axiomComponents ? Appearance.font.family.monospace
                    : Appearance.font.family.main
                pixelSize: Appearance.barLayout.axiomComponents
                    ? Appearance.barVisual.axiomTextSize
                    : Appearance.font.pixelSize.small
                weight: Appearance.barLayout.axiomComponents ? Font.DemiBold : Font.Medium
            }

            horizontalAlignment: Text.AlignLeft

            color: Appearance.barLayout.axiomComponents ? Appearance.barVisual.axiomValue
                : Appearance.colors.colOnLayer1

            text: root.cleanedTitle

            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    Behavior on implicitWidth {
        MotionAnim {
            type: MotionAnim.FastSpatial
            duration: Appearance.barMotion.mediaWidthDuration
        }
    }
}
