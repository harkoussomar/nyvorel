pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

WindowDialog {
    id: root
    atlasStyle: true
    property bool isSink: true
    readonly property int applicationCount: isSink ? Audio.outputAppNodes.length : Audio.inputAppNodes.length
    backgroundWidth: 520
    backgroundHeight: Math.min(height - 20, Math.max(290, 205 + Math.min(applicationCount, 6) * 70))

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        MaterialSymbol {
            text: root.isSink ? "volume_up" : "mic"
            iconSize: 24
            color: Appearance.colors.colPrimary
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                text: root.isSink ? Translation.tr("Audio output") : Translation.tr("Audio input")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.material.textPrimary
            }
            StyledText {
                text: root.applicationCount + " " + Translation.tr("applications")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.material.textMuted
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Appearance.colors.colLayer0Border
    }

    VolumeDialogContent {
        Layout.fillWidth: true
        Layout.fillHeight: true
        isSink: root.isSink
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Appearance.colors.colLayer0Border
    }
    RowLayout {
        Layout.fillWidth: true
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--", ...["bash", "-c", `${Config.options.apps.volumeMixer}`]]);
                GlobalStates.sidebarRightOpen = false;
            }
        }
        Item { Layout.fillWidth: true }
    }
}
