import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

TextField {
    property alias colBackground: background.color
    property alias fieldRadius: background.radius

    Layout.fillHeight: true
    implicitWidth: 200
    padding: 10
    renderType: Text.NativeRendering

    background: Rectangle {
        id: background
        radius: height / 2
    }
}
