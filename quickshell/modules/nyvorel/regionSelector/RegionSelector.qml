pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    property var latestCapture: null
    property string priorPreviewPath: ""
    property var queuedCaptures: []
    property bool previewShown: false
    readonly property string screenshotPreviewDir: (Quickshell.env("XDG_RUNTIME_DIR") || Directories.screenshotTemp) + "/nyvorel-snips"

    function screenByName(name) {
        return Array.from(Quickshell.screens).find(screen => screen.name === name) ?? null;
    }

    function takeCapture(request) {
        const screen = screenByName(request.screenName);
        if (!screen) {
            if (request.source)
                Quickshell.execDetached(["rm", "-f", "--", request.source]);
            Quickshell.execDetached(["notify-send", "-a", "Nyvorel", Translation.tr("The selected display is unavailable")]);
            return;
        }
        const scale = Hyprland.monitorFor(screen)?.scale ?? 1;
        const x = Math.max(0, Math.min(screen.width - 1, request.x));
        const y = Math.max(0, Math.min(screen.height - 1, request.y));
        const width = Math.min(screen.width - x, request.width);
        const height = Math.min(screen.height - y, request.height);
        if (width < 1 || height < 1) {
            if (request.source)
                Quickshell.execDetached(["rm", "-f", "--", request.source]);
            return;
        }
        const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        const source = request.source;
        const previewPath = `${screenshotPreviewDir}/${token}.png`;
        const command = ScreenshotAction.getCommand(x * scale, y * scale, width * scale, height * scale,
            source, ScreenshotAction.Action.Copy, Config.options.screenSnip.savePath, request.radius * scale,
            { previewPath, delay: request.delay, refreshScreen: request.delay ? screen.name : "" });
        previewShown = false;
        queuedCaptures = [...queuedCaptures, { command, previewPath, screenName: screen.name }];
        Qt.callLater(processNext);
    }

    function processNext() {
        if (captureProcess.running || !queuedCaptures.length)
            return;
        captureProcess.job = queuedCaptures[0];
        queuedCaptures = queuedCaptures.slice(1);
        captureProcess.exec(captureProcess.job.command);
    }

    function previewAction(action) {
        if (!latestCapture)
            return;
        const path = action === "folder" ? latestCapture.savedPath : latestCapture.path;
        if (!path)
            return;
        const command = ScreenshotAction.fileAction(path, action);
        if (command.length)
            Quickshell.execDetached(command);
        previewShown = false;
    }

    Process {
        id: captureProcess
        property var job: null
        stdout: StdioCollector { id: output }
        onExited: (code, status) => {
            let result = null;
            try {
                result = code === 0 && status === 0 ? JSON.parse(output.text) : null;
            } catch (error) {}
            if (result && job && result.path === job.previewPath) {
                if (root.priorPreviewPath)
                    Quickshell.execDetached(["rm", "-f", "--", root.priorPreviewPath]);
                root.priorPreviewPath = root.latestCapture?.path ?? "";
                root.latestCapture = Object.assign(result, { screenName: job.screenName });
                root.previewShown = !GlobalStates.regionSelectorOpen;
            } else if (job) {
                Quickshell.execDetached(["rm", "-f", "--", job.previewPath]);
            }
            job = null;
            Qt.callLater(root.processNext);
        }
    }

    Component.onDestruction: {
        const files = [priorPreviewPath, latestCapture?.path, captureProcess.job?.previewPath].filter(Boolean);
        if (files.length)
            Quickshell.execDetached(["rm", "-f", "--", ...files]);
    }

    LazyLoader {
        active: root.previewShown
        component: CapturePreview {
            screen: root.screenByName(root.latestCapture?.screenName)
            capture: root.latestCapture
            shown: root.previewShown
            onActionRequested: action => root.previewAction(action)
            onDismissed: root.previewShown = false
        }
    }

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property string selectionMode: "region"
    property bool systemAudio: true
    property bool microphone: false

    RecordingSession { id: recording }
    
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                onCaptureRequested: request => root.takeCapture(request)
                onModeSelected: mode => root.selectionMode = mode
                recordingAvailable: !recording.active
                onRecordingRequested: (args, delay, screenName) => recording.start(args, delay, screenName)
                onRecordingModeRequested: root.toggleRecordingMode()
                systemAudio: root.systemAudio
                microphone: root.microphone
                onSystemAudioToggled: root.systemAudio = !root.systemAudio
                onMicrophoneToggled: root.microphone = !root.microphone
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    function screenshot() {
        root.previewShown = false
        root.systemAudio = true
        root.microphone = false
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = "region"
        GlobalStates.regionSelectorOpen = true
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        root.selectionMode = "region"
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = "region"
        GlobalStates.regionSelectorOpen = true
    }

    function toggleRecordingMode() {
        if (root.action === RegionSelection.SnipAction.Record) {
            root.action = RegionSelection.SnipAction.Copy;
        } else if (!recording.active) {
            root.action = RegionSelection.SnipAction.Record;
        }
    }

    function record(withAudio) {
        if (recording.active)
            return;
        root.systemAudio = withAudio;
        root.microphone = false;
        root.action = RegionSelection.SnipAction.Record;
        root.selectionMode = "region";
        root.previewShown = false;
        GlobalStates.regionSelectorOpen = true;
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record(false)
        }
        function recordWithSound() {
            root.record(true)
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Open screenshot and video controls"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record(false)
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.record(true)
    }
}
