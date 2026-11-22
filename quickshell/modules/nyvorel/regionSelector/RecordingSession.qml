pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

Scope {
    id: root

    property var queuedArgs: null
    property string queuedScreen: ""
    property double deadline: 0
    property double now: Date.now()
    property bool launching: false
    readonly property var state: {
        try {
            return JSON.parse(stateFile.text());
        } catch (error) {
            return null;
        }
    }
    readonly property string phase: state?.phase ?? (launching ? "starting" : queuedArgs ? "countdown" : "")
    readonly property bool active: phase !== ""
    readonly property var screen: Quickshell.screens.find(candidate =>
        candidate.name === (state?.screen || queuedScreen || Hyprland.focusedMonitor?.name)) ?? Quickshell.screens[0] ?? null
    readonly property int secondsRemaining: Math.max(0, Math.ceil((deadline - now) / 1000))
    readonly property int elapsedSeconds: Math.max(0, Math.floor(((state?.elapsed ?? 0)
        + (phase === "recording" ? Math.max(0, now - state.since) : 0)) / 1000))

    onStateChanged: {
        if (state) {
            launching = false;
            queuedArgs = null;
        }
        now = Date.now();
    }

    function start(args, delay, screenName) {
        if (active)
            return;
        queuedScreen = screenName;
        now = Date.now();
        deadline = now + Math.max(180, delay * 1000);
        queuedArgs = args;
    }

    function control(kind) {
        if (kind === "stop" && queuedArgs) {
            queuedArgs = null;
            return;
        }
        if (!controlProcess.running)
            controlProcess.exec([Directories.recordScriptPath, "--" + kind]);
    }

    FileView {
        id: stateFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/nyvorel-recording.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }

    Timer {
        interval: 150
        running: root.active
        repeat: true
        onTriggered: {
            root.now = Date.now();
            if (root.queuedArgs && root.now >= root.deadline) {
                const args = root.queuedArgs;
                root.launching = true;
                root.queuedArgs = null;
                Quickshell.execDetached([Directories.recordScriptPath, ...args]);
            }
        }
    }

    Timer {
        running: root.launching
        interval: 6000
        onTriggered: {
            stateFile.reload();
            root.launching = false;
        }
    }

    Process {
        id: controlProcess
        onExited: code => {
            stateFile.reload();
            if (code !== 0 && root.active)
                Quickshell.execDetached(["notify-send", "-a", "Nyvorel", Translation.tr("Could not control the recording")]);
        }
    }

    LazyLoader {
        active: root.active
        component: RecordingControls {
            screen: root.screen
            visible: !!root.screen && !GlobalStates.regionSelectorOpen
            phase: root.phase
            seconds: root.phase === "countdown" ? root.secondsRemaining : root.elapsedSeconds
            busy: controlProcess.running
            onControlRequested: kind => root.control(kind)
        }
    }
}
