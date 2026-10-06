import QtQuick

import qs.modules.common
import qs.modules.common.widgets

Loader {
    id: root
    property bool shown: true
    property alias fade: opacityBehavior.enabled
    property alias animation: opacityBehavior.animation
    opacity: shown ? 1 : 0
    visible: opacity > 0
    active: opacity > 0

    Behavior on opacity {
        id: opacityBehavior

        MotionAnim {
            type: MotionAnim.DefaultEffects
        }
    }
}
