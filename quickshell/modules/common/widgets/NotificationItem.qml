import qs
import qs.modules.common
import qs.services
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Item {
    id: root


    property var notificationObject


    property bool expanded:
        false


    property bool onlyNotification:
        false


    property bool popup:
        false


    property real fontSize:
        Appearance.font.pixelSize.small


    // Freedesktop notifications commonly expose a "default"
    // action with no visible label. It belongs on the body click,
    // not as an empty action button.
    readonly property var displayActions:
        (
            root.notificationObject
                ?.actions
            ?? []
        ).filter(
            (action) =>
                action.identifier !== "default"
                && (
                    action.text
                    ?? ""
                ).trim().length > 0
        )


    property real padding:
        onlyNotification ? 0 : 8


    property real summaryElideRatio:
        0.85


    readonly property string notificationKind:
        NotificationUtils.getNotificationKind(
            notificationObject?.summary ?? "",
            notificationObject?.body ?? "",
            notificationObject?.urgency ?? ""
        )


    readonly property string notificationKindIcon:
        NotificationUtils.getNotificationKindIcon(
            root.notificationKind
        )


    // =========================================================
    // Drag
    // =========================================================

    property real dragConfirmThreshold:
        70


    property real dismissOvershoot:
        notificationIcon.implicitWidth + 20


    property var qmlParent:
        root?.parent?.parent


    property var parentDragIndex:
        qmlParent?.dragIndex ?? -1


    property var parentDragDistance:
        qmlParent?.dragDistance ?? 0


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


    implicitHeight:
        background.implicitHeight


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


    TextMetrics {
        id: summaryTextMetrics


        font.pixelSize:
            root.fontSize


        text:
            root.notificationObject
                ?.summary
                ?? ""
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
            Notifications
                .discardNotification(
                    notificationObject
                        .notificationId
                );
        }
    }


    DragManager {
        id: dragManager


        anchors.fill:
            root


        anchors.leftMargin:
            root.expanded
                ? -notificationIcon
                    .implicitWidth

                : 0


        interactive:
            root.expanded


        automaticallyReset:
            false


        acceptedButtons:
            Qt.LeftButton
            | Qt.MiddleButton


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
                && Notifications
                    .attemptInvokeDefaultAction(
                        root.notificationObject
                            .notificationId
                    )
            ) {
                GlobalStates.sidebarRightOpen =
                    false;
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


    // =========================================================
    // Expanded image
    // =========================================================

    NotificationAppIcon {
        id: notificationIcon


        opacity:
            (
                !root.onlyNotification
                && root.notificationObject
                    ?.image
                    !== ""
                && root.expanded
            )
                ? 1
                : 0


        visible:
            opacity > 0


        Behavior on opacity {
            animation:
                Appearance
                    .animation
                    .elementMoveFast
                    .numberAnimation
                    .createObject(this)
        }


        image:
            root.notificationObject
                ?.image
                ?? ""


        anchors {
            right:
                background.left

            top:
                background.top

            rightMargin:
                10
        }
    }


    Rectangle {
        id: background


        width:
            parent.width


        anchors.left:
            parent.left


        radius:
            Appearance.inlayMode ? 0 : Appearance.rounding.small


        anchors.leftMargin:
            root.xOffset


        Behavior on anchors.leftMargin {
            enabled:
                !dragManager.dragging

            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }


        // fluid-notification-readability-v1
        // The item stays visibly layered over the denser toast group without
        // returning to the extremely transparent generic Fluid layer.
        color:
            root.popup
            && Appearance.fluidMode

                ? ColorUtils.transparentize(
                    Appearance
                        .colors
                        .fluidLayer3Tone,

                    0.58
                )

                : (
                    (
                        root.expanded
                        && !root.onlyNotification
                    )

                        ? (
                            root.notificationObject
                                ?.urgency

                            === NotificationUrgency
                                .Critical
                                .toString()

                                ? ColorUtils.mix(
                                    Appearance
                                        .colors
                                        .colSecondaryContainer,

                                    Appearance
                                        .colors
                                        .colLayer2,

                                    0.35
                                )

                                : Appearance
                                    .colors
                                    .colLayer3
                        )

                        : ColorUtils.transparentize(
                            Appearance
                                .colors
                                .colLayer3
                        )
                )


        implicitHeight:
            root.expanded

                ? contentColumn.implicitHeight
                    + root.padding * 2

                : root.popup

                    ? compactPopupColumn
                        .implicitHeight

                    : summaryRow
                        .implicitHeight


        Behavior on implicitHeight {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }


        ColumnLayout {
            id: contentColumn


            anchors.fill:
                parent


            anchors.margins:
                root.expanded
                    ? root.padding
                    : 0


            spacing:
                root.popup
                    ? 4
                    : 3


            Behavior on anchors.margins {
                MotionAnim {
                    type: MotionAnim.FastEffects
                }
            }


            // =================================================
            // Popup compact presentation
            // =================================================

            ColumnLayout {
                id: compactPopupColumn


                visible:
                    root.popup
                    && !root.expanded


                Layout.fillWidth:
                    true


                spacing:
                    3


                RowLayout {
                    Layout.fillWidth:
                        true


                    spacing:
                        7


                    Rectangle {
                        implicitWidth:
                            20


                        implicitHeight:
                            20


                        radius:
                            Appearance.inlayMode
                                ? 0
                                : Appearance.rounding.full


                        color: {
                            switch (
                                root.notificationKind
                            ) {
                            case "critical":
                            case "error":
                                return Appearance
                                    .colors
                                    .colPrimaryContainer;

                            case "success":
                                return Appearance
                                    .colors
                                    .colSecondaryContainer;

                            case "warning":
                                return ColorUtils.mix(
                                    Appearance
                                        .colors
                                        .colPrimaryContainer,

                                    Appearance
                                        .colors
                                        .colSecondaryContainer,

                                    0.5
                                );

                            default:
                                return Appearance
                                    .colors
                                    .colLayer3;
                            }
                        }


                        MaterialSymbol {
                            anchors.centerIn:
                                parent


                            iconSize:
                                Appearance
                                    .font
                                    .pixelSize
                                    .small


                            text:
                                root.notificationKindIcon


                            color:
                                (
                                    root.notificationKind
                                    === "critical"
                                    || root.notificationKind
                                    === "error"
                                )

                                    ? Appearance
                                        .colors
                                        .colOnPrimaryContainer

                                    : Appearance
                                        .colors
                                        .colOnSecondaryContainer
                        }
                    }


                    StyledText {
                        Layout.fillWidth:
                            true


                        text:
                            root.notificationObject
                                ?.summary
                                ?? ""


                        font.pixelSize:
                            root.fontSize


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
                }


                StyledText {
                    Layout.fillWidth:
                        true


                    Layout.leftMargin:
                        27


                    font.pixelSize:
                        root.fontSize


                    color:
                        Appearance
                            .colors
                            .colSubtext


                    wrapMode:
                        Text.Wrap


                    elide:
                        Text.ElideRight


                    maximumLineCount:
                        2


                    textFormat:
                        Text.StyledText


                    text:
                        NotificationUtils
                            .processNotificationBody(
                                root.notificationObject
                                    ?.body
                                    ?? "",

                                (
                                    root.notificationObject?.appName
                                    || root.notificationObject?.summary
                                    || ""
                                )
                            )
                            .replace(
                                /\n/g,
                                "<br/>"
                            )
                }
            }


            // =================================================
            // Existing compact notification-center row
            // =================================================

            RowLayout {
                id: summaryRow


                visible:
                    !root.popup
                    && (
                        !root.onlyNotification
                        || !root.expanded
                    )


                Layout.fillWidth:
                    true


                implicitHeight:
                    Math.max(
                        summaryText.implicitHeight,
                        compactBodyText.implicitHeight
                    )


                StyledText {
                    id: summaryText


                    Layout.fillWidth:
                        summaryTextMetrics.width
                        >= summaryRow.implicitWidth
                            * root.summaryElideRatio


                    visible:
                        !root.onlyNotification


                    font.pixelSize:
                        root.fontSize


                    font.weight:
                        Font.Medium


                    color:
                        Appearance
                            .colors
                            .colOnLayer3


                    elide:
                        Text.ElideRight


                    text:
                        root.notificationObject
                            ?.summary
                            ?? ""
                }


                StyledText {
                    id: compactBodyText


                    opacity:
                        !root.expanded
                            ? 1
                            : 0


                    visible:
                        opacity > 0


                    Layout.fillWidth:
                        true


                    Behavior on opacity {
                        animation:
                            Appearance
                                .animation
                                .elementMoveFast
                                .numberAnimation
                                .createObject(this)
                    }


                    font.pixelSize:
                        root.fontSize


                    color:
                        Appearance
                            .colors
                            .colSubtext


                    elide:
                        Text.ElideRight


                    wrapMode:
                        Text.Wrap


                    maximumLineCount:
                        1


                    textFormat:
                        Text.StyledText


                    text:
                        NotificationUtils
                            .processNotificationBody(
                                root.notificationObject
                                    ?.body
                                    ?? "",

                                (
                                    root.notificationObject?.appName
                                    || root.notificationObject?.summary
                                    || ""
                                )
                            )
                            .replace(
                                /\n/g,
                                "<br/>"
                            )
                }
            }


            // =================================================
            // Expanded content
            // =================================================

            ColumnLayout {
                id: expandedContentColumn


                Layout.fillWidth:
                    true


                opacity:
                    root.expanded
                        ? 1
                        : 0


                visible:
                    opacity > 0


                StyledText {
                    id: notificationBodyText


                    Behavior on opacity {
                        animation:
                            Appearance
                                .animation
                                .elementMoveFast
                                .numberAnimation
                                .createObject(this)
                    }


                    Layout.fillWidth:
                        true


                    font.pixelSize:
                        root.fontSize


                    color:
                        Appearance
                            .colors
                            .colSubtext


                    wrapMode:
                        Text.Wrap


                    elide:
                        Text.ElideRight


                    textFormat:
                        Text.RichText


                    text: {
                        return (
                            `<style>img{max-width:${expandedContentColumn.width}px;}</style>`
                            + NotificationUtils
                                .processNotificationBody(
                                    root.notificationObject
                                        ?.body
                                        ?? "",

                                    (
                                        root.notificationObject
                                            ?.appName

                                        || root.notificationObject
                                            ?.summary

                                        || ""
                                    )
                                )
                                .replace(
                                    /\n/g,
                                    "<br/>"
                                )
                        );
                    }


                    onLinkActivated: (link) => {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", link]);

                        GlobalStates.sidebarRightOpen =
                            false;
                    }


                    PointingHandLinkHover {}
                }


                Item {
                    Layout.fillWidth:
                        true


                    implicitWidth:
                        actionsFlickable
                            .implicitWidth


                    implicitHeight:
                        actionsFlickable
                            .implicitHeight


                    layer.enabled:
                        true


                    layer.effect:
                        OpacityMask {
                            maskSource:
                                Rectangle {
                                    width:
                                        actionsFlickable.width

                                    height:
                                        actionsFlickable.height

                                    radius:
                                        Appearance.inlayMode
                                            ? 0
                                            : Appearance.rounding.small
                                }
                        }


                    ScrollEdgeFade {
                        target:
                            actionsFlickable

                        vertical:
                            false
                    }


                    StyledFlickable {
                        id: actionsFlickable


                        anchors.fill:
                            parent


                        implicitHeight:
                            actionRowLayout
                                .implicitHeight


                        contentWidth:
                            actionRowLayout
                                .implicitWidth


                        Behavior on opacity {
                            animation:
                                Appearance
                                    .animation
                                    .elementMoveFast
                                    .numberAnimation
                                    .createObject(this)
                        }


                        Behavior on height {
                            animation:
                                Appearance
                                    .animation
                                    .elementMoveFast
                                    .numberAnimation
                                    .createObject(this)
                        }


                        Behavior on implicitHeight {
                            animation:
                                Appearance
                                    .animation
                                    .elementMoveFast
                                    .numberAnimation
                                    .createObject(this)
                        }


                        RowLayout {
                            id: actionRowLayout


                            Layout.alignment:
                                Qt.AlignBottom


                            NotificationActionButton {
                                Layout.fillWidth:
                                    true


                                buttonText:
                                    Translation.tr(
                                        "Close"
                                    )


                                urgency:
                                    root.notificationObject
                                        ?.urgency
                                        ?? ""


                                implicitWidth:
                                    (
                                        root.displayActions.length
                                    ) === 0

                                        ? (
                                            (
                                                actionsFlickable.width
                                                - actionRowLayout.spacing
                                            )
                                            / 2
                                        )

                                        : (
                                            contentItem.implicitWidth
                                            + leftPadding
                                            + rightPadding
                                        )


                                onClicked: {
                                    root.destroyWithAnimation();
                                }


                                contentItem:
                                    MaterialSymbol {
                                        iconSize:
                                            Appearance
                                                .font
                                                .pixelSize
                                                .larger


                                        horizontalAlignment:
                                            Text.AlignHCenter


                                        color:
                                            (
                                                root.notificationObject
                                                    ?.urgency

                                                === NotificationUrgency
                                                    .Critical
                                                    .toString()
                                            )

                                                ? Appearance
                                                    .m3colors
                                                    .m3onSurfaceVariant

                                                : Appearance
                                                    .m3colors
                                                    .m3onSurface


                                        text:
                                            "close"
                                    }
                            }


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
                                            ?.urgency
                                            ?? ""


                                    onClicked: {
                                        Notifications
                                            .attemptInvokeAction(
                                                root.notificationObject
                                                    .notificationId,

                                                modelData.identifier
                                            );
                                    }
                                }
                            }


                            NotificationActionButton {
                                Layout.fillWidth:
                                    true


                                urgency:
                                    root.notificationObject
                                        ?.urgency
                                        ?? ""


                                implicitWidth:
                                    (
                                        root.displayActions.length
                                    ) === 0

                                        ? (
                                            (
                                                actionsFlickable.width
                                                - actionRowLayout.spacing
                                            )
                                            / 2
                                        )

                                        : (
                                            contentItem.implicitWidth
                                            + leftPadding
                                            + rightPadding
                                        )


                                onClicked: {
                                    Quickshell.clipboardText =
                                        root.notificationObject
                                            ?.body
                                            ?? "";


                                    copyIcon.text =
                                        "inventory";


                                    copyIconTimer.restart();
                                }


                                Timer {
                                    id: copyIconTimer


                                    interval:
                                        1500


                                    repeat:
                                        false


                                    onTriggered: {
                                        copyIcon.text =
                                            "content_copy";
                                    }
                                }


                                contentItem:
                                    MaterialSymbol {
                                        id: copyIcon


                                        iconSize:
                                            Appearance
                                                .font
                                                .pixelSize
                                                .larger


                                        horizontalAlignment:
                                            Text.AlignHCenter


                                        color:
                                            (
                                                root.notificationObject
                                                    ?.urgency

                                                === NotificationUrgency
                                                    .Critical
                                                    .toString()
                                            )

                                                ? Appearance
                                                    .m3colors
                                                    .m3onSurfaceVariant

                                                : Appearance
                                                    .m3colors
                                                    .m3onSurface


                                        text:
                                            "content_copy"
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
}