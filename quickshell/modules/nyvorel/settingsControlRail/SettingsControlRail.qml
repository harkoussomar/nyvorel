import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var pages: []
    property int currentPage: 0
    property bool expanded: false

    signal searchRequested()
    signal pageRequested(int index)

    implicitWidth: root.expanded ? 210 : 58

    Rectangle {
        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
        }
        width: 1
        color: Appearance.colors.colLayer0Border
    }

    component NavigationButton: RippleButton {
        id: button

        required property string iconName
        required property string label
        property bool selected: false
        property real iconRotation: 0

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        implicitHeight: 44
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.focusable: true
        Accessible.focused: button.activeFocus

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control
        colBackground: selected
            ? Appearance.colors.colSecondaryContainer
            : "transparent"
        colBackgroundHover: selected
            ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: selected
            ? Appearance.colors.colSecondaryContainerActive
            : Appearance.colors.colLayer2Active

        contentItem: Item {
            anchors.fill: parent

            MaterialSymbol {
                id: navigationIcon
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: root.expanded ? parent.left : undefined
                    horizontalCenter: root.expanded
                        ? undefined
                        : parent.horizontalCenter
                    leftMargin: root.expanded ? 12 : 0
                }
                text: button.iconName
                iconSize: 20
                rotation: button.iconRotation
                fill: button.selected ? 1 : 0
                color: button.selected
                    ? Appearance.colors.colOnSecondaryContainer
                    : button.hovered
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnLayer0
            }

            Rectangle {
                visible: button.selected
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                width: 3
                height: 20
                radius: 2
                color: Appearance.colors.colPrimary
            }

            StyledText {
                visible: root.expanded
                anchors {
                    left: navigationIcon.right
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 8
                }
                text: button.label
                color: button.selected
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: button.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }

        StyledToolTip {
            extraVisibleCondition: !root.expanded && button.hovered
            delay: 450
            text: button.label
        }
    }

    Flickable {
        id: navigationScroller
        anchors.fill: parent
        anchors {
            topMargin: 8
            bottomMargin: 8
            leftMargin: 4
            rightMargin: 12
        }
        clip: true
        contentWidth: width
        contentHeight: navigationColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ColumnLayout {
            id: navigationColumn
            width: navigationScroller.width
            spacing: 4

            NavigationButton {
                iconName: "search"
                label: Translation.tr("Search settings")
                onClicked: root.searchRequested()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.topMargin: 5
                Layout.bottomMargin: 5
                color: Appearance.colors.colLayer0Border
            }

            Repeater {
                model: root.pages

                delegate: ColumnLayout {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 3

                    StyledText {
                        visible: root.expanded && (index === 0 || index === 3 || index === 6)
                        Layout.fillWidth: true
                        Layout.topMargin: index === 0 ? 8 : 15
                        Layout.leftMargin: 12
                        text: modelData.group ?? ""
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                    }

                    NavigationButton {
                        iconName: modelData.icon
                        iconRotation: modelData.iconRotation ?? 0
                        label: modelData.name
                        selected: root.currentPage === index

                        onClicked: root.pageRequested(index)
                    }
                }
            }
        }
    }
}
