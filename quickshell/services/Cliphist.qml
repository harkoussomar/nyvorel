pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))

    // SEARCH-CLIPBOARD-V2
    property int maxSearchResults: 200

    function entryId(entry) {
        const raw = `${entry ?? ""}`
        return raw.match(/^\s*(\S+)/)?.[1] ?? ""
    }

    function entryText(entry) {
        return `${entry ?? ""}`.replace(/^\s*\S+\s+/, "")
    }

    function entryUrls(entry) {
        const text = root.entryText(entry)
        const matches =
            text.match(/https?:\/\/[^\s<>"{}|\\^`\[\]]+/gi)

        return matches ? matches : []
    }

    function entryIsLink(entry) {
        return !root.entryIsImage(entry)
            && root.entryUrls(entry).length > 0
    }

    function entryKind(entry) {
        if (root.entryIsImage(entry))
            return "Image"

        if (root.entryIsLink(entry))
            return "Link"

        return "Text"
    }

    function entryKey(entry) {
        const id = root.entryId(entry)
        return id.length > 0
            ? `clipboard:${id}`
            : `clipboard:${root.entryText(entry)}`
    }

    function describeEntry(entry) {
        const urls = root.entryUrls(entry)
        const isImage = root.entryIsImage(entry)
        const isLink = !isImage && urls.length > 0

        return {
            rawValue: `${entry ?? ""}`,
            id: root.entryId(entry),
            key: root.entryKey(entry),
            text: root.entryText(entry),
            kind: isImage ? "Image" : isLink ? "Link" : "Text",
            isImage,
            isLink,
            urls
        }
    }

    function entryShouldBlur(entry, workSafetyActive) {
        return !!workSafetyActive && root.entryIsImage(entry)
    }
    // CLIPBOARD-FILTERS-V2.2
    // One query contract owns filtering, matching and limiting.
    function queryEntries(options): var {
        const opts = options ? options : ({})
        const search =
            opts.text !== undefined
                ? `${opts.text}`
                : ""
        const requestedType =
            opts.type !== undefined
                ? `${opts.type}`.toLowerCase()
                : "all"
        const requestedLimit =
            opts.limit !== undefined
                ? Number(opts.limit)
                : root.maxSearchResults
        const limit =
            Number.isFinite(requestedLimit)
            && requestedLimit > 0
                ? Math.floor(requestedLimit)
                : root.maxSearchResults

        const validType =
            requestedType === "text"
            || requestedType === "image"
            || requestedType === "link"
                ? requestedType
                : "all"

        const candidates =
            validType === "all"
                ? root.entries
                : root.entries.filter(
                    entry =>
                        root.entryKind(entry).toLowerCase()
                        === validType
                )

        if (search.trim() === "")
            return candidates.slice(0, limit)

        if (root.sloppySearch) {
            return candidates
                .map(str => ({
                    entry: str,
                    score:
                        Levendist.computeTextMatchScore(
                            root.entryText(str).toLowerCase(),
                            search.toLowerCase()
                        )
                }))
                .filter(
                    item =>
                        item.score > root.scoreThreshold
                )
                .sort(
                    (a, b) =>
                        b.score - a.score
                )
                .slice(0, limit)
                .map(item => item.entry)
        }

        const preparedCandidates =
            candidates.map(entry => ({
                name:
                    Fuzzy.prepare(
                        root.entryText(entry)
                    ),
                entry
            }))

        return Fuzzy.go(
            search,
            preparedCandidates,
            {
                all: true,
                key: "name"
            }
        )
            .slice(0, limit)
            .map(r => r.obj.entry)
    }

    // Backwards compatibility for callers outside Overview.
    function fuzzyQuery(search: string): var {
        return root.queryEntries({
            text: search,
            type: "all",
            limit: root.maxSearchResults
        })
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy`]);
        }
    }

    function paste(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && wl-paste`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy; ${root.pressPasteCommand}`]);
        }
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`)
        // Act
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)]);
    }

    Process {
        id: deleteProc
        property string entry: ""
        command: ["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(deleteProc.entry)}' | ${root.cliphistBinary} delete`]
        function deleteEntry(entry) {
            deleteProc.entry = entry;
            deleteProc.running = true;
            deleteProc.entry = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function deleteEntry(entry) {
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function wipe() {
        wipeProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
