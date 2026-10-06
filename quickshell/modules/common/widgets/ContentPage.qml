import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property real minContentWidth: 520
    property real maxContentWidth: 760
    property real horizontalPadding: 28
    property real topPadding: 24
    property bool forceWidth: false
    property real bottomContentPadding: 72

    default property alias data: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth
    
    ColumnLayout {
        id: contentColumn
        width: root.forceWidth
            ? Math.min(root.maxContentWidth, Math.max(root.minContentWidth, root.width - root.horizontalPadding * 2))
            : Math.max(root.minContentWidth, implicitWidth)
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: root.topPadding
        }
        spacing: 28
    }

}
