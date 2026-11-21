import QtQuick
import qs.modules.common

/**
 * Material 3 expressive style toolbar.
 * https://m3.material.io/components/toolbars
 */
ToolbarFrame {
    id: root

    property bool enableShadow: true
    colBackground: Appearance.m3colors.m3surfaceContainer
    shadow: enableShadow ? toolbarShadow : null

    readonly property Component toolbarShadow: Component {
        StyledRectangularShadow {
            target: root.frameBackground
            anchors.fill: undefined
        }
    }
}
