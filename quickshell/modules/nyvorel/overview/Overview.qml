import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen

        // glass-system-v2.3b-shape
        Region {
            id: glassOverviewVisibleMask
            item: columnLayout
        }
        HyprlandWindow.visibleMask:
            Config.options.appearance.transparency.enable
                ? glassOverviewVisibleMask
                : null

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        // overview-snip-focus-v1
        // Keep Overview rendered while Region Selector is active, but never
        // let both layer-shell surfaces own keyboard focus at the same time.
        WlrLayershell.keyboardFocus:
            GlobalStates.overviewOpen
            && !GlobalStates.regionSelectorOpen
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            // During snipping the Overview remains visible for capture, but
            // its input region is disabled so the selector owns pointer input.
            item:
                GlobalStates.overviewOpen
                && !GlobalStates.regionSelectorOpen
                    ? columnLayout
                    : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // overview-snip-focus-v1
        // Overview used to stay registered in GlobalFocusGrab while Region
        // Selector stole focus. That caused an Overview close/reopen loop:
        // focus loss -> dismiss -> overviewOpen=false -> GlobalStates restores
        // the active exclusive surface -> Overview grabs focus again.
        function syncDismissable(): void {
            if (
                GlobalStates.overviewOpen
                && !GlobalStates.regionSelectorOpen
                && panelWindow.visible
            ) {
                GlobalFocusGrab.addDismissable(panelWindow)
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow)
            }
        }

        onVisibleChanged:
            panelWindow.syncDismissable()

        Component.onDestruction:
            GlobalFocusGrab.removeDismissable(panelWindow)

        Connections {
            target: GlobalStates

            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation()
                    overviewScope.dontAutoCancelSearch = false
                } else if (!overviewScope.dontAutoCancelSearch) {
                    searchWidget.cancelSearch()
                }

                panelWindow.syncDismissable()
            }

            function onRegionSelectorOpenChanged() {
                // A Super-based snip shortcut must not later fire the pending
                // quick-Super release toggle while the selector is active.
                if (GlobalStates.regionSelectorOpen)
                    GlobalStates.superReleaseMightTrigger = false

                panelWindow.syncDismissable()
            }
        }

        Connections {
            target: GlobalFocusGrab

            function onDismissed() {
                // Region Selector temporarily owns input. Keep Overview
                // rendered underneath it so it can still be captured.
                if (GlobalStates.regionSelectorOpen)
                    return

                GlobalStates.overviewOpen = false
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            enabled: !GlobalStates.regionSelectorOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            // OVERVIEW-UI-PRIORITY-V2.4
            // Search and workspace overview are separate hierarchy layers.
            spacing: 8

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                } else if (event.key === Qt.Key_Left) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch('hl.dsp.focus({workspace = "r-1"})');
                } else if (event.key === Qt.Key_Right) {
                    if (!panelWindow.searchingText)
                        Hyprland.dispatch('hl.dsp.focus({workspace = "r+1"})');
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    visible: (panelWindow.searchingText == "")
                }
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    // super-hold-suppress-v4
    //
    // Super behaves like a tap-vs-hold key:
    //   quick tap  -> keep the existing Search/Overview action
    //   real hold  -> suppress the release action
    // Super+scroll can still suppress immediately through
    // search.toggleReleaseInterrupt().
    Timer {
        id: superHoldSuppressTimer
        interval: 250
        repeat: false

        onTriggered: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }

    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on quick Super tap"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
            superHoldSuppressTimer.restart();
        }

        onReleased: {
            superHoldSuppressTimer.stop();

            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }

            GlobalStates.overviewOpen =
                !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
