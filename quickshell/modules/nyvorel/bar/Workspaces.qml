import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1
    
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / root.workspacesShown)
    property list<bool> workspaceOccupied: []
    property int widgetPadding: Appearance.prismMode ? Appearance.spacing.sm : 3
    property int workspaceButtonWidth: 24
    // Inlay rail uses the same 5px breathing room horizontally as vertically.
    // This keeps the first/last workspace away from the structural border.
    readonly property real inlayRailInset: Appearance.inlayMode ? 5 : 0
    // Keep enough breathing room around the larger workspace app icon so the
    // active-workspace ring remains clearly visible.
    property real activeWorkspaceMargin: Appearance.prismMode ? 3 : 1
    // Workspace app icons need a little more optical size than text/dots.
    // 24px cell -> ~17px normal icon and ~13px compact icon.
    property real workspaceIconSize: workspaceButtonWidth * 0.71
    property real workspaceIconSizeShrinked: workspaceButtonWidth * 0.55
    property real workspaceIconOpacityShrinked: 0.75
    property real workspaceIconMarginShrinked: -3
    property int workspaceIndexInGroup: (effectiveActiveWorkspaceId - 1) % root.workspacesShown

    property bool showNumbers: false
    Timer {
        id: showNumbersTimer
        interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
        repeat: false
        onTriggered: {
            root.showNumbers = true
        }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
            if (GlobalStates.superDown) showNumbersTimer.restart();
            else {
                showNumbersTimer.stop();
                root.showNumbers = false;
            }
        }
        function onSuperReleaseMightTriggerChanged() { 
            showNumbersTimer.stop()
        }
    }

    // Function to update workspaceOccupied
    function updateWorkspaceOccupied() {
        workspaceOccupied = Array.from({ length: root.workspacesShown }, (_, i) => {
            return Hyprland.workspaces.values.some(ws => ws.id === workspaceGroup * root.workspacesShown + i + 1);
        })
    }

    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateWorkspaceOccupied();
        }
    }
    onWorkspaceGroupChanged: {
        updateWorkspaceOccupied();
    }

    implicitWidth:
        root.vertical
            ? Appearance.sizes.verticalBarWidth
            : (root.workspaceButtonWidth * root.workspacesShown)
                + root.inlayRailInset * 2
    implicitHeight: root.vertical ? (root.workspaceButtonWidth * root.workspacesShown) : Appearance.sizes.barHeight

    // Scroll to switch workspaces
    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y < 0)
                Hyprland.dispatch('hl.dsp.focus({workspace = "r+1"})');
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch('hl.dsp.focus({workspace = "r-1"})');
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: (event) => {
            if (event.button === Qt.BackButton) {
                Hyprland.dispatch('hl.dsp.workspace.toggle_special("")');
            } 
        }
    }

    // inlay-v2-i2: recessed workspace channel inside the continuous rail.
    Rectangle {
        id: inlayWorkspaceRail
        z: 0
        visible: Appearance.inlayMode
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        height: Appearance.sizes.baseBarHeight - 10
        radius: 0
        color: Appearance.inlay.insetFill
        border.width: Appearance.inlay.borderWidth
        border.color: Appearance.inlay.borderSection
    }

    // Workspaces - background
    Grid {
        z: 1
        anchors.centerIn: parent

        rowSpacing: 0
        columnSpacing: 0
        columns: root.vertical ? 1 : root.workspacesShown
        rows: root.vertical ? root.workspacesShown : 1

        Repeater {
            model: root.workspacesShown

            Rectangle {
                z: 1
                implicitWidth: workspaceButtonWidth
                implicitHeight: workspaceButtonWidth
                radius: (width / 2)
                property var previousOccupied: (workspaceOccupied[index-1] && !(!activeWindow?.activated && root.effectiveActiveWorkspaceId === index))
                property var rightOccupied: (workspaceOccupied[index+1] && !(!activeWindow?.activated && root.effectiveActiveWorkspaceId === index+2))
                property var radiusPrev: previousOccupied ? 0 : (width / 2)
                property var radiusNext: rightOccupied ? 0 : (width / 2)

                topLeftRadius: radiusPrev
                bottomLeftRadius: root.vertical ? radiusNext : radiusPrev
                topRightRadius: root.vertical ? radiusPrev : radiusNext
                bottomRightRadius: radiusNext
                
                // Fluid: occupied workspaces should read as a faint glass bed,
                // not as a solid warm capsule.
                color: Appearance.fluidMode
                    ? ColorUtils.transparentize(
                        Appearance.colors.colLayer1Hover,
                        0.62
                    )
                    : Appearance.prismMode
                        ? ColorUtils.transparentize(
                            Appearance.colors.colOnLayer1,
                            0.90
                        )
                        : ColorUtils.transparentize(
                            Appearance.m3colors.m3secondaryContainer,
                            0.4
                        )
                opacity: (Appearance.prismMode || Appearance.inlayMode)
                    ? 0
                    : ((workspaceOccupied[index] && !(!activeWindow?.activated && root.effectiveActiveWorkspaceId === index+1)) ? 1 : 0)

                Behavior on opacity {
                    MotionAnim {
                        type: MotionAnim.DefaultEffects
                    }
                }

                Behavior on radiusPrev {
                    MotionAnim {
                        type: MotionAnim.FastSpatial
                    }
                }

                Behavior on radiusNext {
                    MotionAnim {
                        type: MotionAnim.FastSpatial
                    }
                }

            }

        }

    }

    // Active workspace
    Rectangle {
        z: 2
        // Make active ws indicator, which has a brighter color, smaller to look like it is of the same size as ws occupied highlight
        radius: Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Math.min(Appearance.prism.radiusControl / 2, indicatorThickness / 2)
                : Appearance.rounding.full

        // Fluid: the active workspace reads primarily as an accent ring.
        // The fill stays extremely light so it does not become a heavy badge.
        color: Appearance.fluidMode
            ? ColorUtils.transparentize(
                Appearance.colors.colPrimary,
                0.92
            )
            : Appearance.inlayMode
                ? Appearance.inlay.controlFill
                : Appearance.prismMode
                    ? Appearance.prism.persistentActiveFill
                    : Appearance.colors.colPrimary

        border.width: (Appearance.fluidMode || Appearance.prismMode || Appearance.inlayMode) ? 1 : 0
        border.color: Appearance.fluidMode
            ? ColorUtils.transparentize(
                Appearance.colors.colPrimary,
                0.18
            )
            : Appearance.inlayMode
                ? Appearance.inlay.borderFocus
                : Appearance.prismMode
                    ? Appearance.prism.focusBorder
                    : "transparent"

        Behavior on color {
            enabled: Appearance.prismMode || Appearance.inlayMode
            MotionColorAnim { type: MotionColorAnim.FastEffects }
        }

        anchors {
            verticalCenter: vertical ? undefined : parent.verticalCenter
            horizontalCenter: vertical ? parent.horizontalCenter : undefined
        }

        AnimatedTabIndexPair {
            id: idxPair
            index: root.workspaceIndexInGroup
        }
        property real indicatorPosition:
            root.inlayRailInset
            + Math.min(idxPair.idx1, idxPair.idx2) * workspaceButtonWidth
            + root.activeWorkspaceMargin
        property real indicatorLength: Math.abs(idxPair.idx1 - idxPair.idx2) * workspaceButtonWidth + workspaceButtonWidth - root.activeWorkspaceMargin * 2
        property real indicatorThickness: workspaceButtonWidth - root.activeWorkspaceMargin * 2

        x: root.vertical ? null : indicatorPosition
        implicitWidth: root.vertical ? indicatorThickness : indicatorLength
        y: root.vertical ? indicatorPosition : null
        implicitHeight: root.vertical ? indicatorLength : indicatorThickness

    }

    // Workspaces - numbers
    Grid {
        z: 3

        columns: root.vertical ? 1 : root.workspacesShown
        rows: root.vertical ? root.workspacesShown : 1
        columnSpacing: 0
        rowSpacing: 0

        anchors {
            fill: parent
            leftMargin: root.vertical ? 0 : root.inlayRailInset
            rightMargin: root.vertical ? 0 : root.inlayRailInset
        }

        Repeater {
            model: root.workspacesShown

            Button {
                id: button
                property int workspaceValue: workspaceGroup * root.workspacesShown + index + 1
                implicitHeight: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
                implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.verticalBarWidth
                onPressed: Hyprland.dispatch(`hl.dsp.focus({workspace = "${workspaceValue}"})`)
                width: vertical ? undefined : workspaceButtonWidth
                height: vertical ? workspaceButtonWidth : undefined

                background: Item {
                    id: workspaceButtonBackground
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(button.workspaceValue)
                    property var mainAppIconSource: Quickshell.iconPath(AppSearch.guessIcon(biggestWindow?.class), "image-missing")

                    // prism-v2-phase2b1: workspace hover is intentionally
                    // text/icon-only. A second tile behind the travelling active
                    // indicator made the workspace island feel visually stacked.
                    HoverHandler {
                        id: prismWorkspaceHover
                        enabled: Appearance.prismMode || Appearance.inlayMode
                    }

                    Rectangle {
                        z: 1
                        anchors.centerIn: parent
                        width: root.workspaceButtonWidth - 8
                        height: width
                        visible: Appearance.inlayMode
                            && prismWorkspaceHover.hovered
                            && root.effectiveActiveWorkspaceId !== button.workspaceValue
                        radius: 0
                        color: "transparent"
                        border.width: Appearance.inlay.borderWidth
                        border.color: Appearance.inlay.borderControl
                    }

                    StyledText { // Workspace number text
                        opacity: root.showNumbers
                            || ((Config.options?.bar.workspaces.alwaysShowNumbers && (!Config.options?.bar.workspaces.showAppIcons || !workspaceButtonBackground.biggestWindow || root.showNumbers))
                            || (root.showNumbers && !Config.options?.bar.workspaces.showAppIcons)
                            )  ? 1 : 0
                        z: 3

                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font {
                            pixelSize: Appearance.font.pixelSize.small - ((text.length - 1) * (text !== "10") * 2)
                            family: Config.options?.bar.workspaces.useNerdFont ? Appearance.font.family.iconNerd : defaultFont
                        }
                        text: Config.options?.bar.workspaces.numberMap[button.workspaceValue - 1] || button.workspaceValue
                        elide: Text.ElideRight
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue)
                            ? (Appearance.fluidMode
                                ? Appearance.colors.colPrimary
                                : Appearance.inlayMode
                                    ? Appearance.colors.colOnLayer1
                                    : Appearance.prismMode
                                        ? Appearance.colors.colPrimary
                                        : Appearance.m3colors.m3onPrimary)
                            : (workspaceOccupied[index]
                                ? (Appearance.fluidMode
                                    ? Appearance.colors.colOnLayer1
                                    : (Appearance.prismMode || Appearance.inlayMode)
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.m3colors.m3onSecondaryContainer)
                                : ((Appearance.prismMode || Appearance.inlayMode) && prismWorkspaceHover.hovered
                                    ? Appearance.colors.colOnLayer1
                                    : Appearance.colors.colOnLayer1Inactive))

                        Behavior on opacity {
                            MotionAnim {
                                type: MotionAnim.FastEffects
                            }
                        }
                    }
                    Rectangle { // Dot instead of ws number
                        id: wsDot
                        opacity: (Config.options?.bar.workspaces.alwaysShowNumbers
                            || root.showNumbers
                            || (Config.options?.bar.workspaces.showAppIcons && workspaceButtonBackground.biggestWindow)
                            ) ? 0 : 1
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.13
                        height: width
                        radius: Appearance.inlayMode ? 0 : width / 2
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue)
                            ? (Appearance.fluidMode
                                ? Appearance.colors.colPrimary
                                : Appearance.inlayMode
                                    ? Appearance.colors.colOnLayer1
                                    : Appearance.prismMode
                                        ? Appearance.colors.colPrimary
                                        : Appearance.m3colors.m3onPrimary)
                            : (workspaceOccupied[index]
                                ? (Appearance.fluidMode
                                    ? Appearance.colors.colOnLayer1
                                    : (Appearance.prismMode || Appearance.inlayMode)
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.m3colors.m3onSecondaryContainer)
                                : ((Appearance.prismMode || Appearance.inlayMode) && prismWorkspaceHover.hovered
                                    ? Appearance.colors.colOnLayer1
                                    : Appearance.colors.colOnLayer1Inactive))

                        Behavior on opacity {
                            MotionAnim {
                                type: MotionAnim.FastEffects
                            }
                        }
                    }
                    Item { // Main app icon
                        anchors.centerIn: parent
                        width: workspaceButtonWidth
                        height: workspaceButtonWidth
                        opacity: !Config.options?.bar.workspaces.showAppIcons ? 0 :
                            (workspaceButtonBackground.biggestWindow && !root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                            1 : workspaceButtonBackground.biggestWindow ? workspaceIconOpacityShrinked : 0
                            visible: opacity > 0
                        IconImage {
                            id: mainAppIcon
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.bottomMargin: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                                (workspaceButtonWidth - workspaceIconSize) / 2 : workspaceIconMarginShrinked
                            anchors.rightMargin: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                                (workspaceButtonWidth - workspaceIconSize) / 2 : workspaceIconMarginShrinked

                            source: workspaceButtonBackground.mainAppIconSource
                            implicitSize: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? workspaceIconSize : workspaceIconSizeShrinked

                            // IconImage exposes its backing QtQuick Image via
                            // `backer`; request a larger source and let it
                            // downsample into the tiny workspace slot.
                            backer.sourceSize: Qt.size(64, 64)
                            backer.smooth: true
                            asynchronous: true
                            mipmap: true

                            Behavior on opacity {
                                MotionAnim {
                                    type: MotionAnim.FastEffects
                                }
                            }

                            Behavior on anchors.bottomMargin {
                                MotionAnim {
                                    type: MotionAnim.FastSpatial
                                    duration: 260
                                }
                            }

                            Behavior on anchors.rightMargin {
                                MotionAnim {
                                    type: MotionAnim.FastSpatial
                                    duration: 260
                                }
                            }

                            Behavior on implicitSize {
                                MotionAnim {
                                    type: MotionAnim.FastSpatial
                                    duration: 260
                                }
                            }
                        }

                        Loader {
                            active: Config.options.bar.workspaces.monochromeIcons
                            anchors.fill: mainAppIcon
                            sourceComponent: Item {
                                Desaturate {
                                    id: desaturatedIcon
                                    visible: false // There's already color overlay
                                    anchors.fill: parent
                                    source: mainAppIcon
                                    desaturation: 0.8
                                }
                                ColorOverlay {
                                    anchors.fill: desaturatedIcon
                                    source: desaturatedIcon
                                    color: ColorUtils.transparentize(wsDot.color, 0.9)
                                }
                            }
                        }
                    }
                }
                

            }

        }

    }

}
