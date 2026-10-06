import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Layout values belong to this page. Corner geometry does not:
    // every corner uses the project's semantic Appearance.radius.* system.
    readonly property int wideBreakpoint: 700
    readonly property int cardPadding: 14
    readonly property int sectionGap: 12
    readonly property int rowGap: 8
    readonly property int controlHeight: 42
    readonly property int compactControlHeight: 38

    property bool translationExpanded: false

    // >>> TOUCHPAD-SCROLL-SETTINGS-V1 >>>
    readonly property string scrollSettingsHelper:
        `${Directories.home}/.local/bin/nyvorel-scroll-settings`
    property real normalTouchpadScroll: 1.2
    property real fastTouchpadScroll: 12.0
    property int superScrollHoldMs: 250
    property bool inputScrollLoaded: false
    property string inputScrollError: ""

    function formatScrollFactor(value: real): string {
        const rounded = Math.round(value * 10) / 10
        return Number.isInteger(rounded)
            ? rounded.toFixed(0)
            : rounded.toFixed(1)
    }

    function consumeInputScrollResponse(text: string): bool {
        try {
            const data = JSON.parse(String(text).trim())

            if (!data.ok) {
                root.inputScrollError = data.error || Translation.tr("Could not update touchpad scrolling.")
                return false
            }

            root.normalTouchpadScroll = Number(data.normal_touchpad)
            root.fastTouchpadScroll = Number(data.fast_touchpad)
            root.superScrollHoldMs = Number(data.hold_ms || 250)
            root.inputScrollLoaded = true
            root.inputScrollError = ""
            return true
        } catch (error) {
            root.inputScrollError = Translation.tr("Could not read touchpad scrolling settings.")
            return false
        }
    }

    function refreshInputScrollSettings(): void {
        if (inputScrollReadProc.running)
            return

        inputScrollReadProc.command = [root.scrollSettingsHelper, "get"]
        inputScrollReadProc.running = true
    }

    function applyNormalTouchpadScroll(): void {
        if (normalScrollApplyProc.running) {
            normalScrollApplyTimer.restart()
            return
        }

        normalScrollApplyProc.command = [
            root.scrollSettingsHelper,
            "set-normal",
            root.normalTouchpadScroll.toFixed(1)
        ]
        normalScrollApplyProc.running = true
    }

    function applyFastTouchpadScroll(): void {
        if (fastScrollApplyProc.running) {
            fastScrollApplyTimer.restart()
            return
        }

        fastScrollApplyProc.command = [
            root.scrollSettingsHelper,
            "set-fast",
            root.fastTouchpadScroll.toFixed(1)
        ]
        fastScrollApplyProc.running = true
    }
    // <<< TOUCHPAD-SCROLL-SETTINGS-V1 <<<

    readonly property bool batteryThresholdsOrdered:
        Config.options.battery.critical <= Config.options.battery.low
        && (!Config.options.battery.automaticSuspend
            || Config.options.battery.suspend <= Config.options.battery.critical)

    function setTimeFormat(value: string): void {
        if (value === Config.options.time.format)
            return

        if (value === "hh:mm") {
            Quickshell.execDetached([
                "bash",
                "-c",
                `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`
            ])
        } else {
            Quickshell.execDetached([
                "bash",
                "-c",
                `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`
            ])
        }

        Config.options.time.format = value
    }

    Process {
        id: translationProc

        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    // >>> TOUCHPAD-SCROLL-PROCESSES-V1 >>>
    Process {
        id: inputScrollReadProc

        stdout: StdioCollector {
            onStreamFinished: root.consumeInputScrollResponse(this.text)
        }
    }

    Process {
        id: normalScrollApplyProc

        stdout: StdioCollector {
            onStreamFinished: root.consumeInputScrollResponse(this.text)
        }
    }

    Process {
        id: fastScrollApplyProc

        stdout: StdioCollector {
            onStreamFinished: root.consumeInputScrollResponse(this.text)
        }
    }

    Timer {
        id: normalScrollApplyTimer
        interval: 160
        repeat: false
        onTriggered: root.applyNormalTouchpadScroll()
    }

    Timer {
        id: fastScrollApplyTimer
        interval: 160
        repeat: false
        onTriggered: root.applyFastTouchpadScroll()
    }

    Component.onCompleted: root.refreshInputScrollSettings()
    // <<< TOUCHPAD-SCROLL-PROCESSES-V1 <<<

    // -------------------------------------------------------------------------
    // Reusable page-local primitives
    // -------------------------------------------------------------------------

    component SettingsCard: Rectangle {
        id: card

        property string title: ""
        property string subtitle: ""
        property string iconName: ""

        // Natural height is computed only from this card's own content.
        // matchedHeight may point at a sibling's naturalHeight, which avoids
        // circular layout bindings while still guaranteeing equal-height pairs.
        readonly property real naturalHeight:
            cardColumn.implicitHeight + root.cardPadding * 2
        property real matchedHeight: 0

        default property alias content: contentColumn.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.preferredHeight: Math.max(card.naturalHeight, card.matchedHeight)

        implicitHeight: card.naturalHeight

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

        ColumnLayout {
            id: cardColumn

            // Keep the card's content packed from the top. The card itself may
            // be stretched to match its sibling's height, but the content
            // should never stretch/distribute vertically with it.
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
                    visible: card.iconName.length > 0
                    text: card.iconName
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: card.title
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        visible: card.subtitle.length > 0
                        Layout.fillWidth: true
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
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
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

                // Explicit interaction signal: config writes happen because the
                // user toggled the switch, not because a binding changed.
                onToggled: row.userToggled(checked)
            }
        }
    }

    component ChoiceChip: RippleButton {
        id: chip

        required property string label
        required property string iconName

        property string description: ""
        property bool selected: false

        toggled: selected
        implicitHeight: root.compactControlHeight
        implicitWidth: Math.max(90, chipContent.implicitWidth + 24)

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control

        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.description: description

        contentItem: RowLayout {
            id: chipContent

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 6

            MaterialSymbol {
                text: chip.iconName
                iconSize: 16
                fill: chip.selected ? 1 : 0
                color: chip.selected
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colSubtext
            }

            StyledText {
                text: chip.label
                color: chip.selected
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: chip.selected ? Font.DemiBold : Font.Normal
            }
        }

        StyledToolTip {
            extraVisibleCondition: chip.description.length > 0
            text: chip.description
        }
    }

    component FieldLabel: ColumnLayout {
        required property string title
        property string subtitle: ""

        Layout.fillWidth: true
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            text: parent.title
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }

        StyledText {
            visible: parent.subtitle.length > 0
            Layout.fillWidth: true
            text: parent.subtitle
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
            wrapMode: Text.Wrap
        }
    }

    // =========================================================================
    // SYSTEM
    // =========================================================================

    ContentSection {
        icon: "tune"
        title: Translation.tr("System")
        Layout.fillWidth: true

        GridLayout {
            id: systemGrid
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                id: volumeCard
                matchedHeight: systemGrid.columns > 1
                    ? batteryCard.naturalHeight
                    : 0
                title: Translation.tr("Volume protection")
                subtitle: Translation.tr("Limit sudden volume jumps and cap maximum output.")
                iconName: "hearing"

                PreferenceSwitchRow {
                    title: Translation.tr("Enable volume protection")
                    subtitle: Config.options.audio.protection.enable
                        ? Translation.tr("Protection is active.")
                        : Translation.tr("Audio changes are not currently limited.")
                    iconName: "shield"
                    switchChecked: Config.options.audio.protection.enable

                    onUserToggled: checked => {
                        Config.options.audio.protection.enable = checked
                    }
                }

                ColumnLayout {
                    visible: Config.options.audio.protection.enable
                    Layout.fillWidth: true
                    spacing: 8

                    FieldLabel {
                        title: Translation.tr("Protection limits")
                        subtitle: Translation.tr("Values are percentages of the audio level.")
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "arrow_warm_up"
                        text: Translation.tr("Maximum increase (%)")
                        value: Config.options.audio.protection.maxAllowedIncrease
                        from: 0
                        to: 100
                        stepSize: 2

                        onValueChanged: {
                            Config.options.audio.protection.maxAllowedIncrease = value
                        }
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "vertical_align_top"
                        text: Translation.tr("Volume limit (%)")
                        value: Config.options.audio.protection.maxAllowed
                        from: 0
                        to: 154
                        stepSize: 2

                        onValueChanged: {
                            Config.options.audio.protection.maxAllowed = value
                        }
                    }
                }
            }

            SettingsCard {
                id: batteryCard
                matchedHeight: systemGrid.columns > 1
                    ? volumeCard.naturalHeight
                    : 0
                title: Translation.tr("Battery")
                subtitle: Translation.tr("Choose when battery warnings appear and when the system may suspend.")
                iconName: "battery_android_full"

                FieldLabel {
                    title: Translation.tr("Warning thresholds")
                    subtitle: Translation.tr("Battery percentages are evaluated independently by the existing battery service.")
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "warning"
                    text: Translation.tr("Low battery (%)")
                    value: Config.options.battery.low
                    from: 0
                    to: 100
                    stepSize: 5

                    onValueChanged: {
                        Config.options.battery.low = value
                    }
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "dangerous"
                    text: Translation.tr("Critical battery (%)")
                    value: Config.options.battery.critical
                    from: 0
                    to: 100
                    stepSize: 5

                    onValueChanged: {
                        Config.options.battery.critical = value
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Automatic suspend")
                    subtitle: Config.options.battery.automaticSuspend
                        ? Translation.tr("Suspend automatically at the configured battery threshold.")
                        : Translation.tr("Never suspend automatically from this battery rule.")
                    iconName: "pause"
                    switchChecked: Config.options.battery.automaticSuspend

                    onUserToggled: checked => {
                        Config.options.battery.automaticSuspend = checked
                    }
                }

                ConfigSpinBox {
                    visible: Config.options.battery.automaticSuspend
                    Layout.fillWidth: true
                    icon: "battery_1_bar"
                    text: Translation.tr("Suspend at (%)")
                    value: Config.options.battery.suspend
                    from: 0
                    to: 100
                    stepSize: 5

                    onValueChanged: {
                        Config.options.battery.suspend = value
                    }
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "charger"
                    text: Translation.tr("Full-charge warning (%)")
                    value: Config.options.battery.full
                    from: 0
                    to: 101
                    stepSize: 5

                    onValueChanged: {
                        Config.options.battery.full = value
                    }
                }

                Rectangle {
                    visible: !root.batteryThresholdsOrdered
                    Layout.fillWidth: true
                    implicitHeight: batteryWarningRow.implicitHeight + 18

                    radius: Appearance.radius.control
                    color: Appearance.colors.colTertiaryContainer

                    RowLayout {
                        id: batteryWarningRow

                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 8

                        MaterialSymbol {
                            text: "info"
                            iconSize: 18
                            color: Appearance.colors.colOnTertiaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Check the battery order: Suspend should not be above Critical, and Critical should not be above Low.")
                            color: Appearance.colors.colOnTertiaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // INPUT
    // =========================================================================

    // >>> TOUCHPAD-SCROLL-UI-V1 >>>
    ContentSection {
        icon: "touchpad"
        title: Translation.tr("Input")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Touchpad scrolling")
            subtitle: Translation.tr("Tune everyday two-finger scrolling independently from the temporary Super-held fast-scroll mode.")
            iconName: "touchpad"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                FieldLabel {
                    title: Translation.tr("Normal scroll speed")
                    subtitle: Translation.tr("Persistent Hyprland touchpad scroll factor. Hyprland's standard value is 1.0.")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledSlider {
                        id: normalTouchpadScrollSlider
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.XS
                        from: 0.5
                        to: 3.0
                        stepSize: 0.1
                        value: root.normalTouchpadScroll
                        stopIndicatorValues: [0.5, 1.0, 1.2, 1.5, 2.0, 3.0]
                        usePercentTooltip: false
                        enabled: root.inputScrollLoaded
                        Accessible.name: Translation.tr("Normal touchpad scroll speed")

                        onMoved: {
                            root.normalTouchpadScroll = Math.round(value * 10) / 10
                            normalScrollApplyTimer.restart()
                        }
                    }

                    StyledText {
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignRight
                        text: root.formatScrollFactor(root.normalTouchpadScroll) + "×"
                        color: Appearance.colors.colOnLayer2
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }
                }

                FieldLabel {
                    Layout.topMargin: 4
                    title: Translation.tr("Super-held fast scroll")
                    subtitle: Translation.tr("Temporary target used after holding Super for %1 ms. Releasing Super restores the normal value.").arg(root.superScrollHoldMs)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledSlider {
                        id: fastTouchpadScrollSlider
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.XS
                        from: 4
                        to: 20
                        stepSize: 0.5
                        value: root.fastTouchpadScroll
                        stopIndicatorValues: [4, 8, 10, 12, 14, 16, 20]
                        usePercentTooltip: false
                        enabled: root.inputScrollLoaded
                        Accessible.name: Translation.tr("Super-held touchpad scroll speed")

                        onMoved: {
                            root.fastTouchpadScroll = Math.round(value * 2) / 2
                            fastScrollApplyTimer.restart()
                        }
                    }

                    StyledText {
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignRight
                        text: root.formatScrollFactor(root.fastTouchpadScroll) + "×"
                        color: Appearance.colors.colPrimary
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    visible: root.inputScrollError.length > 0
                    Layout.fillWidth: true
                    implicitHeight: inputScrollErrorRow.implicitHeight + 18
                    radius: Appearance.radius.control
                    color: Appearance.colors.colTertiaryContainer

                    RowLayout {
                        id: inputScrollErrorRow
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 8

                        MaterialSymbol {
                            text: "warning"
                            iconSize: 18
                            color: Appearance.colors.colOnTertiaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.inputScrollError
                            color: Appearance.colors.colOnTertiaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            wrapMode: Text.Wrap
                        }

                        RippleButtonWithIcon {
                            implicitHeight: root.compactControlHeight
                            buttonRadius: Appearance.radius.control
                            materialIcon: "refresh"
                            mainText: Translation.tr("Retry")
                            onClicked: root.refreshInputScrollSettings()
                        }
                    }
                }
            }
        }
    }
    // <<< TOUCHPAD-SCROLL-UI-V1 <<<

    // =========================================================================
    // LOCALE & TIME
    // =========================================================================

    ContentSection {
        icon: "language"
        title: Translation.tr("Locale & time")
        Layout.fillWidth: true

        GridLayout {
            id: localeGrid
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                id: languageCard
                matchedHeight: localeGrid.columns > 1
                    ? clockCard.naturalHeight
                    : 0
                title: Translation.tr("Interface language")
                subtitle: Translation.tr("Choose the language used throughout the shell.")
                iconName: "translate"

                StyledComboBox {
                    id: languageSelector

                    Layout.fillWidth: true
                    buttonIcon: "language"
                    buttonRadius: Appearance.radius.control
                    textRole: "displayName"

                    model: [
                        {
                            displayName: Translation.tr("Auto (System)"),
                            value: "auto"
                        },
                        ...Translation.allAvailableLanguages.map(lang => {
                            return {
                                displayName: lang,
                                value: lang
                            }
                        })
                    ]

                    currentIndex: {
                        const index = model.findIndex(
                            item => item.value === Config.options.language.ui
                        )
                        return index !== -1 ? index : 0
                    }

                    onActivated: index => {
                        Config.options.language.ui = model[index].value
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: root.translationExpanded
                        ? "expand_less"
                        : "add_circle"
                    mainText: root.translationExpanded
                        ? Translation.tr("Hide translation generator")
                        : Translation.tr("Missing your language? Generate translation")

                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active

                    onClicked: {
                        root.translationExpanded = !root.translationExpanded
                    }
                }

                ColumnLayout {
                    visible: root.translationExpanded
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Generate a UI translation with Gemini. You need a Gemini API key first; type /key in the sidebar for setup instructions.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }

                    MaterialTextArea {
                        id: localeInput

                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN…")
                        text: Config.options.language.ui === "auto"
                            ? Qt.locale().name
                            : Config.options.language.ui
                    }

                    RippleButtonWithIcon {
                        id: generateTranslationBtn

                        Layout.fillWidth: true
                        implicitHeight: root.controlHeight
                        buttonRadius: Appearance.radius.control
                        nerdIcon: ""

                        enabled:
                            !translationProc.running
                            || translationProc.locale !== localeInput.text.trim()

                        mainText: translationProc.running
                            ? Translation.tr("Generating… Keep this window open")
                            : Translation.tr("Generate translation")

                        colBackground: translationProc.running
                            ? Appearance.colors.colLayer1
                            : Appearance.colors.colPrimaryContainer
                        colBackgroundHover: translationProc.running
                            ? Appearance.colors.colLayer1Hover
                            : Appearance.colors.colPrimaryContainerHover
                        colRipple: translationProc.running
                            ? Appearance.colors.colLayer1Active
                            : Appearance.colors.colPrimaryContainerActive

                        onClicked: {
                            translationProc.locale = localeInput.text.trim()
                            translationProc.running = false
                            translationProc.running = true
                        }
                    }
                }
            }

            SettingsCard {
                id: clockCard
                matchedHeight: localeGrid.columns > 1
                    ? languageCard.naturalHeight
                    : 0
                title: Translation.tr("Clock")
                subtitle: Translation.tr("Choose how time is rendered across the shell and lock screen.")
                iconName: "schedule"

                PreferenceSwitchRow {
                    title: Translation.tr("Second-level clock updates")
                    subtitle: Translation.tr("Keep clocks accurate to the current second.")
                    iconName: "pace"
                    switchChecked: Config.options.time.secondPrecision

                    onUserToggled: checked => {
                        Config.options.time.secondPrecision = checked
                    }
                }

                FieldLabel {
                    title: Translation.tr("Time format")
                    subtitle: Translation.tr("Examples show how the same time will appear.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("13:42")
                        iconName: "schedule"
                        description: Translation.tr("24-hour format")
                        selected: Config.options.time.format === "hh:mm"

                        onClicked: root.setTimeFormat("hh:mm")
                    }

                    ChoiceChip {
                        label: Translation.tr("1:42 pm")
                        iconName: "schedule"
                        description: Translation.tr("12-hour format with lowercase am/pm")
                        selected: Config.options.time.format === "h:mm ap"

                        onClicked: root.setTimeFormat("h:mm ap")
                    }

                    ChoiceChip {
                        label: Translation.tr("1:42 PM")
                        iconName: "schedule"
                        description: Translation.tr("12-hour format with uppercase AM/PM")
                        selected: Config.options.time.format === "h:mm AP"

                        onClicked: root.setTimeFormat("h:mm AP")
                    }
                }
            }
        }
    }

    // =========================================================================
    // FEEDBACK
    // =========================================================================

    ContentSection {
        icon: "notification_sound"
        title: Translation.tr("Feedback")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Sounds")
            subtitle: Translation.tr("Choose which shell events can play a notification sound.")
            iconName: "volume_up"

            PreferenceSwitchRow {
                title: Translation.tr("Battery sounds")
                subtitle: Translation.tr("Play sound feedback for battery events.")
                iconName: "battery_android_full"
                switchChecked: Config.options.sounds.battery

                onUserToggled: checked => {
                    Config.options.sounds.battery = checked
                }
            }

            PreferenceSwitchRow {
                title: Translation.tr("Pomodoro sounds")
                subtitle: Translation.tr("Play sound feedback for Pomodoro timer events.")
                iconName: "av_timer"
                switchChecked: Config.options.sounds.pomodoro

                onUserToggled: checked => {
                    Config.options.sounds.pomodoro = checked
                }
            }
        }
    }

    // =========================================================================
    // PRIVACY & CONTENT
    // =========================================================================

    ContentSection {
        icon: "shield"
        title: Translation.tr("Privacy & content")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Content policies")
            subtitle: Translation.tr("Control optional AI and anime-related features without changing their existing configuration semantics.")
            iconName: "rule"

            FieldLabel {
                title: Translation.tr("AI features")
                subtitle: Translation.tr("Choose whether AI-powered features are available.")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                ChoiceChip {
                    label: Translation.tr("Off")
                    iconName: "close"
                    selected: Config.options.policies.ai === 0
                    onClicked: Config.options.policies.ai = 0
                }

                ChoiceChip {
                    label: Translation.tr("Enabled")
                    iconName: "check"
                    selected: Config.options.policies.ai === 1
                    onClicked: Config.options.policies.ai = 1
                }

                ChoiceChip {
                    label: Translation.tr("Local only")
                    iconName: "sync_saved_locally"
                    description: Translation.tr("Use the project's existing local-only AI policy.")
                    selected: Config.options.policies.ai === 2
                    onClicked: Config.options.policies.ai = 2
                }
            }

            FieldLabel {
                Layout.topMargin: 4
                title: Translation.tr("Anime content")
                subtitle: Translation.tr("Choose how anime-specific content and integrations are handled.")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                ChoiceChip {
                    label: Translation.tr("Off")
                    iconName: "close"
                    selected: Config.options.policies.weeb === 0
                    onClicked: Config.options.policies.weeb = 0
                }

                ChoiceChip {
                    label: Translation.tr("Enabled")
                    iconName: "check"
                    selected: Config.options.policies.weeb === 1
                    onClicked: Config.options.policies.weeb = 1
                }

                ChoiceChip {
                    label: Translation.tr("Closet mode")
                    iconName: "ev_shadow"
                    description: Translation.tr("Preserve the project's existing Closet policy behavior.")
                    selected: Config.options.policies.weeb === 2
                    onClicked: Config.options.policies.weeb = 2
                }
            }
        }

        SettingsCard {
            title: Translation.tr("Work-safe content")
            subtitle: Translation.tr("Reduce potentially distracting or sensitive visual content when work-safety rules apply.")
            iconName: "work"

            PreferenceSwitchRow {
                title: Translation.tr("Filter clipboard images")
                subtitle: Translation.tr("Hide clipboard images from sources flagged by the shell's work-safety rules.")
                iconName: "assignment"
                switchChecked: Config.options.workSafety.enable.clipboard

                onUserToggled: checked => {
                    Config.options.workSafety.enable.clipboard = checked
                }
            }

            PreferenceSwitchRow {
                title: Translation.tr("Filter wallpapers")
                subtitle: Translation.tr("Hide anime or other wallpapers flagged by the shell's work-safety rules.")
                iconName: "wallpaper"
                switchChecked: Config.options.workSafety.enable.wallpaper

                onUserToggled: checked => {
                    Config.options.workSafety.enable.wallpaper = checked
                }
            }
        }
    }
}
