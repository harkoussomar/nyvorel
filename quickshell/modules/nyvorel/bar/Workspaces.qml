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
    property int previewWorkspaceId: 0
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1
    readonly property var clients: HyprlandData.windowList
    readonly property var focusedToplevel: ToplevelManager.activeToplevel
    readonly property string focusedAddress: focusedToplevel?.HyprlandToplevel?.address
        ? `0x${focusedToplevel.HyprlandToplevel.address}` : ""
    readonly property var monitorData: HyprlandData.monitors.find(m => m.name === monitor?.name) ?? null
    
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / root.workspacesShown)
    property list<bool> workspaceOccupied: []
    property int widgetPadding: 3
    property int workspaceButtonWidth: Appearance.barLayout.workspaceCellWidth
    // This keeps the first/last workspace away from the structural border.
    // Keep enough breathing room around the larger workspace app icon so the
    // active-workspace ring remains clearly visible.
    property real activeWorkspaceMargin: 1
    // Give detailed app marks enough pixels to remain legible in a 24px cell.
    property real workspaceIconSize: workspaceButtonWidth * 0.78
    property real workspaceIconSizeShrinked: workspaceButtonWidth * 0.55
    property real workspaceIconOpacityShrinked: 0.75
    property real workspaceIconMarginShrinked: -3
    property int workspaceIndexInGroup: (effectiveActiveWorkspaceId - 1) % root.workspacesShown

    function clientsForWorkspace(workspaceId) {
        const monitorId = root.monitorData?.id ?? root.monitor?.id
        return root.clients.filter(win => win.workspace?.id === workspaceId
            && win.monitor === monitorId)
    }

    function foregroundWindowForWorkspace(workspaceId) {
        const windows = root.clientsForWorkspace(workspaceId)
        if (windows.length === 0) return null

        // Hyprland's active toplevel is the source of truth for the focused
        // workspace. For other workspaces, use the most recent focus history.
        const focused = windows.find(win => win.address === root.focusedAddress)
        if (focused) return focused

        return windows.reduce((best, win) => {
            const rank = Number(win.focusHistoryID)
            const bestRank = Number(best.focusHistoryID)
            const validRank = Number.isFinite(rank) && rank >= 0 ? rank : 999999
            const validBestRank = Number.isFinite(bestRank) && bestRank >= 0
                ? bestRank : 999999
            return validRank < validBestRank ? win : best
        }, windows[0])
    }

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

    // Workspace IDs are global, while each bar represents one monitor.
    // Only windows on this bar's monitor may mark a cell occupied.
    function updateWorkspaceOccupied() {
        const monitorName = root.monitor?.name
        root.workspaceOccupied = Array.from({ length: root.workspacesShown }, (_, i) => {
            const id = root.workspaceGroup * root.workspacesShown + i + 1
            return HyprlandData.workspaces.some(ws =>
                ws.id === id && ws.monitor === monitorName && ws.windows > 0)
        })
    }

    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: HyprlandData
        function onWorkspacesChanged() { root.updateWorkspaceOccupied() }
        function onWindowListChanged() { root.updateWorkspaceOccupied() }
    }
    onWorkspaceGroupChanged: updateWorkspaceOccupied()
    onMonitorChanged: updateWorkspaceOccupied()
    onWorkspacesShownChanged: updateWorkspaceOccupied()

    implicitWidth:
        root.vertical
            ? Appearance.sizes.verticalBarWidth
            : (root.workspaceButtonWidth * root.workspacesShown)

    // nyvorel-phase3a-content-height: floating outer insets are not
    // part of the workspace control plane.
    implicitHeight: root.vertical ? (root.workspaceButtonWidth * root.workspacesShown) : Appearance.barLayout.persistentHeight

    // Scroll to switch workspaces
    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y < 0)
                HyprNative.workspace("r+1");
            else if (event.angleDelta.y > 0)
                HyprNative.workspace("r-1");
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: (event) => {
            if (event.button === Qt.BackButton) {
                HyprNative.toggleSpecial();
            } 
        }
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
                property var previousOccupied: workspaceOccupied[index-1]
                property var rightOccupied: workspaceOccupied[index+1]
                property var radiusPrev: previousOccupied ? 0 : (width / 2)
                property var radiusNext: rightOccupied ? 0 : (width / 2)

                topLeftRadius: radiusPrev
                bottomLeftRadius: root.vertical ? radiusNext : radiusPrev
                topRightRadius: root.vertical ? radiusPrev : radiusNext
                bottomRightRadius: radiusNext
                
                // Fluid: occupied workspaces should read as a faint glass bed,
                // not as a solid warm capsule.
                color: Appearance.barLayout.axiomComponents
                    ? ColorUtils.transparentize(
                        Appearance.colors.colLayer1Hover,
                        0.62
                    )
                    : ColorUtils.transparentize(
                        Appearance.m3colors.m3secondaryContainer,
                        0.4
                    )
                opacity: workspaceOccupied[index] ? 1 : 0

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
        // Axiom / Fluid: compact rectangular precision indicator.
        radius: Appearance.barLayout.axiomComponents
            ? Appearance.rounding.small : Appearance.rounding.full

        // Fluid: the active workspace reads primarily as an accent ring.
        // The fill stays extremely light so it does not become a heavy badge.
        color: Appearance.barLayout.axiomComponents
            ? ColorUtils.transparentize(
                Appearance.colors.colPrimary,
                0.92
            )
            : Appearance.colors.colPrimary

        border.width: Appearance.barLayout.axiomComponents ? 1 : 0
        border.color: Appearance.barLayout.axiomComponents
            ? ColorUtils.transparentize(
                Appearance.colors.colPrimary,
                0.18
            )
            : "transparent"

        Behavior on color {
            enabled: false
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
            Math.min(idxPair.idx1, idxPair.idx2) * workspaceButtonWidth
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
            leftMargin: 0
            rightMargin: 0
        }

        Repeater {
            model: root.workspacesShown

            Button {
                id: button
                property int workspaceValue: workspaceGroup * root.workspacesShown + index + 1
                implicitHeight: vertical ? Appearance.sizes.verticalBarWidth : Appearance.barLayout.persistentHeight
                implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.verticalBarWidth
                onPressed: {
                    HyprNative.workspace(workspaceValue)
                    if (Config.options.bar.tooltips.clickToShow)
                        root.previewWorkspaceId = root.previewWorkspaceId === workspaceValue
                            ? 0 : workspaceValue
                }
                width: vertical ? undefined : workspaceButtonWidth
                height: vertical ? workspaceButtonWidth : undefined

                background: Item {
                    id: workspaceButtonBackground
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var foregroundWindow: root.foregroundWindowForWorkspace(button.workspaceValue)
                    property var mainAppIconSource: Quickshell.iconPath(AppSearch.guessIcon(foregroundWindow?.class), "image-missing")

                    // text/icon-only. A second tile behind the travelling active
                    // indicator made the workspace island feel visually stacked.

                    StyledText { // Workspace number text
                        opacity: root.showNumbers
                            || ((Config.options?.bar.workspaces.alwaysShowNumbers && (!Config.options?.bar.workspaces.showAppIcons || !workspaceButtonBackground.foregroundWindow || root.showNumbers))
                            || (root.showNumbers && !Config.options?.bar.workspaces.showAppIcons)
                            )  ? 1 : 0
                        z: 3

                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font {
                            pixelSize: (Appearance.barLayout.axiomComponents
                                ? Appearance.barVisual.axiomTextSize
                                : Appearance.font.pixelSize.small)
                                - ((text.length - 1) * (text !== "10") * 2)
                            family: Config.options?.bar.workspaces.useNerdFont
                                ? Appearance.font.family.iconNerd
                                : Appearance.barLayout.axiomComponents
                                    ? Appearance.font.family.monospace : defaultFont

                        }
                        text: Config.options?.bar.workspaces.numberMap[button.workspaceValue - 1] || button.workspaceValue
                        elide: Text.ElideRight
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue)
                            ? (Appearance.barLayout.axiomComponents
                                ? Appearance.colors.colPrimary
                                : Appearance.m3colors.m3onPrimary)
                            : (workspaceOccupied[index]
                                ? (Appearance.barLayout.axiomComponents
                                    ? Appearance.colors.colOnLayer1
                                    : Appearance.m3colors.m3onSecondaryContainer)
                                : Appearance.colors.colOnLayer1Inactive)

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
                            || (Config.options?.bar.workspaces.showAppIcons && workspaceButtonBackground.foregroundWindow)
                            ) ? 0 : 1
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.13
                        height: width
                        radius: width / 2
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue)
                            ? (Appearance.barLayout.axiomComponents
                                ? Appearance.colors.colPrimary
                                : Appearance.m3colors.m3onPrimary)
                            : (workspaceOccupied[index]
                                ? (Appearance.barLayout.axiomComponents
                                    ? Appearance.colors.colOnLayer1
                                    : Appearance.m3colors.m3onSecondaryContainer)
                                : Appearance.colors.colOnLayer1Inactive)

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
                            (workspaceButtonBackground.foregroundWindow && !root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ?
                            1 : workspaceButtonBackground.foregroundWindow ? workspaceIconOpacityShrinked : 0
                            visible: opacity > 0
                        Image {
                            id: mainAppIcon
                            visible: !Config.monochromeAppIcons
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.bottomMargin: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                                (workspaceButtonWidth - workspaceIconSize) / 2 : workspaceIconMarginShrinked
                            anchors.rightMargin: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                                (workspaceButtonWidth - workspaceIconSize) / 2 : workspaceIconMarginShrinked

                            source: workspaceButtonBackground.mainAppIconSource
                            width: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? workspaceIconSize : workspaceIconSizeShrinked
                            height: width
                            sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                            mipmap: false

                            Behavior on opacity {
                                MotionAnim {
                                    type: MotionAnim.FastEffects
                                }
                            }

                            Behavior on anchors.bottomMargin {
                                MotionAnim {
                                    type: MotionAnim.FastSpatial
                                    duration: Appearance.barMotion.workspaceIconDuration
                                }
                            }

                            Behavior on anchors.rightMargin {
                                MotionAnim {
                                    type: MotionAnim.FastSpatial
                                    duration: Appearance.barMotion.workspaceIconDuration
                                }
                            }

                            Behavior on width {
                                MotionAnim {
                                    type: MotionAnim.FastSpatial
                                    duration: Appearance.barMotion.workspaceIconDuration
                                }
                            }
                        }

                        Loader {
                            active: Config.monochromeAppIcons
                            anchors.fill: mainAppIcon
                            sourceComponent: Desaturate {
                                anchors.fill: parent
                                source: mainAppIcon
                                desaturation: 1.0
                            }
                        }
                    }
                }

                MouseArea {
                    id: workspaceHoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                StyledPopup {
                    hoverTarget: workspaceHoverArea
                    showOnHover: !Config.options.bar.tooltips.clickToShow
                    forceActive: Config.options.bar.tooltips.clickToShow
                        && root.previewWorkspaceId === button.workspaceValue
                    dismissOnOutsideClick: Config.options.bar.tooltips.clickToShow
                    onDismissRequested: root.previewWorkspaceId = 0
                    irisAnimation: true
                    popupRadius: Appearance.radius.bar
                    contentMargin: 0

                    WorkspacePreview {
                        workspaceId: button.workspaceValue
                        monitorData: root.monitorData
                        windows: root.clientsForWorkspace(button.workspaceValue)
                        foregroundWindow: workspaceButtonBackground.foregroundWindow
                    }
                }
                

            }

        }

    }

}
