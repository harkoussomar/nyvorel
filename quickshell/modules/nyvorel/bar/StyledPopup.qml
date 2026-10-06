import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import QtQuick.Effects

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem

    // prism-v2-phase4ab: transient objects use Prism's semantic island gap.
    property real popupBackgroundMargin:
        Appearance.prismMode
            ? Appearance.prism.islandGap
            : 0

    // Optional overrides. Defaults preserve all existing popups.
    property real popupRadius:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.radius.popup
                : Appearance.rounding.small

    property color popupColor:
        Appearance.inlayMode
            ? Appearance.inlay.surfaceFill
            : Appearance.prismMode
                ? Appearance.prism.transientFill
                : Appearance.colors.colLayer2Base

    property bool showOnHover: true
    property bool forceActive: false

    property bool dismissOnOutsideClick: false

    signal dismissRequested()


    active:
        root.forceActive
        || (
            root.showOnHover
            && root.hoverTarget
            && root.hoverTarget.containsMouse
        )


    component:
        PanelWindow {
            id: popupWindow

            // prism-v2-phase4ab: motion communicates the bar edge that owns the
            // popup. Loader/click-away lifecycle remains unchanged.
            readonly property real prismOriginX:
                !Appearance.prismMode || Appearance.reducedMotion
                    ? 0
                    : Config.options.bar.vertical
                        ? (Config.options.bar.bottom
                            ? Appearance.prism.enterDistance
                            : -Appearance.prism.enterDistance)
                        : 0
            readonly property real prismOriginY:
                !Appearance.prismMode || Appearance.reducedMotion
                    ? 0
                    : !Config.options.bar.vertical
                        ? (Config.options.bar.bottom
                            ? Appearance.prism.enterDistance
                            : -Appearance.prism.enterDistance)
                        : 0

            property real prismMotionX: prismOriginX
            property real prismMotionY: prismOriginY
            property real prismMotionScale:
                Appearance.prismMode && !Appearance.reducedMotion
                    ? Appearance.prism.enterScale
                    : 1
            property real prismMotionOpacity:
                Appearance.prismMode && !Appearance.reducedMotion
                    ? 0
                    : 1

            readonly property int prismTransformOrigin:
                Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Item.Right : Item.Left)
                    : (Config.options.bar.bottom ? Item.Bottom : Item.Top)

            function startPrismEntrance() {
                if (!Appearance.prismMode || Appearance.reducedMotion) {
                    prismMotionX = 0
                    prismMotionY = 0
                    prismMotionScale = 1
                    prismMotionOpacity = 1
                    return
                }

                prismMotionX = prismOriginX
                prismMotionY = prismOriginY
                prismMotionScale = Appearance.prism.enterScale
                prismMotionOpacity = 0
                prismEnterAnimation.restart()
            }

            ParallelAnimation {
                id: prismEnterAnimation
                NumberAnimation { target: popupWindow; property: "prismMotionX"; to: 0; duration: Appearance.prism.enterDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: popupWindow; property: "prismMotionY"; to: 0; duration: Appearance.prism.enterDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: popupWindow; property: "prismMotionScale"; to: 1; duration: Appearance.prism.enterDuration; easing.type: Easing.OutCubic }
                NumberAnimation { target: popupWindow; property: "prismMotionOpacity"; to: 1; duration: Math.round(Appearance.prism.enterDuration * 0.78); easing.type: Easing.OutCubic }
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
                popupWindow.startPrismEntrance()
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
                windows: [ popupWindow ]
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


            mask:
                Region {
                    item: popupBackground
                }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0


            margins {
                left: {
                    if (Config.options.bar.vertical)
                        return Appearance.sizes.verticalBarWidth

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
                        return Appearance.sizes.barHeight

                    return root.QsWindow?.mapFromItem(
                        root.hoverTarget,
                        (
                            root.hoverTarget.height
                            - popupBackground.implicitHeight
                        ) / 2,
                        0
                    ).y
                }

                right:
                    Appearance.sizes.verticalBarWidth

                bottom:
                    Appearance.sizes.barHeight
            }


            // glass-system-v2.3b-shape
            Region {
                id: glassPopupVisibleMask
                item: popupBackground
            }
            HyprlandWindow.visibleMask:
                Config.options.appearance.transparency.enable
                    ? glassPopupVisibleMask
                    : null

            WlrLayershell.namespace:
                "quickshell:popup"

            WlrLayershell.layer:
                WlrLayer.Overlay


            StyledRectangularShadow {
                visible: !Appearance.prismMode && !Appearance.inlayMode
                target: popupBackground
            }

            PrismSurface {
                id: prismPopupSurface
                visible: Appearance.prismMode
                x: popupBackground.x
                y: popupBackground.y
                width: popupBackground.width
                height: popupBackground.height
                depth: Appearance.prism.depthTransient
                surfaceRadius: Appearance.prism.radiusTransient
                opacity: popupWindow.prismMotionOpacity
                scale: popupWindow.prismMotionScale
                transformOrigin: popupWindow.prismTransformOrigin
                transform: Translate {
                    x: popupWindow.prismMotionX
                    y: popupWindow.prismMotionY
                }
            }


            Rectangle {
                id: popupBackground

                readonly property real margin: 12

                anchors {
                    fill: parent

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

                implicitHeight:
                    root.contentItem.implicitHeight
                    + margin * 2

                color:
                    Appearance.prismMode
                        ? "transparent"
                        : root.popupColor

                radius:
                    root.popupRadius

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

                opacity:
                    Appearance.prismMode
                        ? popupWindow.prismMotionOpacity
                        : 1
                scale:
                    Appearance.prismMode
                        ? popupWindow.prismMotionScale
                        : 1
                transformOrigin: popupWindow.prismTransformOrigin
                transform: Translate {
                    x: Appearance.prismMode ? popupWindow.prismMotionX : 0
                    y: Appearance.prismMode ? popupWindow.prismMotionY : 0
                }

                children: [
                    root.contentItem
                ]
            }
        }
}
