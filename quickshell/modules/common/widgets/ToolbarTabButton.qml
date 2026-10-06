import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RippleButton {
    id: root
    required property string materialSymbol
    required property bool current
    horizontalPadding: 10

    implicitHeight: 40
    implicitWidth: implicitContentWidth + horizontalPadding * 2
    buttonRadius: Appearance.inlayMode ? 0 : height / 2

    colBackground:
        Appearance.inlayMode
            ? (current ? Appearance.inlay.insetFill : "transparent")
            : ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
    colBackgroundHover:
        Appearance.inlayMode
            ? (current ? Appearance.inlay.insetFill : Appearance.colors.colLayer2Hover)
            : ColorUtils.transparentize(Appearance.colors.colOnSurface, current ? 1 : 0.95)
    colRipple: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.95)

    background: Rectangle {
        radius: root.buttonEffectiveRadius
        color: root.buttonColor
        border.width:
            Appearance.inlayMode
                ? Appearance.inlay.borderWidth
                : 0
        border.color:
            Appearance.inlayMode
                ? (root.current ? Appearance.colors.colPrimary : Appearance.inlay.borderControl)
                : "transparent"
        Behavior on color {
            MotionColorAnim {
                type: MotionColorAnim.FastEffects
            }
        }
    }

    contentItem: Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            iconSize: 22
            text: root.materialSymbol
            color:
                root.current
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer1
        }
        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color:
                root.current
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer1
        }
    }
}
