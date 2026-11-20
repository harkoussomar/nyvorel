import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

StyledImage {
    id: image

    property string wallpaperPath: ""
    property int fallbackResolution: 512
    readonly property bool failed: wallpaperPath.length > 0 && failedPath === wallpaperPath
    property string resizedPath: ""
    property string failedPath: ""

    source: wallpaperPath ? FileUtils.localFileUrl(resizedPath || wallpaperPath) : ""

    onWallpaperPathChanged: {
        resizedPath = ""
        failedPath = ""
        Qt.callLater(checkFallback)
    }
    onStatusChanged: Qt.callLater(checkFallback)

    function checkFallback(): void {
        if (status !== Image.Error || !wallpaperPath || failed || resizeImage.running)
            return
        if (resizedPath) {
            failedPath = wallpaperPath
            return
        }

        resizeImage.requestedPath = wallpaperPath
        resizeImage.exec([
            FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/system/nyvorel-wallpaper-image")),
            String(fallbackResolution), wallpaperPath
        ])
    }

    Process {
        id: resizeImage
        property string requestedPath: ""
        stdout: StdioCollector { id: resizeOutput }

        onExited: exitCode => {
            if (requestedPath !== image.wallpaperPath) {
                Qt.callLater(image.checkFallback)
                return
            }
            const result = resizeOutput.text.trim()
            if (exitCode === 0 && result.startsWith("/"))
                image.resizedPath = result
            else
                image.failedPath = requestedPath
        }
    }
}
