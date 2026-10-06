pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Flickable {
    id: root
    readonly property var keybinds: HyprlandKeybinds.keybinds
    property real spacing: 20
    property real titleSpacing: 7
    property real padding: 4
    property real maxCommentWidth: 300

    implicitWidth:
        row.implicitWidth + padding * 2

    // Keep the cheatsheet comfortably below full-screen height.
    // All shortcuts remain available through vertical scrolling.
    implicitHeight:
        Math.min(
            row.implicitHeight + padding * 2,
            560
        )

    contentWidth:
        row.implicitWidth + padding * 2

    contentHeight:
        row.implicitHeight + padding * 2

    flickableDirection:
        Flickable.VerticalFlick

    boundsBehavior:
        Flickable.StopAtBounds

    interactive:
        contentHeight > height

    clip:
        true
    // Excellent symbol explaination and source :
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
      })
    property var functionSymbolMap: ({
        "F1":  "󱊫",
        "F2":  "󱊬",
        "F3":  "󱊭",
        "F4":  "󱊮",
        "F5":  "󱊯",
        "F6":  "󱊰",
        "F7":  "󱊱",
        "F8":  "󱊲",
        "F9":  "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶",
    })

    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    property var keyBlacklist: ["Super_L"]
    property var keySubstitutions: Object.assign({
        "Super": "",
        "mouse_up": "Scroll ↓",    // ikr, weird
        "mouse_down": "Scroll ↑",  // trust me bro
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        // "Shift": "",
      },
      !!Config.options.cheatsheet.superKey ? {
          "Super": Config.options.cheatsheet.superKey,
      }: {},
      Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
      Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
      Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    Row { // Keybind columns
        id: row

        x:
            root.padding

        y:
            root.padding

        spacing:
            root.spacing
        
        Repeater {
            model: keybinds.children
            
            delegate: Column { // Keybind sections
                spacing: root.spacing
                required property var modelData
                anchors.top: row.top

                Repeater {
                    model: modelData.children

                    delegate: Item { // Section with real keybinds
                        id: keybindSection
                        required property var modelData
                        implicitWidth: sectionColumn.implicitWidth
                        implicitHeight: sectionColumn.implicitHeight

                        Column {
                            id: sectionColumn
                            anchors.centerIn: parent
                            spacing: root.titleSpacing
                            
                            StyledText {
                                id: sectionTitle
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.title
                                    variableAxes: Appearance.font.variableAxes.title
                                }
                                color: Appearance.colors.colOnLayer0
                                text: keybindSection.modelData.name
                            }

                            GridLayout {
                                id: keybindGrid
                                columns: 2
                                columnSpacing: 4
                                rowSpacing: 4

                                Repeater {
                                    model: {
                                        var result = [];
                                        for (var i = 0; i < keybindSection.modelData.keybinds.length; i++) {
                                            const keybind = keybindSection.modelData.keybinds[i];

                                            if (!Config.options.cheatsheet.splitButtons) {
                                                for (var j = 0; j < keybind.mods.length; j++) {
                                                    keybind.mods[j] = keySubstitutions[keybind.mods[j]] || keybind.mods[j];
                                                }
                                                keybind.mods = [keybind.mods.join(' ') ]
                                                keybind.mods[0] += !keyBlacklist.includes(keybind.key) && keybind.mods[0].length ? ' ' : ''
                                                keybind.mods[0] += !keyBlacklist.includes(keybind.key) ? (keySubstitutions[keybind.key] || keybind.key) : ''
                                            } 

                                            result.push({
                                                "type": "keys",
                                                "mods": keybind.mods,
                                                "key": keybind.key,
                                            });
                                            result.push({
                                                "type": "comment",
                                                "comment": keybind.comment,
                                            });
                                        }
                                        return result;
                                    }
                                    delegate: Item {
                                        required property var modelData
                                        implicitWidth: keybindLoader.implicitWidth
                                        implicitHeight: keybindLoader.implicitHeight

                                        Loader {
                                            id: keybindLoader
                                            sourceComponent: (modelData.type === "keys") ? keysComponent : commentComponent
                                        }

                                        Component {
                                            id: keysComponent
                                            Row {
                                                spacing: 4
                                                Repeater {
                                                    model: modelData.mods
                                                    delegate: KeyboardKey {
                                                        required property var modelData
                                                        key: keySubstitutions[modelData] || modelData
                                                        pixelSize: Config.options.cheatsheet.fontSize.key
                                                    }
                                                }
                                                StyledText {
                                                    id: keybindPlus
                                                    visible: Config.options.cheatsheet.splitButtons && !keyBlacklist.includes(modelData.key) && modelData.mods.length > 0
                                                    text: "+"
                                                }
                                                KeyboardKey {
                                                    id: keybindKey
                                                    visible: Config.options.cheatsheet.splitButtons && !keyBlacklist.includes(modelData.key)
                                                    key: keySubstitutions[modelData.key] || modelData.key
                                                    pixelSize: Config.options.cheatsheet.fontSize.key
                                                    color: Appearance.colors.colOnLayer0
                                                }
                                            }
                                        }

                                        Component {
                                            id: commentComponent
                                            Item {
                                                id: commentItem

                                                implicitWidth:
                                                    Math.min(
                                                        commentText.implicitWidth + 16,
                                                        root.maxCommentWidth
                                                    )

                                                implicitHeight:
                                                    commentText.implicitHeight

                                                StyledText {
                                                    id: commentText

                                                    anchors {
                                                        left: parent.left
                                                        right: parent.right
                                                        verticalCenter: parent.verticalCenter
                                                        leftMargin: 8
                                                        rightMargin: 8
                                                    }

                                                    font.pixelSize:
                                                        Config.options.cheatsheet.fontSize.comment
                                                        || Appearance.font.pixelSize.smaller

                                                    text:
                                                        modelData.comment

                                                    elide:
                                                        Text.ElideRight

                                                    wrapMode:
                                                        Text.NoWrap

                                                    maximumLineCount:
                                                        1
                                                }
                                            }
                                        }
                                    }

                                }
                            }
                        }
                    }

                }
            }
            
        }
    }
    
}
