import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Process {
    id: screenshotProc
    running: true
    property string screenshotDir: Directories.screenshotTemp
    required property ShellScreen screen
    property string screenshotPath: `${screenshotDir}/image-${screen.name}`
    command: captureCommand(screenshotPath)

    function captureCommand(path) {
        return ["bash", "-c", 'mkdir -p -- "$1" && exec grim -t png -o "$2" "$3"',
            "nyvorel-capture", screenshotDir, screen.name, path];
    }
}
