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
    readonly property bool canScrollLeft: tabsFlickable.contentX > 2
    readonly property bool canScrollRight:
        tabsFlickable.contentWidth > tabsFlickable.width + 2
        && tabsFlickable.contentX
            < tabsFlickable.contentWidth - tabsFlickable.width - 2

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

    function scrollTabs(direction) {
        const maxOffset = Math.max(
            0, tabsFlickable.contentWidth - tabsFlickable.width
        )
        const step = Math.max(120, tabsFlickable.width * 0.55)
        tabsFlickable.contentX = Math.max(
            0,
            Math.min(maxOffset, tabsFlickable.contentX + direction * step)
        )
    }

    onCurrentPageChanged:
        Qt.callLater(() => root.ensureTabVisible(root.currentPage))
    onWidthChanged:
        Qt.callLater(() => root.ensureTabVisible(root.currentPage))

    component EdgeCue: Item {
        id: cue
        property bool leftEdge: false

        width: 34
        height: parent.height
        z: 1

        Accessible.role: Accessible.Button
        Accessible.name: cue.leftEdge
            ? "Scroll settings tabs left"
            : "Scroll settings tabs right"
        Accessible.onPressAction:
            root.scrollTabs(cue.leftEdge ? -1 : 1)

        Rectangle {
            anchors.fill: parent
            radius: Appearance.radius.control
            color: Qt.rgba(
                Appearance.colors.colLayer0.r,
                Appearance.colors.colLayer0.g,
                Appearance.colors.colLayer0.b,
                1
            )
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: cue.leftEdge ? "chevron_left" : "chevron_right"
            iconSize: 17
            color: Appearance.colors.colPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.scrollTabs(cue.leftEdge ? -1 : 1)
        }
    }

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

                    buttonRadius: Appearance.radius.control
                    buttonRadiusPressed: Appearance.radius.control

                    colBackground:
                        selected
                            ? (Appearance.colors.colSecondaryContainer)
                            : "transparent"

                    colBackgroundHover:
                          (selected
                             ? Appearance.colors.colSecondaryContainerHover
                             : Appearance.colors.colLayer2Hover)

                    colRipple:
                          (selected
                             ? Appearance.colors.colSecondaryContainerActive
                             : Appearance.colors.colLayer2Active)

                    background: Rectangle {
                        radius: pageButton.buttonEffectiveRadius
                        color: pageButton.buttonColor
                        border.width: 0
                        border.color:
                             "transparent"
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
                                    ? (Appearance.colors.colOnSecondaryContainer)
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
                                    ? (Appearance.colors.colOnSecondaryContainer)
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

    EdgeCue {
        anchors.left: parent.left
        leftEdge: true
        visible: root.canScrollLeft
    }

    EdgeCue {
        anchors.right: parent.right
        visible: root.canScrollRight
    }
}
