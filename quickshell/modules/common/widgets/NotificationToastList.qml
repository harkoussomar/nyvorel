import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import Quickshell

StyledListView {
    id: root

    spacing:
        Appearance.prismMode
            ? Appearance.prism.islandGap
            : 8

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
                        Appearance.inlayMode
                            ? Appearance.inlay.enterDistance
                            : Appearance.prismMode
                                ? Appearance.prism.enterDistance
                                : 28

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
                        Appearance.inlayMode
                            ? 1
                            : Appearance.prismMode && !Appearance.reducedMotion
                                ? Appearance.prism.enterScale
                                : 1

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
                        Appearance.inlayMode
                            ? Appearance.inlay.enterDistance
                            : Appearance.prismMode
                                ? Appearance.prism.enterDistance
                                : 28

                    type:
                        MotionAnim.FastSpatial
                }

                // notification-opacity-stability-v1: keep delegate opacity at 1; position/scale own the transition.

                MotionAnim {
                    properties:
                        "scale"

                    to:
                        Appearance.inlayMode
                            ? 1
                            : Appearance.prismMode && !Appearance.reducedMotion
                                ? 0.985
                                : 1

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
