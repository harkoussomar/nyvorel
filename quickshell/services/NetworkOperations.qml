pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root
    readonly property string backend: Quickshell.shellPath("scripts/system/nyvorel-network")
    property bool active: false
    property var snapshot: ({"ok": false})
    property var checks: []
    property var comparison: []
    property var samples: []
    property string message: ""
    property string error: ""
    property bool operationBusy: mutation.running
    property bool doctorBusy: doctorProcess.running
    property bool comparisonBusy: comparisonProcess.running
    property real downloadRate: 0
    property real uploadRate: 0
    property real lastRx: -1
    property real lastTx: -1
    property real lastSampleTime: 0

    function parse(text) {
        try { return JSON.parse(text) }
        catch (e) { return {"ok": false, "error": "Network backend returned invalid data"} }
    }
    function refresh() {
        if (active && !snapshotProcess.running)
            snapshotProcess.exec([backend, "snapshot"])
    }
    function setDns(provider, primary, secondary) {
        if (operationBusy) return
        error = ""
        message = ""
        const args = [backend, "dns", "set", provider]
        if (provider === "custom") {
            if (primary && primary.trim().length) args.push(primary.trim())
            if (secondary && secondary.trim().length) args.push(secondary.trim())
        }
        mutation.exec(args)
    }
    function rollbackDns() {
        if (operationBusy) return
        error = ""
        message = ""
        mutation.exec([backend, "dns", "rollback"])
    }
    function runDoctor() {
        if (!doctorProcess.running) doctorProcess.exec([backend, "doctor"])
    }
    function compareDns() {
        if (!comparisonProcess.running) comparisonProcess.exec([backend, "compare"])
    }
    onActiveChanged: {
        if (active) refresh()
        else snapshotProcess.running = false
    }
    Connections {
        target: Network
        function onNetworkNameChanged() { root.refresh() }
        function onWifiStatusChanged() { root.refresh() }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }
    Process {
        id: snapshotProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text)
                if (!result.ok) { root.error = result.error || "Network snapshot unavailable"; return }
                root.snapshot = result
                const traffic = result.traffic || {}
                const rx = Number(traffic.rx || 0)
                const tx = Number(traffic.tx || 0)
                const now = Date.now()
                const seconds = (now - root.lastSampleTime) / 1000
                if (root.lastSampleTime > 0 && seconds > 0 && rx >= root.lastRx && tx >= root.lastTx) {
                    root.downloadRate = (rx - root.lastRx) / seconds
                    root.uploadRate = (tx - root.lastTx) / seconds
                    const history = root.samples.slice(-59)
                    history.push({"down": root.downloadRate, "up": root.uploadRate, "at": now})
                    root.samples = history
                }
                root.lastRx = rx
                root.lastTx = tx
                root.lastSampleTime = now
            }
        }
    }
    Process {
        id: mutation
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text)
                root.message = result.message || ""
                root.error = result.ok ? "" : (result.error || result.message || "DNS change failed")
                root.refresh()
                Network.update()
            }
        }
    }
    Process {
        id: doctorProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text)
                root.checks = result.ok ? (result.checks || []) : []
                if (!result.ok) root.error = result.error || "Diagnostics failed"
            }
        }
    }
    Process {
        id: comparisonProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parse(text)
                root.comparison = result.ok ? (result.results || []) : []
                if (!result.ok) root.error = result.error || "DNS comparison failed"
            }
        }
    }
}
