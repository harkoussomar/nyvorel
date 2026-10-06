import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property bool usePercentTooltip: true
    property real from: slider.from
    property real to: slider.to
    property real textWidth: 170
    readonly property string displayValue: usePercentTooltip
        ? `${Math.round(((value - from) / Math.max(0.0001, to - from)) * 100)}%`
        : `${Math.round(value)}`

    RowLayout {
        id: row
        spacing: 10

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            Layout.preferredWidth: root.textWidth
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
    
    StyledSlider {
        id: slider
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: root.from
        to: root.to
    }

    StyledText {
        Layout.preferredWidth: 54
        horizontalAlignment: Text.AlignRight
        text: root.displayValue
        color: Appearance.colors.colSubtext
        font.family: Appearance.font.family.numbers
        font.variableAxes: Appearance.font.variableAxes.numbers
    }
}