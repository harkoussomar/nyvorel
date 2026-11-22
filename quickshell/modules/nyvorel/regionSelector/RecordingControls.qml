pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

PanelWindow {
    id: root

    required property string phase
    required property int seconds
    required property bool busy
    signal controlRequested(string kind)

    readonly property bool paused: phase === "paused"
    readonly property bool canPause: phase === "recording" || paused
    readonly property bool pending: phase === "countdown"
    readonly property string status: {
        switch (phase) {
        case "countdown": return Translation.tr("Starting in %1 s").arg(seconds);
        case "starting": return Translation.tr("Starting recording");
        case "paused": return Translation.tr("Paused");
        case "stopping": return Translation.tr("Saving recording");
        default: return Translation.tr("Recording");
        }
    }
    readonly property string elapsed: {
        const hours = Math.floor(seconds / 3600);
        const minutes = String(Math.floor(seconds / 60) % 60).padStart(2, "0");
        const remainder = String(seconds % 60).padStart(2, "0");
        return (hours ? hours + ":" : "") + minutes + ":" + remainder;
    }

    color: "transparent"
    implicitWidth: actions.implicitWidth + 20
    implicitHeight: actions.implicitHeight + 10
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:recordingControls"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    mask: Region { item: surface }
    anchors { top: true; right: true }
    margins {
        top: 12 + (GlobalStates.barOpen && !Config.options.bar.vertical && !Config.options.bar.bottom ? Appearance.sizes.barHeight : 0)
        right: 12 + (GlobalStates.barOpen && Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 0)
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Appearance.radius.bar
        color: Appearance.m3colors.m3surfaceContainer
        border.color: Appearance.m3colors.m3outlineVariant

        RowLayout {
            id: actions
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                implicitWidth: 8
                implicitHeight: 8
                radius: width / 2
                color: root.phase === "recording" ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
            }
            StyledText {
                text: root.status
            }
            StyledText {
                visible: root.canPause || root.phase === "stopping"
                text: root.elapsed
                font.family: Appearance.font.family.monospace
                Accessible.name: Translation.tr("Recording time %1").arg(text)
            }
            CaptureButton {
                visible: root.canPause
                enabled: !root.busy
                iconName: root.paused ? "play_arrow" : "pause"
                text: root.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                tooltip: ""
                onClicked: root.controlRequested(root.paused ? "resume" : "pause")
            }
            CaptureButton {
                visible: root.canPause || root.pending
                enabled: !root.busy
                iconName: root.pending ? "close" : "stop"
                text: root.pending ? Translation.tr("Cancel") : Translation.tr("Stop")
                tooltip: ""
                onClicked: root.controlRequested("stop")
            }
        }
    }
}
