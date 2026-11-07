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
                    root.contentItem.implicitWidth
                    + margin * 2
                    + (popupWindow.joinedHorizontal
                        ? popupWindow.joinedInset * 2 : 0)

                implicitHeight:
                    root.contentItem.implicitHeight
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

                // A single open-top outline joins the bar's lower edge.
                // The shoulders curve into the panel instead of drawing a
                // second rounded card underneath the navbar.
                Shape {
                    id: attachedSurface
                    visible: popupWindow.joinedHorizontal
                        && !popupWindow.joinedBottom
                    anchors.fill: parent
                    readonly property real shoulder: Math.min(
                        popupWindow.joinedInset, height / 3)
                    readonly property real lowerRadius: Math.min(
                        popupBackground.joinedRadius,
                        popupWindow.joinedInset, height / 4)
                    ShapePath {
                        strokeWidth: -1
                        fillColor: popupBackground.joinedFill
                        startX: 0
                        startY: 0
                        PathLine { x: attachedSurface.width; y: 0 }
                        PathQuad { controlX: attachedSurface.width - attachedSurface.shoulder; controlY: 0; x: attachedSurface.width - attachedSurface.shoulder; y: attachedSurface.shoulder }
                        PathLine { x: attachedSurface.width - attachedSurface.shoulder; y: attachedSurface.height - attachedSurface.lowerRadius }
                        PathQuad { controlX: attachedSurface.width - attachedSurface.shoulder; controlY: attachedSurface.height; x: attachedSurface.width - attachedSurface.shoulder - attachedSurface.lowerRadius; y: attachedSurface.height }
                        PathLine { x: attachedSurface.shoulder + attachedSurface.lowerRadius; y: attachedSurface.height }
                        PathQuad { controlX: attachedSurface.shoulder; controlY: attachedSurface.height; x: attachedSurface.shoulder; y: attachedSurface.height - attachedSurface.lowerRadius }
                        PathLine { x: attachedSurface.shoulder; y: attachedSurface.shoulder }
                        PathQuad { controlX: attachedSurface.shoulder; controlY: 0; x: 0; y: 0 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: popupBackground.joinedBorder
                        strokeWidth: popupBackground.joinedBorderWidth
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 0
                        startY: 0
                        PathQuad { controlX: attachedSurface.shoulder; controlY: 0; x: attachedSurface.shoulder; y: attachedSurface.shoulder }
                        PathLine { x: attachedSurface.shoulder; y: attachedSurface.height - attachedSurface.lowerRadius }
                        PathQuad { controlX: attachedSurface.shoulder; controlY: attachedSurface.height; x: attachedSurface.shoulder + attachedSurface.lowerRadius; y: attachedSurface.height }
                        PathLine { x: attachedSurface.width - attachedSurface.shoulder - attachedSurface.lowerRadius; y: attachedSurface.height }
                        PathQuad { controlX: attachedSurface.width - attachedSurface.shoulder; controlY: attachedSurface.height; x: attachedSurface.width - attachedSurface.shoulder; y: attachedSurface.height - attachedSurface.lowerRadius }
                        PathLine { x: attachedSurface.width - attachedSurface.shoulder; y: attachedSurface.shoulder }
                        PathQuad { controlX: attachedSurface.width - attachedSurface.shoulder; controlY: 0; x: attachedSurface.width; y: 0 }
                    }
                }

                // The same open seam faces the owning bar edge on bottom,
                // left and right.
                function joinedPath(outline) {
                    const w = width
                    const h = height
                    const s = Math.min(popupWindow.joinedInset,
                        popupWindow.joinedVertical ? w / 3 : h / 3)
                    const r = Math.min(joinedRadius,
                        popupWindow.joinedInset,
                        popupWindow.joinedVertical ? w / 4 : h / 4)

                    if (popupWindow.joinedBottom) {
                        if (outline)
                            return `M 0 ${h} Q ${s} ${h} ${s} ${h-s} L ${s} ${r+1} Q ${s} 1 ${s+r} 1 L ${w-s-r} 1 Q ${w-s} 1 ${w-s} ${r+1} L ${w-s} ${h-s} Q ${w-s} ${h} ${w} ${h}`
                        return `M 0 ${h} L ${w} ${h} Q ${w-s} ${h} ${w-s} ${h-s} L ${w-s} ${r} Q ${w-s} 0 ${w-s-r} 0 L ${s+r} 0 Q ${s} 0 ${s} ${r} L ${s} ${h-s} Q ${s} ${h} 0 ${h} Z`
                    }
                    if (popupWindow.joinedRight) {
                        if (outline)
                            return `M ${w} ${h} Q ${w} ${h-s} ${w-s} ${h-s} L ${r+1} ${h-s} Q 1 ${h-s} 1 ${h-s-r} L 1 ${s+r} Q 1 ${s} ${r+1} ${s} L ${w-s} ${s} Q ${w} ${s} ${w} 0`
                        return `M ${w} 0 L ${w} ${h} Q ${w} ${h-s} ${w-s} ${h-s} L ${r} ${h-s} Q 0 ${h-s} 0 ${h-s-r} L 0 ${s+r} Q 0 ${s} ${r} ${s} L ${w-s} ${s} Q ${w} ${s} ${w} 0 Z`
                    }
                    if (outline)
                        return `M 0 0 Q 0 ${s} ${s} ${s} L ${w-r-1} ${s} Q ${w-1} ${s} ${w-1} ${s+r} L ${w-1} ${h-s-r} Q ${w-1} ${h-s} ${w-r-1} ${h-s} L ${s} ${h-s} Q 0 ${h-s} 0 ${h}`
                    return `M 0 ${h} L 0 0 Q 0 ${s} ${s} ${s} L ${w-r} ${s} Q ${w} ${s} ${w} ${s+r} L ${w} ${h-s-r} Q ${w} ${h-s} ${w-r} ${h-s} L ${s} ${h-s} Q 0 ${h-s} 0 ${h} Z`
                }

                Shape {
                    visible: root.attachedToBar
                        && (popupWindow.joinedBottom
                            || popupWindow.joinedVertical)
                    anchors.fill: parent
                    ShapePath {
                        strokeWidth: -1
                        fillColor: popupBackground.joinedFill
                        PathSvg { path: popupBackground.joinedPath(false) }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: popupBackground.joinedBorder
                        strokeWidth: popupBackground.joinedBorderWidth
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: popupBackground.joinedPath(true) }
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
                    children: [ root.contentItem ]
                }
            }
        }
}
