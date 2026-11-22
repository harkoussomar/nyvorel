pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Emojis.
 */
Singleton {
    id: root
    property string emojiScriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.sh`
    property list<string> list
    property bool loaded: false
    readonly property var preparedEntries: list.map(entry => ({ name: Fuzzy.prepare(entry), entry }))

    function fuzzyQuery(search: string): var {
        const term = search.trim().toLowerCase()
        if (!term)
            return root.list
        const words = term.split(/\s+/)
        const direct = root.list.filter(entry => words.every(word => entry.toLowerCase().includes(word)))
        if (direct.length)
            return direct
        return Fuzzy.go(term, preparedEntries, {key: "name"}).map(result => result.obj.entry)
    }

    function load() {
        emojiFileView.reload()
    }

    function updateEmojis(fileContent) {
        const lines = fileContent.split("\n")
        const start = lines.indexOf("### DATA ###")
        const end = lines.indexOf("NYVOREL_EMOJI_DATA", start + 1)
        const seen = new Set()
        root.list = start < 0 ? [] : lines.slice(start + 1, end < 0 ? lines.length : end)
            .map(line => line.trim()).filter(line => {
                const glyph = line.match(/^(\S+)\s+/)?.[1]
                if (!glyph || seen.has(glyph))
                    return false
                seen.add(glyph)
                return true
            })
        root.loaded = true
    }

    FileView {
        id: emojiFileView
        path: Qt.resolvedUrl(root.emojiScriptPath)
        onLoadedChanged: {
            if (emojiFileView.loaded)
                root.updateEmojis(emojiFileView.text())
        }
        onLoadFailed: error => { root.loaded = true }
    }
}
