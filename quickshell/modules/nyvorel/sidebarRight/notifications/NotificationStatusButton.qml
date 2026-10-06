import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

GroupButton {
    id: button
    property string buttonIcon: ""
    property string buttonText: ""

    baseHeight: 36
    baseWidth: content.implicitWidth + 46
    clickedWidth: baseWidth + 6

    buttonRadius: Appearance.inlayMode ? 0 : baseHeight / 2
    buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.rounding.small
    colBackground: Appearance.inlayMode ? Appearance.inlay.insetFill : Appearance.colors.colLayer2
    colBackgroundHover: Appearance.inlayMode ? Appearance.inlay.hoverFill : Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.inlayMode ? Appearance.inlay.pressedFill : Appearance.colors.colLayer2Active
    colBackgroundToggled: Appearance.inlayMode ? Appearance.inlay.selectedFill : Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.inlayMode ? Appearance.inlay.hoverFill : Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: Appearance.inlayMode ? Appearance.inlay.pressedFill : Appearance.colors.colPrimaryActive
    property color colText:
        Appearance.inlayMode
            ? Appearance.colors.colOnLayer1
            : toggled
                ? Appearance.m3colors.m3onPrimary
                : Appearance.colors.colOnLayer1

    background: Rectangle {
        radius: button.radius
        color: button.color
        border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : (button.tabbedTo ? 2 : 0)
        border.color:
            Appearance.inlayMode
                ? (button.toggled ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                : Appearance.colors.colSecondary
    }

    contentItem: Item {
        id: content
        anchors.fill: parent
        implicitWidth: contentRowLayout.implicitWidth
        implicitHeight: contentRowLayout.implicitHeight
        RowLayout {
            id: contentRowLayout
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                visible: buttonIcon !== ""
                text: buttonIcon
                iconSize: Appearance.font.pixelSize.huge
                color: button.colText
            }
            StyledText {
                visible: buttonText !== ""
                text: buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                color: button.colText
            }
        }
    }

}