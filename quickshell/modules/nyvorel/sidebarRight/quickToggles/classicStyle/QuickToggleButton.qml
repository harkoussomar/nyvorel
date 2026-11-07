import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

GroupButton {
    id: button
    property string buttonIcon
    baseWidth: 40
    baseHeight: 40
    clickedWidth: baseWidth + 20
    toggled: false
    buttonRadius: 9
    buttonRadiusPressed: 9

    colBackground: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colBackgroundToggled: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.72)
    colBackgroundToggledHover: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1Hover, 0.64)
    colBackgroundToggledActive: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1Active, 0.64)

    background: Rectangle {
        radius: button.radius
        color: button.color
        border.width: button.tabbedTo ? 2 : 1
        border.color: button.tabbedTo ? Appearance.colors.colSecondary
            : button.toggled ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.53)
            : Appearance.colors.colLayer0Border
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        iconSize: 22
        fill: toggled ? 1 : 0
        color: toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: buttonIcon

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
