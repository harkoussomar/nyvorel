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
    readonly property var allEntries: collectEntries(HyprlandKeybinds.bindings)
    readonly property var filteredEntries: allEntries.filter(entry => {
        if (root.category !== "All" && entry.category !== root.category)
            return false
        const q = root.query.trim().toLowerCase()
        return q === "" || (entry.title + " " + entry.category + " " + entry.chord
            + " " + (entry.editor?.defaultLabel ?? "")).toLowerCase().includes(q)
    })

    function displayKey(bind) {
        const aliases = {
            slash: "/", backslash: "\\", period: ".", comma: ",", return: "Enter",
            page_up: "Page Up", page_down: "Page Down", bracketleft: "[", bracketright: "]",
            semicolon: ";", apostrophe: "'", minus: "−", equal: "=",
            "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
            mouse_up: "Scroll up", mouse_down: "Scroll down",
            super_l: "Super", super_r: "Super",
            xf86audiolowervolume: "Volume down", xf86audioraisevolume: "Volume up",
            xf86audiomute: "Mute", xf86audiomicmute: "Mic mute", xf86audionext: "Next track",
            xf86audioprev: "Previous track", xf86audioplay: "Play", xf86audiopause: "Pause",
            xf86monbrightnessup: "Brightness up", xf86monbrightnessdown: "Brightness down"
        }
        const key = String(bind.key || "")
        if (key.length > 0) {
            const name = bind.mouse && /^\d+$/.test(key) ? "mouse:" + key : key
            return aliases[name.toLowerCase()] ?? (name.length === 1 ? name.toUpperCase() : name)
        }

        const code = Number(bind.keycode)
        if (code >= 10 && code <= 19)
            return String((code - 9) % 10)
        const keypad = { 79: 7, 80: 8, 81: 9, 82: "−", 83: 4, 84: 5, 85: 6,
            86: "+", 87: 1, 88: 2, 89: 3, 90: 0 }
        if (code in keypad)
            return "Keypad " + keypad[code]
        return bind.displayKey || (code > 0 ? "Keycode " + code : "")
    }

    function categoryFor(title) {
        const text = title.toLowerCase()
        if (/capture|screenshot|record|ocr|color|text from a region|search what you see/.test(text)) return "Capture"
        if (/workspace|overview/.test(text)) return "Workspaces"
        if (/window|floating|fullscreen|scratchpad|split ratio|display|virtual machine/.test(text)) return "Windows"
        if (/media|track|audio|volume|mute|microphone/.test(text)) return "Media"
        if (/suspend|lock|remote|backup|recovery|reload|session|brightness|shut down|task manager/.test(text)) return "System"
        return "Shell"
    }

    function collectEntries(bindings) {
        const modifiers = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"], [2, "Caps Lock"],
            [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]]
        const result = []
        const seen = new Set()
        for (const bind of bindings) {
            const title = String(bind.description ?? "").trim()
            if (!title || title.startsWith("[hidden]") || bind.catch_all || (bind.submap && bind.submap !== "global"))
                continue
            const key = root.displayKey(bind)
            if (!key)
                continue
            const mask = Number(bind.modmask)
            const parts = modifiers.filter(([bit, label]) => (mask & bit) && label !== key)
                .map(([, label]) => label)
            const chord = [...parts, key].join(" + ")
            const identity = (bind.editor?.id ?? chord.toLowerCase()) + "\n" + title.toLowerCase()
            if (seen.has(identity))
                continue
            seen.add(identity)
            result.push({ title, chord, mask, keyLabel: key, editor: bind.editor,
                key: bind.keycode ? `code:${bind.keycode}` : String(bind.key ?? ""),
                category: root.categoryFor(bind.editor?.defaultLabel ?? title) })
        }
        return result
    }

    KeybindEditor { id: bindingEditor; parent: root }

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
                    }
                    RippleButtonWithIcon {
                        implicitHeight: 36
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Restore defaults")
                        enabled: HyprlandKeybinds.customized && !HyprlandKeybinds.saving
                        onClicked: bindingEditor.confirmReset()
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
                            delegate: RippleButton {
                                id: entry
                                required property var modelData
                                width: rows.width < 660 ? rows.width : (rows.width - rows.spacing) / 2
                                height: 54
                                enabled: !HyprlandKeybinds.saving
                                activeFocusOnTab: true
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                buttonRadius: Appearance.radius.control
                                Accessible.name: modelData.title + ", " + modelData.chord
                                onClicked: bindingEditor.edit(modelData)

                                contentItem: Item {
                                  Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Appearance.colors.colLayer0Border
                                }
                                  StyledText {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
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
                                    anchors.right: editIcon.left
                                    anchors.rightMargin: 8
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
                                  MaterialSymbol {
                                    id: editIcon
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: entry.modelData.editor ? "edit" : "info"
                                    iconSize: 14
                                    color: entry.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                  }
                                }
                            }
                        }
                        StyledText {
                            visible: root.filteredEntries.length === 0
                            text: !HyprlandKeybinds.loaded ? Translation.tr("Loading shortcuts…")
                                : HyprlandKeybinds.failed ? Translation.tr("Could not read active Hyprland shortcuts.")
                                : root.allEntries.length === 0 ? Translation.tr("No described shortcuts are active.")
                                : Translation.tr("No matching shortcuts.")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
}
