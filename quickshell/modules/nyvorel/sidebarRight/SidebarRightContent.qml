import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

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
    readonly property real screenWidth: root.QsWindow?.window?.screen?.width ?? 1200
    readonly property real screenHeight: root.QsWindow?.window?.screen?.height ?? 900
    readonly property bool compact: screenWidth < 1000
    readonly property bool narrow: screenWidth < 760
    readonly property real availableHeight: screenHeight - (Config.options.bar.vertical ? 32 : 84)
    readonly property real quickPanelHeight: Math.max(200,
        Math.min(narrow ? 520 : 292, availableHeight - 213))
    readonly property int visibleNotificationCount: Math.min(4, Notifications.list.length)
    readonly property real activityTargetHeight: Math.max(132, 116 + visibleNotificationCount * 72)
    // Let the notification model settle before resizing the native popup once.
    property real activityHeight: activityTargetHeight
    onActivityTargetHeightChanged: activityRelayoutTimer.restart()
    Timer {
        id: activityRelayoutTimer
        interval: 16
        repeat: false
        onTriggered: root.activityHeight = root.activityTargetHeight
    }
    implicitWidth: Math.max(350, Math.min(compact ? 660 : 900,
        screenWidth - (Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 0) - 50))
    implicitHeight: Math.min(quickPanelHeight + 37 + 44 + activityHeight, availableHeight)

    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) return
            root.showWifiDialog = false
            root.showBluetoothDialog = false
            root.showAudioOutputDialog = false
            root.showAudioInputDialog = false
            root.showNightLightDialog = false
            root.editMode = false
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 11
        spacing: 11

        GridLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.quickPanelHeight
            Layout.minimumHeight: root.quickPanelHeight
            Layout.maximumHeight: root.quickPanelHeight
            columns: root.narrow ? 1 : 2
            columnSpacing: 11
            rowSpacing: 11

            QuickSliders {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 430
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 430
                radius: 13
                color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.62)
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 25
                        StyledText {
                            Layout.fillWidth: true
                            text: "Quick controls"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: `${(Config.options.sidebar.quickToggles.android.toggles?.length ?? 0)} CONTROLS`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.letterSpacing: 1.1
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentHeight: panelColumn.implicitHeight
                        ColumnLayout {
                            id: panelColumn
                            width: parent.width
                            spacing: 0
                            LoaderedQuickPanelImplementation {
                                styleName: "classic"
                                sourceComponent: ClassicQuickPanel {}
                            }
                            LoaderedQuickPanelImplementation {
                                styleName: "android"
                                sourceComponent: AndroidQuickPanel {
                                    editMode: false
                                    columnsOverride: 2
                                    cellHeightOverride: 68
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: root.activityHeight
            Layout.minimumHeight: 132
            radius: 13
            color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.62)
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 9
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 29
                    spacing: 8
                    StyledText {
                        text: "Activity"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Notifications.list.length > 0
                            ? `${Notifications.list.length} notifications` : "All clear"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    ActionTextButton {
                        buttonText: "Clear"
                        buttonIcon: "delete_sweep"
                        enabled: Notifications.list.length > 0
                        onActivated: Notifications.discardAllNotifications()
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colLayer0Border
                }
                NotificationListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    expandGroupsByDefault: true
                    popup: false
                    animateAppearance: false
                    visible: Notifications.list.length > 0
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: Notifications.list.length === 0
                    text: "You’re all caught up"
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 37
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: "CONTROLS / LOCAL"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.letterSpacing: 1.1
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }
            ActionIcon {
                visible: Config.options.sidebar.quickToggles.style === "android"
                symbol: "edit"
                toolTip: root.editMode ? "Finish editing controls" : "Edit quick controls"
                selected: root.editMode
                onActivated: root.editMode = !root.editMode
            }
            ActionIcon {
                symbol: "restart_alt"
                toolTip: "Reload Hyprland and Quickshell"
                onActivated: {
                    Quickshell.execDetached(["hyprctl", "reload"])
                    Quickshell.reload(true)
                }
            }
            ActionIcon {
                symbol: "settings"
                toolTip: "Open settings"
                onActivated: {
                    Quickshell.execDetached([`${Directories.home}/.local/bin/nyvorel-settings`])
                    GlobalStates.sidebarRightOpen = false
                }
            }
            ActionIcon {
                symbol: "power_settings_new"
                toolTip: "Session actions"
                onActivated: {
                    GlobalStates.sidebarRightOpen = false
                    GlobalStates.sessionOpen = true
                }
            }
        }
    }

    Rectangle {
        id: editSheet
        anchors.fill: parent
        anchors.margins: 6
        z: 10
        visible: root.editMode
        radius: Math.max(0, Math.round(Appearance.radius.bar / 2))
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                StyledText {
                    Layout.fillWidth: true
                    text: "Edit quick controls"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }
                ActionTextButton {
                    buttonText: "Done"
                    buttonIcon: "check"
                    onActivated: root.editMode = false
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: "Click a tile to add or remove it. Scroll over a tile to reorder."
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: editPanel.implicitHeight
                AndroidQuickPanel {
                    id: editPanel
                    width: parent.width
                    height: implicitHeight
                    editMode: true
                    columnsOverride: 3
                    cellHeightOverride: 56
                }
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




    component ActionIcon: Rectangle {
        id: action
        required property string symbol
        property string toolTip: ""
        property bool selected: false
        property bool hovered: hover.containsMouse
        signal activated()
        width: 36
        height: 36
        radius: 9
        color: selected ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.55)
            : hovered ? Appearance.colors.colLayer1Hover
            : ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        MaterialSymbol {
            anchors.centerIn: parent
            text: action.symbol
            iconSize: 21
            color: action.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.activated()
        }
        StyledToolTip { text: action.toolTip }
    }

    component ActionTextButton: Rectangle {
        id: action
        required property string buttonText
        required property string buttonIcon
        property bool hovered: hover.containsMouse
        signal activated()
        implicitWidth: label.implicitWidth + 36
        implicitHeight: 32
        radius: 8
        color: hovered && enabled ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        opacity: enabled ? 1 : 0.45
        RowLayout {
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                text: action.buttonIcon
                iconSize: 15
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                id: label
                text: action.buttonText
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer1
            }
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            enabled: action.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.activated()
        }
    }
}
