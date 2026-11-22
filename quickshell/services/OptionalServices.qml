pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    readonly property alias archRemote: archRemotePreference
    readonly property alias backupRecovery: backupRecoveryPreference
    property bool shortcutReloadFailed: false

    ServicePreference { id: archRemotePreference; name: "arch-remote" }
    ServicePreference { id: backupRecoveryPreference; name: "backup-recovery" }

    Timer {
        id: shortcutReload
        interval: 80
        onTriggered: {
            if (reloadProcess.running)
                restart()
            else
                reloadProcess.running = true
        }
    }

    Process {
        id: reloadProcess
        command: ["hyprctl", "reload"]
        onExited: (code, status) => root.shortcutReloadFailed = code !== 0 || status !== 0
    }

    component ServicePreference: FileView {
        required property string name
        readonly property bool enabled: text().trim() === "enabled"
        property bool saving: false
        property bool writeFailed: false

        path: `${Directories.shellConfig}/${name}.enabled`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        function setEnabled(value: bool): void {
            if (saving || enabled === value)
                return
            writeFailed = false
            saving = true
            setText(value ? "enabled\n" : "disabled\n")
        }

        onSaved: {
            saving = false
            reload()
            shortcutReload.restart()
        }

        onSaveFailed: {
            saving = false
            writeFailed = true
        }
    }
}
