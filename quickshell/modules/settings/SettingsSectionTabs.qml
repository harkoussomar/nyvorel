import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

TabBar {
    id: tabs

    required property var sections
    required property string section
    signal sectionRequested(string id)

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    leftPadding: 10
    rightPadding: 10
    topPadding: 4
    spacing: 0

    currentIndex: Math.max(0, sections.findIndex(entry => entry.id === section))
    onCurrentIndexChanged: {
        const selected = sections[currentIndex]
        if (count === sections.length && selected && selected.id !== section)
            sectionRequested(selected.id)
    }

    background: Item {
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Appearance.colors.colLayer0Border
        }
    }

    Repeater {
        model: tabs.sections

        TabButton {
            id: tab

            required property var modelData
            readonly property color foreground: checked
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer1

            text: modelData.label
            implicitHeight: 44
            leftPadding: 6
            rightPadding: 6
            activeFocusOnTab: checked
            Accessible.name: text

            PointingHandInteraction {}

            background: Item {
                Rectangle {
                    anchors.fill: parent
                    anchors.bottomMargin: 2
                    topLeftRadius: Appearance.radius.control
                    topRightRadius: Appearance.radius.control
                    color: tab.checked
                        ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.40)
                        : tab.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                    border.width: tab.visualFocus ? 1 : 0
                    border.color: Appearance.colors.colPrimary
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 2
                    color: Appearance.colors.colPrimary
                    visible: tab.checked
                }
            }

            contentItem: Item {
                RowLayout {
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width)
                    spacing: 6

                    MaterialSymbol {
                        visible: tab.availableWidth >= tabLabel.implicitWidth + 28
                        text: tab.modelData.icon
                        iconSize: 17
                        color: tab.foreground
                    }

                    StyledText {
                        id: tabLabel

                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: tab.text
                        color: tab.foreground
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
