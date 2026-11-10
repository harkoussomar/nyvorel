pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string helperPath: FileUtils.trimFileProtocol(
        Quickshell.shellPath("scripts/system/nyvorel-keyboard-layout")
    )
    property bool active: false
    property bool catalogueReady: false
    property bool statusReady: false
    property var catalogue: []
    property string currentLayout: ""
    property string currentVariant: ""
    property string activeKeymap: ""
    property string lastError: ""
    property string pendingCode: ""
    property string desiredCode: ""
    property string previousPreference: ""
    property string appliedPreference: ""
    property bool selectionSucceeded: false
    property bool restorePending: false
    property bool restoreSucceeded: false
    readonly property bool busy: selectionProc.running || restorePending

    readonly property string currentCode: currentLayout
        + (currentVariant.length > 0 ? ":" + currentVariant : "")
    readonly property string currentDisplay: {
        if (!statusReady)
            return "Detecting layout…"
        const item = catalogue.find(choice => choice.value === currentCode)
        if (item)
            return item.displayName
        if (activeKeymap.length > 0)
            return activeKeymap
        return currentCode.length > 0 ? currentCode : "Unknown layout"
    }
    readonly property var choices: {
        const items = catalogue.slice().sort((a, b) =>
            a.displayName.localeCompare(b.displayName))
        items.unshift({
            displayName: "Use Hyprland setting",
            value: "auto", layout: "", variant: "", family: "Hyprland"
        })
        return items
    }

    function filteredChoices(query: string): var {
        const text = query.toLowerCase().trim()
        if (text.length === 0)
            return choices
        return choices.filter(item =>
            `${item.displayName} ${item.family} ${item.layout} ${item.variant}`
                .toLowerCase().includes(text))
    }

    function load(): void {
        if (active)
            return
        active = true
        catalogProc.exec([helperPath, "catalog"])
        refresh()
        scheduleApply()
    }

    function refresh(): void {
        if (active && !statusProc.running)
            statusProc.exec([helperPath, "status"])
    }

    function scheduleApply(): void {
        if (active && Config.ready && !busy)
            applyTimer.restart()
    }

    function applyConfigured(): void {
        if (!active || !Config.ready || busy)
            return
        const code = Config.options.language.keyboardLayout
        if (!code || code === "auto") {
            appliedPreference = "auto"
            refresh()
            return
        }
        if (code === appliedPreference)
            return
        pendingCode = code
        selectionSucceeded = false
        selectionProc.exec([helperPath, "set", code])
    }

    function select(code: string): void {
        load()
        if (busy || !catalogueReady)
            return
        lastError = ""
        previousPreference = Config.options.language.keyboardLayout
        desiredCode = code
        selectionSettleTimer.restart()
        pendingCode = code
        selectionSucceeded = false
        if (code === "auto") {
            // Persist the intent before reloading Hyprland, so another running
            // Nyvorel process cannot reapply the old layout on configreloaded.
            restorePending = true
            restoreSucceeded = false
            Config.options.language.keyboardLayout = "auto"
            restoreTimer.restart()
        } else {
            selectionProc.exec([helperPath, "set", code])
        }
    }

    function acceptStatus(payload): void {
        currentLayout = payload.layout ?? ""
        currentVariant = payload.variant ?? ""
        activeKeymap = payload.activeKeymap ?? ""
        statusReady = true
    }

    Timer {
        id: applyTimer
        interval: 180
        repeat: false
        onTriggered: root.applyConfigured()
    }

    Timer {
        id: selectionSettleTimer
        interval: 2000
        repeat: false
        onTriggered: root.desiredCode = ""
    }

    Timer {
        id: reloadApplyTimer
        interval: 800
        repeat: false
        onTriggered: {
            root.appliedPreference = ""
            root.scheduleApply()
        }
    }

    Timer {
        id: restoreTimer
        // Let Config's preceding selection write settle before restoring
        // Hyprland and observing the persisted "auto" preference.
        interval: 400
        repeat: false
        onTriggered: restoreProc.exec([helperPath, "restore"])
    }

    Process {
        id: catalogProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(text)
                    if (!payload.ok)
                        throw new Error(payload.error ?? "Could not read XKB layouts")
                    root.catalogue = payload.choices
                    root.catalogueReady = true
                    root.lastError = ""
                } catch (error) {
                    root.lastError = String(error)
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !root.lastError)
                root.lastError = "Could not read installed keyboard layouts."
        }
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(text)
                    if (!payload.ok)
                        throw new Error(payload.error ?? "Could not read keyboard state")
                    root.acceptStatus(payload)
                    root.lastError = ""
                } catch (error) {
                    root.lastError = String(error)
                }
            }
        }
    }

    Process {
        id: selectionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(text)
                    if (!payload.ok)
                        throw new Error(payload.error ?? "Could not change keyboard layout")
                    root.acceptStatus(payload)
                    root.selectionSucceeded = true
                    root.lastError = ""
                } catch (error) {
                    root.lastError = String(error)
                }
            }
        }
        onExited: (code, status) => {
            if (code === 0 && root.selectionSucceeded) {
                root.appliedPreference = root.pendingCode
                Config.options.language.keyboardLayout = root.pendingCode
                root.refresh()
            } else if (!root.lastError) {
                root.lastError = "Could not change keyboard layout."
            }
            if (code !== 0 || !root.selectionSucceeded) {
                root.desiredCode = ""
                selectionSettleTimer.stop()
            }
            root.pendingCode = ""
        }
    }

    Process {
        id: restoreProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(text)
                    if (!payload.ok)
                        throw new Error(payload.error ?? "Could not restore Hyprland layout")
                    root.acceptStatus(payload)
                    root.restoreSucceeded = true
                    root.lastError = ""
                } catch (error) {
                    root.lastError = String(error)
                }
            }
        }
        onExited: (code, status) => {
            const succeeded = code === 0 && root.restoreSucceeded
            if (succeeded) {
                root.appliedPreference = "auto"
                root.refresh()
            } else {
                if (!root.lastError)
                    root.lastError = "Could not restore Hyprland layout."
                root.desiredCode = ""
                selectionSettleTimer.stop()
                Config.options.language.keyboardLayout = root.previousPreference
                root.appliedPreference = ""
            }
            root.pendingCode = ""
            root.restorePending = false
            if (!succeeded && root.previousPreference !== "auto")
                root.scheduleApply()
        }
    }

    Connections {
        target: Config
        function onReadyChanged() { root.scheduleApply() }
    }

    Connections {
        target: Config.options.language
        function onKeyboardLayoutChanged() {
            // A delayed FileView write from the previous choice must not undo
            // the user's latest selection while the transaction is settling.
            if (selectionSettleTimer.running && root.desiredCode.length > 0
                && Config.options.language.keyboardLayout !== root.desiredCode) {
                Config.options.language.keyboardLayout = root.desiredCode
                return
            }
            if (Config.options.language.keyboardLayout !== root.appliedPreference)
                root.scheduleApply()
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout")
                root.refresh()
            else if (event.name === "configreloaded") {
                root.refresh()
                if (!root.busy)
                    reloadApplyTimer.restart()
            }
        }
    }
}
