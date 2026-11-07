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
         ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)

    colBackgroundHover:
         Appearance.colors.colLayer2Hover

    colBackgroundActive:
         Appearance.colors.colLayer2Active

    colBackgroundToggled:
          ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.72)

    colBackgroundToggledHover:
          ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1Hover, 0.64)

    colBackgroundToggledActive:
          ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1Active, 0.64)

    buttonRadius: 10
    buttonRadiusPressed: 10


    property color colText: ColorUtils.transparentize(
        Appearance.colors.colOnLayer1, root.enabled ? 0 : 0.65)


    background: Rectangle {
        radius: root.radius
        color: root.color
        border.width: root.tabbedTo ? 2 : 1
        border.color: root.tabbedTo ? Appearance.colors.colSecondary
            : root.toggled ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.53)
            : Appearance.colors.colLayer0Border

        Behavior on color { MotionColorAnim { type: MotionColorAnim.FastEffects } }
    }


    property color colSecondaryText: Appearance.colors.colSubtext


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

                implicitWidth: 34
                implicitHeight: 34
                radius: 8

                color: root.toggled
                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                    : Appearance.colors.colLayer2

                border.width: 0
                border.color:
                     "transparent"


                MaterialSymbol {
                    anchors.centerIn: parent

                    fill: root.toggled ? 1 : 0
                    iconSize: 20
                    color: root.toggled ? Appearance.colors.colPrimary : root.colText
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
            const config = Config.options.sidebar.quickToggles.android
            const toggles = Array.from(config.toggles)
            const buttonType = root.buttonData.type
            const existingIndex = toggles.findIndex(toggle => toggle.type === buttonType)
            if (existingIndex < 0)
                toggles.push({ type: buttonType, size: 1 })
            else
                toggles.splice(existingIndex, 1)
            config.toggles = toggles
        }

        function toggleSize() {
            const config = Config.options.sidebar.quickToggles.android
            const toggles = Array.from(config.toggles)
            const index = toggles.findIndex(toggle => toggle.type === root.buttonData.type)
            if (index < 0) return
            toggles[index] = { type: toggles[index].type, size: 3 - toggles[index].size }
            config.toggles = toggles
        }

        function movePositionBy(offset) {
            const config = Config.options.sidebar.quickToggles.android
            const toggles = Array.from(config.toggles)
            const index = toggles.findIndex(toggle => toggle.type === root.buttonData.type)
            const targetIndex = index + offset
            if (index < 0 || targetIndex < 0 || targetIndex >= toggles.length)
                return
            const moved = toggles.splice(index, 1)[0]
            toggles.splice(targetIndex, 0, moved)
            config.toggles = toggles
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
