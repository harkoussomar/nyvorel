import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets


GroupButton {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property bool expandedSize
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    signal openMenu()

    property QuickToggleModel toggleModel

    property string name:
        toggleModel?.name ?? ""

    property string statusText:
        toggleModel?.hasStatusText
            ? (
                toggleModel?.statusText
                || (
                    toggled
                        ? Translation.tr("Active")
                        : Translation.tr("Inactive")
                )
            )
            : ""

    property string tooltipText:
        toggleModel?.tooltipText ?? ""

    property string buttonIcon:
        toggleModel?.icon ?? "close"

    property bool available:
        toggleModel?.available ?? true

    toggled:
        toggleModel?.toggled ?? false

    property var mainAction:
        toggleModel?.mainAction ?? null

    altAction:
        toggleModel?.hasMenu
            ? (() => root.openMenu())
            : (toggleModel?.altAction ?? null)

    property bool editMode: false


    // Equal-width tiles: Settings "Tiles per row" is authoritative.
    baseWidth:
        root.baseCellWidth

    baseHeight:
        root.baseCellHeight

    clickedWidth:
        baseWidth

    enableImplicitWidthAnimation:
        false

    enableImplicitHeightAnimation:
        false


    Behavior on baseWidth {
        animation:
            Appearance.animation.elementMove
                .numberAnimation
                .createObject(this)
    }

    Behavior on baseHeight {
        animation:
            Appearance.animation.elementMove
                .numberAnimation
                .createObject(this)
    }


    opacity: 0

    Component.onCompleted:
        opacity = 1

    Behavior on opacity {
        animation:
            Appearance.animation.elementMoveFast
                .numberAnimation
                .createObject(this)
    }


    enabled:
        root.available || root.editMode

    padding: 0
    horizontalPadding: 0
    verticalPadding: 0

    colBackground:
        Appearance.inlayMode
            ? Appearance.inlay.insetFill
            : Appearance.colors.colLayer2

    colBackgroundHover:
        Appearance.inlayMode
            ? Appearance.inlay.hoverFill
            : Appearance.colors.colLayer2Hover

    colBackgroundActive:
        Appearance.inlayMode
            ? Appearance.inlay.pressedFill
            : Appearance.colors.colLayer2Active

    // prism-v2-phase3b1: state is visible without turning the full tile into
    // a saturated accent slab. Accent belongs to the state/icon, not the surface.
    colBackgroundToggled:
        Appearance.inlayMode
            ? Appearance.inlay.selectedFill
            : Appearance.prismMode
                ? ColorUtils.mix(
                    Appearance.prism.interactiveFill,
                    Appearance.colors.colPrimary,
                    0.86
                )
                : Appearance.colors.colPrimary

    colBackgroundToggledHover:
        Appearance.inlayMode
            ? Appearance.inlay.hoverFill
            : Appearance.prismMode
                ? ColorUtils.mix(
                    Appearance.prism.interactiveFill,
                    Appearance.colors.colPrimary,
                    0.80
                )
                : Appearance.colors.colPrimaryHover

    colBackgroundToggledActive:
        Appearance.inlayMode
            ? Appearance.inlay.pressedFill
            : Appearance.prismMode
                ? ColorUtils.mix(
                    Appearance.prism.interactiveFill,
                    Appearance.colors.colPrimary,
                    0.74
                )
                : Appearance.colors.colPrimaryActive

    buttonRadius:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.prism.radiusControl + 2
                : 18
    buttonRadiusPressed:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.prism.radiusControl
                : 14


    property color colText:
        root.toggled && root.enabled
            ? (
                Appearance.inlayMode
                    ? Appearance.colors.colOnLayer1
                    : Appearance.prismMode
                        ? Appearance.colors.colOnLayer1
                        : Appearance.colors.colOnPrimary
            )
            : ColorUtils.transparentize(
                Appearance.colors.colOnLayer2,
                root.enabled ? 0 : 0.65
            )


    background: Rectangle {
        radius: root.radius
        color: root.color
        border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : (root.tabbedTo ? 2 : 0)
        border.color:
            Appearance.inlayMode
                ? (root.toggled ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                : Appearance.colors.colSecondary

        Behavior on color { MotionColorAnim { type: MotionColorAnim.FastEffects } }
    }


    property color colSecondaryText:
        root.toggled
            ? (
                (Appearance.prismMode || Appearance.inlayMode)
                    ? Appearance.colors.colSubtext
                    : ColorUtils.transparentize(
                        Appearance.colors.colOnPrimary,
                        0.22
                    )
            )
            : Appearance.colors.colSubtext


    // Card click toggles the feature.
    onClicked: {
        if (root.mainAction)
            root.mainAction()
    }


    contentItem:
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            anchors.topMargin: 10
            anchors.bottomMargin: 10

            spacing: 10


            Rectangle {
                Layout.alignment: Qt.AlignVCenter

                implicitWidth: 36
                implicitHeight: 36
                radius: Appearance.inlayMode ? 0 : 13

                color:
                    Appearance.inlayMode
                        ? Appearance.inlay.controlFill
                        : root.toggled
                            ? (
                                Appearance.prismMode
                                    ? ColorUtils.mix(
                                        Appearance.prism.interactiveFill,
                                        Appearance.colors.colPrimary,
                                        0.70
                                    )
                                    : ColorUtils.transparentize(
                                        Appearance.colors.colOnPrimary,
                                        0.82
                                    )
                            )
                            : Appearance.colors.colLayer3

                border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
                border.color:
                    Appearance.inlayMode
                        ? (root.toggled
                            ? Appearance.inlay.borderFocus
                            : Appearance.inlay.borderControl)
                        : "transparent"


                MaterialSymbol {
                    anchors.centerIn: parent

                    fill: root.toggled ? 1 : 0
                    iconSize: 22
                    color:
                        Appearance.inlayMode && root.toggled
                            ? Appearance.inlay.borderFocus
                            : Appearance.prismMode && root.toggled
                                ? Appearance.colors.colPrimary
                                : root.colText
                    text: root.buttonIcon
                }
            }


            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1


                StyledText {
                    Layout.fillWidth: true

                    text: root.name

                    font.pixelSize:
                        Appearance.font.pixelSize.small

                    font.weight: Font.DemiBold
                    color: root.colText
                    elide: Text.ElideRight
                }


                StyledText {
                    Layout.fillWidth: true

                    visible:
                        root.statusText.length > 0

                    text: root.statusText

                    font.pixelSize:
                        Appearance.font.pixelSize.smaller

                    color: root.colSecondaryText
                    elide: Text.ElideRight
                }
            }


            Item {
                Layout.alignment: Qt.AlignVCenter

                implicitWidth:
                    root.altAction ? 28 : 0

                implicitHeight: 32

                visible:
                    root.altAction !== null


                MaterialSymbol {
                    anchors.centerIn: parent

                    text: "chevron_right"
                    iconSize: 19
                    color: root.colSecondaryText
                }


                MouseArea {
                    anchors.fill: parent

                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: event => {
                        event.accepted = true

                        if (root.altAction)
                            root.altAction()
                    }
                }
            }
        }


    // Existing edit behavior preserved.
    MouseArea {
        id: editModeInteraction

        visible: root.editMode
        anchors.fill: parent

        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton


        function toggleEnabled() {
            const index = root.buttonIndex

            const toggleList =
                Config.options.sidebar
                    .quickToggles.android.toggles

            const buttonType =
                root.buttonData.type

            if (
                !toggleList.find(
                    toggle =>
                        toggle.type === buttonType
                )
            ) {
                toggleList.push(
                    {
                        type: buttonType,
                        size: 1
                    }
                )
            } else {
                toggleList.splice(index, 1)
            }
        }


        function toggleSize() {
            const index = root.buttonIndex

            const toggleList =
                Config.options.sidebar
                    .quickToggles.android.toggles

            const buttonType =
                root.buttonData.type

            if (
                !toggleList.find(
                    toggle =>
                        toggle.type === buttonType
                )
            ) {
                return
            }

            toggleList[index].size =
                3 - toggleList[index].size
        }


        function movePositionBy(offset) {
            const index = root.buttonIndex

            const toggleList =
                Config.options.sidebar
                    .quickToggles.android.toggles

            const buttonType =
                root.buttonData.type

            const targetIndex =
                index + offset

            if (
                !toggleList.find(
                    toggle =>
                        toggle.type === buttonType
                )
            ) {
                return
            }

            if (
                targetIndex < 0
                || targetIndex >= toggleList.length
            ) {
                return
            }

            const temp = toggleList[index]

            toggleList[index] =
                toggleList[targetIndex]

            toggleList[targetIndex] =
                temp
        }


        onReleased: event => {
            if (event.button === Qt.LeftButton)
                toggleEnabled()
        }

        onWheel: event => {
            if (event.angleDelta.y < 0)
                movePositionBy(1)
            else if (event.angleDelta.y > 0)
                movePositionBy(-1)

            event.accepted = true
        }
    }


    StyledToolTip {
        extraVisibleCondition:
            root.tooltipText !== ""

        text: root.tooltipText
    }
}
