import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Page-local layout metrics only. Corner geometry always comes from
    // Appearance.radius.* so this page follows the global radius system.
    readonly property int wideBreakpoint: 700
    readonly property int cardPadding: 14
    readonly property int sectionGap: 12
    readonly property int rowGap: 8
    readonly property int controlHeight: 42
    readonly property int compactControlHeight: 38

    property bool workspaceNumberingExpanded: false

    readonly property var hanNumberMap: [
        "一", "二", "三", "四", "五",
        "六", "七", "八", "九", "十",
        "十一", "十二", "十三", "十四", "十五",
        "十六", "十七", "十八", "十九", "二十"
    ]

    readonly property var romanNumberMap: [
        "I", "II", "III", "IV", "V",
        "VI", "VII", "VIII", "IX", "X",
        "XI", "XII", "XIII", "XIV", "XV",
        "XVI", "XVII", "XVIII", "XIX", "XX"
    ]

    readonly property string workspaceNumberStyle: {
        const value = JSON.stringify(Config.options.bar.workspaces.numberMap)

        if (value === JSON.stringify([]))
            return "normal"

        if (value === JSON.stringify(root.hanNumberMap))
            return "han"

        if (value === JSON.stringify(root.romanNumberMap))
            return "roman"

        return "custom"
    }

    function currentBarPosition(): int {
        return (Config.options.bar.bottom ? 1 : 0)
            | (Config.options.bar.vertical ? 2 : 0)
    }

    function setBarPosition(value: int): void {
        Config.options.bar.bottom = (value & 1) !== 0
        Config.options.bar.vertical = (value & 2) !== 0
    }

    function setWorkspaceNumberStyle(style: string): void {
        if (style === "normal") {
            Config.options.bar.workspaces.numberMap = []
        } else if (style === "han") {
            Config.options.bar.workspaces.numberMap = root.hanNumberMap.slice()
        } else if (style === "roman") {
            Config.options.bar.workspaces.numberMap = root.romanNumberMap.slice()
        }
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

        // A sibling's naturalHeight can be supplied to align paired cards
        // without creating a circular layout dependency.
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

    component PositionChoice: RippleButton {
        id: choice

        required property string label
        required property int value

        readonly property bool selected:
            root.currentBarPosition() === value

        toggled: selected

        Layout.fillWidth: true
        implicitHeight: 72

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
        Accessible.description: Translation.tr("Place the bar on the %1 edge of the screen.").arg(label.toLowerCase())

        onClicked: root.setBarPosition(value)

        contentItem: ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 44
                implicitHeight: 28

                Rectangle {
                    id: miniScreen

                    anchors.fill: parent
                    radius: Appearance.radius.window
                    color: choice.selected
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer2
                    border.width: 1
                    border.color: choice.selected
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOutlineVariant

                    Rectangle {
                        readonly property bool vertical:
                            choice.value === 2 || choice.value === 3
                        readonly property bool farEdge:
                            choice.value === 1 || choice.value === 3

                        width: vertical ? 4 : miniScreen.width - 8
                        height: vertical ? miniScreen.height - 8 : 4

                        x: vertical
                            ? (farEdge ? miniScreen.width - width - 4 : 4)
                            : 4

                        y: vertical
                            ? 4
                            : (farEdge ? miniScreen.height - height - 4 : 4)

                        radius: Appearance.radius.bar
                        color: choice.selected
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colPrimary
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: choice.label
                color: choice.selected
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: choice.selected ? Font.DemiBold : Font.Normal
            }
        }
    }

    component UtilityToggleTile: RippleButton {
        id: tile

        required property string title
        required property string iconName

        property string subtitle: ""
        property bool switchChecked: false

        signal userToggled(bool checked)

        Layout.fillWidth: true
        implicitHeight: Math.max(58, utilityContent.implicitHeight + 18)

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control

        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        Accessible.role: Accessible.CheckBox
        Accessible.name: title
        Accessible.description: subtitle
        Accessible.checked: switchChecked

        onClicked: tile.userToggled(!tile.switchChecked)

        contentItem: RowLayout {
            id: utilityContent

            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 10

            MaterialSymbol {
                text: tile.iconName
                iconSize: 18
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: tile.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }

                StyledText {
                    visible: tile.subtitle.length > 0
                    Layout.fillWidth: true
                    text: tile.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                }
            }

            StyledSwitch {
                checked: tile.switchChecked
                onToggled: tile.userToggled(checked)
            }
        }
    }

    // =========================================================================
    // BAR LAYOUT
    // =========================================================================

    ContentSection {
        icon: "toolbar"
        title: Translation.tr("Bar layout")
        Layout.fillWidth: true

        SettingsCard {
            showHeader: false

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                FieldLabel {
                    title: Translation.tr("Position")
                    subtitle: Translation.tr("Choose which screen edge holds the bar.")
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 620 ? 4 : 2
                    columnSpacing: 8
                    rowSpacing: 8

                    PositionChoice {
                        label: Translation.tr("Top")
                        value: 0
                    }

                    PositionChoice {
                        label: Translation.tr("Left")
                        value: 2
                    }

                    PositionChoice {
                        label: Translation.tr("Bottom")
                        value: 1
                    }

                    PositionChoice {
                        label: Translation.tr("Right")
                        value: 3
                    }
                }

                PreferenceSwitchRow {
                    Layout.topMargin: 2
                    title: Translation.tr("Automatically hide bar")
                    subtitle: Translation.tr("Slide the bar off-screen until its edge is hovered or it is explicitly shown.")
                    iconName: "shelf_auto_hide"
                    switchChecked: Config.options.bar.autoHide.enable

                    onUserToggled: checked => {
                        Config.options.bar.autoHide.enable = checked
                    }
                }

                FieldLabel {
                    Layout.topMargin: 2
                    title: Translation.tr("Bar style")
                    subtitle: Translation.tr("Change the bar's outer geometry without changing its contents.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("Compact")
                        iconName: "line_curve"
                        description: Translation.tr("Keep the bar attached to the screen edge with the existing compact treatment.")
                        selected: Config.options.bar.cornerStyle === 0

                        onClicked: Config.options.bar.cornerStyle = 0
                    }

                    ChoiceChip {
                        label: Translation.tr("Floating")
                        iconName: "page_header"
                        description: Translation.tr("Add an outer gap, rounded bar geometry, and a border.")
                        selected: Config.options.bar.cornerStyle === 1

                        onClicked: Config.options.bar.cornerStyle = 1
                    }

                    ChoiceChip {
                        label: Translation.tr("Full width")
                        iconName: "toolbar"
                        description: Translation.tr("Use the plain rectangular bar style.")
                        selected: Config.options.bar.cornerStyle === 2

                        onClicked: Config.options.bar.cornerStyle = 2
                    }
                }

                FieldLabel {
                    Layout.topMargin: 2
                    title: Translation.tr("Group style")
                    subtitle: Translation.tr("Choose whether bar widgets appear as grouped pills or as a borderless separated layout.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("Pills")
                        iconName: "location_chip"
                        selected: !Config.options.bar.borderless

                        onClicked: Config.options.bar.borderless = false
                    }

                    ChoiceChip {
                        label: Translation.tr("Separated")
                        iconName: "split_scene"
                        selected: Config.options.bar.borderless

                        onClicked: Config.options.bar.borderless = true
                    }
                }
            }
        }
    }

    // =========================================================================
    // BAR CONTENT
    // =========================================================================

    ContentSection {
        icon: "dashboard_customize"
        title: Translation.tr("Bar content")
        Layout.fillWidth: true

        GridLayout {
            id: contentGrid

            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                id: indicatorsCard

                matchedHeight: contentGrid.columns > 1
                    ? trayCard.naturalHeight
                    : 0

                title: Translation.tr("Indicators & interaction")
                subtitle: Translation.tr("Control lightweight information and popup behavior in the bar.")
                iconName: "notifications"

                PreferenceSwitchRow {
                    title: Translation.tr("Show unread notification count")
                    subtitle: Translation.tr("Show the unread number instead of only the compact notification dot.")
                    iconName: "counter_2"
                    switchChecked: Config.options.bar.indicators.notifications.showUnreadCount

                    onUserToggled: checked => {
                        Config.options.bar.indicators.notifications.showUnreadCount = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Show weather in bar")
                    subtitle: Translation.tr("Display the current weather icon and temperature when the active bar layout supports it.")
                    iconName: "cloud"
                    switchChecked: Config.options.bar.weather.enable

                    onUserToggled: checked => {
                        Config.options.bar.weather.enable = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Require click for supported popups")
                    subtitle: Translation.tr("Disable hover-triggered popups for bar widgets that honor this preference.")
                    iconName: "ads_click"
                    switchChecked: Config.options.bar.tooltips.clickToShow

                    onUserToggled: checked => {
                        Config.options.bar.tooltips.clickToShow = checked
                    }
                }
            }

            SettingsCard {
                id: trayCard

                matchedHeight: contentGrid.columns > 1
                    ? indicatorsCard.naturalHeight
                    : 0

                title: Translation.tr("System tray")
                subtitle: Translation.tr("Control how tray applications are grouped and colored.")
                iconName: "shelf_auto_hide"

                PreferenceSwitchRow {
                    title: Translation.tr("Invert tray pinning")
                    subtitle: Translation.tr("Treat apps outside the pinned list as pinned, and listed apps as unpinned.")
                    iconName: "keep"
                    switchChecked: Config.options.tray.invertPinnedItems

                    onUserToggled: checked => {
                        Config.options.tray.invertPinnedItems = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Monochrome tray icons")
                    subtitle: Translation.tr("Replace original tray icon colors with the shell's themed tint.")
                    iconName: "colors"
                    switchChecked: Config.options.tray.monochromeIcons

                    onUserToggled: checked => {
                        Config.options.tray.monochromeIcons = checked
                    }
                }
            }

            SettingsCard {
                Layout.columnSpan: contentGrid.columns

                title: Translation.tr("Bar content & utility actions")
                subtitle: Translation.tr("Choose visible bar content and optional quick-action buttons.")
                iconName: "widgets"

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.wideBreakpoint ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    UtilityToggleTile {
                        title: Translation.tr("Screen snip")
                        subtitle: Translation.tr("Show the screenshot selection action.")
                        iconName: "content_cut"
                        switchChecked: Config.options.bar.utilButtons.showScreenSnip

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showScreenSnip = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Color picker")
                        subtitle: Translation.tr("Show the on-screen color sampling action.")
                        iconName: "colorize"
                        switchChecked: Config.options.bar.utilButtons.showColorPicker

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showColorPicker = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Keyboard layout")
                        subtitle: Translation.tr("Show the keyboard-layout toggle.")
                        iconName: "keyboard"
                        switchChecked: Config.options.bar.utilButtons.showKeyboardToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showKeyboardToggle = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Microphone")
                        subtitle: Translation.tr("Show the microphone mute toggle.")
                        iconName: "mic"
                        switchChecked: Config.options.bar.utilButtons.showMicToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showMicToggle = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Light / dark")
                        subtitle: Translation.tr("Show the light/dark appearance toggle.")
                        iconName: "dark_mode"
                        switchChecked: Config.options.bar.utilButtons.showDarkModeToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showDarkModeToggle = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Resource usage")
                        subtitle: Translation.tr("Show RAM / CPU usage directly in the bar.")
                        iconName: "monitoring"
                        switchChecked: Config.options.bar.visibility.resources

                        onUserToggled: checked => {
                            Config.options.bar.visibility.resources = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Clock")
                        subtitle: Translation.tr("Show the current time directly in the bar.")
                        iconName: "schedule"
                        switchChecked: Config.options.bar.visibility.clock

                        onUserToggled: checked => {
                            Config.options.bar.visibility.clock = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Keep awake")
                        subtitle: Translation.tr("Show a quick toggle that prevents automatic idle / sleep.")
                        iconName: "coffee"
                        switchChecked: Config.options.bar.utilButtons.showKeepAwakeToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showKeepAwakeToggle = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Night light")
                        subtitle: Translation.tr("Show a quick display-warmth / night-light toggle.")
                        iconName: "brightness_4"
                        switchChecked: Config.options.bar.utilButtons.showNightLightToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showNightLightToggle = checked
                        }
                    }

                    UtilityToggleTile {
                        title: Translation.tr("Screen recording")
                        subtitle: Translation.tr("Show the screen-recording action.")
                        iconName: "videocam"
                        switchChecked: Config.options.bar.utilButtons.showScreenRecord

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showScreenRecord = checked
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // WORKSPACES
    // =========================================================================

    ContentSection {
        icon: "workspaces"
        title: Translation.tr("Workspace indicator")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Workspace appearance")
            subtitle: Translation.tr("Control what each workspace button shows and how many workspaces are represented.")
            iconName: "workspaces"

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                PreferenceSwitchRow {
                    title: Translation.tr("Always show workspace numbers")
                    subtitle: Translation.tr("Keep workspace numbers visible instead of falling back to dots or app-only presentation.")
                    iconName: "counter_1"
                    switchChecked: Config.options.bar.workspaces.alwaysShowNumbers

                    onUserToggled: checked => {
                        Config.options.bar.workspaces.alwaysShowNumbers = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Show app icons")
                    subtitle: Translation.tr("Show the main application icon for occupied workspaces.")
                    iconName: "award_star"
                    switchChecked: Config.options.bar.workspaces.showAppIcons

                    onUserToggled: checked => {
                        Config.options.bar.workspaces.showAppIcons = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: Config.options.bar.workspaces.showAppIcons
                    title: Translation.tr("Monochrome app icons")
                    subtitle: Config.options.bar.workspaces.showAppIcons
                        ? Translation.tr("Tint workspace app icons using the current workspace/theme color.")
                        : Translation.tr("Enable app icons first to use themed icon tinting.")
                    iconName: "colors"
                    switchChecked: Config.options.bar.workspaces.monochromeIcons

                    onUserToggled: checked => {
                        Config.options.bar.workspaces.monochromeIcons = checked
                    }
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "view_column"
                    text: Translation.tr("Visible workspaces")
                    value: Config.options.bar.workspaces.shown
                    from: 1
                    to: 30
                    stepSize: 1

                    onValueChanged: {
                        Config.options.bar.workspaces.shown = value
                    }
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                implicitHeight: root.compactControlHeight
                buttonRadius: Appearance.radius.control

                materialIcon: root.workspaceNumberingExpanded
                    ? "expand_less"
                    : "format_list_numbered"

                mainText: root.workspaceNumberingExpanded
                    ? Translation.tr("Hide workspace numbering")
                    : Translation.tr("Workspace numbering")

                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active

                onClicked: {
                    root.workspaceNumberingExpanded =
                        !root.workspaceNumberingExpanded
                }
            }

            ColumnLayout {
                visible: root.workspaceNumberingExpanded
                Layout.fillWidth: true
                spacing: 8

                FieldLabel {
                    title: Translation.tr("Number reveal")
                    subtitle: Translation.tr("Configure the workspace labels shown when number visibility is requested.")
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "touch_long"
                    text: Translation.tr("Number reveal delay (ms)")
                    value: Config.options.bar.workspaces.showNumberDelay
                    from: 0
                    to: 1000
                    stepSize: 50

                    onValueChanged: {
                        Config.options.bar.workspaces.showNumberDelay = value
                    }
                }

                FieldLabel {
                    title: Translation.tr("Number style")
                    subtitle: Translation.tr("Choose the preset used to label workspace numbers.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("Normal")
                        iconName: "timer_10"
                        selected: root.workspaceNumberStyle === "normal"

                        onClicked: root.setWorkspaceNumberStyle("normal")
                    }

                    ChoiceChip {
                        label: Translation.tr("Han")
                        iconName: "square_dot"
                        selected: root.workspaceNumberStyle === "han"

                        onClicked: root.setWorkspaceNumberStyle("han")
                    }

                    ChoiceChip {
                        label: Translation.tr("Roman")
                        iconName: "account_balance"
                        selected: root.workspaceNumberStyle === "roman"

                        onClicked: root.setWorkspaceNumberStyle("roman")
                    }
                }

                Rectangle {
                    visible: root.workspaceNumberStyle === "custom"
                    Layout.fillWidth: true
                    implicitHeight: customNumberMapRow.implicitHeight + 18

                    radius: Appearance.radius.control
                    color: Appearance.colors.colTertiaryContainer

                    RowLayout {
                        id: customNumberMapRow

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
                            text: Translation.tr("A custom workspace number map is active. Choosing a preset will replace it.")
                            color: Appearance.colors.colOnTertiaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
