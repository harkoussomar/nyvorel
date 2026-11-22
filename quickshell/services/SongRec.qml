pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    enum MonitorSource { Monitor, Input }

    property int monitorSource: SongRec.MonitorSource.Monitor
    property int timeoutInterval: Config.options.musicRecognition.interval
    property int timeoutDuration: Config.options.musicRecognition.timeout
    readonly property bool running: recognition.running
    property bool cancelling: false
    property var recognizedTrack: null

    function toggleRunning(requested) {
        const start = requested === undefined ? !running : requested
        if (cancelling || start === running)
            return
        if (start) {
            cancelling = false
            notification.running = false
            recognition.running = true
        } else {
            cancelling = true
            recognition.running = false
        }
    }

    function toggleMonitorSource(source) {
        const next = monitorSource === SongRec.MonitorSource.Monitor ? SongRec.MonitorSource.Input : SongRec.MonitorSource.Monitor
        monitorSource = source === undefined ? next : source
    }

    function notifyFailure(code) {
        let message
        switch (code) {
        case 2: message = Translation.tr("No match. Keep the track playing and try again."); break
        case 3: message = Translation.tr("SongRec or an audio dependency is missing."); break
        case 4: message = Translation.tr("The selected audio source is unavailable."); break
        case 5: message = Translation.tr("Could not record audio from the selected source."); break
        default: message = Translation.tr("Could not reach the music recognition service. Try again."); break
        }
        Quickshell.execDetached(["notify-send", "-a", "Nyvorel", Translation.tr("Music recognition"), message])
    }

    Process {
        id: recognition
        command: [Quickshell.shellPath("scripts/musicRecognition/recognize-music.sh"),
            "-i", String(root.timeoutInterval), "-t", String(root.timeoutDuration),
            "-s", root.monitorSource === SongRec.MonitorSource.Monitor ? "monitor" : "input"]
        stdout: StdioCollector { id: response }
        onExited: (code, status) => {
            if (root.cancelling) {
                root.cancelling = false
                return
            }
            if (code !== 0 || status !== 0) {
                root.notifyFailure(code)
                return
            }
            try {
                const track = JSON.parse(response.text).track
                if (!track?.title)
                    throw new Error("Missing track title")
                root.recognizedTrack = track
                notification.running = true
            } catch (error) {
                root.notifyFailure(2)
            }
        }
    }

    Process {
        id: notification
        command: {
            const track = root.recognizedTrack
            if (!track)
                return []
            const description = [track.title, track.subtitle].filter(Boolean).join(" · ")
            return ["timeout", "20s", "notify-send", "-a", "Nyvorel", "-t", "12000",
                "--action=shazam=Shazam", "--action=youtube=YouTube",
                Translation.tr("Music recognized"), description]
        }
        stdout: StdioCollector { id: selection }
        onExited: {
            const track = root.recognizedTrack
            const action = selection.text.trim()
            if (!track || (action !== "shazam" && action !== "youtube"))
                return
            const query = encodeURIComponent([track.title, track.subtitle].filter(Boolean).join(" "))
            const url = action === "youtube" ? "https://www.youtube.com/results?search_query=" + query
                : /^https:\/\/(www\.)?shazam\.com\//i.test(track.url ?? "") ? track.url : "https://www.shazam.com/search/" + query
            Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", url])
        }
    }
}
