import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * Recreation of GTK revealer. Expects one single child.
 */
Item {
    id: root
    property bool reveal
    property bool vertical: false
    clip: true

    implicitWidth: (reveal || vertical) ? childrenRect.width : 0
    implicitHeight: (reveal || !vertical) ? childrenRect.height : 0
    visible: reveal || (width > 0 && height > 0)

    Behavior on implicitWidth {
        enabled: !vertical

        MotionAnim {
            type: MotionAnim.FastSpatial
        }
    }

    Behavior on implicitHeight {
        enabled: vertical

        MotionAnim {
            type: MotionAnim.FastSpatial
        }
    }
}
