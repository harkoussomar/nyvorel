import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool show: false
    default property alias data: contentColumn.data
    property real backgroundHeight: dialogBackground.implicitHeight
    property real backgroundWidth: 350
    property real backgroundAnimationMovementDistance: 60

    property bool interfaceStyleAware: false
    property bool atlasStyle: false

    readonly property color effectiveDialogColor:
        root.atlasStyle
            ? ColorUtils.applyAlpha(
                ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82),
                1)
            : !root.interfaceStyleAware
            ? Appearance.m3colors.m3surfaceContainerHigh
            : Appearance.fluidMode
                ? Appearance.material.modalFill
                : Appearance.m3colors.m3surfaceContainerHigh

    readonly property color effectiveDialogBorderColor:
        root.atlasStyle
            ? Appearance.colors.colLayer0Border
            : !root.interfaceStyleAware
            ? "transparent"
            : Appearance.fluidMode
                ? Appearance.material.modalBorder
                : Appearance.colors.colOutlineVariant

    readonly property int effectiveDialogBorderWidth:
        (root.atlasStyle || root.interfaceStyleAware) ? 1 : 0

    readonly property real effectiveDialogRadius:
        root.atlasStyle
            ? 13
            : !root.interfaceStyleAware
            ? Appearance.rounding.large
            : Appearance.radius.modal

    readonly property color effectiveScrimColor:
        root.atlasStyle
            ? "transparent"
            : !root.interfaceStyleAware
            ? Appearance.colors.colScrim
            : Appearance.fluidMode
                ? ColorUtils.transparentize(Appearance.colors.colScrim, 0.72)
                : Appearance.colors.colScrim
    
    signal dismiss()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        }
    }

    color: root.show ? root.effectiveScrimColor : ColorUtils.transparentize(root.effectiveScrimColor)
    Behavior on color {
        MotionColorAnim {
            type: MotionColorAnim.DefaultEffects
        }
    }
    visible: dialogBackground.implicitHeight > 0

    onShowChanged: {
        dialogBackground.implicitHeight = show ? (atlasStyle ? Math.min(backgroundHeight, Math.max(0, height - 20)) : backgroundHeight) : 0
    }
    onBackgroundHeightChanged: {
        if (atlasStyle && show)
            dialogBackground.implicitHeight = Math.min(backgroundHeight, Math.max(0, height - 20))
    }
    onHeightChanged: {
        if (atlasStyle && show)
            dialogBackground.implicitHeight = Math.min(backgroundHeight, Math.max(0, height - 20))
    }

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    MouseArea { // Clicking outside the dialog should dismiss
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.dismiss()
        onWheel: (wheel) => { if (root.atlasStyle) wheel.accepted = true }
    }

    Rectangle {
        id: dialogBackground
        x: root.atlasStyle && root.width > 650
            ? Math.max(10, root.width - width - 14)
            : Math.max(10, (root.width - width) / 2)
        radius: root.effectiveDialogRadius
        color: root.effectiveDialogColor
        border.width: root.effectiveDialogBorderWidth
        border.color: root.effectiveDialogBorderColor
        
        property real targetY: root.atlasStyle
            ? Math.max(10, (root.height - dialogBackground.implicitHeight) / 2)
            : root.height / 2 - root.backgroundHeight / 2
        y: root.show ? targetY : (targetY - root.backgroundAnimationMovementDistance)
        implicitWidth: root.atlasStyle ? Math.min(root.backgroundWidth, Math.max(0, root.width - 20)) : root.backgroundWidth
        implicitHeight: contentColumn.implicitHeight + dialogBackground.radius * 2
        Behavior on implicitHeight {
            MotionAnim {
                type: root.show ? MotionAnim.DefaultSpatial : MotionAnim.FastSpatial
            }
        }
        Behavior on y {
            MotionAnim {
                type: root.show ? MotionAnim.DefaultSpatial : MotionAnim.FastSpatial
            }
        }

        MouseArea { // So clicking inside the dialog won't dismiss
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onWheel: (wheel) => { if (root.atlasStyle) wheel.accepted = true }
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: root.atlasStyle ? 18 : dialogBackground.radius
            }
            spacing: root.atlasStyle ? 12 : 16
            opacity: root.show ? 1 : 0
            Behavior on opacity {
                MotionAnim {
                    type: MotionAnim.DefaultEffects
                }
            }

        }
    }
}
