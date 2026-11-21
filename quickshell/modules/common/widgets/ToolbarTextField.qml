import QtQuick
import qs.modules.common

ToolbarInput {
    colBackground: Appearance.colors.colLayer1
    fieldRadius: Appearance.rounding.full

    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer1
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
}
