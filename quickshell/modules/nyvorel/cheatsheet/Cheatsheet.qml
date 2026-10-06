import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root

    // modal-material-stability-v1
    readonly property bool stableCheatsheetOpen:
        GlobalStates.exclusiveSurfaceActive("cheatsheet")
    property var tabButtonList: [
        {
            "icon": "keyboard",
            "name": Translation.tr("Keybinds")
        },
        {
            "icon": "experiment",
            "name": Translation.tr("Elements")
        },
    ]

    Loader {
        id: cheatsheetLoader
        active:
            Config.options.appearance.transparency.enable
                ? true
                : root.stableCheatsheetOpen

        sourceComponent: PanelWindow { // Window
            id: cheatsheetRoot
            function syncShellCaptureRegion(): void {
                if (
                    !root.stableCheatsheetOpen
                    || !cheatsheetRoot.screen
                    || cheatsheetBackground.width <= 0
                    || cheatsheetBackground.height <= 0
                ) {
                    GlobalStates.clearCaptureRegion("cheatsheet")
                    return
                }

                // snip-global-geometry-v1
                const monitor =
                    Hyprland.monitorFor(cheatsheetRoot.screen)
                const monitorData =
                    HyprlandData.monitors.find(
                        entry => entry.id === monitor?.id
                    )
                const reserved =
                    monitorData?.reserved ?? [0, 0, 0, 0]
                const surfaceX = reserved[0] ?? 0
                const surfaceY = reserved[1] ?? 0

                GlobalStates.registerCaptureRegion(
                    "cheatsheet",
                    cheatsheetRoot.screen.name,
                    surfaceX + cheatsheetBackground.x,
                    surfaceY + cheatsheetBackground.y,
                    cheatsheetBackground.width,
                    cheatsheetBackground.height,
                    145,
                    "Cheatsheet",
                    4
                ) // SNIP-GEOMETRY-V2.3-LIVE cheatsheet
            }

            onVisibleChanged:
                Qt.callLater(
                    () => cheatsheetRoot.syncShellCaptureRegion()
                )

            onScreenChanged:
                Qt.callLater(
                    () => cheatsheetRoot.syncShellCaptureRegion()
                )
            visible:
                Config.options.appearance.transparency.enable
                    ? true
                    : root.stableCheatsheetOpen

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide() {
                GlobalStates.closeExclusiveSurface("cheatsheet", false)
            }
            exclusiveZone: 0
            implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
            // glass-system-v2.3b-shape
            Region {
                id: glassCheatsheetVisibleMask
                item:
                    root.stableCheatsheetOpen
                        ? cheatsheetBackground
                        : null
            }
            HyprlandWindow.visibleMask:
                Config.options.appearance.transparency.enable
                    ? glassCheatsheetVisibleMask
                    : null

            WlrLayershell.namespace: "quickshell:cheatsheet"
            // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            mask: Region {
                item:
                    root.stableCheatsheetOpen
                        ? cheatsheetBackground
                        : null
            }

            Component.onCompleted: {
                if (root.stableCheatsheetOpen)
                    GlobalFocusGrab.addDismissable(cheatsheetRoot);
                Qt.callLater(() => cheatsheetRoot.syncShellCaptureRegion());
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
                GlobalStates.clearCaptureRegion("cheatsheet");
            }
            Connections {
                target: root

                function onStableCheatsheetOpenChanged() {
                    if (root.stableCheatsheetOpen)
                        GlobalFocusGrab.addDismissable(cheatsheetRoot)
                    else
                        GlobalFocusGrab.removeDismissable(cheatsheetRoot)

                    Qt.callLater(
                        () => cheatsheetRoot.syncShellCaptureRegion()
                    )
                }
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    cheatsheetRoot.hide();
                }
            }

            // Background
            StyledRectangularShadow {
                visible: !Appearance.prismMode && !Appearance.inlayMode
                target: cheatsheetBackground
            }

            // prism-v2-phase7: cheatsheet/keybinds join the depth-4 modal plane.
            PrismSurface {
                visible: Appearance.prismMode && root.stableCheatsheetOpen
                x: cheatsheetBackground.x
                y: cheatsheetBackground.y
                width: cheatsheetBackground.width
                height: cheatsheetBackground.height
                depth: Appearance.prism.depthModal
                surfaceRadius: Appearance.prism.radiusModal
                elevated: true
            }

            Rectangle {
                id: cheatsheetBackground

                visible: root.stableCheatsheetOpen
                onXChanged:
                    cheatsheetRoot.syncShellCaptureRegion()
                onYChanged:
                    cheatsheetRoot.syncShellCaptureRegion()
                onWidthChanged:
                    cheatsheetRoot.syncShellCaptureRegion()
                onHeightChanged:
                    cheatsheetRoot.syncShellCaptureRegion()
                anchors.centerIn: parent
                color:
                    Appearance.prismMode
                        ? "transparent"
                        : Appearance.inlayMode
                            ? Appearance.inlay.surfaceFill
                            : Appearance.colors.colLayer0
                border.width:
                    Appearance.prismMode
                        ? 0
                        : Appearance.inlayMode
                            ? Appearance.inlay.borderWidth
                            : 1
                border.color:
                    Appearance.inlayMode
                        ? Appearance.inlay.borderControl
                        : Appearance.colors.colLayer0Border
                radius:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.prismMode
                            ? Appearance.prism.radiusModal
                            : Appearance.rounding.windowRounding
                property real padding: 20
                implicitWidth:
                    Math.min(
                        cheatsheetColumnLayout.implicitWidth + padding * 2,
                        cheatsheetRoot.width - 48
                    )

                implicitHeight:
                    cheatsheetColumnLayout.implicitHeight + padding * 2

                Keys.onPressed: event => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        cheatsheetRoot.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_PageDown) {
                            tabBar.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            tabBar.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                            event.accepted = true;
                        }
                    }
                }

                Rectangle { // Close button normalized to Battery dialog DNA
                    id: closeButton
                    focus: cheatsheetRoot.visible
                    activeFocusOnTab: true
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: height / 2
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 20
                        rightMargin: 20
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: "Close cheatsheet"
                    Accessible.focusable: true
                    Accessible.focused: closeButton.activeFocus
                    Accessible.onPressAction: cheatsheetRoot.hide()

                    Keys.onPressed: event => {
                        if (
                            event.key === Qt.Key_Space
                            || event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter
                        ) {
                            cheatsheetRoot.hide()
                            event.accepted = true
                        }
                    }

                    color:
                        Appearance.prismMode
                            ? (cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                                ? Appearance.prism.persistentActiveFill
                                : "transparent")
                            : (cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Qt.rgba(
                                    Appearance.colors.colOnSurfaceVariant.r,
                                    Appearance.colors.colOnSurfaceVariant.g,
                                    Appearance.colors.colOnSurfaceVariant.b,
                                    0.07
                                  ))

                    border.width: 1
                    border.color:
                        Appearance.prismMode
                            ? (cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                                ? Appearance.prism.focusBorder
                                : Appearance.prism.borderSubtle)
                            : (cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 20
                        text: "close"
                        color:
                            cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                                ? (Appearance.prismMode
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOnPrimary)
                                : Appearance.colors.colOnSurfaceVariant
                    }

                    MouseArea {
                        id: cheatsheetCloseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cheatsheetRoot.hide()
                    }
                }

                ColumnLayout { // Real content
                    id: cheatsheetColumnLayout
                    anchors.centerIn: parent
                    spacing: 10

                    Toolbar {
                        Layout.alignment: Qt.AlignHCenter
                        enableShadow: false
                        ToolbarTabBar {
                            id: tabBar
                            tabButtonList: root.tabButtonList

                            Synchronizer on currentIndex {
                                property alias source: swipeView.currentIndex
                            }
                        }
                    }

                    SwipeView { // Content pages
                        id: swipeView
                        Layout.topMargin: 5
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        currentIndex: Persistent.states.cheatsheet.tabIndex
                        onCurrentIndexChanged: {
                            Persistent.states.cheatsheet.tabIndex = currentIndex;
                        }

                        implicitWidth: Math.max.apply(null, contentChildren.map(child => child.implicitWidth || 0))
                        implicitHeight: Math.max.apply(null, contentChildren.map(child => child.implicitHeight || 0))

                        clip: true
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: swipeView.width
                                height: swipeView.height
                                radius: Appearance.rounding.small
                            }
                        }

                        CheatsheetKeybinds {}
                        CheatsheetPeriodicTable {}
                    }
                }
            }
        }
    }





    // CHEATSHEET-DYNAMIC-V3: public controller lives in family scope
}
