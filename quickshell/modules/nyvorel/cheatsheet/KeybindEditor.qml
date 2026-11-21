pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Controls.Popup {
    id: editor

    property var entry: null
    property bool resetAll: false
    property var recorded: null
    property var pressedKey: null
    property int heldModifiers: 0
    property bool recording: false
    property bool primaryHeld: false
    property bool cancelOnRelease: false
    property string feedback: ""
    property bool submitted: false
    readonly property bool editable: !!entry?.editor
    readonly property bool movable: !!entry?.editor?.movable
    readonly property bool changedChord: !!recorded && (recorded.mask !== entry?.mask
        || recorded.key.toLowerCase() !== entry?.key?.toLowerCase())
    readonly property bool edited: !!entry?.editor?.overridden
    readonly property string draftShortcut: recorded
        ? shortcutText(recorded.mask, recorded.label) : entry?.chord ?? ""
    readonly property string recorderText: !recording ? draftShortcut
        : !HyprlandKeybinds.captureActive ? Translation.tr("Starting recorder…")
        : pressedKey ? shortcutText(pressedKey.mask, pressedKey.label)
        : heldModifiers ? shortcutText(heldModifiers, "…") : Translation.tr("Press a key combination…")

    width: Math.min(510, parent.width - 26)
    x: Math.round((parent.width - width) / 2)
    y: Math.max(8, Math.round((parent.height - height) / 2))
    focus: true
    modal: true
    padding: 18
    closePolicy: editor.submitted || editor.recording ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape

    onClosed: stopRecording()
    Component.onDestruction: stopRecording()

    function shortcutText(mask: int, key: string): string {
        const modifiers = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]]
        return [...modifiers.filter(([bit]) => mask & bit).map(([, label]) => label), key].join(" + ")
    }

    function modifierMask(flags: int): int {
        return ((flags & Qt.MetaModifier) ? 64 : 0)
            | ((flags & Qt.ControlModifier) ? 4 : 0)
            | ((flags & Qt.AltModifier) ? 8 : 0)
            | ((flags & Qt.ShiftModifier) ? 1 : 0)
    }

    function modifierBit(key: int): int {
        switch (key) {
        case Qt.Key_Meta:
        case Qt.Key_Super_L:
        case Qt.Key_Super_R: return 64
        case Qt.Key_Control: return 4
        case Qt.Key_Alt: return 8
        case Qt.Key_Shift: return 1
        default: return 0
        }
    }

    function captureKey(event, mask: int) {
        const key = event.key
        const names = {
            [Qt.Key_Space]: ["space", "Space"],
            [Qt.Key_Tab]: ["Tab", "Tab"], [Qt.Key_Backtab]: ["Tab", "Tab"],
            [Qt.Key_Return]: ["Return", "Enter"], [Qt.Key_Escape]: ["Escape", "Esc"],
            [Qt.Key_Backspace]: ["BackSpace", "Backspace"], [Qt.Key_Delete]: ["Delete", "Delete"],
            [Qt.Key_Insert]: ["Insert", "Insert"],
            [Qt.Key_Left]: ["Left", "Left"], [Qt.Key_Right]: ["Right", "Right"],
            [Qt.Key_Up]: ["Up", "Up"], [Qt.Key_Down]: ["Down", "Down"],
            [Qt.Key_Home]: ["Home", "Home"], [Qt.Key_End]: ["End", "End"],
            [Qt.Key_PageUp]: ["Page_Up", "Page Up"], [Qt.Key_PageDown]: ["Page_Down", "Page Down"],
            [Qt.Key_Print]: ["Print", "Print Screen"], [Qt.Key_Pause]: ["Pause", "Pause"],
            [Qt.Key_Menu]: ["Menu", "Menu"],
            [Qt.Key_VolumeUp]: ["XF86AudioRaiseVolume", "Volume up"],
            [Qt.Key_VolumeDown]: ["XF86AudioLowerVolume", "Volume down"],
            [Qt.Key_VolumeMute]: ["XF86AudioMute", "Mute"], [Qt.Key_MicMute]: ["XF86AudioMicMute", "Mic mute"],
            [Qt.Key_MediaPlay]: ["XF86AudioPlay", "Play"], [Qt.Key_MediaPause]: ["XF86AudioPause", "Pause media"],
            [Qt.Key_MediaPrevious]: ["XF86AudioPrev", "Previous track"], [Qt.Key_MediaNext]: ["XF86AudioNext", "Next track"],
            [Qt.Key_MediaStop]: ["XF86AudioStop", "Stop media"],
            [Qt.Key_MonBrightnessUp]: ["XF86MonBrightnessUp", "Brightness up"],
            [Qt.Key_MonBrightnessDown]: ["XF86MonBrightnessDown", "Brightness down"]
        }
        const punctuation = {
            "-": "minus", "=": "equal", "[": "bracketleft", "]": "bracketright", "\\": "backslash",
            ";": "semicolon", "'": "apostrophe", "`": "grave", ",": "comma", ".": "period", "/": "slash"
        }
        const printable = key >= 0x21 && key < 0x01000000 ? String.fromCodePoint(key) : ""
        const keypad = !!(event.modifiers & Qt.KeypadModifier) || key === Qt.Key_Enter
        let pair = keypad ? null : names[key]
        if (!keypad && !pair) {
            if (key >= Qt.Key_F1 && key <= Qt.Key_F35) {
                const name = "F" + (key - Qt.Key_F1 + 1)
                pair = [name, name]
            } else if (/^[A-Z0-9]$/.test(printable)) {
                pair = [printable, printable]
            } else if (!(mask & 1) && punctuation[printable]) {
                pair = [punctuation[printable], printable]
            }
        }
        // Shift can change the glyph on a key. Its scan code still identifies
        // the key that Hyprland matches, including on non-US layouts and keypads.
        const scan = event.nativeScanCode
        if (!pair && scan >= 8 && scan <= 775) {
            const label = (keypad ? "Keypad " : "") + (printable || (names[key] || [])[1]
                || (key === Qt.Key_Enter ? "Enter" : "Keycode " + scan))
            pair = ["code:" + scan, label]
        }
        return pair ? {key: pair[0], label: pair[1], qtKey: key, scan, mask} : null
    }

    function startRecording(): void {
        if (recording || HyprlandKeybinds.captureBusy)
            return
        feedback = ""
        recorder.forceActiveFocus(Qt.OtherFocusReason)
        recording = true
        HyprlandKeybinds.setCapture(true)
    }

    function stopRecording(): void {
        if (!recording)
            return
        recording = false
        pressedKey = null
        heldModifiers = 0
        primaryHeld = false
        cancelOnRelease = false
        HyprlandKeybinds.setCapture(false)
    }

    function recordPress(event): void {
        if (!recording)
            return
        event.accepted = true
        if (event.isAutoRepeat)
            return
        const mask = modifierMask(event.modifiers)
        if (event.key === Qt.Key_Escape && mask === 0 && !(event.modifiers & Qt.GroupSwitchModifier)) {
            cancelOnRelease = true
            return
        }
        if (!HyprlandKeybinds.captureActive || pressedKey || cancelOnRelease)
            return
        heldModifiers = mask | modifierBit(event.key)
        if (modifierBit(event.key) || [Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_ScrollLock].includes(event.key))
            return
        if (event.modifiers & Qt.GroupSwitchModifier) {
            feedback = Translation.tr("Use Super, Ctrl, Alt or Shift to record a shortcut. AltGr is reserved for typing.")
            return
        }
        const candidate = captureKey(event, mask)
        if (!candidate) {
            feedback = Translation.tr("This key could not be recorded. Try another combination.")
            return
        }
        feedback = ""
        pressedKey = candidate
        primaryHeld = true
    }

    function recordRelease(event): void {
        if (!recording)
            return
        event.accepted = true
        if (event.isAutoRepeat)
            return
        if (cancelOnRelease && event.key === Qt.Key_Escape) {
            stopRecording()
            return
        }
        heldModifiers = modifierMask(event.modifiers) & ~modifierBit(event.key)
        if (!pressedKey)
            return
        if (pressedKey.scan ? event.nativeScanCode === pressedKey.scan : event.key === pressedKey.qtKey)
            primaryHeld = false
        if (!primaryHeld && heldModifiers === 0) {
            recorded = pressedKey
            stopRecording()
        }
    }

    function edit(entry): void {
        editor.entry = entry
        editor.resetAll = false
        editor.recorded = null
        editor.feedback = ""
        description.text = entry.title
        editor.open()
    }

    function confirmReset(): void {
        editor.entry = null
        editor.resetAll = true
        editor.feedback = ""
        editor.open()
    }

    function submit(args): void {
        editor.feedback = ""
        editor.submitted = true
        HyprlandKeybinds.apply(args)
    }

    Timer {
        interval: 12000
        running: editor.recording
        onTriggered: {
            editor.stopRecording()
            editor.feedback = Translation.tr("Recording timed out. Click the shortcut to try again.")
        }
    }

    Connections {
        target: HyprlandKeybinds
        function onCaptureFailed(message) {
            if (editor.opened) {
                editor.stopRecording()
                editor.feedback = message
            }
        }
        function onEditFinished(succeeded, message) {
            if (!editor.submitted)
                return
            editor.submitted = false
            if (succeeded)
                editor.close()
            else
                editor.feedback = message || Translation.tr("Could not save the shortcut.")
        }
    }

    background: Rectangle {
        color: Appearance.colors.colLayer0
        border.color: Appearance.colors.colLayer0Border
        border.width: 1
        radius: Appearance.radius.card
    }

    contentItem: ColumnLayout {
        spacing: 12

        StyledText {
            Layout.fillWidth: true
            text: editor.resetAll ? Translation.tr("Restore default shortcuts?") : Translation.tr("Edit shortcut")
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        StyledText {
            Layout.fillWidth: true
            text: editor.resetAll
                ? Translation.tr("Remove all edits made here and restore the original shortcuts and descriptions.")
                : ""
            visible: editor.resetAll
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !editor.resetAll

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Description")
                color: Appearance.colors.colOnLayer0
            }

            Controls.TextField {
                id: description
                Layout.fillWidth: true
                enabled: editor.editable && !editor.submitted
                maximumLength: 100
                selectByMouse: true
                Accessible.name: Translation.tr("Description")
                color: Appearance.colors.colOnLayer1
                selectionColor: Appearance.colors.colSecondaryContainer
                selectedTextColor: Appearance.colors.colOnSecondaryContainer
                font.family: Appearance.font.family.main
                background: Rectangle {
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1
                    border.color: description.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: editor.movable
                text: Translation.tr("Key combination")
                color: Appearance.colors.colOnLayer0
            }

            Controls.Button {
                id: recorder

                Layout.fillWidth: true
                Layout.preferredHeight: 43
                visible: editor.movable
                enabled: !editor.submitted
                Accessible.name: Translation.tr("Record key combination")
                Accessible.description: editor.recorderText

                onClicked: editor.startRecording()
                onActiveFocusChanged: if (!activeFocus) editor.stopRecording()
                Keys.onShortcutOverride: event => { if (editor.recording) event.accepted = true }
                Keys.onPressed: event => editor.recordPress(event)
                Keys.onReleased: event => editor.recordRelease(event)

                background: Rectangle {
                    radius: Appearance.radius.control
                    color: editor.recording || recorder.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                    border.color: editor.recording || recorder.visualFocus
                        ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                }

                contentItem: RowLayout {
                    spacing: 9
                    MaterialSymbol {
                        iconSize: 18
                        text: "keyboard"
                        color: editor.recording ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: editor.recorderText
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: editor.movable
                text: editor.recording ? Translation.tr("Esc to cancel") : Translation.tr("Click the shortcut, then press the new combination.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: !editor.editable ? Translation.tr("This binding is managed outside this editor.")
                    : editor.entry?.editor?.suspended ? Translation.tr("The saved shortcut is now in use. The original shortcut is active until you choose another.")
                    : !editor.movable ? Translation.tr("You can change the description for this special shortcut.")
                    : editor.entry?.editor?.count > 1 ? Translation.tr("Actions that share this shortcut move together.") : ""
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: editor.feedback.length > 0 || editor.submitted
            text: editor.submitted ? Translation.tr("Applying shortcuts…") : editor.feedback
            color: editor.submitted ? Appearance.colors.colSubtext : Appearance.colors.colError
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                visible: !editor.resetAll && editor.edited
                enabled: !editor.submitted && !editor.recording && !HyprlandKeybinds.captureBusy
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restore default")
                onClicked: editor.submit(["reset", editor.entry.editor.id])
            }

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                enabled: !editor.submitted
                materialIcon: "close"
                mainText: editor.editable || editor.resetAll ? Translation.tr("Cancel") : Translation.tr("Close")
                onClicked: editor.close()
            }

            RippleButtonWithIcon {
                visible: editor.editable || editor.resetAll
                enabled: !editor.submitted && !editor.recording && !HyprlandKeybinds.captureBusy && (editor.resetAll || (description.text.trim().length > 0
                    && (editor.changedChord || description.text.trim() !== editor.entry?.title)))
                materialIcon: editor.resetAll ? "restart_alt" : "check"
                mainText: editor.resetAll ? Translation.tr("Restore defaults") : Translation.tr("Save")
                onClicked: {
                    if (editor.resetAll)
                        editor.submit(["reset-all"])
                    else
                        editor.submit(["save", editor.entry.editor.id, editor.entry.editor.chord,
                            editor.entry.editor.label, String(editor.recorded?.mask ?? editor.entry.mask),
                            editor.changedChord ? editor.recorded.key : "", description.text.trim()])
                }
            }
        }
    }
}
