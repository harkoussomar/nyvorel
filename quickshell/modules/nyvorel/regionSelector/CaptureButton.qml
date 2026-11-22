pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Controls.Button {
    id: button

    required property string iconName
    property bool selected: false
    property bool showLabel: true
    property string tooltip: text
    property color foregroundColor: selected ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface

    implicitWidth: Math.max(38, buttonContent.implicitWidth + 16)
    implicitHeight: 38
    padding: 8
    Accessible.name: text

    background: Rectangle {
        radius: Appearance.radius.control
        color: button.selected ? Appearance.colors.colSecondaryContainer
            : button.hovered || button.down ? Appearance.m3colors.m3surfaceContainerHigh : "transparent"
        border.width: button.visualFocus || button.selected ? 1 : 0
        border.color: button.visualFocus ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
    }

    contentItem: RowLayout {
        id: buttonContent
        spacing: 6

        MaterialSymbol {
            Layout.alignment: Qt.AlignCenter
            text: button.iconName
            iconSize: 19
            color: button.foregroundColor
        }

        StyledText {
            visible: button.showLabel
            text: button.text
            color: button.foregroundColor
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    StyledToolTip {
        text: button.tooltip
        extraVisibleCondition: button.tooltip.length > 0
    }
}
