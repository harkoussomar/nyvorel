pragma ComponentBehavior: Bound

import qs.modules.common.widgets
import qs.services

import QtQuick
import Quickshell

StyledListView {
    id: root


    property bool popup:
        false


    // Avoid creating a huge toast wall.
    property int popupMaxGroups:
        3


    spacing:
        root.popup
            ? 6
            : 3


    model:
        ScriptModel {
            values: {
                if (!root.popup) {
                    return Notifications
                        .appNameList;
                }


                return Notifications
                    .popupAppNameList
                    .slice(
                        0,
                        root.popupMaxGroups
                    );
            }
        }


    delegate:
        NotificationGroup {
            required property int index
            required property var modelData


            popup:
                root.popup


            width:
                ListView.view.width


            notificationGroup:
                root.popup

                    ? Notifications
                        .popupGroupsByAppName[
                            modelData
                        ]

                    : Notifications
                        .groupsByAppName[
                            modelData
                        ]
        }

    add:
        Transition {
            ParallelAnimation {
                MotionAnim {
                    properties: "x"
                    from: 32
                    to: 0
                    type: MotionAnim.FastSpatial
                }

                MotionAnim {
                    properties: "opacity"
                    from: 0
                    to: 1
                    type: MotionAnim.DefaultEffects
                }
            }
        }

    addDisplaced:
        Transition {
            MotionAnim {
                properties: "y"
                type: MotionAnim.FastSpatial
            }
        }

    removeDisplaced:
        Transition {
            MotionAnim {
                properties: "y"
                type: MotionAnim.FastSpatial
            }
        }
}