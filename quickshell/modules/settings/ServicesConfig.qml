import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Layout-only values. Corner geometry always uses Appearance.radius.*.
    readonly property int wideBreakpoint: 700
    readonly property int cardPadding: 14
    readonly property int sectionGap: 12
    readonly property int rowGap: 8
    readonly property int controlHeight: 42
    readonly property int compactControlHeight: 38

    property bool aiPromptExpanded: false
    property bool recognitionAdvancedExpanded: false
    property bool searchPrefixesExpanded: false
    property bool webSearchExpanded: false
    property bool weatherAdvancedExpanded: false
    property bool networkingAdvancedExpanded: false
    property bool performanceAdvancedExpanded: false

    function secondsText(milliseconds: real): string {
        const seconds = milliseconds / 1000
        return Number.isInteger(seconds)
            ? Translation.tr("%1 s").arg(seconds)
            : Translation.tr("%1 s").arg(seconds.toFixed(1))
    }

    // -------------------------------------------------------------------------
    // Reusable page-local primitives
    // -------------------------------------------------------------------------

    component SettingsCard: Rectangle {
        id: card

        property string title: ""
        property string subtitle: ""
        property string iconName: ""
        property bool showHeader: true

        readonly property real naturalHeight:
            cardColumn.implicitHeight + root.cardPadding * 2

        // Optional sibling natural height. This keeps paired cards equal
        // without creating a circular layout binding.
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
                visible: card.showHeader
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
                        visible: card.subtitle.length > 0
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

    component InfoBox: Rectangle {
        id: box

        property string text: ""
        property string iconName: "info"
        property bool warning: false

        Layout.fillWidth: true
        implicitHeight: infoRow.implicitHeight + 18

        radius: Appearance.radius.control
        color: warning
            ? Appearance.colors.colTertiaryContainer
            : Appearance.colors.colLayer1

        RowLayout {
            id: infoRow

            anchors.fill: parent
            anchors.margins: 9
            spacing: 8

            MaterialSymbol {
                text: box.iconName
                iconSize: 18
                color: box.warning
                    ? Appearance.colors.colOnTertiaryContainer
                    : Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: box.text
                color: box.warning
                    ? Appearance.colors.colOnTertiaryContainer
                    : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                wrapMode: Text.Wrap
            }
        }
    }

    component PrefixEditor: Rectangle {
        id: editor

        required property string title
        required property string iconName
        required property string currentValue

        signal edited(string value)

        Layout.fillWidth: true
        implicitHeight: editorColumn.implicitHeight + 18

        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1
        clip: true

        ColumnLayout {
            id: editorColumn

            anchors {
                fill: parent
                margins: 9
            }

            spacing: 5

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                MaterialSymbol {
                    text: editor.iconName
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: editor.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Prefix")
                text: editor.currentValue
                wrapMode: TextEdit.NoWrap

                onTextChanged: {
                    if (text !== editor.currentValue)
                        editor.edited(text)
                }
            }
        }
    }

    component PathField: ColumnLayout {
        id: pathField

        required property string title
        required property string iconName
        required property string currentValue

        property string subtitle: ""
        property string placeholder: ""

        signal edited(string value)

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            MaterialSymbol {
                text: pathField.iconName
                iconSize: 17
                color: Appearance.colors.colPrimary
            }

            FieldLabel {
                title: pathField.title
                subtitle: pathField.subtitle
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: pathField.placeholder
            text: pathField.currentValue
            wrapMode: TextEdit.NoWrap

            onTextChanged: {
                if (text !== pathField.currentValue)
                    pathField.edited(text)
            }
        }
    }

    component SliderSetting: Rectangle {
        id: sliderSetting

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
                    text: sliderSetting.iconName
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
                        text: sliderSetting.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        visible: sliderSetting.subtitle.length > 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: sliderSetting.subtitle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }

                StyledText {
                    text: sliderSetting.valueLabel
                    color: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.XS
                from: sliderSetting.from
                to: sliderSetting.to
                stepSize: sliderSetting.stepSize
                value: sliderSetting.sliderValue
                stopIndicatorValues: sliderSetting.stopIndicatorValues
                usePercentTooltip: false

                onMoved: sliderSetting.moved(value)
            }
        }
    }

    // =========================================================================
    // AI & RECOGNITION
    // =========================================================================

    ContentSection {
        icon: "neurology"
        title: Translation.tr("AI & recognition")
        Layout.fillWidth: true

        GridLayout {
            id: aiRecognitionGrid

            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                id: aiAssistantCard

                matchedHeight: aiRecognitionGrid.columns > 1
                    ? musicRecognitionCard.naturalHeight
                    : 0

                title: Translation.tr("AI assistant")
                subtitle: Translation.tr("Edit the system prompt used by the sidebar AI assistant. Model choice and API keys remain managed by the AI interface.")
                iconName: "neurology"

                InfoBox {
                    iconName: "cloud"
                    text: Translation.tr("Depending on the selected model, the AI service can use online providers or a local Ollama endpoint. This page only controls the system prompt.")
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: promptSummaryRow.implicitHeight + 18
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1
                    clip: true

                    RowLayout {
                        id: promptSummaryRow

                        anchors {
                            fill: parent
                            margins: 9
                        }

                        spacing: 10

                        MaterialSymbol {
                            text: "description"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1

                            StyledText {
                                text: Translation.tr("System prompt")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("%1 characters configured")
                                    .arg(Config.options.ai.systemPrompt.length)
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.Wrap
                            }
                        }

                        RippleButtonWithIcon {
                            implicitHeight: root.compactControlHeight
                            buttonRadius: Appearance.radius.control
                            materialIcon: root.aiPromptExpanded
                                ? "expand_less"
                                : "edit"
                            mainText: root.aiPromptExpanded
                                ? Translation.tr("Close")
                                : Translation.tr("Edit")

                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active

                            onClicked: {
                                root.aiPromptExpanded = !root.aiPromptExpanded
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: root.aiPromptExpanded
                    Layout.fillWidth: true
                    spacing: 6

                    FieldLabel {
                        title: Translation.tr("System prompt editor")
                        subtitle: Translation.tr("Placeholders such as {DISTRO}, {DE}, {DATETIME}, and {WINDOWCLASS} are substituted by the AI service at runtime.")
                    }

                    MaterialTextArea {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 280
                        placeholderText: Translation.tr("System prompt")
                        text: Config.options.ai.systemPrompt
                        wrapMode: TextEdit.Wrap

                        onTextChanged: {
                            if (text === Config.options.ai.systemPrompt)
                                return

                            Qt.callLater(() => {
                                Config.options.ai.systemPrompt = text
                            })
                        }
                    }
                }
            }

            SettingsCard {
                id: musicRecognitionCard

                matchedHeight: aiRecognitionGrid.columns > 1
                    ? aiAssistantCard.naturalHeight
                    : 0

                title: Translation.tr("Music recognition")
                subtitle: Translation.tr("Tune the on-demand SongRec recognition process used when identifying currently playing audio.")
                iconName: "music_cast"

                InfoBox {
                    iconName: "music_search"
                    text: Translation.tr("Recognition runs only when requested. It launches the existing SongRec script and reports an error if the songrec dependency is unavailable.")
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: recognitionSummary.implicitHeight + 18
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        id: recognitionSummary

                        anchors {
                            fill: parent
                            margins: 9
                        }

                        spacing: 10

                        MaterialSymbol {
                            text: "timer"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: Translation.tr("Recognition window")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                            }

                            StyledText {
                                text: Translation.tr("%1 s timeout · retry every %2 s")
                                    .arg(Config.options.musicRecognition.timeout)
                                    .arg(Config.options.musicRecognition.interval)
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                }

                ExpandButton {
                    collapsedText: Translation.tr("Advanced recognition timing")
                    expandedText: Translation.tr("Hide recognition timing")
                    expanded: root.recognitionAdvancedExpanded

                    onClicked: {
                        root.recognitionAdvancedExpanded =
                            !root.recognitionAdvancedExpanded
                    }
                }

                GridLayout {
                    visible: root.recognitionAdvancedExpanded
                    Layout.fillWidth: true
                    columns: width >= 520 ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "timer_off"
                        text: Translation.tr("Recognition timeout (s)")
                        value: Config.options.musicRecognition.timeout
                        from: 10
                        to: 100
                        stepSize: 2

                        onValueChanged: {
                            Config.options.musicRecognition.timeout = value
                        }
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "av_timer"
                        text: Translation.tr("Retry interval (s)")
                        value: Config.options.musicRecognition.interval
                        from: 2
                        to: 10
                        stepSize: 1

                        onValueChanged: {
                            Config.options.musicRecognition.interval = value
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SEARCH & WEB
    // =========================================================================

    ContentSection {
        icon: "search"
        title: Translation.tr("Search & web")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Search & launcher")
            subtitle: Translation.tr("Control launcher matching, command prefixes, and the web-search destination shared by launcher and sidebar search actions.")
            iconName: "search"

            PreferenceSwitchRow {
                title: Translation.tr("Typo-tolerant matching")
                subtitle: Translation.tr("Use Levenshtein-distance scoring. It can help with heavily mistyped queries, but acronyms and exact app names may rank less predictably.")
                iconName: "spellcheck"
                switchChecked: Config.options.search.sloppy

                onUserToggled: checked => {
                    Config.options.search.sloppy = checked
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Search shortcuts")
                expandedText: Translation.tr("Hide search shortcuts")
                expanded: root.searchPrefixesExpanded

                onClicked: {
                    root.searchPrefixesExpanded =
                        !root.searchPrefixesExpanded
                }
            }

            GridLayout {
                visible: root.searchPrefixesExpanded
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 3 : width >= 500 ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                PrefixEditor {
                    title: Translation.tr("Actions")
                    iconName: "bolt"
                    currentValue: Config.options.search.prefix.action

                    onEdited: value => {
                        Config.options.search.prefix.action = value
                    }
                }

                PrefixEditor {
                    title: Translation.tr("Clipboard")
                    iconName: "content_paste"
                    currentValue: Config.options.search.prefix.clipboard

                    onEdited: value => {
                        Config.options.search.prefix.clipboard = value
                    }
                }

                PrefixEditor {
                    title: Translation.tr("Emoji")
                    iconName: "emoji_emotions"
                    currentValue: Config.options.search.prefix.emojis

                    onEdited: value => {
                        Config.options.search.prefix.emojis = value
                    }
                }

                PrefixEditor {
                    title: Translation.tr("Math")
                    iconName: "calculate"
                    currentValue: Config.options.search.prefix.math

                    onEdited: value => {
                        Config.options.search.prefix.math = value
                    }
                }

                PrefixEditor {
                    title: Translation.tr("Shell command")
                    iconName: "terminal"
                    currentValue: Config.options.search.prefix.shellCommand

                    onEdited: value => {
                        Config.options.search.prefix.shellCommand = value
                    }
                }

                PrefixEditor {
                    title: Translation.tr("Web search")
                    iconName: "language"
                    currentValue: Config.options.search.prefix.webSearch

                    onEdited: value => {
                        Config.options.search.prefix.webSearch = value
                    }
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Web search provider")
                expandedText: Translation.tr("Hide web search provider")
                expanded: root.webSearchExpanded

                onClicked: {
                    root.webSearchExpanded = !root.webSearchExpanded
                }
            }

            ColumnLayout {
                visible: root.webSearchExpanded
                Layout.fillWidth: true
                spacing: 7

                FieldLabel {
                    title: Translation.tr("Web search base URL")
                    subtitle: Translation.tr("The launcher appends the query to this URL. Sidebar AI search and translator search actions use the same setting.")
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("https://www.google.com/search?q=")
                    text: Config.options.search.engineBaseUrl
                    wrapMode: TextEdit.NoWrap

                    onTextChanged: {
                        if (text !== Config.options.search.engineBaseUrl)
                            Config.options.search.engineBaseUrl = text
                    }
                }
            }
        }
    }

    // =========================================================================
    // WEATHER & NETWORK
    // =========================================================================

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Weather & network")
        Layout.fillWidth: true

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                title: Translation.tr("Weather data")
                subtitle: Translation.tr("Configure how the existing weather service chooses a location and formats measurements.")
                iconName: "weather_mix"

                InfoBox {
                    iconName: "cloud"
                    text: Translation.tr("Weather data is fetched from wttr.in. GPS mode uses your coordinates when available; otherwise the configured city is used.")
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Use GPS location")
                    subtitle: Translation.tr("Use device coordinates when the position service returns a valid latitude and longitude.")
                    iconName: "assistant_navigation"
                    switchChecked: Config.options.bar.weather.enableGPS

                    onUserToggled: checked => {
                        Config.options.bar.weather.enableGPS = checked
                    }
                }

                FieldLabel {
                    title: Translation.tr("Units")
                    subtitle: Translation.tr("This changes temperature, wind speed, precipitation, visibility, and pressure formatting.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("Metric")
                        iconName: "straighten"
                        description: Translation.tr("°C, km/h, mm, km, and hPa.")
                        selected: !Config.options.bar.weather.useUSCS

                        onClicked: Config.options.bar.weather.useUSCS = false
                    }

                    ChoiceChip {
                        label: Translation.tr("US customary")
                        iconName: "thermometer"
                        description: Translation.tr("°F and the service's US customary measurement formatting.")
                        selected: Config.options.bar.weather.useUSCS

                        onClicked: Config.options.bar.weather.useUSCS = true
                    }
                }

                PathField {
                    title: Config.options.bar.weather.enableGPS
                        ? Translation.tr("Fallback city")
                        : Translation.tr("City")
                    iconName: "location_city"
                    subtitle: Config.options.bar.weather.enableGPS
                        ? Translation.tr("Used when GPS is unavailable or has not produced a valid position.")
                        : Translation.tr("Location sent to the weather service.")
                    placeholder: Translation.tr("City name")
                    currentValue: Config.options.bar.weather.city

                    onEdited: value => {
                        Config.options.bar.weather.city = value
                    }
                }

                ExpandButton {
                    collapsedText: Translation.tr("Advanced weather")
                    expandedText: Translation.tr("Hide advanced weather")
                    expanded: root.weatherAdvancedExpanded

                    onClicked: {
                        root.weatherAdvancedExpanded =
                            !root.weatherAdvancedExpanded
                    }
                }

                ConfigSpinBox {
                    visible: root.weatherAdvancedExpanded
                    Layout.fillWidth: true
                    icon: "refresh"
                    text: Translation.tr("Weather refresh interval (min)")
                    value: Config.options.bar.weather.fetchInterval
                    from: 5
                    to: 50
                    stepSize: 5

                    onValueChanged: {
                        Config.options.bar.weather.fetchInterval = value
                    }
                }
            }

            SettingsCard {
                title: Translation.tr("Advanced networking")
                subtitle: Translation.tr("Low-level compatibility settings for services that may need a custom HTTP identity.")
                iconName: "cell_tower"

                InfoBox {
                    iconName: "info"
                    text: Translation.tr("The current audit found no active runtime consumer of this User-Agent setting in this build, so it is kept as an advanced compatibility option.")
                }

                ExpandButton {
                    collapsedText: Translation.tr("Custom User-Agent")
                    expandedText: Translation.tr("Hide custom User-Agent")
                    expanded: root.networkingAdvancedExpanded

                    onClicked: {
                        root.networkingAdvancedExpanded =
                            !root.networkingAdvancedExpanded
                    }
                }

                ColumnLayout {
                    visible: root.networkingAdvancedExpanded
                    Layout.fillWidth: true
                    spacing: 6

                    FieldLabel {
                        title: Translation.tr("Stored User-Agent override")
                        subtitle: Translation.tr("Preserves the existing networking configuration value without implying that a current service actively consumes it.")
                    }

                    MaterialTextArea {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("User-Agent")
                        text: Config.options.networking.userAgent
                        wrapMode: TextEdit.Wrap

                        onTextChanged: {
                            if (text !== Config.options.networking.userAgent)
                                Config.options.networking.userAgent = text
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // STORAGE & PERFORMANCE
    // =========================================================================

    ContentSection {
        icon: "folder_managed"
        title: Translation.tr("Storage & performance")
        Layout.fillWidth: true

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                title: Translation.tr("Capture storage")
                subtitle: Translation.tr("Choose where screen recordings and screenshots are saved.")
                iconName: "folder_open"

                PathField {
                    title: Translation.tr("Screen recordings folder")
                    iconName: "videocam"
                    subtitle: Translation.tr("Recording output is saved to this directory.")
                    placeholder: Translation.tr("Recording path")
                    currentValue: Config.options.screenRecord.savePath

                    onEdited: value => {
                        Config.options.screenRecord.savePath = value
                    }
                }

                PathField {
                    title: Translation.tr("Screenshots folder")
                    iconName: "screenshot"
                    subtitle: Translation.tr("Leave empty to copy the screenshot without saving it to a directory.")
                    placeholder: Translation.tr("Leave empty for clipboard only")
                    currentValue: Config.options.screenSnip.savePath

                    onEdited: value => {
                        Config.options.screenSnip.savePath = value
                    }
                }
            }

            SettingsCard {
                title: Translation.tr("Media refresh")
                subtitle: Translation.tr("Control how often playing-media progress is refreshed in the bar, vertical bar, and media controls.")
                iconName: "speed"

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: mediaSummary.implicitHeight + 18
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        id: mediaSummary

                        anchors {
                            fill: parent
                            margins: 9
                        }

                        spacing: 10

                        MaterialSymbol {
                            text: "music_note"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1

                            StyledText {
                                text: Translation.tr("Media progress refresh")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Currently every %1. Lower values update progress more often.")
                                    .arg(root.secondsText(
                                        Config.options.resources.updateInterval
                                    ))
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                ExpandButton {
                    collapsedText: Translation.tr("Advanced refresh timing")
                    expandedText: Translation.tr("Hide refresh timing")
                    expanded: root.performanceAdvancedExpanded

                    onClicked: {
                        root.performanceAdvancedExpanded =
                            !root.performanceAdvancedExpanded
                    }
                }

                SliderSetting {
                    visible: root.performanceAdvancedExpanded
                    title: Translation.tr("Media progress refresh")
                    subtitle: Translation.tr("This timer runs while an active media player is playing.")
                    iconName: "av_timer"
                    valueLabel: root.secondsText(
                        Config.options.resources.updateInterval
                    )
                    sliderValue: Config.options.resources.updateInterval
                    from: 100
                    to: 10000
                    stepSize: 100
                    stopIndicatorValues: [500, 1000, 3000, 5000, 10000]

                    onMoved: value => {
                        Config.options.resources.updateInterval =
                            Math.round(value / 100) * 100
                    }
                }
            }
        }
    }

    // System-update controls intentionally remain absent here.
    // The original Services page explicitly hid them because the shell does not
    // currently expose an update indicator/status surface.
}
