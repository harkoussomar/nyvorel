pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Controls.Button {
    id: button

    required property string iconName
    property bool selected: false
    property bool showLabel: true
    property bool framed: false
    property bool outerControl: false
    property string tooltip: text
    property color foregroundColor: Appearance.material.textPrimary
    property color iconColor: selected || highlighted ? Appearance.material.accent : foregroundColor

    implicitWidth: Math.max(38, Math.ceil(implicitContentWidth + leftPadding + rightPadding))
    implicitHeight: 36
    padding: Appearance.spacing.md
    leftPadding: padding
    rightPadding: padding
    topPadding: Appearance.spacing.xs
    bottomPadding: topPadding
    topInset: 0
    bottomInset: 0
    hoverEnabled: true
    Accessible.name: text

    background: CaptureSurface {
        id: backdrop

        radius: button.outerControl ? Appearance.radius.bar : Appearance.radius.control
        color: button.outerControl
            ? Qt.tint(backdrop.panelFill, ColorUtils.applyAlpha(Appearance.material.accent,
                button.down ? 0.21 : button.hovered ? 0.13 : 0))
            : button.highlighted || button.selected
            ? ColorUtils.applyAlpha(Appearance.material.accent, button.down ? 0.25 : button.hovered ? 0.21 : 0.15)
            : button.down ? Appearance.material.groupActive
            : button.hovered ? Appearance.material.groupHover
            : button.framed ? Appearance.material.groupFill : "transparent"
        border.width: button.visualFocus ? 2 : button.outerControl || button.framed || button.highlighted ? 1 : 0
        border.color: button.visualFocus ? Appearance.material.accent
            : button.outerControl ? Appearance.material.chromeBorder
            : button.highlighted ? ColorUtils.applyAlpha(Appearance.material.accent, 0.46)
            : Appearance.material.groupBorder
    }

    contentItem: RowLayout {
        spacing: Appearance.spacing.sm

        MaterialSymbol {
            Layout.alignment: Qt.AlignCenter
            text: button.iconName
            iconSize: 18
            color: button.iconColor
        }

        StyledText {
            visible: button.showLabel
            Layout.fillWidth: true
            text: button.text
            color: button.foregroundColor
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideRight
        }
    }

    StyledToolTip {
        text: button.tooltip
        extraVisibleCondition: button.tooltip.length > 0
    }
}
