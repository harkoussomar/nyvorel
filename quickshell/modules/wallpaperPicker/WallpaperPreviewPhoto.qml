import QtQuick
import QtQuick.Window
import qs.modules.common.widgets

WallpaperImage {
    anchors.fill: parent
    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                        Math.ceil(height * Screen.devicePixelRatio))
    clip: true
    opacity: 0
}
