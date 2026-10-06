import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.nyvorel.sidebarRight.quickToggles.classicStyle

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"

    ButtonGroup {
        id: buttonGroup
        spacing:
            Appearance.inlayMode
                ? Appearance.spacing.sm
                : Appearance.prismMode
                    ? Appearance.spacing.md
                    : 5
        padding: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 5
        color:
            (Appearance.prismMode || Appearance.inlayMode)
                ? "transparent"
                : Appearance.colors.colLayer1

        NetworkToggle {
            altAction: () => {
                root.openWifiDialog();
            }
        }
        BluetoothToggle {
            altAction: () => {
                root.openBluetoothDialog();
            }
        }
        NightLight {}
        GameMode {}
        IdleInhibitor {}
        EasyEffectsToggle {}
        CloudflareWarp {}
    }
}
