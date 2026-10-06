import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    readonly property int cardPadding: 14
    readonly property int sectionGap: 12
    readonly property int rowGap: 8
    readonly property int controlHeight: 44
    readonly property int compactControlHeight: 38

    property bool terminalTuningExpanded: false

    component SettingsCard: Rectangle {
        id: card

        property string title: ""
        property string subtitle: ""
        property string iconName: ""

        readonly property real naturalHeight:
            cardColumn.implicitHeight + root.cardPadding * 2

        default property alias content: contentColumn.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: naturalHeight

        radius:
            Appearance.prismMode
                ? Appearance.prism.radiusPersistent
                : Appearance.radius.card
        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.colors.colLayer2
        border.width: 1
        border.color:
            Appearance.prismMode
                ? Appearance.prism.borderSubtle
                : Appearance.colors.colLayer0Border
        clip: true

        ColumnLayout {
            id: cardColumn

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: root.cardPadding
                leftMargin: root.cardPadding
                rightMargin: root.cardPadding
            }

            spacing: root.sectionGap

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: card.iconName
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: card.title
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: card.subtitle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }
            }

            ColumnLayout {
                id: contentColumn
                Layout.fillWidth: true
                spacing: root.rowGap
            }
        }
    }

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
            font.pixelSize: Appearance.font.pixelSize.smallest
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
                    font.pixelSize: Appearance.font.pixelSize.smallest
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
                font.pixelSize: Appearance.font.pixelSize.smallest
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
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }

                StyledText {
                    text: setting.valueLabel
                    color: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallest
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

    ContentSection {
        icon: "colors"
        title: Translation.tr("Color generation")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Wallpaper-generated colors")
            subtitle: Translation.tr("Choose which desktop targets receive colors derived from the current wallpaper, then fine-tune terminal generation only when needed.")
            iconName: "palette"

            FieldLabel {
                title: Translation.tr("Theming targets")
                subtitle: Translation.tr("Shell & utilities is the base target. Qt and terminal theming depend on it.")
            }

            PreferenceSwitchRow {
                title: Translation.tr("Shell & utilities")
                subtitle: Translation.tr("Apply wallpaper-generated colors to the shell and supported utility surfaces.")
                iconName: "hardware"
                switchChecked:
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell

                onUserToggled: checked => {
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell =
                        checked
                }
            }

            PreferenceSwitchRow {
                enabled:
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell

                title: Translation.tr("Qt applications")
                subtitle:
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell
                        ? Translation.tr("Generate matching colors for supported Qt applications.")
                        : Translation.tr("Enable Shell & utilities first.")
                iconName: "tv_options_input_settings"
                switchChecked:
                    Config.options.appearance.wallpaperTheming.enableQtApps

                onUserToggled: checked => {
                    Config.options.appearance.wallpaperTheming.enableQtApps =
                        checked
                }
            }

            PreferenceSwitchRow {
                enabled:
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell

                title: Translation.tr("Terminal")
                subtitle:
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell
                        ? Translation.tr("Generate a terminal palette from the wallpaper-derived theme.")
                        : Translation.tr("Enable Shell & utilities first.")
                iconName: "terminal"
                switchChecked:
                    Config.options.appearance.wallpaperTheming.enableTerminal

                onUserToggled: checked => {
                    Config.options.appearance.wallpaperTheming.enableTerminal =
                        checked
                }
            }

            FieldLabel {
                Layout.topMargin: 2
                title: Translation.tr("Terminal appearance")
                subtitle: Translation.tr("These controls affect terminal palette generation only.")
            }

            PreferenceSwitchRow {
                enabled:
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    && Config.options.appearance.wallpaperTheming.enableTerminal

                title: Translation.tr("Force dark terminal palette")
                subtitle:
                    Config.options.appearance.wallpaperTheming.enableTerminal
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
                    Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    && Config.options.appearance.wallpaperTheming.enableTerminal

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
                    && Config.options.appearance.wallpaperTheming.enableAppsAndShell
                    && Config.options.appearance.wallpaperTheming.enableTerminal

                Layout.fillWidth: true
                spacing: 8

                InfoBox {
                    iconName: "tune"
                    text: Translation.tr("These are expert generation parameters. The source audit confirms their stored values, but does not expose enough of the generation algorithm to make stronger claims about each parameter's visual effect.")
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
    }
}
