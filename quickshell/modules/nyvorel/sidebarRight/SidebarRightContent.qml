import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.nyvorel.sidebarRight.quickToggles
import qs.modules.nyvorel.sidebarRight.quickToggles.classicStyle

import qs.modules.nyvorel.sidebarRight.bluetoothDevices
import qs.modules.nyvorel.sidebarRight.nightLight
import qs.modules.nyvorel.sidebarRight.volumeMixer
import qs.modules.nyvorel.sidebarRight.wifiNetworks


Item {
    id: root

    property int sidebarWidth: 420
    property int sidebarPadding:
        Appearance.prismMode
            ? Appearance.prism.panelPadding
            : Appearance.spacing.lg

    property string settingsQmlPath:
        Quickshell.shellPath("settings.qml")

    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false


    Connections {
        target: GlobalStates

        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false
                root.showBluetoothDialog = false
                root.showAudioOutputDialog = false
                root.showAudioInputDialog = false
                root.showNightLightDialog = false
            }
        }
    }


    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth


    StyledRectangularShadow {
        visible: !Appearance.prismMode && !Appearance.inlayMode
        target: sidebarRightBackground
    }

    PrismSurface {
        visible: Appearance.prismMode
        x: sidebarRightBackground.x
        y: sidebarRightBackground.y
        width: sidebarRightBackground.width
        height: sidebarRightBackground.height
        depth: Appearance.prism.depthInteractive
        surfaceRadius: Appearance.prism.radiusInteractive
    }


    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent

        implicitHeight:
            parent.height
            - Appearance.sizes.hyprlandGapsOut * 2

        implicitWidth:
            root.sidebarWidth
            - Appearance.sizes.hyprlandGapsOut * 2

        // phase6b-material-pilot-v1
        // Legacy styles keep the existing chrome. Prism is rendered by the
        // depth-2 PrismSurface sibling behind this transparent content host.
        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.inlayMode
                    ? Appearance.inlay.surfaceFill
                    : Appearance.material.chromeFill
        border.width:
            Appearance.prismMode
                ? 0
                : Appearance.inlayMode
                    ? Appearance.inlay.borderWidth
                    : Appearance.material.frameBorderWidth
        border.color:
            Appearance.inlayMode
                ? Appearance.inlay.borderSubtle
                : Appearance.material.chromeBorder

        property real prismBaseSidebarRadius:
            Config.options.appearance.transparency.enable
                ? Appearance.radius.window
                : (
                    Appearance.rounding.screenRounding
                    - Appearance.sizes.hyprlandGapsOut
                    + 1
                )

        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusInteractive
                    : prismBaseSidebarRadius
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.sidebarPadding
            spacing:
                Appearance.prismMode
                    ? Appearance.spacing.md
                    : Appearance.spacing.lg


            SystemButtonRow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.topMargin:
                    Appearance.prismMode
                        ? 0
                        : Appearance.spacing.xs
            }

            PrismSectionDivider {}

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }


            LoaderedQuickPanelImplementation {
                styleName: "android"

                sourceComponent:
                    AndroidQuickPanel {
                        editMode: root.editMode
                    }
            }

            PrismSectionDivider {}

            RowLayout {
                visible: Appearance.prismMode || Appearance.inlayMode
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 24 : 0
                spacing: Appearance.spacing.md

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "notifications"
                    iconSize: 18
                    fill: 0
                    color: Appearance.material.textMuted
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Notifications")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.material.textSecondary
                }
            }

            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.topMargin:
                    Appearance.prismMode
                        ? -Appearance.spacing.xs
                        : 0
            }

            PrismSectionDivider {
                shown: slidersLoader.active
            }

            // Brightness and volume live at the bottom.
            Loader {
                id: slidersLoader

                Layout.fillWidth: true
                Layout.fillHeight: false

                visible: active

                active: {
                    const sliders =
                        Config.options.sidebar.quickSliders

                    if (!sliders.enable)
                        return false

                    return (
                        sliders.showBrightness
                        || sliders.showVolume
                        || sliders.showMic
                    )
                }

                sourceComponent: QuickSliders {}
            }
        }

}


    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"

        dialog:
            VolumeDialog {
                isSink: true
            }
    }


    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"

        dialog:
            VolumeDialog {
                isSink: false
            }
    }


    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}

        onShownChanged: {
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false
            } else {
                Bluetooth.defaultAdapter.enabled = true
                Bluetooth.defaultAdapter.discovering = true
            }
        }
    }


    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }


    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}

        onShownChanged: {
            if (!shown)
                return

            Network.enableWifi()
            Network.rescanWifi()
        }
    }


    component ToggleDialog: Loader {
        id: toggleDialogLoader

        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]

        anchors.fill: parent

        onShownChanged: {
            if (shown)
                toggleDialogLoader.active = true
        }

        active: shown

        onActiveChanged: {
            if (active && item) {
                item.show = true
                item.forceActiveFocus()
            }
        }

        Connections {
            target: toggleDialogLoader.item

            function onDismiss() {
                if (!toggleDialogLoader.item)
                    return

                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false
            }

            function onVisibleChanged() {
                if (
                    toggleDialogLoader.item
                    && !toggleDialogLoader.item.visible
                    && !root[toggleDialogLoader.shownPropertyString]
                ) {
                    toggleDialogLoader.active = false
                }
            }
        }
    }


    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader

        required property string styleName

        Layout.alignment:
            item?.Layout.alignment
            ?? Qt.AlignHCenter

        Layout.fillWidth:
            item?.Layout.fillWidth
            ?? false

        visible: active

        active:
            Config.options.sidebar.quickToggles.style
            === styleName

        Connections {
            target: quickPanelImplLoader.item

            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true
            }

            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true
            }

            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true
            }

            function onOpenNightLightDialog() {
                root.showNightLightDialog = true
            }

            function onOpenWifiDialog() {
                root.showWifiDialog = true
            }
        }
    }


    component PrismSectionDivider: Rectangle {
        property bool shown: true

        visible: (Appearance.prismMode || Appearance.inlayMode) && shown
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 1 : 0
        Layout.topMargin: visible ? Appearance.spacing.xs : 0
        Layout.bottomMargin: visible ? Appearance.spacing.xs : 0

        color:
            Appearance.inlayMode
                ? Appearance.inlay.borderSection
                : Appearance.prism.borderSubtle
        opacity: Appearance.inlayMode ? 1 : 0.62
    }


    component SystemButtonRow: Item {
        implicitHeight: 44


        Rectangle {
            id: uptimeContainer

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            implicitHeight: 40
            implicitWidth:
                uptimeRow.implicitWidth
                + ((Appearance.prismMode || Appearance.inlayMode) ? 8 : 22)

            radius:
                Appearance.inlayMode
                    ? 0
                    : Appearance.prismMode
                        ? Appearance.prism.radiusControl
                        : 18
            color:
                (Appearance.prismMode || Appearance.inlayMode)
                    ? "transparent"
                    : Appearance.material.groupFill


            Row {
                id: uptimeRow

                anchors.centerIn: parent
                spacing: Appearance.spacing.md


                CustomIcon {
                    anchors.verticalCenter: parent.verticalCenter

                    width: 24
                    height: 24

                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.material.textPrimary
                }


                StyledText {
                    anchors.verticalCenter: parent.verticalCenter

                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.material.textPrimary

                    text:
                        Translation.tr(
                            "Up %1"
                        ).arg(DateTime.uptime)

                    textFormat: Text.MarkdownText
                }
            }
        }


        ButtonGroup {
            id: systemButtonsRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            color:
                (Appearance.prismMode || Appearance.inlayMode)
                    ? "transparent"
                    : Appearance.material.groupFill
            padding:
                (Appearance.prismMode || Appearance.inlayMode)
                    ? 0
                    : Appearance.spacing.xxs


            QuickToggleButton {
                toggled: root.editMode

                visible:
                    Config.options.sidebar.quickToggles.style
                    === "android"

                buttonIcon: "edit"

                onClicked:
                    root.editMode = !root.editMode

                StyledToolTip {
                    text:
                        Translation.tr("Edit quick toggles")
                }
            }


            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"

                onClicked: {
                    Hyprland.dispatch("reload")
                    Quickshell.reload(true)
                }

                StyledToolTip {
                    text:
                        Translation.tr(
                            "Reload Hyprland & Quickshell"
                        )
                }
            }


            QuickToggleButton {
                toggled: false
                buttonIcon: "settings"

                onClicked: {
                    GlobalStates.sidebarRightOpen = false

                    Quickshell.execDetached(
                        [
                            "qs",
                            "-p",
                            root.settingsQmlPath
                        ]
                    )
                }

                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }


            QuickToggleButton {
                toggled: false
                buttonIcon: "power_settings_new"

                onClicked:
                    GlobalStates.sessionOpen = true

                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
