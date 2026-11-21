import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property real padding: 8
    property alias colBackground: background.color
    property alias radius: background.radius
    property alias spacing: toolbarLayout.spacing
    property Component shadow
    readonly property alias frameBackground: background
    default property alias controls: toolbarLayout.data

    implicitWidth: background.implicitWidth
    implicitHeight: background.implicitHeight

    Loader {
        anchors.fill: background
        active: root.shadow !== null
        sourceComponent: root.shadow
    }

    Rectangle {
        id: background
        anchors.fill: parent
        implicitWidth: toolbarLayout.implicitWidth + root.padding * 2
        implicitHeight: 56
        radius: height / 2

        RowLayout {
            id: toolbarLayout
            spacing: 4
            anchors.fill: parent
            anchors.margins: root.padding
        }
    }
}
