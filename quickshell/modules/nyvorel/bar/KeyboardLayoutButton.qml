import QtQuick
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
    readonly property var quickChoices: {
        const codes = ["auto", KeyboardLayout.currentCode, "us", "gb", "it", "fr", "de", "es"]
        const seen = new Set()
        return codes.filter(code => {
            if (!code || seen.has(code)) return false
            seen.add(code)
            return code === "auto" || KeyboardLayout.catalogue.some(choice => choice.value === code)
        }).map(code => code === "auto"
            ? { value: "auto", displayName: Translation.tr("Use Hyprland setting") }
            : KeyboardLayout.catalogue.find(choice => choice.value === code))
    }
    readonly property var layoutChoices: {
        const quick = root.quickChoices
        const used = new Set(quick.map(choice => choice.value))
        return quick.concat(KeyboardLayout.choices.filter(choice => !used.has(choice.value)))
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
        contentMargin: 10
        onDismissRequested: GlobalStates.closeBarPopup("keyboardLayout", root.barScreenName)

        Item {
            width: 220
            implicitWidth: width
            implicitHeight: KeyboardLayout.lastError.length > 0 ? 346 : 310

            ListView {
                id: layoutList
                x: 12
                width: parent.width
                height: parent.height - (KeyboardLayout.lastError.length > 0 ? 80 : 42)
                clip: true
                spacing: 3
                boundsBehavior: Flickable.StopAtBounds
                model: root.layoutChoices

                delegate: RippleButton {
                    required property var modelData
                    readonly property bool selected: Config.options.language.keyboardLayout === "auto"
                        ? modelData.value === "auto"
                        : modelData.value === KeyboardLayout.currentCode
                    width: layoutList.width - 8
                    implicitHeight: 38
                    enabled: KeyboardLayout.catalogueReady && !KeyboardLayout.busy
                    buttonRadius: Appearance.radius.control
                    toggled: selected
                    colBackground: "transparent"
                    colBackgroundToggled: Appearance.colors.colLayer1Base
                    colBackgroundToggledHover: Appearance.colors.colLayer1Hover
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: KeyboardLayout.select(modelData.value)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.displayName
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialSymbol {
                            visible: selected
                            text: "check"
                            iconSize: 16
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            StyledText {
                visible: KeyboardLayout.lastError.length > 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: oskButton.top
                anchors.bottomMargin: 7
                text: KeyboardLayout.lastError
                wrapMode: Text.WordWrap
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            Rectangle {
                x: 12
                y: oskButton.y - 5
                width: parent.width - 8
                height: 1
                color: Appearance.colors.colLayer0Border
            }

            RippleButton {
                id: oskButton
                x: 12
                y: parent.height - 34
                width: parent.width - 8
                implicitHeight: 32
                buttonRadius: Appearance.radius.control
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
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
                        text: GlobalStates.oskOpen
                            ? Translation.tr("Close virtual keyboard")
                            : Translation.tr("Open virtual keyboard")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
