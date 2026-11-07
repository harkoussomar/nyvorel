import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import Quickshell

StyledListView {
    id: root

    spacing:
         8

    interactive:
        false

    model:
        ScriptModel {
            values:
                Notifications
                    .popupQueue
                    .slice(
                        0,
                        Notifications
                            .popupMaxVisible
                    )
        }

    delegate:
        NotificationToast {
            required property int index
            required property var modelData

            notificationObject:
                modelData

            width:
                ListView.view.width
        }

    add:
        Transition {
            ParallelAnimation {
                MotionAnim {
                    properties:
                        "x"

                    from:
                          28

                    to:
                        0

                    type:
                        MotionAnim.FastSpatial
                }

                // notification-opacity-stability-v1: keep delegate opacity at 1; position/scale own the transition.

                MotionAnim {
                    properties:
                        "scale"

                    from:
                          1

                    to:
                        1

                    type:
                        MotionAnim.FastSpatial
                }
            }
        }

    addDisplaced:
        Transition {
            MotionAnim {
                properties:
                    "y"

                type:
                    MotionAnim.FastSpatial
            }
        }

    remove:
        Transition {
            ParallelAnimation {
                MotionAnim {
                    properties:
                        "x"

                    to:
                          28

                    type:
                        MotionAnim.FastSpatial
                }

                // notification-opacity-stability-v1: keep delegate opacity at 1; position/scale own the transition.

                MotionAnim {
                    properties:
                        "scale"

                    to:
                          1

                    type:
                        MotionAnim.FastEffects
                }
            }
        }

    removeDisplaced:
        Transition {
            MotionAnim {
                properties:
                    "y"

                type:
                    MotionAnim.FastSpatial
            }
        }
}
