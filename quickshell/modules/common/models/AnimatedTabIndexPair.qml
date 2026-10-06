import QtQuick
import qs.modules.common.widgets

// idx1 is the leading edge; idx2 trails behind to create the elastic
// workspace-indicator stretch. Phase 2E keeps the same architecture but
// routes both edges through the semantic motion system.
QtObject {
    id: root

    required property int index

    property real idx1: index
    property real idx2: index

    property int idx1Duration: 160
    property int idx2Duration: 420

    Behavior on idx1 {
        MotionAnim {
            type: MotionAnim.FastSpatial
            duration: root.idx1Duration
        }
    }

    Behavior on idx2 {
        MotionAnim {
            type: MotionAnim.DefaultSpatial
            duration: root.idx2Duration
        }
    }
}
