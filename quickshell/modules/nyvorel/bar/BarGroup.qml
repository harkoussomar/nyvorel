import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property bool quiet: false
    property real padding: 5
    property real verticalRowSpacing: 12
    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight
    default property alias items: gridLayout.children


    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color:
            root.quiet || (Config.options && Config.options.bar && Config.options.bar.borderless)
                ? "transparent"
                : Appearance.fluidMode
                    ? Appearance.barVisual.fluidGroupFill
                    : Appearance.barVisual.defaultGroupFill
        radius:
              (
                 Appearance.fluidMode
                     ? Appearance.radius.bar
                     : Appearance.rounding.small
             )
        // Fluid uses tonal glass hierarchy rather than framing every group.
        border.width: 0
        border.color: Appearance.colors.colLayer0Border
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors {
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            left: root.vertical ? undefined : parent.left
            right: root.vertical ? undefined : parent.right
            top: root.vertical ? parent.top : undefined
            bottom: root.vertical ? parent.bottom : undefined
            margins: root.padding
        }
        columnSpacing: Appearance.barLayout.groupColumnGap
        rowSpacing: root.verticalRowSpacing
    }
}
