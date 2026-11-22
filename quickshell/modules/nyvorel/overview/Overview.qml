import qs.modules.common.functions
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.nyvorel.bar as Bar
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
    property bool workspaceMode: false

    PanelWindow {
        id: panelWindow
        readonly property string searchingText: searchWidget.searchingText
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        property bool remappingLayer: false
        visible: GlobalStates.overviewOpen && !remappingLayer
        readonly property bool verticalBar: Config.options.bar.vertical
        readonly property bool oppositeEdge: Config.options.bar.bottom
        readonly property bool attachedToBar: !overviewScope.workspaceMode && GlobalStates.barOpen && !GlobalStates.screenLocked
            && Config.options.bar.showBackground && !!screen
            && (Config.options.bar.screenList.length === 0 || Config.options.bar.screenList.includes(screen.name))
        readonly property real barGap: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        readonly property real joinOffset: Math.max(0,
            (verticalBar ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight) - barGap - 1)

        exclusionMode: attachedToBar ? ExclusionMode.Ignore : ExclusionMode.Auto

        onAttachedToBarChanged: {
            if (!visible)
                return
            // Wayland applies a layer namespace when the surface is mapped.
            remappingLayer = true
            Qt.callLater(() => {
                panelWindow.remappingLayer = false
                if (panelWindow.visible)
                    searchWidget.focusSearchInput()
            })
        }

        Binding {
            target: GlobalStates
            property: "searchAttachedScreen"
            value: panelWindow.visible && panelWindow.attachedToBar ? panelWindow.screen.name : ""
        }

        // glass-system-v2.3b-shape
        Region {
            id: glassOverviewVisibleMask
            item: presentation
        }
        HyprlandWindow.visibleMask:
            Config.options.appearance.transparency.enable
                ? glassOverviewVisibleMask
                : null

        WlrLayershell.namespace: attachedToBar ? "quickshell:searchPanel" : "quickshell:overview"
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
                    ? presentation
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
                    overviewScope.dontAutoCancelSearch = false
                    overviewScope.workspaceMode = false
                    searchWidget.cancelSearch()
                } else if (!overviewScope.dontAutoCancelSearch) {
                    searchWidget.cancelSearch()
                }
                if (GlobalStates.overviewOpen)
                    Qt.callLater(searchWidget.focusSearchInput)

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
                if (GlobalStates.regionSelectorOpen || panelWindow.remappingLayer)
                    return

                GlobalStates.overviewOpen = false
            }
        }
        implicitWidth: presentation.width
        implicitHeight: presentation.height

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
            searchWidget.focusSearchInput();
        }

        Item {
            id: presentation

            readonly property real horizontalPadding: !panelWindow.attachedToBar ? 0
                : panelWindow.verticalBar ? 10 : frame.inset + 10
            readonly property real verticalPadding: !panelWindow.attachedToBar ? 0
                : panelWindow.verticalBar ? frame.inset : 4

            visible: GlobalStates.overviewOpen
            enabled: !GlobalStates.regionSelectorOpen
            width: columnLayout.implicitWidth + horizontalPadding * 2
            height: columnLayout.implicitHeight + verticalPadding * 2
            x: panelWindow.attachedToBar && panelWindow.verticalBar
                ? panelWindow.oppositeEdge ? parent.width - panelWindow.joinOffset - width : panelWindow.joinOffset
                : Math.round((parent.width - width) / 2)
            y: !panelWindow.attachedToBar ? 0
                : panelWindow.verticalBar ? Math.max(0, Math.min(panelWindow.barGap + 12, parent.height - height))
                : panelWindow.oppositeEdge ? parent.height - panelWindow.joinOffset - height : panelWindow.joinOffset

            Bar.AttachedBarSurface {
                id: frame

                anchors.fill: parent
                visible: panelWindow.attachedToBar
                vertical: panelWindow.verticalBar
                reverse: panelWindow.oppositeEdge
                cornerRadius: Appearance.radius.bar
                fillColor: Appearance.barVisual.attachedSurfaceFill
                strokeColor: Appearance.colors.colLayer0Border
            }

            Column {
                id: columnLayout
                x: presentation.horizontalPadding
                y: presentation.verticalPadding
                // OVERVIEW-UI-PRIORITY-V2.4
                // Search and workspace overview are separate hierarchy layers.
                spacing: 8

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.overviewOpen = false;
                    } else if (event.key === Qt.Key_Left) {
                        if (overviewScope.workspaceMode && !panelWindow.searchingText)
                            HyprNative.workspace("r-1");
                    } else if (event.key === Qt.Key_Right) {
                        if (overviewScope.workspaceMode && !panelWindow.searchingText)
                            HyprNative.workspace("r+1");
                    }
                }

                SearchWidget {
                    id: searchWidget
                    anchors.horizontalCenter: parent.horizontalCenter
                    attachedToBar: panelWindow.attachedToBar
                    availableWidth: Math.max(1, panelWindow.width - presentation.horizontalPadding * 2
                        - (panelWindow.attachedToBar && panelWindow.verticalBar ? panelWindow.joinOffset : 0))
                    availableHeight: Math.max(1, panelWindow.height - presentation.verticalPadding * 2
                        - (panelWindow.attachedToBar && !panelWindow.verticalBar ? panelWindow.joinOffset : 0))
                }

                Loader {
                    id: overviewLoader
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: GlobalStates.overviewOpen && overviewScope.workspaceMode && (Config?.options.overview.enable ?? true)
                    visible: active && panelWindow.searchingText === ""
                    sourceComponent: OverviewWidget {
                        screen: panelWindow.screen
                    }
                }
            }
        }
    }

    function toggleWorkspaces() {
        if (GlobalStates.overviewOpen && workspaceMode && !panelWindow.searchingText) {
            GlobalStates.overviewOpen = false;
            return;
        }
        workspaceMode = true;
        if (GlobalStates.overviewOpen)
            panelWindow.setSearchingText("");
        else
            GlobalStates.overviewOpen = true;
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && LauncherSearch.mode === "clipboard") {
            GlobalStates.overviewOpen = false;
            return;
        }
        workspaceMode = false;
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && LauncherSearch.mode === "emoji") {
            GlobalStates.overviewOpen = false;
            return;
        }
        workspaceMode = false;
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
            overviewScope.toggleWorkspaces();
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
            overviewScope.toggleWorkspaces();
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
