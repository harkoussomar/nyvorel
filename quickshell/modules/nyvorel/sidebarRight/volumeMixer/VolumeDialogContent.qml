import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

ColumnLayout {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property bool hasApps: appPwNodes.length > 0
    spacing: 9

    StyledText {
        text: Translation.tr("Applications")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.material.textMuted
    }

    StyledListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 75
        visible: root.hasApps
        clip: true
        spacing: 7
        animateAppearance: false
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: root.appPwNodes }
        delegate: VolumeMixerEntry {
            required property var modelData
            node: modelData
            width: ListView.view.width
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 75
        visible: !root.hasApps
        radius: 10
        color: Appearance.material.nestedFill
        border.width: 1
        border.color: Appearance.material.nestedBorder
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("No applications using this device")
            color: Appearance.material.textMuted
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    StyledText {
        text: root.isSink ? Translation.tr("Output device") : Translation.tr("Input device")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.material.textMuted
    }

    StyledComboBox {
        id: deviceSelector
        Layout.fillWidth: true
        Layout.fillHeight: false
        buttonRadius: 9
        model: root.devices.map(node => Audio.friendlyDeviceName(node))
        currentIndex: root.devices.findIndex(item => {
            if (root.isSink) {
                return item.id === Pipewire.defaultAudioSink?.id
            } else {
                return item.id === Pipewire.defaultAudioSource?.id
            }
        })
        onActivated: (index) => {
            const item = root.devices[index]
            if (root.isSink) {
                Audio.setDefaultSink(item)
            } else {
                Audio.setDefaultSource(item)
            }
        }
    }
}
