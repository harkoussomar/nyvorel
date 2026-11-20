import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: root
    required property bool targetEnabled
    readonly property int controlHeight: 44
    readonly property int compactControlHeight: 38
    property bool terminalTuningExpanded: false
    spacing: 8

    component FieldLabel: ColumnLayout {
        required property string title
        property string subtitle: ""

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: parent.title
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }

        StyledText {
            visible: parent.subtitle.length > 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: parent.subtitle
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
        }
    }

    component PreferenceSwitchRow: RippleButton {
        id: row

        required property string title
        required property string iconName

        property string subtitle: ""
        property bool switchChecked: false

        signal userToggled(bool checked)

        Layout.fillWidth: true
        implicitHeight: Math.max(root.controlHeight, rowContent.implicitHeight + 18)

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control

        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        Accessible.role: Accessible.CheckBox
        Accessible.name: title
        Accessible.description: subtitle
        Accessible.checked: switchChecked

        onClicked: row.userToggled(!row.switchChecked)

        contentItem: RowLayout {
            id: rowContent

            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 10

            MaterialSymbol {
                text: row.iconName
                iconSize: 18
                color: row.enabled
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
                opacity: row.enabled ? 1 : 0.45
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: row.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    opacity: row.enabled ? 1 : 0.45
                    wrapMode: Text.Wrap
                }

                StyledText {
                    visible: row.subtitle.length > 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: row.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    opacity: row.enabled ? 1 : 0.45
                    wrapMode: Text.Wrap
                }
            }

            StyledSwitch {
                checked: row.switchChecked
                enabled: row.enabled

                onToggled: row.userToggled(checked)
            }
        }
    }

    component InfoBox: Rectangle {
        id: box

        property string text: ""
        property string iconName: "info"

        Layout.fillWidth: true
        implicitHeight: infoRow.implicitHeight + 18

        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1
        clip: true

        RowLayout {
            id: infoRow

            anchors.fill: parent
            anchors.margins: 9
            spacing: 8

            MaterialSymbol {
                text: box.iconName
                iconSize: 18
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: box.text
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }
        }
    }

    component ExpandButton: RippleButtonWithIcon {
        id: expand

        required property string collapsedText
        required property string expandedText
        required property bool expanded

        Layout.fillWidth: true
        implicitHeight: root.compactControlHeight

        buttonRadius: Appearance.radius.control
        materialIcon: expanded ? "expand_less" : "expand_more"
        mainText: expanded ? expandedText : collapsedText

        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
    }

    component SliderSetting: Rectangle {
        id: setting

        required property string title
        required property string iconName

        property string subtitle: ""
        property string valueLabel: ""
        property real sliderValue: 0
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property var stopIndicatorValues: []

        signal moved(real value)

        Layout.fillWidth: true
        implicitHeight: sliderColumn.implicitHeight + 18

        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1
        clip: true

        ColumnLayout {
            id: sliderColumn

            anchors {
                fill: parent
                margins: 9
            }

            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: setting.iconName
                    iconSize: 17
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: setting.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        visible: setting.subtitle.length > 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: setting.subtitle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }
                }

                StyledText {
                    text: setting.valueLabel
                    color: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.XS
                from: setting.from
                to: setting.to
                stepSize: setting.stepSize
                value: setting.sliderValue
                stopIndicatorValues: setting.stopIndicatorValues
                usePercentTooltip: false

                onMoved: setting.moved(value)
            }
        }
    }

    FieldLabel {
        Layout.topMargin: 2
        title: Translation.tr("Terminal appearance")
        subtitle: Translation.tr("These controls affect terminal palette generation only.")
    }

    PreferenceSwitchRow {
        enabled:
            root.targetEnabled

        title: Translation.tr("Force dark terminal palette")
        subtitle:
            root.targetEnabled
                ? Translation.tr("Prefer a dark generated terminal palette regardless of the current light/dark appearance.")
                : Translation.tr("Enable Terminal theming first.")
        iconName: "dark_mode"
        switchChecked:
            Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode

        onUserToggled: checked => {
            Config.options.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode =
                checked
        }
    }

    ExpandButton {
        enabled:
            root.targetEnabled

        collapsedText: Translation.tr("Terminal color tuning")
        expandedText: Translation.tr("Hide terminal color tuning")
        expanded: root.terminalTuningExpanded

        onClicked: {
            root.terminalTuningExpanded =
                !root.terminalTuningExpanded
        }
    }

    ColumnLayout {
        visible:
            root.terminalTuningExpanded
            && root.targetEnabled

        Layout.fillWidth: true
        spacing: 8

        InfoBox {
            iconName: "tune"
            text: Translation.tr("These options are used by the standalone terminal color generator.")
        }

        SliderSetting {
            title: Translation.tr("Harmony")
            subtitle: Translation.tr("Terminal color-generation tuning value.")
            iconName: "invert_colors"
            valueLabel:
                Math.round(
                    Config.options.appearance.wallpaperTheming
                        .terminalGenerationProps.harmony * 100
                ) + "%"
            sliderValue:
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.harmony * 100
            from: 0
            to: 100
            stepSize: 10
            stopIndicatorValues: [0, 20, 40, 60, 80, 100]

            onMoved: value => {
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.harmony = value / 100
            }
        }

        SliderSetting {
            title: Translation.tr("Harmonize threshold")
            subtitle: Translation.tr("Threshold used by terminal color generation.")
            iconName: "gradient"
            valueLabel:
                Math.round(
                    Config.options.appearance.wallpaperTheming
                        .terminalGenerationProps.harmonizeThreshold
                ).toString()
            sliderValue:
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.harmonizeThreshold
            from: 0
            to: 100
            stepSize: 10
            stopIndicatorValues: [0, 20, 40, 60, 80, 100]

            onMoved: value => {
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.harmonizeThreshold =
                        Math.round(value)
            }
        }

        SliderSetting {
            title: Translation.tr("Foreground boost")
            subtitle: Translation.tr("Terminal foreground-generation tuning value.")
            iconName: "format_color_text"
            valueLabel:
                Math.round(
                    Config.options.appearance.wallpaperTheming
                        .terminalGenerationProps.termFgBoost * 100
                ) + "%"
            sliderValue:
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.termFgBoost * 100
            from: 0
            to: 100
            stepSize: 5
            stopIndicatorValues: [0, 25, 50, 75, 100]

            onMoved: value => {
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.termFgBoost = value / 100
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            implicitHeight: root.compactControlHeight

            buttonRadius: Appearance.radius.control
            materialIcon: "restart_alt"
            mainText: Translation.tr("Reset terminal tuning")

            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active

            onClicked: {
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.harmony = 0.6
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.harmonizeThreshold = 100
                Config.options.appearance.wallpaperTheming
                    .terminalGenerationProps.termFgBoost = 0.35
            }
        }
    }
}
