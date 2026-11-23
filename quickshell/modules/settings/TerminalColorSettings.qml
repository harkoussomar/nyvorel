import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: root
    required property bool targetEnabled
    required property bool editingAllowed
    readonly property int controlHeight: 44
    readonly property int compactControlHeight: 38
    property bool terminalTuningExpanded: false
    property var draft: null
    property bool queued: false
    property string errorText: ""
    readonly property bool pending: queued || applyTerminal.running
    readonly property var values: draft ?? Config.options.appearance.wallpaperTheming.terminalGenerationProps
    spacing: 8

    function change(changes): void {
        root.draft = Object.assign({
            forceDarkMode: root.values.forceDarkMode,
            harmony: root.values.harmony,
            harmonizeThreshold: root.values.harmonizeThreshold,
            termFgBoost: root.values.termFgBoost
        }, changes)
        root.queued = true
        root.errorText = ""
        applyDelay.restart()
    }

    onEditingAllowedChanged: {
        if (editingAllowed && queued)
            applyDelay.restart()
    }

    Timer {
        id: applyDelay
        interval: 240
        onTriggered: {
            if (!root.queued || !root.editingAllowed || applyTerminal.running)
                return
            root.queued = false
            applyTerminal.exec([FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/system/nyvorel-appearance-studio")),
                "terminal-colors", JSON.stringify(root.draft)])
        }
    }

    Process {
        id: applyTerminal
        stdout: StdioCollector { id: reply }
        onExited: exitCode => {
            if (exitCode !== 0) {
                try { root.errorText = JSON.parse(reply.text).error }
                catch (e) { root.errorText = Translation.tr("Could not apply terminal colors.") }
            }
            Config.reload()
            if (root.queued)
                applyDelay.restart()
            else
                root.draft = null
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
        subtitle: Translation.tr("Adjust the generated terminal colors independently of the desktop palette.")
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.errorText.length > 0
        text: root.errorText
        color: Appearance.m3colors.m3error
        wrapMode: Text.Wrap
    }

    PreferenceSwitchRow {
        enabled:
            root.targetEnabled && root.editingAllowed

        title: Translation.tr("Always use dark terminal colors")
        subtitle:
            root.targetEnabled
                ? Translation.tr("Prefer a dark generated terminal palette regardless of the current light/dark appearance.")
                : Translation.tr("Enable Terminal theming first.")
        iconName: "dark_mode"
        switchChecked: root.values.forceDarkMode

        onUserToggled: checked => root.change({forceDarkMode: checked})
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
        enabled: root.editingAllowed

        Layout.fillWidth: true
        spacing: 8

        SliderSetting {
            title: Translation.tr("Accent influence")
            subtitle: Translation.tr("Shift ANSI colors toward the current theme accent.")
            iconName: "invert_colors"
            valueLabel:
                Math.round(
                    root.values.harmony * 100
                ) + "%"
            sliderValue:
                root.values.harmony * 100
            from: 0
            to: 100
            stepSize: 10
            stopIndicatorValues: [0, 20, 40, 60, 80, 100]

            onMoved: value => root.change({harmony: value / 100})
        }

        SliderSetting {
            title: Translation.tr("Hue shift limit")
            subtitle: Translation.tr("Limit how far each ANSI color can shift toward the accent.")
            iconName: "gradient"
            valueLabel:
                Math.round(
                    root.values.harmonizeThreshold
                ) + "°"
            sliderValue: root.values.harmonizeThreshold
            enabled: root.values.harmony > 0
            from: 0
            to: 180
            stepSize: 10
            stopIndicatorValues: [0, 30, 60, 90, 120, 150, 180]

            onMoved: value => root.change({harmonizeThreshold: Math.round(value)})
        }

        SliderSetting {
            title: Translation.tr("Text contrast boost")
            subtitle: Translation.tr("Increase the difference between terminal text and its background.")
            iconName: "format_color_text"
            valueLabel:
                Math.round(
                    root.values.termFgBoost * 100
                ) + "%"
            sliderValue:
                root.values.termFgBoost * 100
            from: 0
            to: 100
            stepSize: 5
            stopIndicatorValues: [0, 25, 50, 75, 100]

            onMoved: value => root.change({termFgBoost: value / 100})
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

            onClicked: root.change({harmony: 0.6, harmonizeThreshold: 100, termFgBoost: 0.35})
        }
    }
}
