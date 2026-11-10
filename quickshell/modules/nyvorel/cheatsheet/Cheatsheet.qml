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
            "icon": "public",
            "name": Translation.tr("Universe")
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
            // Request keyboard input only while the guide is open, as the other
            // interactive Nyvorel panels do. This makes search focus on first click.
            WlrLayershell.keyboardFocus:
                root.stableCheatsheetOpen
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None
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
                visible: true
                target: cheatsheetBackground
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
                      Appearance.colors.colLayer0
                border.width:
                      1
                border.color:
                     Appearance.colors.colLayer0Border
                radius:
                      Appearance.rounding.windowRounding
                property real padding: 20
                width: Math.max(360, Math.min(1320, cheatsheetRoot.width - 48))
                height: Math.max(420, Math.min(760, cheatsheetRoot.height - 48))

                Keys.onPressed: event => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        cheatsheetRoot.hide();
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_PageDown) {
                            swipeView.currentIndex = Math.min(1, swipeView.currentIndex + 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            swipeView.currentIndex = Math.max(0, swipeView.currentIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            swipeView.currentIndex = (swipeView.currentIndex + 1) % root.tabButtonList.length;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            swipeView.currentIndex = (swipeView.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length;
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
                         (cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                            ? Appearance.colors.colPrimary
                            : Qt.rgba(
                                Appearance.colors.colOnSurfaceVariant.r,
                                Appearance.colors.colOnSurfaceVariant.g,
                                Appearance.colors.colOnSurfaceVariant.b,
                                0.07
                              ))

                    border.width: 1
                    border.color:
                         (cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer0Border)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 20
                        text: "close"
                        color:
                            cheatsheetCloseArea.containsMouse || closeButton.activeFocus
                                ? (Appearance.colors.colOnPrimary)
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
                    anchors.fill: parent
                    anchors.margins: cheatsheetBackground.padding
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 47
                        spacing: 10
                        StyledText {
                            text: "Nyvorel"
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            id: tabRail
                            readonly property int tabInset: 5
                            readonly property int tabGap: 5
                            Layout.rightMargin: 58
                            Layout.preferredWidth: 240 + 2 * tabInset + tabGap
                            Layout.preferredHeight: 42
                            radius: Appearance.radius.card
                            color: Appearance.colors.colLayer1
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border

                            Rectangle {
                                id: activeTabSurface
                                x: tabRail.tabInset + swipeView.currentIndex * (120 + tabRail.tabGap)
                                y: tabRail.tabInset
                                width: 120
                                height: parent.height - 2 * tabRail.tabInset
                                radius: Math.max(2, Appearance.radius.card - tabRail.tabInset)
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: Qt.rgba(
                                    Appearance.colors.colPrimary.r,
                                    Appearance.colors.colPrimary.g,
                                    Appearance.colors.colPrimary.b,
                                    0.58
                                )
                                Behavior on x {
                                    enabled: !Appearance.reducedMotion
                                    NumberAnimation { duration: Appearance.barMotion.statusDuration; easing.type: Easing.OutCubic }
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.margins: tabRail.tabInset
                                spacing: tabRail.tabGap
                                Repeater {
                                    model: root.tabButtonList
                                    delegate: Item {
                                        id: tabButton
                                        required property int index
                                        required property var modelData
                                        width: 120
                                        height: parent.height
                                        readonly property bool selected: swipeView.currentIndex === index

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Math.max(2, Appearance.radius.card - tabRail.tabInset)
                                            color: tabMouse.containsMouse && !tabButton.selected
                                                ? Appearance.colors.colLayer1Hover : "transparent"
                                        }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 7
                                            MaterialSymbol {
                                                text: tabButton.modelData.icon
                                                iconSize: 16
                                                color: tabButton.selected
                                                    ? Appearance.colors.colPrimary
                                                    : Appearance.colors.colOnLayer1
                                            }
                                            StyledText {
                                                text: tabButton.modelData.name
                                                color: tabButton.selected
                                                    ? Appearance.colors.colOnLayer0
                                                    : Appearance.colors.colOnLayer1
                                                font.pixelSize: 12
                                                font.weight: tabButton.selected ? Font.DemiBold : Font.Normal
                                            }
                                        }
                                        MouseArea {
                                            id: tabMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: swipeView.currentIndex = tabButton.index
                                        }
                                    }
                                }
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

                        clip: true
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: swipeView.width
                                height: swipeView.height
                                radius: Appearance.rounding.small
                            }
                        }

                        CheatsheetKeybinds { id: keybindsPage }
                        CheatsheetUniverse {
                            id: universePage
                            viewActive: root.stableCheatsheetOpen && swipeView.currentIndex === 1
                        }
                    }
                }
            }
        }
    }





    // CHEATSHEET-DYNAMIC-V3: public controller lives in family scope
}
