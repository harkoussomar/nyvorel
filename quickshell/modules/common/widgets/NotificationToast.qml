import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Layouts

import Quickshell.Services.Notifications

Item {
    id: root

    required property var notificationObject

    property real padding:
        12

    property real dragConfirmThreshold:
        70

    property real dismissOvershoot:
        24

    property real settledX:
        0

    readonly property string appNameText:
        (
            root.notificationObject
            && root.notificationObject.appName
        )
            ? root.notificationObject.appName
            : "Notification"

    readonly property string summaryText:
        (
            root.notificationObject
            && root.notificationObject.summary
        )
            ? root.notificationObject.summary
            : ""

    readonly property string bodyText: {
        if (!root.notificationObject)
            return "";

        return NotificationUtils
            .processNotificationBody(
                root.notificationObject.body || "",
                root.notificationObject.appName
                    || root.notificationObject.summary
                    || ""
            )
            .replace(
                /\n/g,
                "<br/>"
            );
    }

    readonly property bool isCritical:
        root.notificationObject
        && root.notificationObject.urgency
            === NotificationUrgency
                .Critical
                .toString()

    readonly property var displayActions: {
        if (!root.notificationObject)
            return [];

        const actions =
            root.notificationObject.actions
            || [];

        return actions
            .filter(
                (action) =>
                    action.identifier !== "default"
                    && (
                        action.text
                        || ""
                    ).trim().length > 0
            )
            .slice(
                0,
                2
            );
    }

    implicitHeight:
        card.implicitHeight

    // One flat ListView delegate owns one concrete height. Height itself is
    // never animated; content replacement reflows immediately and atomically.
    height:
        implicitHeight


    function dismissWithMotion(left = false) {
        if (dismissAnimation.running)
            return;

        dismissAnimation.left =
            left;

        dismissAnimation.restart();
    }


    HoverHandler {
        id: hoverHandler

        onHoveredChanged: {
            if (!root.notificationObject)
                return;

            if (hovered) {
                Notifications.pauseTimeout(
                    root.notificationObject
                        .notificationId
                );

            } else {
                Notifications.resumeTimeout(
                    root.notificationObject
                        .notificationId
                );
            }
        }
    }


    DragManager {
        id: dragManager

        anchors.fill:
            parent

        acceptedButtons:
            Qt.LeftButton
            | Qt.MiddleButton

        automaticallyReset:
            false

        onClicked: (mouse) => {
            if (!root.notificationObject)
                return;

            if (
                mouse.button
                === Qt.MiddleButton
            ) {
                Notifications.discardNotification(
                    root.notificationObject
                        .notificationId
                );
                return;
            }


            if (
                mouse.button
                === Qt.LeftButton
            ) {
                Notifications.attemptInvokeDefaultAction(
                    root.notificationObject
                        .notificationId
                );
            }
        }

        onDragDiffXChanged: {
            root.settledX =
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
                root.dismissWithMotion(
                    diffX < 0
                );

            } else {
                dragManager.resetDrag();
                root.settledX =
                    0;
            }
        }
    }


    Behavior on settledX {
        enabled:
            !dragManager.dragging
            && !dismissAnimation.running

        MotionAnim {
            type:
                MotionAnim.FastSpatial
        }
    }


    SequentialAnimation {
        id: dismissAnimation

        property bool left:
            false

        MotionAnim {
            target:
                root

            property:
                "settledX"

            to:
                (
                    root.width
                    + root.dismissOvershoot
                )
                * (
                    dismissAnimation.left
                        ? -1
                        : 1
                )

            type:
                MotionAnim.FastSpatial
        }

        onFinished: {
            if (!root.notificationObject)
                return;

            Notifications.discardNotification(
                root.notificationObject
                    .notificationId
            );
        }
    }


    StyledRectangularShadow {
        visible: !Appearance.prismMode && !Appearance.inlayMode
        target:
            card
    }

    PrismSurface {
        visible: Appearance.prismMode
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        depth: Appearance.prism.depthTransient
        surfaceRadius: Appearance.prism.radiusTransient
    }


    Rectangle {
        id: card

        x:
            root.settledX

        width:
            root.width

        implicitHeight:
            contentColumn.implicitHeight
            + root.padding * 2

        height:
            implicitHeight

        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusTransient
                    : Appearance.rounding.normal

        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.inlayMode
                    ? Appearance.inlay.surfaceFill
                    : Appearance.fluidMode

                    ? ColorUtils.transparentize(
                        Appearance
                            .colors
                            .fluidLayer2Tone,

                        0.16
                    )

                    : Appearance
                        .colors
                        .colBackgroundSurfaceContainer

        border.width:
            Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
        border.color:
            Appearance.inlayMode
                ? (root.isCritical ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                : "transparent"


        ColumnLayout {
            id: contentColumn

            anchors.fill:
                parent

            anchors.margins:
                root.padding

            spacing:
                7


            RowLayout {
                Layout.fillWidth:
                    true

                spacing:
                    10


                NotificationAppIcon {
                    Layout.alignment:
                        Qt.AlignTop

                    appIcon:
                        root.notificationObject
                            ? root.notificationObject.appIcon
                            : ""

                    image:
                        root.notificationObject
                            ? root.notificationObject.image
                            : ""

                    summary:
                        root.summaryText

                    urgency:
                        root.isCritical
                            ? NotificationUrgency.Critical
                            : NotificationUrgency.Normal
                }


                ColumnLayout {
                    Layout.fillWidth:
                        true

                    spacing:
                        3


                    RowLayout {
                        Layout.fillWidth:
                            true

                        spacing:
                            8


                        StyledText {
                            Layout.fillWidth:
                                true

                            text:
                                root.appNameText

                            font.pixelSize:
                                Appearance
                                    .font
                                    .pixelSize
                                    .smaller

                            font.weight:
                                Font.Medium

                            color:
                                Appearance
                                    .colors
                                    .colSubtext

                            elide:
                                Text.ElideRight

                            maximumLineCount:
                                1
                        }


                        StyledText {
                            text:
                                root.notificationObject

                                    ? NotificationUtils
                                        .getFriendlyNotifTimeString(
                                            root.notificationObject
                                                .time
                                        )

                                    : ""

                            font.pixelSize:
                                Appearance
                                    .font
                                    .pixelSize
                                    .smaller

                            color:
                                Appearance
                                    .colors
                                    .colSubtext
                        }
                    }


                    StyledText {
                        Layout.fillWidth:
                            true

                        visible:
                            text.length > 0

                        text:
                            root.summaryText

                        font.pixelSize:
                            Appearance
                                .font
                                .pixelSize
                                .small

                        font.weight:
                            Font.DemiBold

                        color:
                            Appearance
                                .colors
                                .colOnLayer2

                        elide:
                            Text.ElideRight

                        maximumLineCount:
                            1
                    }


                    StyledText {
                        Layout.fillWidth:
                            true

                        visible:
                            text.length > 0

                        text:
                            root.bodyText

                        textFormat:
                            Text.StyledText

                        wrapMode:
                            Text.Wrap

                        elide:
                            Text.ElideRight

                        maximumLineCount:
                            2

                        font.pixelSize:
                            Appearance
                                .font
                                .pixelSize
                                .small

                        color:
                            Appearance
                                .colors
                                .colSubtext
                    }
                }


                Item {
                    Layout.alignment:
                        Qt.AlignTop

                    implicitWidth:
                        28

                    implicitHeight:
                        28


                    Rectangle {
                        anchors.fill:
                            parent

                        radius:
                            Appearance.rounding.full

                        color:
                            closeArea.containsMouse

                                ? Appearance
                                    .colors
                                    .colLayer3Hover

                                : "transparent"
                    }


                    MaterialSymbol {
                        anchors.centerIn:
                            parent

                        text:
                            "close"

                        iconSize:
                            Appearance
                                .font
                                .pixelSize
                                .small

                        color:
                            Appearance
                                .colors
                                .colSubtext
                    }


                    MouseArea {
                        id: closeArea

                        anchors.fill:
                            parent

                        hoverEnabled:
                            true

                        cursorShape:
                            Qt.PointingHandCursor

                        onClicked: {
                            if (!root.notificationObject)
                                return;

                            Notifications.discardNotification(
                                root.notificationObject
                                    .notificationId
                            );
                        }
                    }
                }
            }


            RowLayout {
                Layout.fillWidth:
                    true

                visible:
                    root.displayActions.length > 0

                spacing:
                    6


                Repeater {
                    model:
                        root.displayActions


                    NotificationActionButton {
                        required property var modelData

                        Layout.fillWidth:
                            true

                        buttonText:
                            modelData.text

                        urgency:
                            root.notificationObject
                                ? root.notificationObject.urgency
                                : ""

                        onClicked: {
                            if (!root.notificationObject)
                                return;

                            Notifications.attemptInvokeAction(
                                root.notificationObject
                                    .notificationId,

                                modelData.identifier
                            );
                        }
                    }
                }
            }
        }


        // Border is completely inside the card geometry. The toast itself does
        // not clip, so the bottom edge can never be lost to its own clip.
        Rectangle {
            anchors.fill:
                parent

            anchors.margins:
                1

            radius:
                Math.max(
                    0,
                    card.radius - 1
                )

            color:
                "transparent"

            border.width:
                Appearance.fluidMode
                    ? 1
                    : 0

            border.color:
                Appearance.fluidMode

                    ? Appearance
                        .colors
                        .fluidBorderMedium

                    : "transparent"

            z:
                100
        }
    }
}
