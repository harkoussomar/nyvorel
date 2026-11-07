import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    atlasStyle: true
    backgroundWidth: 520
    backgroundHeight: Math.min(height - 20, Math.max(245, 142 + Math.min(wifiList.contentHeight, 430)))

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        MaterialSymbol {
            text: "wifi"
            iconSize: 24
            color: Appearance.colors.colPrimary
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                text: Translation.tr("Connect to Wi-Fi")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.material.textPrimary
            }
            StyledText {
                text: Network.wifiScanning ? Translation.tr("Scanning for networks") :
                    (wifiList.count + " " + Translation.tr("networks available"))
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.material.textMuted
            }
        }
    }

    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Appearance.colors.colLayer0Border
    }

    StyledListView {
        id: wifiList
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 70
        clip: true
        spacing: 7
        animateAppearance: false
        boundsBehavior: Flickable.StopAtBounds

        model: ScriptModel { values: Network.friendlyWifiNetworks }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            wifiNetwork: modelData
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
        spacing: 4
        DialogButton {
            buttonText: "Network Operations"
            onClicked: {
                root.dismiss()
                GlobalStates.openBarPopup("network")
            }
        }
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--", ...["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]]);
                GlobalStates.sidebarRightOpen = false;
            }
        }
        Item { Layout.fillWidth: true }
    }
}
