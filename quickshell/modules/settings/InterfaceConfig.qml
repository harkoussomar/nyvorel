import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

SettingsTabbedPage {
    id: root
    sections: [
        { id: "surfaces", label: Translation.tr("Shell surfaces"), icon: "dashboard_customize" },
        { id: "lock-feedback", label: Translation.tr("Lock & feedback"), icon: "lock" },
        { id: "overlays", label: Translation.tr("Capture tools"), icon: "select_window" },
        { id: "sidebars", label: Translation.tr("Navigation & sidebars"), icon: "side_navigation" },
        { id: "typography", label: Translation.tr("Typography"), icon: "text_format" }
    ]

    // Page-local layout values only. Corner geometry always comes from the
    // project's semantic Appearance.radius.* system.
    readonly property int wideBreakpoint: 700
    readonly property int cardPadding: 14
    readonly property int sectionGap: 12
    readonly property int rowGap: 8
    readonly property int controlHeight: 42
    readonly property int compactControlHeight: 38

    property bool superSymbolExpanded: false
    property bool shortcutTypographyExpanded: false
    property bool lockSecurityExpanded: false
    property bool lockAppearanceExpanded: false
    property bool regionStylesExpanded: false
    property bool sidebarCornerAdvancedExpanded: false
    property bool overviewOrderingExpanded: false
    property bool fontsExpanded: false

    readonly property var superKeySymbols: [
        "Super", "󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "",
        "", "", "󱄛", "", "", "", "⌘", "󰀲", "󰟍", ""
    ]

    // -------------------------------------------------------------------------
    // Reusable page-local primitives
    // -------------------------------------------------------------------------

    function revealSetting(group: string): void {
        switch (group) {
        case "shortcutTypography": root.shortcutTypographyExpanded = true; break
        case "lockSecurity": root.lockSecurityExpanded = true; break
        case "lockAppearance": root.lockAppearanceExpanded = true; break
        case "regionStyles": root.regionStylesExpanded = true; break
        case "sidebarCornerAdvanced": root.sidebarCornerAdvancedExpanded = true; break
        case "overviewOrdering": root.overviewOrderingExpanded = true; break
        case "fonts": root.fontsExpanded = true; break
        }
    }

    component SettingsCard: Rectangle {
        id: card

        property string title: ""
        property string subtitle: ""
        property string iconName: ""
        property bool showHeader: true

        readonly property real naturalHeight:
            cardColumn.implicitHeight + root.cardPadding * 2

        property real matchedHeight: 0

        default property alias content: contentColumn.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.preferredHeight: Math.max(card.naturalHeight, card.matchedHeight)
        implicitHeight: card.naturalHeight

        radius: Appearance.radius.card
        color: Appearance.colors.colLayer2
        clip: true
        border.width: 0
        border.color: Appearance.colors.colLayer0Border

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
                        font.pixelSize: Appearance.font.pixelSize.smaller
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
                text: box.text
                color: box.warning
                    ? Appearance.colors.colOnTertiaryContainer
                    : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }
        }
    }

    component SuperSymbolChoice: RippleButton {
        id: symbolChoice

        required property string symbol

        readonly property bool selected:
            Config.options.cheatsheet.superKey === symbol

        toggled: selected
        implicitWidth: Math.max(46, symbolText.implicitWidth + 16)
        implicitHeight: 42

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control

        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        onClicked: Config.options.cheatsheet.superKey = symbol

        contentItem: StyledText {
            id: symbolText
            anchors.centerIn: parent
            text: symbolChoice.symbol
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: symbolChoice.selected
                ? Appearance.colors.colOnPrimaryContainer
                : Appearance.colors.colOnLayer1
            font.family: Appearance.font.family.iconNerd
            font.pixelSize: Appearance.font.pixelSize.large
        }
    }

    component FontField: ColumnLayout {
        id: fontField

        required property string title
        required property string subtitle
        required property string value

        signal edited(string value)

        Layout.fillWidth: true
        spacing: 4

        FieldLabel {
            title: fontField.title
            subtitle: fontField.subtitle
        }

        MaterialTextField {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            placeholderText: Translation.tr("Font family name")
            text: fontField.value
            Accessible.name: fontField.title

            onEditingFinished: {
                const family = text.trim()
                if (family.length && family !== fontField.value)
                    fontField.edited(family)
                text = Qt.binding(() => fontField.value)
            }
        }
    }

    component OverviewPreview: Rectangle {
        id: overviewPreview

        readonly property int previewRows:
            Math.max(1, Math.min(3, Config.options.overview.rows))

        readonly property int previewColumns:
            Math.max(1, Math.min(6, Config.options.overview.columns))

        Layout.fillWidth: true
        implicitHeight: 140

        radius: Appearance.radius.card
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        GridLayout {
            anchors.centerIn: parent
            columns: overviewPreview.previewColumns
            rows: overviewPreview.previewRows
            columnSpacing: 6
            rowSpacing: 6

            Repeater {
                model:
                    overviewPreview.previewRows
                    * overviewPreview.previewColumns

                delegate: Rectangle {
                    required property int index

                    implicitWidth: 38
                    implicitHeight: 24

                    radius: Appearance.radius.control
                    color: index === 0
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer2

                    border.width: 1
                    border.color: index === 0
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOutlineVariant

                    MaterialSymbol {
                        visible: Config.options.overview.centerIcons
                        anchors.centerIn: parent
                        text: "circle"
                        iconSize: 8
                        color: index === 0
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }
                }
            }
        }

        StyledText {
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: 10
            }

            text: Translation.tr("%1 × %2 · %3%")
                .arg(Config.options.overview.rows)
                .arg(Config.options.overview.columns)
                .arg(Math.round(Config.options.overview.scale * 100))

            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // =========================================================================
    // SHELL SURFACES
    // =========================================================================

    ColumnLayout {
        visible: root.currentSection === "surfaces"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 12

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                title: Translation.tr("Dock")
                subtitle: Translation.tr("Show pinned and running apps at the bottom of the screen.")
                iconName: "call_to_action"

                PreferenceSwitchRow {
                    title: Translation.tr("Show dock")
                    subtitle: Translation.tr("The dock appears briefly when you turn it on.")
                    iconName: "call_to_action"
                    switchChecked: Config.options.dock.enable

                    onUserToggled: checked => {
                        Config.options.dock.enable = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: Config.options.dock.enable
                    title: Translation.tr("Reveal at the bottom edge")
                    subtitle: Translation.tr("Move the pointer to the bottom center. The dock also appears on empty workspaces.")
                    iconName: "highlight_mouse_cursor"
                    switchChecked: Config.options.dock.hoverToReveal

                    onUserToggled: checked => {
                        Config.options.dock.hoverToReveal = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: Config.options.dock.enable
                    title: Translation.tr("Keep dock visible")
                    subtitle: Translation.tr("Pin the dock now and start future sessions with it pinned.")
                    iconName: "keep"
                    switchChecked: Config.options.dock.pinnedOnStartup

                    onUserToggled: checked => {
                        Config.options.dock.pinnedOnStartup = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: Config.options.dock.enable
                    title: Translation.tr("Monochrome app icons")
                    subtitle: Translation.tr("Tint dock app icons using the current shell theme.")
                    iconName: "colors"
                    switchChecked: Config.options.dock.monochromeIcons

                    onUserToggled: checked => {
                        Config.options.dock.monochromeIcons = checked
                    }
                }
            }

            SettingsCard {
                title: Translation.tr("Shortcut labels")
                subtitle: Translation.tr("Choose how keys and shortcuts appear in the shortcut guide.")
                iconName: "keyboard"

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: selectedSuperRow.implicitHeight + 18
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1
                    clip: true

                    RowLayout {
                        id: selectedSuperRow

                        anchors {
                            fill: parent
                            margins: 9
                        }

                        spacing: 10

                        StyledText {
                            text: Config.options.cheatsheet.superKey
                            color: Appearance.colors.colPrimary
                            font.family: Appearance.font.family.iconNerd
                            font.pixelSize: Appearance.font.pixelSize.large
                        }

                        ColumnLayout {
                            // Allow this column to shrink. Without an explicit
                            // zero minimum, the long helper text contributes its
                            // full implicit width and pushes the Choose button
                            // outside the card.
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Super key symbol")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Replace the Super label in the shortcut guide.")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                wrapMode: Text.Wrap
                            }
                        }

                        RippleButtonWithIcon {
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            implicitHeight: root.compactControlHeight
                            buttonRadius: Appearance.radius.control
                            materialIcon:
                                root.superSymbolExpanded
                                    ? "expand_less"
                                    : "edit"
                            mainText: root.superSymbolExpanded
                                ? Translation.tr("Close")
                                : Translation.tr("Choose")

                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active

                            onClicked: {
                                root.superSymbolExpanded =
                                    !root.superSymbolExpanded
                            }
                        }
                    }
                }

                Flow {
                    visible: root.superSymbolExpanded
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.superKeySymbols

                        delegate: SuperSymbolChoice {
                            required property string modelData
                            symbol: modelData
                        }
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("macOS-style modifier symbols")
                    subtitle: Translation.tr("Show Ctrl, Alt, and Shift as ⌃, ⌥, and ⇧.")
                    iconName: "keyboard_command_key"
                    switchChecked: Config.options.cheatsheet.useMacSymbol

                    onUserToggled: checked => {
                        Config.options.cheatsheet.useMacSymbol = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Symbolic function keys")
                    subtitle: Translation.tr("Use glyphs for function-key labels such as F1–F12.")
                    iconName: "keyboard"
                    switchChecked: Config.options.cheatsheet.useFnSymbol

                    onUserToggled: checked => {
                        Config.options.cheatsheet.useFnSymbol = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Symbolic mouse actions")
                    subtitle: Translation.tr("Show mouse and scroll symbols in shortcut key labels.")
                    iconName: "mouse"
                    switchChecked: Config.options.cheatsheet.useMouseSymbol

                    onUserToggled: checked => {
                        Config.options.cheatsheet.useMouseSymbol = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Separate modifier keycaps")
                    subtitle: Translation.tr("Display combinations such as Ctrl + A as distinct keycaps.")
                    iconName: "highlight_keyboard_focus"
                    switchChecked: Config.options.cheatsheet.splitButtons

                    onUserToggled: checked => {
                        Config.options.cheatsheet.splitButtons = checked
                    }
                }

                ExpandButton {
                    collapsedText: Translation.tr("Shortcut guide text size")
                    expandedText: Translation.tr("Hide shortcut guide text size")
                    expanded: root.shortcutTypographyExpanded

                    onClicked: {
                        root.shortcutTypographyExpanded =
                            !root.shortcutTypographyExpanded
                    }
                }

                GridLayout {
                    visible: root.shortcutTypographyExpanded
                    Layout.fillWidth: true
                    columns: width >= 520 ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "keyboard"
                        text: Translation.tr("Key label size (px)")
                        value: Config.options.cheatsheet.fontSize.key
                        from: 8
                        to: 30
                        stepSize: 1

                        onValueChanged: {
                            Config.options.cheatsheet.fontSize.key = value
                        }
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "notes"
                        text: Translation.tr("Shortcut description size (px)")
                        value: Config.options.cheatsheet.fontSize.comment
                        from: 8
                        to: 30
                        stepSize: 1

                        onValueChanged: {
                            Config.options.cheatsheet.fontSize.comment = value
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // LOCK & FEEDBACK
    // =========================================================================

    ColumnLayout {
        visible: root.currentSection === "lock-feedback"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 12

        SettingsCard {
            title: Translation.tr("Lock screen")
            subtitle: Translation.tr("Configure startup locking, security, and lock-screen appearance.")
            iconName: "lock"

            PreferenceSwitchRow {
                title: Translation.tr("Lock on shell startup")
                subtitle: Translation.tr("Lock immediately when a new Hyprland shell instance starts.")
                iconName: "account_circle"
                switchChecked: Config.options.lock.launchOnStartup

                onUserToggled: checked => {
                    Config.options.lock.launchOnStartup = checked
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Security")
                expandedText: Translation.tr("Hide security")
                expanded: root.lockSecurityExpanded

                onClicked: {
                    root.lockSecurityExpanded = !root.lockSecurityExpanded
                }
            }

            ColumnLayout {
                visible: root.lockSecurityExpanded
                Layout.fillWidth: true
                spacing: 8

                PreferenceSwitchRow {
                    title: Translation.tr("Require password for power actions")
                    subtitle: Translation.tr("Require authentication before the shell performs power off or restart actions. This cannot prevent a physical forced shutdown.")
                    iconName: "settings_power"
                    switchChecked:
                        Config.options.lock.security.requirePasswordToPower

                    onUserToggled: checked => {
                        Config.options.lock.security.requirePasswordToPower =
                            checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Unlock login keyring")
                    subtitle: Translation.tr("Unlock the user's keyring after successful authentication.")
                    iconName: "key_vertical"
                    switchChecked:
                        Config.options.lock.security.unlockKeyring

                    onUserToggled: checked => {
                        Config.options.lock.security.unlockKeyring = checked
                    }
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Lock appearance")
                expandedText: Translation.tr("Hide lock appearance")
                expanded: root.lockAppearanceExpanded

                onClicked: {
                    root.lockAppearanceExpanded = !root.lockAppearanceExpanded
                }
            }

            ColumnLayout {
                visible: root.lockAppearanceExpanded
                Layout.fillWidth: true
                spacing: 8

                PreferenceSwitchRow {
                    enabled: Config.options.background.widgets.clock.enable
                    title: Translation.tr("Center lock-screen clock")
                    subtitle: enabled
                        ? Translation.tr("Center the clock while the screen is locked.")
                        : Translation.tr("Turn on the clock widget in Desktop first.")
                    iconName: "center_focus_weak"
                    switchChecked: Config.options.lock.centerClock

                    onUserToggled: checked => {
                        Config.options.lock.centerClock = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: Config.options.background.widgets.clock.enable
                    title: Translation.tr("Show “Locked” label")
                    subtitle: enabled
                        ? Translation.tr("Show the label below the lock-screen clock.")
                        : Translation.tr("Turn on the clock widget in Desktop first.")
                    iconName: "info"
                    switchChecked: Config.options.lock.showLockedText

                    onUserToggled: checked => {
                        Config.options.lock.showLockedText = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Use shapes for password dots")
                    subtitle: Translation.tr("Use varying Material-style shapes instead of ordinary password dots.")
                    iconName: "shapes"
                    switchChecked: Config.options.lock.materialShapeChars

                    onUserToggled: checked => {
                        Config.options.lock.materialShapeChars = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Blur wallpaper while locked")
                    subtitle: Translation.tr("Soften the background behind the lock screen.")
                    iconName: "blur_on"
                    switchChecked: Config.options.lock.blur.enable

                    onUserToggled: checked => {
                        Config.options.lock.blur.enable = checked
                    }
                }

                ConfigSpinBox {
                    visible: Config.options.lock.blur.enable

                    Layout.fillWidth: true
                    icon: "loupe"
                    text: Translation.tr("Blur wallpaper zoom (%)")
                    value: Config.options.lock.blur.extraZoom * 100
                    from: 100
                    to: 150
                    stepSize: 1

                    onValueChanged: {
                        Config.options.lock.blur.extraZoom = value / 100
                    }
                }

                InfoBox {
                    visible: Config.options.lock.blur.enable

                    iconName: "speed"
                    text: Translation.tr("Lock-screen blur uses an additional GPU effect while the Quickshell lock surface is active.")
                }
            }
        }

        SettingsCard {
            title: Translation.tr("Popup duration")
            subtitle: Translation.tr("Set how long notifications and indicators such as volume stay on screen. Apps can set their own notification duration.")
            iconName: "notifications"

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "notifications"
                    text: Translation.tr("Default notification duration (s)")
                    value: Math.round(Config.options.notifications.timeout / 1000)
                    from: 1
                    to: 60
                    stepSize: 1

                    onValueChanged: {
                        Config.options.notifications.timeout = value * 1000
                    }
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "voting_chip"
                    text: Translation.tr("On-screen indicator duration (ms)")
                    value: Config.options.osd.timeout
                    from: 100
                    to: 3000
                    stepSize: 100

                    onValueChanged: {
                        Config.options.osd.timeout = value
                    }
                }
            }
        }
    }

    // =========================================================================
    // CAPTURE TOOLS
    // =========================================================================

    ColumnLayout {
        visible: root.currentSection === "overlays"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 12

        SettingsCard {
            title: Translation.tr("Region selector")
            subtitle: Translation.tr("Configure selection suggestions and rectangle guides.")
            iconName: "screenshot_frame_2"

            FieldLabel {
                title: Translation.tr("Selection suggestions")
                subtitle: Translation.tr("Choose which locally detected regions can be suggested while selecting an area.")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 3 : 1
                columnSpacing: 8
                rowSpacing: 8

                PreferenceSwitchRow {
                    title: Translation.tr("Application windows")
                    subtitle: Translation.tr("Suggest visible app windows as regions to capture.")
                    iconName: "select_window"
                    switchChecked:
                        Config.options.regionSelector.targetRegions.windows

                    onUserToggled: checked => {
                        Config.options.regionSelector.targetRegions.windows =
                            checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Bar, dock, and panels")
                    subtitle: Translation.tr("Suggest shell panels as regions to capture.")
                    iconName: "right_panel_open"
                    switchChecked:
                        Config.options.regionSelector.targetRegions.layers

                    onUserToggled: checked => {
                        Config.options.regionSelector.targetRegions.layers =
                            checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Detected content")
                    subtitle: Translation.tr("Suggest contained screen content using local image processing; no AI is used.")
                    iconName: "nearby"
                    switchChecked:
                        Config.options.regionSelector.targetRegions.content

                    onUserToggled: checked => {
                        Config.options.regionSelector.targetRegions.content =
                            checked
                    }
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Selection styles")
                expandedText: Translation.tr("Hide selection styles")
                expanded: root.regionStylesExpanded

                onClicked: {
                    root.regionStylesExpanded = !root.regionStylesExpanded
                }
            }

            ColumnLayout {
                visible: root.regionStylesExpanded
                Layout.fillWidth: true
                spacing: 8

                PreferenceSwitchRow {
                    title: Translation.tr("Show selection crosshair")
                    subtitle: Translation.tr("Show guide lines while making a rectangular selection.")
                    iconName: "point_scan"
                    switchChecked:
                        Config.options.regionSelector.rect.showAimLines

                    onUserToggled: checked => {
                        Config.options.regionSelector.rect.showAimLines =
                            checked
                    }
                }

            }
        }
    }

    // =========================================================================
    // NAVIGATION & SIDEBARS
    // =========================================================================

    ColumnLayout {
        visible: root.currentSection === "sidebars"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 12

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                title: Translation.tr("Sidebar content")
                subtitle: Translation.tr("Choose what appears in the sidebars and how quick controls are arranged.")
                iconName: "side_navigation"

                FieldLabel {
                    title: Translation.tr("Quick-toggle layout")
                    subtitle: Translation.tr("Choose between compact controls and a tile grid.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("Classic")
                        iconName: "password_2"
                        selected:
                            Config.options.sidebar.quickToggles.style
                            === "classic"

                        onClicked: {
                            Config.options.sidebar.quickToggles.style =
                                "classic"
                        }
                    }

                    ChoiceChip {
                        label: Translation.tr("Tile grid")
                        iconName: "action_key"
                        selected:
                            Config.options.sidebar.quickToggles.style
                            === "android"

                        onClicked: {
                            Config.options.sidebar.quickToggles.style =
                                "android"
                        }
                    }
                }

                ConfigSpinBox {
                    visible:
                        Config.options.sidebar.quickToggles.style === "android"

                    Layout.fillWidth: true
                    icon: "splitscreen_left"
                    text: Translation.tr("Tiles per row")
                    value:
                        Config.options.sidebar.quickToggles.android.columns
                    from: 1
                    to: 2
                    stepSize: 1

                    onValueChanged: {
                        Config.options.sidebar.quickToggles.android.columns =
                            value
                    }
                }

            }

            SettingsCard {
                title: Translation.tr("Sidebar interaction")
                subtitle: Translation.tr("Open sidebars from screen corners independently of the current bar position.")
                iconName: "highlight_mouse_cursor"

                PreferenceSwitchRow {
                    title: Translation.tr("Corner shortcuts")
                    subtitle: Translation.tr("Create invisible corner interaction regions for opening the left and right sidebars.")
                    iconName: "screenshot_frame_2"
                    switchChecked: Config.options.sidebar.cornerOpen.enable

                    onUserToggled: checked => {
                        Config.options.sidebar.cornerOpen.enable = checked
                    }
                }

                ColumnLayout {
                    visible: Config.options.sidebar.cornerOpen.enable
                    Layout.fillWidth: true
                    spacing: 8

                    PreferenceSwitchRow {
                        title: Translation.tr("Open on hover")
                        subtitle: Translation.tr("Open the sidebar by hovering its corner; otherwise a click is required.")
                        iconName: "highlight_mouse_cursor"
                        switchChecked:
                            Config.options.sidebar.cornerOpen.clickless

                        onUserToggled: checked => {
                            Config.options.sidebar.cornerOpen.clickless =
                                checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Use bottom corners")
                        subtitle: Translation.tr("Move the active sidebar corner regions to the bottom edge.")
                        iconName: "vertical_align_bottom"
                        switchChecked: Config.options.sidebar.cornerOpen.bottom

                        onUserToggled: checked => {
                            Config.options.sidebar.cornerOpen.bottom = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Scroll corners to adjust brightness and volume")
                        subtitle: Translation.tr("Scroll the left corner region for brightness and the right corner region for volume.")
                        iconName: "unfold_more_double"
                        switchChecked:
                            Config.options.sidebar.cornerOpen.valueScroll

                        onUserToggled: checked => {
                            Config.options.sidebar.cornerOpen.valueScroll =
                                checked
                        }
                    }

                    ExpandButton {
                        collapsedText: Translation.tr("Advanced hit area")
                        expandedText: Translation.tr("Hide advanced hit area")
                        expanded: root.sidebarCornerAdvancedExpanded

                        onClicked: {
                            root.sidebarCornerAdvancedExpanded =
                                !root.sidebarCornerAdvancedExpanded
                        }
                    }

                    ColumnLayout {
                        visible: root.sidebarCornerAdvancedExpanded
                        Layout.fillWidth: true
                        spacing: 8

                        PreferenceSwitchRow {
                            visible:
                                !Config.options.sidebar.cornerOpen.clickless

                            title: Translation.tr("Open on hover at the exact corner")
                            subtitle: Translation.tr("Inside the wider hit area, a click is still required.")
                            iconName: "ads_click"
                            switchChecked:
                                Config.options.sidebar.cornerOpen.clicklessCornerEnd

                            onUserToggled: checked => {
                                Config.options.sidebar.cornerOpen.clicklessCornerEnd =
                                    checked
                            }
                        }

                        ConfigSpinBox {
                            visible:
                                !Config.options.sidebar.cornerOpen.clickless
                                && Config.options.sidebar.cornerOpen.clicklessCornerEnd

                            Layout.fillWidth: true
                            icon: "arrow_cool_down"
                            text: Translation.tr("Hover distance from edge (px)")
                            value:
                                Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                            from: 0
                            to: 20
                            stepSize: 1

                            onValueChanged: {
                                Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset =
                                    value
                            }
                        }

                        PreferenceSwitchRow {
                            title: Translation.tr("Show corner hit area")
                            subtitle: Translation.tr("Show the otherwise invisible corner hit area for tuning.")
                            iconName: "visibility"
                            switchChecked:
                                Config.options.sidebar.cornerOpen.visualize

                            onUserToggled: checked => {
                                Config.options.sidebar.cornerOpen.visualize =
                                    checked
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: width >= 520 ? 2 : 1
                            columnSpacing: 8
                            rowSpacing: 8

                            ConfigSpinBox {
                                Layout.fillWidth: true
                                icon: "arrow_range"
                                text: Translation.tr("Hit area width (px)")
                                value:
                                    Config.options.sidebar.cornerOpen.cornerRegionWidth
                                from: 1
                                to: 300
                                stepSize: 1

                                onValueChanged: {
                                    Config.options.sidebar.cornerOpen.cornerRegionWidth =
                                        value
                                }
                            }

                            ConfigSpinBox {
                                Layout.fillWidth: true
                                icon: "height"
                                text: Translation.tr("Hit area height (px)")
                                value:
                                    Config.options.sidebar.cornerOpen.cornerRegionHeight
                                from: 1
                                to: 300
                                stepSize: 1

                                onValueChanged: {
                                    Config.options.sidebar.cornerOpen.cornerRegionHeight =
                                        value
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            title: Translation.tr("Overview")
            subtitle: Translation.tr("Configure the workspace overview grid and how its window previews are arranged.")
            iconName: "overview_key"

            PreferenceSwitchRow {
                title: Translation.tr("Show workspace grid")
                subtitle: Translation.tr("Show workspace previews when pressing Super + Tab. Search stays available.")
                iconName: "check"
                switchChecked: Config.options.overview.enable

                onUserToggled: checked => {
                    Config.options.overview.enable = checked
                }
            }

            GridLayout {
                id: overviewLayout
                visible: Config.options.overview.enable
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 14
                rowSpacing: 12

                OverviewPreview {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    PreferenceSwitchRow {
                        title: Translation.tr("Center app icons")
                        subtitle: Translation.tr("Place application icons in the center of overview window previews.")
                        iconName: "center_focus_strong"
                        switchChecked: Config.options.overview.centerIcons

                        onUserToggled: checked => {
                            Config.options.overview.centerIcons = checked
                        }
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "loupe"
                        text: Translation.tr("Preview scale (%)")
                        value: Config.options.overview.scale * 100
                        from: 1
                        to: 100
                        stepSize: 1

                        onValueChanged: {
                            Config.options.overview.scale = value / 100
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 520 ? 2 : 1
                        columnSpacing: 8
                        rowSpacing: 8

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "splitscreen_bottom"
                            text: Translation.tr("Rows")
                            value: Config.options.overview.rows
                            from: 1
                            to: 20
                            stepSize: 1

                            onValueChanged: {
                                Config.options.overview.rows = value
                            }
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "splitscreen_right"
                            text: Translation.tr("Columns")
                            value: Config.options.overview.columns
                            from: 1
                            to: 20
                            stepSize: 1

                            onValueChanged: {
                                Config.options.overview.columns = value
                            }
                        }
                    }
                }

                ExpandButton {
                    Layout.columnSpan: overviewLayout.columns
                    collapsedText: Translation.tr("Overview ordering")
                    expandedText: Translation.tr("Hide overview ordering")
                    expanded: root.overviewOrderingExpanded

                    onClicked: {
                        root.overviewOrderingExpanded =
                            !root.overviewOrderingExpanded
                    }
                }

                GridLayout {
                    visible: root.overviewOrderingExpanded
                    Layout.columnSpan: overviewLayout.columns
                    Layout.fillWidth: true
                    columns: overviewLayout.columns
                    columnSpacing: 12
                    rowSpacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        FieldLabel {
                            title: Translation.tr("Horizontal order")
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            ChoiceChip {
                                label: Translation.tr("Left to right")
                                iconName: "arrow_forward"
                                selected:
                                    Config.options.overview.orderRightLeft === 0

                                onClicked:
                                    Config.options.overview.orderRightLeft = 0
                            }

                            ChoiceChip {
                                label: Translation.tr("Right to left")
                                iconName: "arrow_back"
                                selected:
                                    Config.options.overview.orderRightLeft === 1

                                onClicked:
                                    Config.options.overview.orderRightLeft = 1
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        FieldLabel {
                            title: Translation.tr("Vertical order")
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            ChoiceChip {
                                label: Translation.tr("Top-down")
                                iconName: "arrow_downward"
                                selected:
                                    Config.options.overview.orderBottomUp === 0

                                onClicked:
                                    Config.options.overview.orderBottomUp = 0
                            }

                            ChoiceChip {
                                label: Translation.tr("Bottom-up")
                                iconName: "arrow_upward"
                                selected:
                                    Config.options.overview.orderBottomUp === 1

                                onClicked:
                                    Config.options.overview.orderBottomUp = 1
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // TYPOGRAPHY
    // =========================================================================

    ColumnLayout {
        visible: root.currentSection === "typography"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 12

        SettingsCard {
            title: Translation.tr("Interface fonts")
            subtitle: Translation.tr("Use an installed font family name. Press Enter or leave the field to apply it.")
            iconName: "text_format"

            FontField {
                title: Translation.tr("Main font")
                subtitle: Translation.tr("General interface text.")
                value: Config.options.appearance.fonts.main

                onEdited: value => {
                    Config.options.appearance.fonts.main = value
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("More font roles")
                expandedText: Translation.tr("Hide additional font roles")
                expanded: root.fontsExpanded

                onClicked: root.fontsExpanded = !root.fontsExpanded
            }

            GridLayout {
                visible: root.fontsExpanded
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 12
                rowSpacing: 12

                FontField {
                    title: Translation.tr("Numbers font")
                    subtitle: Translation.tr("Numeric values and counters.")
                    value: Config.options.appearance.fonts.numbers

                    onEdited: value => {
                        Config.options.appearance.fonts.numbers = value
                    }
                }

                FontField {
                    title: Translation.tr("Title font")
                    subtitle: Translation.tr("Headings and larger titles.")
                    value: Config.options.appearance.fonts.title

                    onEdited: value => {
                        Config.options.appearance.fonts.title = value
                    }
                }

                FontField {
                    title: Translation.tr("Monospace font")
                    subtitle: Translation.tr("Code and terminal-like text.")
                    value: Config.options.appearance.fonts.monospace

                    onEdited: value => {
                        Config.options.appearance.fonts.monospace = value
                    }
                }

                FontField {
                    title: Translation.tr("Nerd Font icons")
                    subtitle: Translation.tr("Glyph source for Nerd Font symbols.")
                    value: Config.options.appearance.fonts.iconNerd

                    onEdited: value => {
                        Config.options.appearance.fonts.iconNerd = value
                    }
                }

                FontField {
                    title: Translation.tr("Reading font")
                    subtitle: Translation.tr("Large blocks of reading-focused text.")
                    value: Config.options.appearance.fonts.reading

                    onEdited: value => {
                        Config.options.appearance.fonts.reading = value
                    }
                }

                FontField {
                    title: Translation.tr("Expressive font")
                    subtitle: Translation.tr("Decorative and expressive interface text.")
                    value: Config.options.appearance.fonts.expressive

                    onEdited: value => {
                        Config.options.appearance.fonts.expressive = value
                    }
                }
            }
        }
    }
}
