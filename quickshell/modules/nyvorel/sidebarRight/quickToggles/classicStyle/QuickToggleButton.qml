import qs.modules.common
import qs.modules.common.widgets
import QtQuick

GroupButton {
    id: button
    property string buttonIcon
    baseWidth: 40
    baseHeight: 40
    clickedWidth: baseWidth + 20
    toggled: false
    buttonRadius:
        Appearance.inlayMode
            ? 0
            : (altAction && toggled)
                ? Appearance?.rounding.normal
                : Math.min(baseHeight, baseWidth) / 2
    buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance?.rounding?.small

    colBackground: Appearance.inlayMode ? Appearance.inlay.insetFill : "transparent"
    colBackgroundHover: Appearance.inlayMode ? Appearance.inlay.hoverFill : Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.inlayMode ? Appearance.inlay.pressedFill : Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.inlayMode ? Appearance.inlay.selectedFill : Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.inlayMode ? Appearance.inlay.hoverFill : Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: Appearance.inlayMode ? Appearance.inlay.pressedFill : Appearance.colors.colPrimaryActive

    background: Rectangle {
        radius: button.radius
        color: button.color
        border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : (button.tabbedTo ? 2 : 0)
        border.color:
            Appearance.inlayMode
                ? (button.toggled ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                : Appearance.colors.colSecondary
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        iconSize: 22
        fill: toggled ? 1 : 0
        color:
            Appearance.inlayMode
                ? Appearance.colors.colOnLayer1
                : toggled
                    ? Appearance.m3colors.m3onPrimary
                    : Appearance.colors.colOnLayer1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: buttonIcon

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
