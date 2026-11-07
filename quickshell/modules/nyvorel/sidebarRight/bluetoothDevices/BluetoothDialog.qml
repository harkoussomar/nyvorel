import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell

WindowDialog {
    id: root
    atlasStyle: true
    backgroundWidth: 520
    backgroundHeight: Math.min(height - 20, Math.max(245, 142 + Math.min(deviceList.contentHeight, 430)))

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        MaterialSymbol {
            text: "bluetooth"
            iconSize: 24
            color: Appearance.colors.colPrimary
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                text: Translation.tr("Bluetooth devices")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.material.textPrimary
            }
            StyledText {
                text: (Bluetooth.defaultAdapter?.discovering ?? false)
                    ? Translation.tr("Searching for devices")
                    : (deviceList.count + " " + Translation.tr("devices available"))
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.material.textMuted
            }
        }
    }

    StyledIndeterminateProgressBar {
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        Layout.fillWidth: true
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Appearance.colors.colLayer0Border
    }

    StyledListView {
        id: deviceList
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 70
        clip: true
        spacing: 7
        animateAppearance: false
        boundsBehavior: Flickable.StopAtBounds

        model: ScriptModel { values: BluetoothStatus.friendlyDeviceList }
        delegate: BluetoothDeviceItem {
            required property BluetoothDevice modelData
            device: modelData
            width: ListView.view.width
        }
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
                Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--", ...["bash", "-c", `${Config.options.apps.bluetooth}`]]);
                GlobalStates.sidebarRightOpen = false;
            }
        }
        Item { Layout.fillWidth: true }
    }
}
