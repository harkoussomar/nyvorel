pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string category: "All"
    property string query: ""
    readonly property var categories: ["All", "Shell", "Windows", "Workspaces", "Capture", "Media", "System"]
    readonly property var allEntries: collectEntries(HyprlandKeybinds.keybinds)
    readonly property var filteredEntries: allEntries.filter(entry => {
        if (root.category !== "All" && entry.category !== root.category)
            return false
        const q = root.query.trim().toLowerCase()
        return q === "" || (entry.title + " " + entry.category + " " + entry.chord).toLowerCase().includes(q)
    })

    function displayKey(key) {
        const aliases = {
            "SUPER": "Super", "CTRL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift",
            "Slash": "/", "Period": ".", "Return": "Enter", "Space": "Space",
            "BackSpace": "Backspace", "mouse:272": "Left click", "mouse:273": "Right click",
            "mouse:274": "Middle click", "Super_L": "Super", "Super_R": "Super"
        }
        return aliases[String(key)] ?? String(key)
    }

    function actionTitle(bind) {
        const raw = String(bind.comment ?? "").trim()
        const key = String(bind.key ?? "")
        const mods = (bind.mods ?? []).join("+")
        if (raw === "Exec cmd") {
            if (mods === "SUPER" && key === "Y") return "Arch Remote"
            if (mods === "SUPER" && key === "U") return "Backup & Recovery"
            return ""
        }
        if (raw === "Global" || raw === "Window" || raw.startsWith("Execute:"))
            return ""
        const names = {
            "Clipboard history >> clipboard": "Clipboard history",
            "Emoji >> clipboard": "Emoji picker",
            "Toggle cheatsheet": "Shortcut guide",
            "Toggle search on tap": "Search and launch",
            "OCR region to clipboard": "Copy text from screen",
            "Region screenshot": "Capture a region",
            "Visual search": "Search what you see",
            "Toggle floating / tiled": "Toggle floating",
            "Move window to display on the left": "Move to left display",
            "Move window to display on the right": "Move to right display"
        }
        const title = names[raw] ?? raw.replace(/^Toggle /, "")
        return title.length > 0 ? title.charAt(0).toUpperCase() + title.slice(1) : ""
    }

    function categoryFor(title) {
        const text = title.toLowerCase()
        if (/capture|screenshot|record|ocr|text from screen|color picker|search what you see/.test(text)) return "Capture"
        if (/workspace|overview/.test(text)) return "Workspaces"
        if (/window|floating|fullscreen|scratchpad|split ratio|display|vm mode/.test(text)) return "Windows"
        if (/media|track|audio|volume|mute/.test(text)) return "Media"
        if (/suspend|lock|remote|backup|recovery|reload|session/.test(text)) return "System"
        return "Shell"
    }

    function collectEntries(tree) {
        const result = [], seen = new Set()
        function walk(node) {
            for (const bind of (node.keybinds ?? [])) {
                const title = root.actionTitle(bind)
                if (title === "") continue
                const rawKey = String(bind.key ?? "")
                if (rawKey === "catchall") continue
                const parts = [...(bind.mods ?? []), rawKey].map(root.displayKey)
                const chord = parts.filter((part, index) => !(part === "Super" && index > 0 && parts[0] === "Super")).join(" + ")
                const identity = chord.toLowerCase()
                if (seen.has(identity)) continue
                seen.add(identity)
                result.push({ title: title, chord: chord, category: root.categoryFor(title) })
            }
            for (const child of (node.children ?? [])) walk(child)
        }
        walk(tree ?? {})
        return result
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.preferredWidth: 174
            Layout.fillHeight: true
            Column {
                anchors.fill: parent
                anchors.topMargin: 17
                anchors.leftMargin: 16
                anchors.rightMargin: 18
                spacing: 4
                StyledText {
                    text: "CATEGORIES"
                    color: Appearance.colors.colOnLayer1Inactive
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    bottomPadding: 12
                }
                Repeater {
                    model: root.categories
                    delegate: Rectangle {
                        id: categoryButton
                        required property string modelData
                        width: parent.width
                        height: 37
                        radius: Appearance.rounding.small
                        color: root.category === modelData
                            ? Appearance.colors.colLayer1Active : "transparent"
                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            text: categoryButton.modelData
                            color: root.category === categoryButton.modelData
                                ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1
                            font.pixelSize: 12
                        }
                        StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: categoryButton.modelData === "All"
                                ? String(root.allEntries.length)
                                : String(root.allEntries.filter(e => e.category === categoryButton.modelData).length)
                            color: Appearance.colors.colOnLayer1Inactive
                            font.pixelSize: 10
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.category = categoryButton.modelData
                        }
                    }
                }
            }
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Appearance.colors.colLayer0Border
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 27
                anchors.rightMargin: 27
                anchors.topMargin: 18
                anchors.bottomMargin: 15
                spacing: 16
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15
                    Column {
                        Layout.fillWidth: true
                        spacing: 3
                        StyledText {
                            text: "Shortcuts"
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: 25
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: "COMMAND ATLAS"
                            color: Appearance.colors.colOnLayer1Inactive
                            font.pixelSize: 10
                            font.letterSpacing: 1.5
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: Math.min(315, root.width * 0.31)
                        Layout.preferredHeight: 38
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        MaterialSymbol {
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search"
                            color: Appearance.colors.colOnLayer1
                            iconSize: 18
                        }
                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.leftMargin: 42
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            activeFocusOnPress: true
                            color: Appearance.colors.colOnLayer0
                            selectionColor: Appearance.colors.colPrimary
                            font.family: Appearance.font.family.main
                            font.pixelSize: 12
                            onTextChanged: root.query = text
                        }
                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text === "" && !searchInput.activeFocus
                            enabled: false
                            text: "Action or key…"
                            color: Appearance.colors.colOnLayer1Inactive
                            font.pixelSize: 12
                        }
                        TapHandler {
                            onPressedChanged: {
                                if (pressed)
                                    searchInput.forceActiveFocus()
                            }
                        }
                    }
                }
                Flickable {
                    id: resultFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: rows.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    onContentHeightChanged: contentY = 0
                    Flow {
                        id: rows
                        width: resultFlick.width
                        spacing: 10
                        Repeater {
                            model: root.filteredEntries
                            delegate: Item {
                                id: entry
                                required property var modelData
                                width: rows.width < 660 ? rows.width : (rows.width - rows.spacing) / 2
                                height: 54
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Appearance.colors.colLayer0Border
                                }
                                StyledText {
                                    anchors.left: parent.left
                                    anchors.right: chord.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: entry.modelData.title
                                    color: Appearance.colors.colOnLayer0
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    id: chord
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: chordText.implicitWidth + 14
                                    height: 25
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer1
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0Border
                                    StyledText {
                                        id: chordText
                                        anchors.centerIn: parent
                                        text: entry.modelData.chord
                                        color: Appearance.colors.colOnLayer1
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                        StyledText {
                            visible: root.filteredEntries.length === 0
                            text: root.allEntries.length === 0 ? "Loading shortcuts…" : "No matching shortcuts."
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
}
