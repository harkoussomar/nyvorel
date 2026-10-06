import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root

    property string iconName: ""
    property string label: ""
    property string accessibleName: label
    property bool prominent: false

    implicitHeight: 30
    implicitWidth: contentRow.implicitWidth + 14

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName

    buttonRadius: Appearance.radius.control
    buttonRadiusPressed: Appearance.radius.control

    colBackground:
        prominent
            ? Appearance.colors.colSecondaryContainer
            : Appearance.colors.colLayer2
    colBackgroundHover:
        prominent
            ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colLayer2Hover
    colRipple:
        prominent
            ? Appearance.colors.colSecondaryContainerActive
            : Appearance.colors.colLayer2Active

    contentItem: RowLayout {
        id: contentRow

        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            visible: root.iconName.length > 0
            text: root.iconName
            iconSize: 15
            color:
                root.prominent
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnLayer2
        }

        StyledText {
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            color:
                root.prominent
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnLayer2
        }
    }
}
