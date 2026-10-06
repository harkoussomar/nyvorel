import qs.services
import qs.modules.common
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Services.Notifications

MouseArea {
    id: root


    property var notificationGroup


    property var notifications:
        notificationGroup?.notifications
        ?? []


    property int notificationCount:
        notifications.length


    property bool multipleNotifications:
        notificationCount > 1


    property bool expanded:
        false


    property bool popup:
        false


    property real padding:
        10


implicitHeight:
    root.expanded

        ? row.implicitHeight
            + root.padding * 2

        : root.popup

            ? Math.min(
                300,
                row.implicitHeight
                    + root.padding * 2
            )

            : Math.min(
                80,
                row.implicitHeight
                    + root.padding * 2
            )


    // =========================================================
    // Drag
    // =========================================================

    property real dragConfirmThreshold:
        70


    property real dismissOvershoot:
        20


    property var qmlParent:
        root?.parent?.parent


    property var parentDragIndex:
        qmlParent?.dragIndex


    property var parentDragDistance:
        qmlParent?.dragDistance


    property var dragIndexDiff:
        Math.abs(
            parentDragIndex - index
        )


    property real xOffset:
        dragIndexDiff === 0

            ? parentDragDistance

            : Math.abs(
                parentDragDistance
            ) > dragConfirmThreshold

                ? 0

                : dragIndexDiff === 1

                    ? parentDragDistance * 0.3

                    : dragIndexDiff === 2

                        ? parentDragDistance * 0.1

                        : 0


    function destroyWithAnimation(
        left = false
    ) {
        root.qmlParent.resetDrag();


        background.anchors.leftMargin =
            background.anchors.leftMargin;


        destroyAnimation.left =
            left;


        destroyAnimation.running =
            true;
    }


    // =========================================================
    // Hover timeout
    // =========================================================

    hoverEnabled:
        true


    onContainsMouseChanged: {
        if (!root.popup)
            return;


        if (root.containsMouse) {
            root.notifications.forEach(
                (notif) => {
                    Notifications.pauseTimeout(
                        notif.notificationId
                    );
                }
            );

        } else {
            root.notifications.forEach(
                (notif) => {
                    Notifications.resumeTimeout(
                        notif.notificationId
                    );
                }
            );
        }
    }


    // =========================================================
    // Dismiss animation
    // =========================================================

    SequentialAnimation {
        id: destroyAnimation


        property bool left:
            true


        running:
            false


        MotionAnim {
            target:
                background.anchors

            property:
                "leftMargin"

            to:
                (
                    root.width
                    + root.dismissOvershoot
                )
                * (
                    destroyAnimation.left
                        ? -1
                        : 1
                )

            type:
                MotionAnim.FastSpatial
        }


        onFinished: {
            root.notifications.forEach(
                (notif) => {
                    Qt.callLater(
                        () => {
                            Notifications
                                .discardNotification(
                                    notif.notificationId
                                );
                        }
                    );
                }
            );
        }
    }


    // =========================================================
    // Expand
    // =========================================================

    function toggleExpanded() {
        if (expanded)
            implicitHeightAnim.enabled = true;
        else
            implicitHeightAnim.enabled = false;


        root.expanded =
            !root.expanded;
    }


    // =========================================================
    // Drag manager
    // =========================================================

    DragManager {
        id: dragManager


        anchors.fill:
            parent


        interactive:
            !expanded


        automaticallyReset:
            false


        acceptedButtons:
            Qt.LeftButton
            | Qt.RightButton
            | Qt.MiddleButton


        onPressed: {
            if (
                mouse.button
                === Qt.RightButton
            ) {
                root.toggleExpanded();
            }
        }


        onClicked: (mouse) => {
            if (
                mouse.button
                === Qt.MiddleButton
            ) {
                root.destroyWithAnimation();
                return;
            }

            if (
                mouse.button
                === Qt.LeftButton
            ) {
                const latestNotification =
                    root.notifications[
                        root.notificationCount - 1
                    ];

                if (
                    latestNotification
                    && Notifications
                        .attemptInvokeDefaultAction(
                            latestNotification
                                .notificationId
                        )
                ) {
                    GlobalStates.sidebarRightOpen =
                        false;
                }
            }
        }


        onDraggingChanged: {
            if (dragging) {
                root.qmlParent.dragIndex =
                    root.index
                    ?? root.parent.children
                        .indexOf(root);
            }
        }


        onDragDiffXChanged: {
            root.qmlParent.dragDistance =
                dragDiffX;
        }


        onDragReleased: (
            diffX,
            diffY
        ) => {
            if (
                Math.abs(diffX)
                > root.dragConfirmThreshold
            ) {
                root.destroyWithAnimation(
                    diffX < 0
                );

            } else {
                dragManager.resetDrag();
            }
        }
    }


    StyledRectangularShadow {
        target:
            background

        visible:
            root.popup
    }


    Rectangle {
        id: background


        anchors.left:
            parent.left


        width:
            parent.width


        // fluid-notification-readability-v1
        // Toasts can appear over arbitrary text, browsers and terminals.
        // Keep Fluid blur/translucency, but give popup groups an 84%-dense
        // neutral substrate so background content cannot compete with text.
        color:
            root.popup

                ? (
                    Appearance.fluidMode

                        ? ColorUtils.transparentize(
                            Appearance
                                .colors
                                .fluidLayer2Tone,

                            0.16
                        )

                        : Appearance
                            .colors
                            .colBackgroundSurfaceContainer
                )

                : Appearance
                    .colors
                    .colLayer2


        radius:
            Appearance.rounding.normal


        border.width:
            root.popup
            && Appearance.fluidMode
                ? 1
                : 0


        border.color:
            root.popup
            && Appearance.fluidMode

                ? Appearance
                    .colors
                    .fluidBorderMedium

                : "transparent"


        anchors.leftMargin:
            root.xOffset


        Behavior on anchors.leftMargin {
            enabled:
                !dragManager.dragging

            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }


        clip:
            true


        implicitHeight:
            root.expanded

                 ? row.implicitHeight
            + root.padding * 2

        : root.popup

            // Popup content already limits how many
            // notification items are rendered.
            // Let the actual visible content determine
            // the card height so ListView geometry
            // stays correct.
            ? row.implicitHeight
                + root.padding * 2

            : Math.min(
                80,
                row.implicitHeight
                    + root.padding * 2
            )


        Behavior on implicitHeight {
            id: implicitHeightAnim

            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }


        RowLayout {
            id: row


            anchors {
                top:
                    parent.top

                left:
                    parent.left

                right:
                    parent.right

                margins:
                    root.padding
            }


            spacing:
                10


            NotificationAppIcon {
                // Expanded notification items may render their
                // own image/avatar. Hide the group icon only when
                // that would otherwise create a duplicate image.
                visible: {
                    if (!root.expanded)
                        return true;

                    const itemImagesWillShow =
                        (
                            root.popup
                            || root.notificationCount > 1
                        )
                        && root.notifications.some(
                            (notification) =>
                                (
                                    notification
                                        ?.image
                                    ?? ""
                                ) !== ""
                        );

                    return !itemImagesWillShow;
                }


                Layout.alignment:
                    Qt.AlignTop


                Layout.fillWidth:
                    false


                image:
                    root.multipleNotifications

                        ? ""

                        : root.notificationGroup
                            ?.notifications[0]
                            ?.image
                            ?? ""


                appIcon:
                    root.notificationGroup
                        ?.appIcon


                summary:
                    root.notificationGroup
                        ?.notifications[
                            root.notificationCount - 1
                        ]
                        ?.summary


                urgency:
                    root.notifications.some(
                        (notification) =>
                            notification.urgency
                            === NotificationUrgency
                                .Critical
                                .toString()
                    )

                        ? NotificationUrgency
                            .Critical

                        : NotificationUrgency
                            .Normal
            }


            ColumnLayout {
                Layout.fillWidth:
                    true


                spacing:
                    root.expanded
                        ? 5
                        : 2


                Behavior on spacing {
                    animation:
                        Appearance
                            .animation
                            .elementMoveFast
                            .numberAnimation
                            .createObject(this)
                }


                // =================================================
                // Header
                // =================================================

                Item {
                    id: topRow


                    Layout.fillWidth:
                        true


                    property real fontSize:
                        Appearance
                            .font
                            .pixelSize
                            .smaller


                    property bool showAppName:
                        root.popup
                        || root.multipleNotifications


                    implicitHeight:
                        Math.max(
                            topTextRow.implicitHeight,
                            expandButton.implicitHeight
                        )


                    RowLayout {
                        id: topTextRow


                        anchors {
                            left:
                                parent.left

                            right:
                                expandButton.left

                            verticalCenter:
                                parent.verticalCenter
                        }


                        spacing:
                            5


                        StyledText {
                            id: appName


                            Layout.fillWidth:
                                true


                            elide:
                                Text.ElideRight


                            text:
                                (
                                    topRow.showAppName

                                        ? root.notificationGroup
                                            ?.appName

                                        : root.notificationGroup
                                            ?.notifications[0]
                                            ?.summary
                                )
                                || ""


                            font.pixelSize:
                                topRow.showAppName

                                    ? topRow.fontSize

                                    : Appearance
                                        .font
                                        .pixelSize
                                        .small


                            font.weight:
                                topRow.showAppName
                                    ? Font.Medium
                                    : Font.DemiBold


                            color:
                                topRow.showAppName

                                    ? Appearance
                                        .colors
                                        .colSubtext

                                    : Appearance
                                        .colors
                                        .colOnLayer2
                        }


                        StyledText {
                            Layout.rightMargin:
                                8


                            horizontalAlignment:
                                Text.AlignLeft


                            text:
                                NotificationUtils
                                    .getFriendlyNotifTimeString(
                                        root.notificationGroup
                                            ?.time
                                    )


                            font.pixelSize:
                                topRow.fontSize


                            color:
                                Appearance
                                    .colors
                                    .colSubtext
                        }
                    }


                    NotificationGroupExpandButton {
                        id: expandButton


                        anchors {
                            right:
                                parent.right

                            verticalCenter:
                                parent.verticalCenter
                        }


                        count:
                            root.notificationCount


                        expanded:
                            root.expanded


                        showNewLabel:
                            root.popup
                            && root.notificationCount > 1


                        fontSize:
                            topRow.fontSize


                        onClicked: {
                            root.toggleExpanded();
                        }


                        altAction:
                            () => {
                                root.toggleExpanded();
                            }


                        StyledToolTip {
                            text:
                                Translation.tr(
                                    "Tip: right-clicking a group\nalso expands it"
                                )
                        }
                    }
                }


                // =================================================
                // Notifications
                // =================================================

                StyledListView {
                    id: notificationsColumn


                    implicitHeight:
                        contentHeight


                    Layout.fillWidth:
                        true


                    spacing:
                        root.expanded
                            ? 5
                            : 3


                    interactive:
                        false


                    Behavior on spacing {
                        animation:
                            Appearance
                                .animation
                                .elementMoveFast
                                .numberAnimation
                                .createObject(this)
                    }

model: ScriptModel {
    values: {
        const newestFirst =
            root.notifications
                .slice()
                .reverse();


        if (root.expanded)
            return newestFirst;


        // Toast:
        // newest two items are enough to show
        // that this is a stack.
        if (root.popup)
            return newestFirst.slice(
                0,
                2
            );


        // Sidebar preview.
        return newestFirst.slice(
            0,
            2
        );
    }
}


                    delegate: NotificationItem {
                        required property int index
                        required property var modelData


                        notificationObject:
                            modelData


                        expanded:
                            root.expanded


                        popup:
                            root.popup


                        onlyNotification:
                            root.notificationCount === 1
                            && !root.popup

opacity: {
    if (
        root.expanded
        || !root.popup
    ) {
        return 1;
    }


    // Newest notification.
    if (index === 0)
        return 1;


    // Previous notification in the stack.
    if (index === 1)
        return 0.68;


    return 1;
}


              visible:
                  root.expanded
                  || (
                      root.popup
                      && index < 2
                  )
                  || (
                      !root.popup
                      && index < 2
                  )


                        anchors {
                            left:
                                parent?.left

                            right:
                                parent?.right
                        }
                    }
                }
            }
        }
    }
}