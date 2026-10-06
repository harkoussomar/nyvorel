import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

TextField {
    id: filterField

    property alias colBackground: background.color

    Layout.fillHeight: true
    implicitWidth: 200
    padding: 10

    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer1
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer

    background: Rectangle {
        id: background
        color:
            Appearance.inlayMode
                ? "transparent"
                : Appearance.colors.colLayer1
        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.rounding.full
        border.width:
            Appearance.inlayMode
                ? Appearance.inlay.borderWidth
                : 0
        border.color:
            Appearance.inlayMode
                ? Appearance.inlay.borderControl
                : "transparent"
    }
}
