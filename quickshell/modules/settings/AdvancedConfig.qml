import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

SettingsTabbedPage {
    id: root

    sections: [{ id: "configuration", label: Translation.tr("Configuration file"), icon: "data_object" }]

    readonly property int compactControlHeight: 38
    readonly property string configFilePath:
        FileUtils.trimFileProtocol(`${Directories.config}/nyvorel/config.json`)

    ContentSection {
        icon: "data_object"
        title: Translation.tr("Configuration file")
        Layout.fillWidth: true

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Edit advanced options")
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Edit config.json to change options without a Settings control. Saved changes reload automatically.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: "edit"
                    mainText: Translation.tr("Open config")
                    onClicked: Quickshell.execDetached([
                        Quickshell.shellPath("scripts/system/nyvorel-app-launch"),
                        "--open", root.configFilePath
                    ])
                }

                RippleButtonWithIcon {
                    id: copyConfigPathButton
                    property bool copied: false
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: copied ? "check" : "content_copy"
                    mainText: copied
                        ? Translation.tr("Path copied")
                        : Translation.tr("Copy path")
                    onClicked: {
                        Quickshell.clipboardText = root.configFilePath
                        copied = true
                        copyResetTimer.restart()
                    }
                    Timer {
                        id: copyResetTimer
                        interval: 1500
                        onTriggered: copyConfigPathButton.copied = false
                    }
                }
            }
        }
    }
}
