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

    readonly property color effectiveDialogColor:
        !root.interfaceStyleAware
            ? Appearance.m3colors.m3surfaceContainerHigh
            : Appearance.inlayMode
                ? Appearance.inlay.surfaceFill
                : Appearance.prismMode
                    ? Appearance.prism.modalFill
                    : Appearance.fluidMode
                        ? Appearance.material.modalFill
                        : Appearance.m3colors.m3surfaceContainerHigh

    readonly property color effectiveDialogBorderColor:
        !root.interfaceStyleAware
            ? "transparent"
            : Appearance.inlayMode
                ? Appearance.inlay.borderSection
                : Appearance.prismMode
                    ? Appearance.prism.borderStrong
                    : Appearance.fluidMode
                        ? Appearance.material.modalBorder
                        : Appearance.colors.colOutlineVariant

    readonly property int effectiveDialogBorderWidth:
        root.interfaceStyleAware ? 1 : 0

    readonly property real effectiveDialogRadius:
        !root.interfaceStyleAware
            ? Appearance.rounding.large
            : Appearance.inlayMode
                ? Appearance.inlay.radius
                : Appearance.prismMode
                    ? Appearance.prism.radiusModal
                    : Appearance.radius.modal

    readonly property color effectiveScrimColor:
        !root.interfaceStyleAware
            ? Appearance.colors.colScrim
            : Appearance.fluidMode
                ? ColorUtils.transparentize(Appearance.colors.colScrim, 0.72)
                : Appearance.prismMode
                    ? ColorUtils.transparentize(Appearance.colors.colScrim, 0.62)
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
        dialogBackground.implicitHeight = show ? backgroundHeight : 0
    }

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    MouseArea { // Clicking outside the dialog should dismiss
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.dismiss()
    }

    Rectangle {
        id: dialogBackground
        anchors.horizontalCenter: parent.horizontalCenter
        radius: root.effectiveDialogRadius
        color: root.effectiveDialogColor
        border.width: root.effectiveDialogBorderWidth
        border.color: root.effectiveDialogBorderColor
        
        property real targetY: root.height / 2 - root.backgroundHeight / 2
        y: root.show ? targetY : (targetY - root.backgroundAnimationMovementDistance)
        implicitWidth: root.backgroundWidth
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
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: dialogBackground.radius
            }
            spacing: 16
            opacity: root.show ? 1 : 0
            Behavior on opacity {
                MotionAnim {
                    type: MotionAnim.DefaultEffects
                }
            }

        }
    }
}
