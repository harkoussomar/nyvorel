import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: pickerButton
    property string label: ""
    property string materialIcon: ""
    property bool iconOnly: false
    property bool filled: false
    readonly property color ink: filled && enabled
        ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
    implicitHeight: 35
    horizontalPadding: 10
    buttonRadius: Appearance.radius.control
    Accessible.name: label
    colBackground: filled && enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
    colBackgroundHover: filled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
    colRipple: filled ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active

    contentItem: RowLayout {
        spacing: 6
        MaterialSymbol {
            text: pickerButton.materialIcon
            iconSize: 16
            color: pickerButton.ink
        }
        StyledText {
            visible: !pickerButton.iconOnly
            text: pickerButton.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: pickerButton.ink
        }
    }

    ToolTip.visible: hovered && iconOnly
    ToolTip.text: label
    ToolTip.delay: 450
}
