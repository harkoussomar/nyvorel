import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import QtQuick.Shapes

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property Component contentComponent
    readonly property Item popupContent: contentComponent ? deferredContent.item : contentItem
    property Loader deferredContent: Loader {
        active: root.contentComponent !== null && (root.fadeRequested || hasOpened)
        property bool hasOpened: false
        sourceComponent: root.contentComponent
        // Preserve panel selections and actions in progress after first use.
        onLoaded: hasOpened = true
    }

    property real popupBackgroundMargin: 0
    property real contentMargin: 12

    // Optional overrides. Defaults preserve all existing popups.
    property real popupRadius: Appearance.rounding.small

    property color popupColor: Appearance.colors.colLayer0

    property bool showOnHover: true
    property bool forceActive: false

    property bool dismissOnOutsideClick: false

    signal dismissRequested()

    // The primary navbar popups opt into a button-origin reveal.
    property bool irisAnimation: false
    readonly property bool fadeRequested: root.forceActive
        || (root.showOnHover && root.hoverTarget && root.hoverTarget.containsMouse)
    readonly property bool fadeOptIn: root.irisAnimation
        && Appearance.barLayout.axiomComponents
    // Geometry belongs to the bar surface; Axiom's edge reveal is separate.
    readonly property bool attachedToBar: Config.options.bar.showBackground
    readonly property bool fadeMotionAllowed: root.fadeOptIn
        && root.attachedToBar
        && !Appearance.reducedMotion
    property bool fadeRetained: false
    property bool fadeClosing: false

    // Keep the Wayland surface alive for the edge-collapse animation. This timer
    // belongs to the outer LazyLoader so unloading won't cancel it.
    property var fadeUnloadTimer: Timer {
        interval: 205
        repeat: false
        onTriggered: {
            root.fadeRetained = false
            root.fadeClosing = false
        }
    }

    function syncFadeVisibility() {
        if (!fadeMotionAllowed) {
            fadeUnloadTimer.stop()
            fadeClosing = false
            fadeRetained = false
            return
        }
        if (fadeRequested) {
            fadeUnloadTimer.stop()
            fadeClosing = false
            fadeRetained = true
        } else if (fadeRetained && !fadeClosing) {
            fadeClosing = true
            fadeUnloadTimer.restart()
        }
    }

    onFadeRequestedChanged: syncFadeVisibility()
    onFadeMotionAllowedChanged: syncFadeVisibility()
    Component.onCompleted: syncFadeVisibility()

    active: root.fadeMotionAllowed ? root.fadeRetained : root.fadeRequested


    component:
        PanelWindow {
            id: popupWindow
            screen: root.hoverTarget?.QsWindow?.window?.screen

            // Reveal height from a horizontal bar or width from a vertical bar.
            // The panel stays attached to its owning edge throughout.
            readonly property bool fadeEnabled: root.fadeMotionAllowed
            readonly property var triggerCenter: root.hoverTarget
                ? root.QsWindow?.mapFromItem(root.hoverTarget,
                    root.hoverTarget.width / 2, root.hoverTarget.height / 2)
                : null
            readonly property real morphOriginX: Math.max(0, Math.min(
                popupBackground.width,
                (triggerCenter?.x ?? (margins.left + popupBackground.x
                    + popupBackground.width / 2)) - margins.left - popupBackground.x))
            readonly property real morphOriginY: Math.max(0, Math.min(
                popupBackground.height,
                (triggerCenter?.y ?? (margins.top + popupBackground.y))
                    - margins.top - popupBackground.y))
            readonly property real closedScaleX: Config.options.bar.vertical
                ? Math.max(0.07, Math.min(0.9,
                    (root.hoverTarget?.width ?? 32)
                        / Math.max(1, popupBackground.implicitWidth)))
                : 1
            readonly property bool joinedHorizontal: root.attachedToBar
                && !Config.options.bar.vertical
            readonly property bool joinedVertical: root.attachedToBar
                && Config.options.bar.vertical
            readonly property bool joinedBottom: joinedHorizontal
                && Config.options.bar.bottom
            readonly property bool joinedRight: joinedVertical
                && Config.options.bar.bottom
            readonly property real joinedInset: 18
            readonly property real barEdgeInset: Appearance.sizes.elevationMargin
                + (Config.options.bar.cornerStyle === 1
                    ? Appearance.sizes.hyprlandGapsOut : 0)
            readonly property real closedScaleY: Config.options.bar.vertical
                ? 1
                : Math.max(0.07, Math.min(0.9,
                    (root.hoverTarget?.height ?? 32)
                        / Math.max(1, popupBackground.implicitHeight)))
            property real morphScaleX: fadeEnabled ? closedScaleX : 1
            property real morphScaleY: fadeEnabled ? closedScaleY : 1
            function beginFadeEntrance() {
                morphOut.stop()
                morphIn.stop()
                if (!fadeEnabled) {
                    morphScaleX = 1
                    morphScaleY = 1
                    return
                }
                // Reopening continues from the current height.
                morphIn.start()
            }

            function beginFadeExit() {
                if (!fadeEnabled)
                    return
                morphIn.stop()
                morphOut.stop()
                morphOut.start()
            }

            ParallelAnimation {
                id: morphIn
                NumberAnimation { target: popupWindow; property: "morphScaleX"; to: 1; duration: 255; easing.type: Easing.OutCubic }
                NumberAnimation { target: popupWindow; property: "morphScaleY"; to: 1; duration: 255; easing.type: Easing.OutCubic }
            }
            ParallelAnimation {
                id: morphOut
                NumberAnimation { target: popupWindow; property: "morphScaleX"; to: popupWindow.closedScaleX; duration: 185; easing.type: Easing.InCubic }
                NumberAnimation { target: popupWindow; property: "morphScaleY"; to: popupWindow.closedScaleY; duration: 185; easing.type: Easing.InCubic }
            }
            Connections {
                target: root
                function onFadeClosingChanged() {
                    if (!popupWindow.fadeEnabled)
                        return
                    if (root.fadeClosing)
                        popupWindow.beginFadeExit()
                    else if (root.fadeRequested)
                        popupWindow.beginFadeEntrance()
                }
            }

            // ----------------------------------------------------
            // Native Hyprland click-away dismissal.
            // Arm shortly after opening so the click which opened the
            // popup cannot immediately count as an outside click.
            // ----------------------------------------------------

            WlrLayershell.keyboardFocus:
                root.dismissOnOutsideClick
                && root.forceActive
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None

            property bool dismissArmed: false

            Timer {
                id: dismissArmTimer
                interval: 120
                repeat: false

                onTriggered:
                    popupWindow.dismissArmed =
                        root.dismissOnOutsideClick
                        && root.forceActive
            }

            function syncDismissGrab() {
                popupWindow.dismissArmed = false
                dismissArmTimer.stop()

                if (
                    root.dismissOnOutsideClick
                    && root.forceActive
                ) {
                    dismissArmTimer.restart()
                }
            }

            Component.onCompleted: {
                popupWindow.syncDismissGrab()
                popupWindow.beginFadeEntrance()
            }

            Connections {
                target: root

                function onForceActiveChanged() {
                    popupWindow.syncDismissGrab()
                }

                function onDismissOnOutsideClickChanged() {
                    popupWindow.syncDismissGrab()
                }
            }

            HyprlandFocusGrab {
                id: outsideDismissGrab
                // Keep navbar controls clickable while this popup owns focus.
                // Their shared selection closes this panel and opens the next.
                windows: [ popupWindow, root.QsWindow?.window ]
                active: popupWindow.dismissArmed

                onCleared: {
                    if (
                        popupWindow.dismissArmed
                        && root.dismissOnOutsideClick
                        && root.forceActive
                    ) {
                        popupWindow.dismissArmed = false
                        root.dismissRequested()
                    }
                }
            }

            Shortcut {
                sequence: "Esc"
                enabled:
                    root.dismissOnOutsideClick
                    && root.forceActive

                onActivated:
                    root.dismissRequested()
            }

            color: "transparent"

            anchors.left:
                !Config.options.bar.vertical
                || (
                    Config.options.bar.vertical
                    && !Config.options.bar.bottom
                )

            anchors.right:
                Config.options.bar.vertical
                && Config.options.bar.bottom

            anchors.top:
                Config.options.bar.vertical
                || (
                    !Config.options.bar.vertical
                    && !Config.options.bar.bottom
                )

            anchors.bottom:
                !Config.options.bar.vertical
                && Config.options.bar.bottom


            implicitWidth:
                popupBackground.implicitWidth
                + Appearance.sizes.elevationMargin * 2
                + root.popupBackgroundMargin

            implicitHeight:
                popupBackground.implicitHeight
                + Appearance.sizes.elevationMargin * 2
                + root.popupBackgroundMargin


            mask: Region {
                item: root.fadeOptIn ? null : popupBackground
                x: root.fadeOptIn ? popupWindow.morphRegionX : 0
                y: root.fadeOptIn ? popupWindow.morphRegionY : 0
                width: root.fadeOptIn ? popupWindow.morphRegionWidth : 0
                height: root.fadeOptIn ? popupWindow.morphRegionHeight : 0
            }

            readonly property int morphRegionX: popupWindow.joinedVertical
                ? Math.floor(popupBackground.x)
                : Math.floor(popupBackground.x
                    + morphOriginX * (1 - morphScaleX))
            readonly property int morphRegionY: root.attachedToBar
                ? Math.floor(popupBackground.y)
                : Math.floor(popupBackground.y + morphOriginY * (1 - morphScaleY))
            readonly property int morphRegionWidth: popupWindow.joinedVertical
                ? Math.ceil(popupBackground.width) + 1
                : Math.ceil(popupBackground.width * morphScaleX) + 1
            readonly property int morphRegionHeight: root.attachedToBar
                ? Math.ceil(popupBackground.height) + 1
                : Math.ceil(popupBackground.height * morphScaleY) + 1

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0


            margins {
                left: {
                    if (Config.options.bar.vertical)
                        return Math.max(0, Appearance.sizes.verticalBarWidth
                            - popupWindow.barEdgeInset
                            - (root.attachedToBar ? 1 : 0))

                    const mapped =
                        root.QsWindow?.mapFromItem(
                            root.hoverTarget,
                            (
                                root.hoverTarget.width
                                - popupBackground.implicitWidth
                            ) / 2,
                            0
                        )

                    const wantedX = mapped?.x ?? 0

                    const screenWidth =
                        root.QsWindow.window?.screen?.width
                        ?? 0

                    const edgeMargin = 8
                    const popupWidth = popupWindow.implicitWidth

                    if (screenWidth <= 0)
                        return Math.max(edgeMargin, wantedX)

                    const maxX =
                        Math.max(
                            edgeMargin,
                            screenWidth
                            - popupWidth
                            - edgeMargin
                        )

                    return Math.max(
                        edgeMargin,
                        Math.min(wantedX, maxX)
                    )
                }

                top: {
                    if (!Config.options.bar.vertical)
                        return Math.max(0, Appearance.sizes.barHeight
                            - popupWindow.barEdgeInset
                            - (root.attachedToBar ? 1 : 0))

                    const mapped = root.QsWindow?.mapFromItem(
                        root.hoverTarget,
                        0,
                        (root.hoverTarget.height
                            - popupBackground.implicitHeight) / 2)
                    const wantedY = mapped?.y ?? 0
                    const screenHeight = root.QsWindow.window?.screen?.height ?? 0
                    const edgeMargin = 8
                    if (screenHeight <= 0)
                        return Math.max(edgeMargin, wantedY)
                    const maxY = Math.max(edgeMargin,
                        screenHeight - popupWindow.implicitHeight - edgeMargin)
                    return Math.max(edgeMargin, Math.min(wantedY, maxY))
                }

                right:
                    Math.max(0, Appearance.sizes.verticalBarWidth
                        - popupWindow.barEdgeInset
                        - (popupWindow.joinedRight ? 1 : 0))

                bottom:
                    Math.max(0, Appearance.sizes.barHeight
                        - popupWindow.barEdgeInset
                        - (root.attachedToBar ? 1 : 0))
            }


            // glass-system-v2.3b-shape
            Region {
                id: glassPopupVisibleMask
                item: root.fadeOptIn ? null : popupBackground
                x: root.fadeOptIn ? popupWindow.morphRegionX : 0
                y: root.fadeOptIn ? popupWindow.morphRegionY : 0
                width: root.fadeOptIn ? popupWindow.morphRegionWidth : 0
                height: root.fadeOptIn ? popupWindow.morphRegionHeight : 0
            }
            HyprlandWindow.visibleMask:
                Config.options.appearance.transparency.enable
                    ? glassPopupVisibleMask
                    : null

            // Isolated namespace: the compositor leaves motion to QML.
            WlrLayershell.namespace:
                root.fadeOptIn
                    ? "quickshell:popup-quickfade"
                    : "quickshell:popup"

            WlrLayershell.layer:
                WlrLayer.Overlay


            StyledRectangularShadow {
                visible: !root.attachedToBar
                target: popupBackground
                opacity: 1
                transform: Scale {
                    origin.x: popupWindow.morphOriginX
                    origin.y: popupWindow.morphOriginY
                    xScale: root.fadeOptIn ? popupWindow.morphScaleX : 1
                    yScale: root.fadeOptIn ? popupWindow.morphScaleY : 1
                }
            }



            Rectangle {
                id: popupBackground

                readonly property real margin: root.contentMargin
                readonly property color joinedFill: Config.options.bar.showBackground
                    ? Appearance.barVisual.attachedSurfaceFill : root.popupColor
                readonly property color joinedBorder: Appearance.colors.colLayer0Border
                readonly property real joinedRadius: root.popupRadius
                readonly property real joinedBorderWidth: 1

                anchors {
                    fill: root.attachedToBar ? undefined : parent
                    left: root.attachedToBar && !popupWindow.joinedRight
                        ? parent.left : undefined
                    right: root.attachedToBar && (popupWindow.joinedHorizontal
                        || popupWindow.joinedRight) ? parent.right : undefined
                    top: root.attachedToBar && !popupWindow.joinedBottom
                        ? parent.top : undefined
                    bottom: popupWindow.joinedBottom
                        ? parent.bottom : undefined

                    leftMargin:
                        Appearance.sizes.elevationMargin
                        + root.popupBackgroundMargin
                            * (!popupWindow.anchors.left)

                    rightMargin:
                        Appearance.sizes.elevationMargin
                        + root.popupBackgroundMargin
                            * (!popupWindow.anchors.right)

                    topMargin:
                        Appearance.sizes.elevationMargin
                        + root.popupBackgroundMargin
                            * (!popupWindow.anchors.top)

                    bottomMargin:
                        Appearance.sizes.elevationMargin
                        + root.popupBackgroundMargin
                            * (!popupWindow.anchors.bottom)
                }

                implicitWidth:
                    (root.popupContent?.implicitWidth ?? 0)
                    + margin * 2
                    + (popupWindow.joinedHorizontal
                        ? popupWindow.joinedInset * 2 : 0)

                implicitHeight:
                    (root.popupContent?.implicitHeight ?? 0)
                    + margin * 2
                    + (popupWindow.joinedVertical
                        ? popupWindow.joinedInset * 2 : 0)

                Binding {
                    target: popupBackground
                    property: "height"
                    value: Math.max(1,
                        popupBackground.implicitHeight * popupWindow.morphScaleY)
                    when: popupWindow.joinedHorizontal || popupWindow.joinedVertical
                    restoreMode: Binding.RestoreBinding
                }
                Binding {
                    target: popupBackground
                    property: "width"
                    value: Math.max(1,
                        popupBackground.implicitWidth * popupWindow.morphScaleX)
                    when: popupWindow.joinedVertical
                    restoreMode: Binding.RestoreBinding
                }
                clip: root.attachedToBar

                color:
                    root.attachedToBar ? "transparent" : root.popupColor

                radius:
                    root.attachedToBar ? 0 : root.popupRadius

                border.width:
                    root.attachedToBar ? 0 : 1
                border.color:
                    Appearance.colors.colLayer0Border

                transform: Scale {
                    origin.x: popupWindow.morphOriginX
                    origin.y: popupWindow.morphOriginY
                    xScale: root.fadeOptIn && !popupWindow.joinedVertical
                        ? popupWindow.morphScaleX : 1
                    yScale: root.fadeOptIn && !popupWindow.joinedHorizontal
                        ? popupWindow.morphScaleY : 1
                }

                // Draw one contour with its open edge against the bar.
                // Rotation maps that edge to the other bar positions.
                Shape {
                    id: attachedSurface

                    visible: root.attachedToBar
                    preferredRendererType: Shape.CurveRenderer
                    transformOrigin: Item.TopLeft
                    width: popupWindow.joinedVertical ? popupBackground.height : popupBackground.width
                    height: popupWindow.joinedVertical ? popupBackground.width : popupBackground.height
                    x: popupWindow.joinedRight || popupWindow.joinedBottom ? popupBackground.width : 0
                    y: popupWindow.joinedBottom || (popupWindow.joinedVertical && !popupWindow.joinedRight)
                        ? popupBackground.height : 0
                    rotation: popupWindow.joinedBottom ? 180
                        : popupWindow.joinedVertical ? (popupWindow.joinedRight ? 90 : -90) : 0

                    // Keep the full stroke inside the exposed edge of the clip.
                    readonly property real outerEdge: Math.max(0, height - popupBackground.joinedBorderWidth / 2)
                    readonly property real shoulder: Math.min(popupWindow.joinedInset, outerEdge / 3)
                    readonly property real corner: Math.min(popupBackground.joinedRadius,
                        popupWindow.joinedInset, outerEdge / 4)
                    readonly property real rightSide: width - shoulder

                    ShapePath {
                        fillColor: popupBackground.joinedFill
                        strokeColor: popupBackground.joinedBorder
                        strokeWidth: popupBackground.joinedBorderWidth
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 0
                        startY: 0

                        PathArc {
                            x: attachedSurface.shoulder
                            y: attachedSurface.shoulder
                            radiusX: attachedSurface.shoulder
                            radiusY: attachedSurface.shoulder
                            direction: PathArc.Clockwise
                        }
                        PathLine {
                            x: attachedSurface.shoulder
                            y: attachedSurface.outerEdge - attachedSurface.corner
                        }
                        PathArc {
                            x: attachedSurface.shoulder + attachedSurface.corner
                            y: attachedSurface.outerEdge
                            radiusX: attachedSurface.corner
                            radiusY: attachedSurface.corner
                            direction: PathArc.Counterclockwise
                        }
                        PathLine {
                            x: attachedSurface.rightSide - attachedSurface.corner
                            y: attachedSurface.outerEdge
                        }
                        PathArc {
                            x: attachedSurface.rightSide
                            y: attachedSurface.outerEdge - attachedSurface.corner
                            radiusX: attachedSurface.corner
                            radiusY: attachedSurface.corner
                            direction: PathArc.Counterclockwise
                        }
                        PathLine {
                            x: attachedSurface.rightSide
                            y: attachedSurface.shoulder
                        }
                        PathArc {
                            x: attachedSurface.width
                            y: 0
                            radiusX: attachedSurface.shoulder
                            radiusY: attachedSurface.shoulder
                            direction: PathArc.Clockwise
                        }
                    }
                }

                // Clip a full-size content plane as the surface grows. Text
                // keeps its natural size; no opacity animation is needed.
                Item {
                    x: popupWindow.joinedHorizontal
                        ? popupWindow.joinedInset
                        : popupWindow.joinedRight
                            ? popupBackground.width - popupBackground.implicitWidth
                            : 0
                    y: popupWindow.joinedBottom
                        ? popupBackground.height - height
                        : popupWindow.joinedVertical
                            ? popupWindow.joinedInset : 0
                    width: popupWindow.joinedVertical
                        ? popupBackground.implicitWidth
                        : parent.width - (popupWindow.joinedHorizontal
                            ? popupWindow.joinedInset * 2 : 0)
                    height: popupWindow.joinedHorizontal
                        ? popupBackground.implicitHeight
                        : parent.height - (popupWindow.joinedVertical
                            ? popupWindow.joinedInset * 2 : 0)
                    children: root.popupContent ? [root.popupContent] : []
                }
            }
        }
}
