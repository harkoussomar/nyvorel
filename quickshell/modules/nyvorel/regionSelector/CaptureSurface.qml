import QtQuick
import qs.modules.common
import qs.modules.common.functions

Rectangle {
    readonly property color panelFill: ColorUtils.applyAlpha(Appearance.material.chromeFill,
        Config.options.appearance.transparency.enable ? Math.max(0.82, Appearance.material.chromeFill.a) : 1)

    radius: Appearance.radius.bar
    color: panelFill
    border.color: Appearance.material.chromeBorder
}
