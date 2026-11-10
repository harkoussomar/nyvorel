import qs
import qs.services

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris

// Keep the established shortcut and IPC contract. The actual player surface
// now belongs to the bar, so it shares the bar's notch and screen ownership.
Scope {
    id: root

    function toggle() {
        GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
    }

    Connections {
        target: GlobalStates

        function onMediaControlsOpenChanged() {
            if (!GlobalStates.mediaControlsOpen) {
                GlobalStates.closeBarPopup("media")
                GlobalStates.mediaControlsScreenName = ""
                return
            }

            const players = MprisController.players.filter(player =>
                player && player.trackTitle
                    && player.playbackState !== MprisPlaybackState.Stopped)
            if (players.length === 0) {
                GlobalStates.mediaControlsOpen = false
                return
            }

            const owner = GlobalStates.mediaControlsScreenName
                || Hyprland.focusedMonitor?.name || ""
            GlobalStates.mediaControlsScreenName = owner
            GlobalStates.openBarPopup("media", owner)
            Notifications.timeoutAll()
        }

        function onActiveBarPopupChanged() {
            if (GlobalStates.activeBarPopup !== "media"
                && GlobalStates.mediaControlsOpen)
                GlobalStates.mediaControlsOpen = false
        }
    }

    IpcHandler {
        target: "mediaControls"
        function toggle(): void { root.toggle() }
        function close(): void { GlobalStates.mediaControlsOpen = false }
        function open(): void { GlobalStates.mediaControlsOpen = true }
        function openOnScreen(screenName: string): void {
            GlobalStates.mediaControlsScreenName = screenName
            if (GlobalStates.mediaControlsOpen)
                GlobalStates.openBarPopup("media", screenName)
            else
                GlobalStates.mediaControlsOpen = true
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"
        onPressed: root.toggle()
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = true
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"
        onPressed: GlobalStates.mediaControlsOpen = false
    }
}
