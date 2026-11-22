pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

Item {
    id: root

    required property string selectionMode
    required property bool captureOptions
    required property bool recordingAvailable
    required property bool precision
    required property int delaySeconds
    required property bool recording
    required property bool systemAudio
    required property bool microphone
    required property real availableWidth
    required property bool canConfirm

    signal selectMode(string mode)
    signal togglePrecision()
    signal cycleDelay()
    signal toggleRecordingMode()
    signal toggleSystemAudio()
    signal toggleMicrophone()
    signal confirmCapture()

    readonly property bool compact: availableWidth < 700
    readonly property int groupGap: 8
    readonly property real modeSpace: modeSwitch.visible ? modeSwitch.width + groupGap : 0
    readonly property real confirmSpace: confirm.visible ? confirm.width + groupGap : 0
    implicitWidth: modeSpace + actions.width + confirmSpace
    implicitHeight: actions.height

    Rectangle {
        id: actions
        x: root.modeSpace
        width: buttons.width + 16
        height: buttons.height + 16
        radius: Appearance.radius.bar
        color: Appearance.m3colors.m3surfaceContainer
        border.color: Appearance.m3colors.m3outlineVariant

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Flow {
            id: buttons
            anchors.centerIn: parent
            spacing: 3
            readonly property real naturalWidth: {
                const visibleButtons = Array.from(children).filter(item => item.visible && item.implicitWidth > 0)
                return visibleButtons.reduce((width, item) => width + item.implicitWidth, 0)
                    + Math.max(0, visibleButtons.length - 1) * spacing
            }
            width: Math.max(38, Math.min(naturalWidth, root.availableWidth - root.modeSpace - root.confirmSpace - 16))

            Repeater {
                model: [
                    {mode: "region", icon: "crop_free", label: Translation.tr("Region"), key: "1"},
                    {mode: "screen", icon: "desktop_windows", label: Translation.tr("Screen"), key: "2"}
                ]
                delegate: CaptureButton {
                    required property var modelData
                    visible: root.captureOptions || modelData.mode === "region"
                    iconName: modelData.icon
                    text: modelData.label
                    tooltip: text + " · " + modelData.key
                    showLabel: !root.compact
                    selected: root.selectionMode === modelData.mode
                    onClicked: root.selectMode(modelData.mode)
                }
            }

            CaptureButton {
                visible: root.captureOptions
                enabled: root.selectionMode === "region"
                iconName: "straighten"
                text: Translation.tr("Precision")
                showLabel: !root.compact
                tooltip: text + " · P"
                selected: root.precision
                onClicked: root.togglePrecision()
            }

            CaptureButton {
                visible: root.captureOptions
                iconName: "timer"
                text: root.delaySeconds ? Translation.tr("%1 s").arg(root.delaySeconds) : Translation.tr("Delay")
                tooltip: root.delaySeconds
                    ? Translation.tr("Capture delay: %1 seconds · D").arg(root.delaySeconds)
                    : Translation.tr("Capture delay off · D")
                selected: root.delaySeconds > 0
                onClicked: root.cycleDelay()
            }

            CaptureButton {
                visible: root.recording
                iconName: root.systemAudio ? "volume_up" : "volume_off"
                text: Translation.tr("System audio")
                tooltip: root.systemAudio ? Translation.tr("System audio on") : Translation.tr("System audio off")
                showLabel: !root.compact
                selected: root.systemAudio
                Accessible.checkable: true
                Accessible.checked: root.systemAudio
                onClicked: root.toggleSystemAudio()
            }

            CaptureButton {
                visible: root.recording
                iconName: root.microphone ? "mic" : "mic_off"
                text: Translation.tr("Microphone")
                tooltip: root.microphone ? Translation.tr("Microphone on") : Translation.tr("Microphone off")
                showLabel: !root.compact
                selected: root.microphone
                Accessible.checkable: true
                Accessible.checked: root.microphone
                onClicked: root.toggleMicrophone()
            }
        }
    }

    CaptureButton {
        id: modeSwitch
        anchors.left: parent.left
        anchors.top: actions.top
        height: actions.height
        visible: root.captureOptions
        enabled: root.recording || root.recordingAvailable
        opacity: enabled ? 1 : 0.48
        iconName: root.recording ? "photo_camera" : "videocam"
        text: root.recording ? Translation.tr("Photo") : Translation.tr("Video")
        tooltip: (root.recording ? Translation.tr("Switch to screenshot") : Translation.tr("Switch to video")) + " · V"
        showLabel: !root.compact
        foregroundColor: root.recording ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
        onClicked: root.toggleRecordingMode()

        background: Rectangle {
            radius: actions.radius
            color: root.recording
                ? (modeSwitch.down ? Appearance.colors.colPrimaryContainerActive
                    : modeSwitch.hovered ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
                : (modeSwitch.down ? Appearance.colors.colErrorContainerActive
                    : modeSwitch.hovered ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer)
            border.color: root.recording ? Appearance.colors.colPrimary : Appearance.colors.colError
            border.width: modeSwitch.visualFocus ? 2 : 1
        }
    }

    CaptureButton {
        id: confirm
        anchors.left: actions.right
        anchors.leftMargin: root.groupGap
        anchors.top: actions.top
        height: actions.height
        visible: root.canConfirm
        iconName: root.recording ? "radio_button_checked" : "photo_camera"
        text: root.recording ? Translation.tr("Record") : Translation.tr("Capture")
        tooltip: text + " · Enter"
        showLabel: !root.compact
        onClicked: root.confirmCapture()

        background: Rectangle {
            radius: actions.radius
            color: confirm.down || confirm.hovered ? Appearance.m3colors.m3surfaceContainerHigh : actions.color
            border.color: confirm.visualFocus ? Appearance.colors.colPrimary : actions.border.color
        }
    }
}
