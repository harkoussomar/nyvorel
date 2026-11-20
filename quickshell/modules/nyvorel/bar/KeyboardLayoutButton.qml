import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    readonly property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""
    readonly property bool popupOpen: GlobalStates.isBarPopupOpen("keyboardLayout", root.barScreenName)
    readonly property string activeCode: (KeyboardLayout.currentLayout
        || HyprlandXkb.currentLayoutCode || HyprlandXkb.layoutCodes[0]
        || "KB").split(":")[0].trim().toLowerCase()
    readonly property var layoutChoices: {
        const current = KeyboardLayout.currentCode
        const installed = KeyboardLayout.choices.filter(choice => choice.value !== "auto")
        const quick = [...new Set([current, "us", "gb", "it", "fr", "de", "es"].filter(Boolean))]
        const featured = quick.map(code => installed.find(choice => choice.value === code)
            ?? (code === current ? { value: code, displayName: KeyboardLayout.currentDisplay, readOnly: true } : null))
            .filter(Boolean)
        return featured.concat(installed.filter(choice => !quick.includes(choice.value)))
    }

    implicitWidth: 30
    implicitHeight: 28

    CircleUtilButton {
        id: button
        anchors.centerIn: parent
        implicitWidth: 30
        implicitHeight: 28
        Accessible.name: Translation.tr("Keyboard controls, current layout %1")
            .arg(root.activeCode.toUpperCase())
        toggled: root.popupOpen
        colBackgroundToggled: "transparent"
        colBackgroundToggledHover: Appearance.colors.colLayer1Hover
        onClicked: {
            KeyboardLayout.load()
            KeyboardLayout.refresh()
            GlobalStates.toggleBarPopup("keyboardLayout", root.barScreenName)
        }

        MaterialSymbol {
            text: "keyboard"
            iconSize: Appearance.font.pixelSize.large
            fill: 0
            horizontalAlignment: Qt.AlignHCenter
            color: root.popupOpen ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer2
        }
    }

    StyledPopup {
        hoverTarget: button
        showOnHover: false
        forceActive: root.popupOpen
        dismissOnOutsideClick: true
        irisAnimation: true
        popupRadius: Appearance.radius.bar
        contentMargin: 0
        onDismissRequested: GlobalStates.closeBarPopup("keyboardLayout", root.barScreenName)

        Item {
            id: menu
            implicitWidth: 240
            implicitHeight: body.implicitHeight + 2 * padding
            width: implicitWidth
            height: implicitHeight

            readonly property int padding: 10
            readonly property int rowHeight: 36
            readonly property int rowGap: 4
            readonly property int visibleRows: Math.min(6, Math.max(1, Math.floor(
                ((root.QsWindow?.window?.screen?.height ?? 720) - 152) / (rowHeight + rowGap))))

            ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: menu.padding
                spacing: 7

                ListView {
                    id: layoutList

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(menu.rowHeight,
                        Math.min(count, menu.visibleRows) * (menu.rowHeight + menu.rowGap) - menu.rowGap)
                    clip: true
                    spacing: menu.rowGap
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.layoutChoices
                    Accessible.name: Translation.tr("Keyboard layouts")

                    ScrollBar.vertical: StyledScrollBar {
                        policy: layoutList.count > menu.visibleRows ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                        topPadding: 2
                        bottomPadding: 2
                    }

                    delegate: RippleButton {
                        id: layoutOption
                        required property var modelData
                        readonly property bool selected: modelData.value === KeyboardLayout.currentCode
                        width: layoutList.width - (layoutList.count > menu.visibleRows ? 8 : 0)
                        height: menu.rowHeight
                        enabled: !modelData.readOnly && KeyboardLayout.catalogueReady && !KeyboardLayout.busy
                        buttonRadius: Appearance.radius.control
                        toggled: selected
                        colBackground: "transparent"
                        colBackgroundToggled: Appearance.colors.colLayer1Base
                        colBackgroundToggledHover: Appearance.colors.colLayer1Hover
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        Accessible.name: modelData.displayName
                        Accessible.selected: selected
                        onClicked: {
                            if (!selected)
                                KeyboardLayout.select(modelData.value)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: layoutOption.modelData.displayName
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                            MaterialSymbol {
                                visible: layoutOption.selected
                                text: "check"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        visible: layoutList.count === 0
                        text: KeyboardLayout.lastError.length > 0
                            ? Translation.tr("No layouts available") : Translation.tr("Loading layouts…")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                StyledText {
                    visible: KeyboardLayout.lastError.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    text: KeyboardLayout.lastError
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                RippleButton {
                    id: oskButton
                    readonly property string label: GlobalStates.oskOpen
                        ? Translation.tr("Close virtual keyboard") : Translation.tr("Open virtual keyboard")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    buttonRadius: Appearance.radius.control
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    Accessible.name: label
                    onClicked: {
                        GlobalStates.oskOpen = !GlobalStates.oskOpen
                        GlobalStates.closeBarPopup("keyboardLayout", root.barScreenName)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: oskButton.label
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }
    }
}
