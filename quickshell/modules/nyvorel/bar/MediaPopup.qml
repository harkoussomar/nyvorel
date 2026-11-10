import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Services.Mpris

StyledPopup {
    id: root

    // Preserve the previous player's ability to control every media source.
    // MprisController already removes duplicate native browser integrations.
    readonly property var players: MprisController.players.filter(player =>
        player && player.trackTitle
            && player.playbackState !== MprisPlaybackState.Stopped)
    readonly property real screenWidth: root.QsWindow?.window?.screen?.width ?? 420
    readonly property real screenHeight: root.QsWindow?.window?.screen?.height ?? 900
    readonly property real panelWidth: Math.min(370, Math.max(160,
        screenWidth - (Config.options.bar.vertical
            ? Appearance.sizes.verticalBarWidth + 82 : 56)))
    // Reserve the notch, content padding and screen edge before scrolling.
    readonly property real maximumContentHeight: Math.max(150,
        screenHeight - (Config.options.bar.vertical
            ? 100 : Appearance.sizes.barHeight + 100))

    showOnHover: false
    irisAnimation: true
    dismissOnOutsideClick: true
    popupRadius: Appearance.radius.bar
    contentMargin: 14
    onDismissRequested: GlobalStates.mediaControlsOpen = false

    Controls.ScrollView {
        id: scrollView
        anchors.centerIn: parent
        implicitWidth: root.panelWidth
        implicitHeight: Math.min(playerStack.implicitHeight,
            root.maximumContentHeight)
        contentWidth: availableWidth
        clip: playerStack.implicitHeight > root.maximumContentHeight
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

        ColumnLayout {
            id: playerStack
            width: scrollView.availableWidth
            spacing: 14

            Repeater {
                model: root.players

                MediaPlayerEntry {
                    required property MprisPlayer modelData
                    required property int index
                    player: modelData
                    separated: index > 0
                    Layout.fillWidth: true
                }
            }
        }
    }
}
