import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var pages: []
    property int currentPage: 0
    property bool entered: false

    signal pageRequested(int index)

    implicitHeight: 40
    opacity: root.entered ? 1 : 0

    transform: Translate {
        y: root.entered ? 0 : -6

        Behavior on y {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }
    }

    Behavior on opacity {
        MotionAnim {
            type: MotionAnim.DefaultEffects
        }
    }

    Component.onCompleted: Qt.callLater(() => root.entered = true)

    function ensureTabVisible(index) {
        if (!pageRepeater || index < 0 || index >= pageRepeater.count)
            return

        const item = pageRepeater.itemAt(index)
        if (!item)
            return

        const left = item.x
        const right = item.x + item.width
        const viewportLeft = tabsFlickable.contentX
        const viewportRight =
            tabsFlickable.contentX + tabsFlickable.width

        if (left < viewportLeft) {
            tabsFlickable.contentX =
                Math.max(0, left - 6)
        } else if (right > viewportRight) {
            tabsFlickable.contentX =
                Math.min(
                    Math.max(
                        0,
                        tabsFlickable.contentWidth
                            - tabsFlickable.width
                    ),
                    right - tabsFlickable.width + 6
                )
        }
    }

    function focusTab(index) {
        if (!pageRepeater || pageRepeater.count <= 0)
            return

        const count = pageRepeater.count
        const normalized =
            ((index % count) + count) % count

        root.ensureTabVisible(normalized)

        Qt.callLater(() => {
            const item = pageRepeater.itemAt(normalized)
            if (item)
                item.forceActiveFocus(Qt.TabFocusReason)
        })
    }

    function activateTab(index) {
        if (!pageRepeater || pageRepeater.count <= 0)
            return

        const count = pageRepeater.count
        const normalized =
            ((index % count) + count) % count

        root.pageRequested(normalized)
        root.focusTab(normalized)
    }

    onCurrentPageChanged:
        Qt.callLater(() => root.ensureTabVisible(root.currentPage))

    Flickable {
        id: tabsFlickable

        anchors.fill: parent
        clip: true

        contentWidth: tabsRow.width
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width

        Row {
            id: tabsRow

            height: parent.height
            spacing: 5

            Repeater {
                id: pageRepeater
                model: root.pages

                delegate: RippleButton {
                    id: pageButton

                    required property int index
                    required property var modelData

                    readonly property bool selected:
                        root.currentPage === index

                    anchors.verticalCenter: parent.verticalCenter

                    implicitHeight: 36
                    implicitWidth:
                        Math.max(
                            72,
                            24
                                + pageButtonText.implicitWidth
                                + (
                                    pageButtonIcon.visible
                                        ? pageButtonIcon.iconSize + 7
                                        : 0
                                )
                        )

                    activeFocusOnTab: true

                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name

                    buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
                    buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.radius.control

                    colBackground:
                        selected
                            ? (Appearance.inlayMode
                                ? Appearance.inlay.selectedFill
                                : Appearance.prismMode
                                    ? Appearance.prism.persistentActiveFill
                                    : Appearance.colors.colSecondaryContainer)
                            : "transparent"

                    colBackgroundHover:
                        Appearance.inlayMode
                            ? Appearance.inlay.hoverFill
                            : Appearance.prismMode
                                ? Appearance.prism.persistentHoverFill
                                : (selected
                                    ? Appearance.colors.colSecondaryContainerHover
                                    : Appearance.colors.colLayer2Hover)

                    colRipple:
                        Appearance.inlayMode
                            ? Appearance.inlay.pressedFill
                            : Appearance.prismMode
                                ? Appearance.prism.persistentActiveFill
                                : (selected
                                    ? Appearance.colors.colSecondaryContainerActive
                                    : Appearance.colors.colLayer2Active)

                    background: Rectangle {
                        radius: pageButton.buttonEffectiveRadius
                        color: pageButton.buttonColor
                        border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
                        border.color:
                            Appearance.inlayMode
                                ? (pageButton.selected ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                                : "transparent"
                    }

                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => {
                        if (event.modifiers !== Qt.NoModifier)
                            return

                        if (event.key === Qt.Key_Left) {
                            root.activateTab(index - 1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Right) {
                            root.activateTab(index + 1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Home) {
                            root.activateTab(0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root.activateTab(pageRepeater.count - 1)
                            event.accepted = true
                        }
                    }

                    onClicked: root.pageRequested(index)

                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 12
                        }

                        spacing: 7

                        MaterialSymbol {
                            id: pageButtonIcon

                            visible:
                                pageButton.modelData.icon !== undefined
                                && String(pageButton.modelData.icon).length > 0

                            text:
                                visible
                                    ? pageButton.modelData.icon
                                    : ""

                            rotation:
                                pageButton.modelData.iconRotation || 0

                            iconSize: 17
                            fill: pageButton.selected ? 1 : 0
                            color:
                                pageButton.selected
                                    ? (Appearance.inlayMode
                                        ? Appearance.colors.colPrimary
                                        : Appearance.prismMode
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colOnSecondaryContainer)
                                    : Appearance.colors.colSubtext
                        }

                        StyledText {
                            id: pageButtonText

                            Layout.preferredWidth: implicitWidth
                            Layout.minimumWidth: implicitWidth
                            text: pageButton.modelData.name
                            elide: Text.ElideNone
                            color:
                                pageButton.selected
                                    ? (Appearance.inlayMode
                                        ? Appearance.colors.colPrimary
                                        : Appearance.prismMode
                                            ? Appearance.colors.colOnLayer0
                                            : Appearance.colors.colOnSecondaryContainer)
                                    : Appearance.colors.colOnLayer0

                            font {
                                pixelSize: Appearance.font.pixelSize.small
                                weight:
                                    pageButton.selected
                                        ? Font.DemiBold
                                        : Font.Normal
                            }
                        }
                    }
                }
            }
        }
    }
}
