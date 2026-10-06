import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button

    property string buttonText: ""
    property string tooltipText: ""
    property string accessibleName: buttonText
    property bool forceCircle: false

    implicitHeight: 30
    implicitWidth:
        forceCircle
            ? implicitHeight
            : contentItem.implicitWidth + 8 * 2

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name:
        accessibleName.length > 0
            ? accessibleName
            : buttonText

    buttonRadius:
        forceCircle
            ? height / 2
            : Appearance.radius.control
    buttonRadiusPressed: buttonRadius

    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    contentItem: StyledText {
        text: button.buttonText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnLayer1
    }

    StyledToolTip {
        text: button.tooltipText
        extraVisibleCondition:
            button.hovered
            && button.tooltipText.length > 0
        delay: 450
    }
}
