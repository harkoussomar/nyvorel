import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

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
    property bool crosshairExpanded: false
    property bool floatingImageExpanded: false
    property bool regionStylesExpanded: false
    property bool sidebarCornerAdvancedExpanded: false
    property bool overviewOrderingExpanded: false
    property bool fontsExpanded: false

    readonly property var superKeySymbols: [
        "󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "",
        "", "", "󱄛", "", "", "", "⌘", "󰀲", "󰟍", ""
    ]

    // -------------------------------------------------------------------------
    // Semantic window-radius bridge
    // -------------------------------------------------------------------------

    property int pendingWindowRadius: Appearance.radius.window

    function queueWindowRadius(value: real): void {
        pendingWindowRadius = Math.max(0, Math.min(40, Math.round(value)))
        windowRadiusApplyTimer.restart()
    }

    Timer {
        id: windowRadiusApplyTimer
        interval: 90
        repeat: false

        onTriggered: {
            Quickshell.execDetached([
                "@HOME@/.config/quickshell/nyvorel/scripts/appearance-studio/semantic_radius_hypr.py",
                "window",
                String(root.pendingWindowRadius)
            ])
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
        clip: true
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
                font.pixelSize: Appearance.font.pixelSize.smallest
                wrapMode: Text.Wrap
            }
        }
    }

    component RadiusRoleEditor: Rectangle {
        id: editor

        required property string role
        required property string title
        required property string iconName
        required property int resetValue

        property bool resetFollowsGlobal: false

        readonly property bool followsGlobal:
            Appearance.semanticRadiusFollowsGlobal(role)

        readonly property int storedValue:
            Appearance.semanticRadiusStoredValue(role)

        readonly property int resolvedValue:
            Appearance.semanticRadiusResolvedValue(role)

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: editorColumn.implicitHeight + 20

        radius: Appearance.radius.control
        color: Appearance.colors.colLayer1
        clip: true

        ColumnLayout {
            id: editorColumn

            anchors {
                fill: parent
                margins: 10
            }

            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: editor.iconName
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: editor.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: editor.followsGlobal
                            ? Translation.tr("Using Global")
                            : Translation.tr("Custom value")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }

                StyledText {
                    text: editor.resolvedValue + " px"
                    color: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: inheritRow.implicitHeight + 16
                radius: Appearance.radius.control
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: inheritRow

                    anchors {
                        fill: parent
                        margins: 8
                    }

                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Follow Global radius")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }

                    StyledSwitch {
                        checked: editor.followsGlobal

                        onToggled: {
                            Appearance.setSemanticRadiusFollowGlobal(editor.role, checked)

                            if (editor.role === "window")
                                root.queueWindowRadius(Appearance.radius.window)
                        }
                    }
                }
            }

            ColumnLayout {
                visible: !editor.followsGlobal
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledSlider {
                        id: roleSlider

                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.XS
                        from: 0
                        to: 40
                        value: editor.storedValue
                        stopIndicatorValues: [0, 8, 12, 17, 23, 30, 40]
                        usePercentTooltip: false

                        onMoved: {
                            Appearance.setSemanticRadiusValue(editor.role, value)

                            if (editor.role === "window")
                                root.queueWindowRadius(Appearance.radius.window)
                        }
                    }

                    StyledText {
                        text: editor.storedValue + " px"
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Reset")

                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active

                    onClicked: {
                        Appearance.setSemanticRadiusValue(
                            editor.role,
                            editor.resetValue
                        )
                        Appearance.setSemanticRadiusFollowGlobal(
                            editor.role,
                            editor.resetFollowsGlobal
                        )

                        if (editor.role === "window")
                            root.queueWindowRadius(Appearance.radius.window)
                    }
                }
            }
        }
    }

    component GeometryPreview: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 160

        radius: Appearance.radius.card
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        Rectangle {
            id: previewWindow

            anchors {
                fill: parent
                margins: 18
            }

            radius: Appearance.radius.window
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }

                height: 28
                radius: Appearance.radius.bar
                color: Appearance.colors.colPrimaryContainer

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Window")
                    color: Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }

            Rectangle {
                width: Math.min(220, parent.width * 0.48)
                height: 74
                anchors.centerIn: parent

                radius: Appearance.radius.modal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                Rectangle {
                    width: parent.width - 28
                    height: 28
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                        bottomMargin: 12
                    }

                    radius: Appearance.radius.control
                    color: Appearance.colors.colPrimaryContainer

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Control")
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }
            }
        }
    }

    component SuperSymbolChoice: RippleButton {
        id: symbolChoice

        required property string symbol

        readonly property bool selected:
            Config.options.cheatsheet.superKey === symbol

        toggled: selected
        implicitWidth: 46
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

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name")
            text: fontField.value
            wrapMode: TextEdit.NoWrap

            onTextChanged: {
                if (text !== fontField.value)
                    fontField.edited(text)
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
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    // =========================================================================
    // APPEARANCE & GEOMETRY
    // =========================================================================

    ContentSection {
        icon: "rounded_corner"
        title: Translation.tr("Appearance & geometry")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Corner geometry")
            subtitle: Translation.tr("Set one global corner radius, then override individual interface surfaces only where needed.")
            iconName: "rounded_corner"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                FieldLabel {
                    title: Translation.tr("Global radius")
                    subtitle: Translation.tr("Used by every semantic role configured to follow Global.")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledSlider {
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.XS
                        from: 0
                        to: 40
                        value: Appearance.semanticRadiusStoredValue("global")
                        stopIndicatorValues: [0, 8, 12, 17, 23, 30, 40]
                        usePercentTooltip: false

                        onMoved: {
                            Appearance.setSemanticRadiusGlobal(value)

                            if (Appearance.semanticRadiusFollowsGlobal("window"))
                                root.queueWindowRadius(Appearance.radius.window)
                        }
                    }

                    StyledText {
                        text: Appearance.radius.global + " px"
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Reset Global to 17 px")

                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active

                    onClicked: {
                        Appearance.setSemanticRadiusGlobal(17)

                        if (Appearance.semanticRadiusFollowsGlobal("window"))
                            root.queueWindowRadius(Appearance.radius.window)
                    }
                }

                InfoBox {
                    text: Translation.tr("Window radius changes are also synchronized with Hyprland through the semantic-radius bridge.")
                    iconName: "info"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 760 ? 2 : 1
                    columnSpacing: 10
                    rowSpacing: 10

                    RadiusRoleEditor {
                        role: "window"
                        title: Translation.tr("Windows")
                        iconName: "desktop_windows"
                        resetValue: 8
                    }

                    RadiusRoleEditor {
                        role: "bar"
                        title: Translation.tr("Bar")
                        iconName: "view_agenda"
                        resetValue: 8
                    }

                    RadiusRoleEditor {
                        role: "modal"
                        title: Translation.tr("Modals")
                        iconName: "select_window"
                        resetValue: 23
                    }

                    RadiusRoleEditor {
                        role: "card"
                        title: Translation.tr("Cards")
                        iconName: "dashboard"
                        resetValue: 17
                        resetFollowsGlobal: true
                    }

                    RadiusRoleEditor {
                        role: "control"
                        title: Translation.tr("Controls")
                        iconName: "buttons_alt"
                        resetValue: 12
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: filePickerRow.implicitHeight + 18
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1
                    clip: true

                    RowLayout {
                        id: filePickerRow

                        anchors {
                            fill: parent
                            margins: 9
                        }

                        spacing: 10

                        MaterialSymbol {
                            text: "wallpaper_slideshow"
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: Translation.tr("System wallpaper file picker")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                text: Translation.tr("Use the desktop system file dialog when choosing a wallpaper.")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.Wrap
                            }
                        }

                        StyledSwitch {
                            checked:
                                Config.options.wallpaperSelector.useSystemFileDialog

                            onToggled: {
                                Config.options.wallpaperSelector.useSystemFileDialog =
                                    checked
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SHELL SURFACES
    // =========================================================================

    ContentSection {
        icon: "dashboard_customize"
        title: Translation.tr("Shell surfaces")
        Layout.fillWidth: true

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                title: Translation.tr("Dock")
                subtitle: Translation.tr("Control whether the dock is loaded and how it reveals itself.")
                iconName: "call_to_action"

                PreferenceSwitchRow {
                    title: Translation.tr("Show dock")
                    subtitle: Config.options.dock.enable
                        ? Translation.tr("The dock panel is loaded on each monitor.")
                        : Translation.tr("The dock panel is disabled.")
                    iconName: "call_to_action"
                    switchChecked: Config.options.dock.enable

                    onUserToggled: checked => {
                        Config.options.dock.enable = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: Config.options.dock.enable
                    title: Translation.tr("Reveal on pointer hover")
                    subtitle: Translation.tr("When off, the dock reveals only on an empty workspace.")
                    iconName: "highlight_mouse_cursor"
                    switchChecked: Config.options.dock.hoverToReveal

                    onUserToggled: checked => {
                        Config.options.dock.hoverToReveal = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: Config.options.dock.enable
                    title: Translation.tr("Pinned on startup")
                    subtitle: Translation.tr("Start with the dock in its pinned state.")
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
                subtitle: Translation.tr("Customize how the keyboard cheat sheet represents Super, modifiers, function keys, and mouse actions.")
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
                                text: Translation.tr("Used wherever the cheat sheet renders the Super key.")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
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
                    subtitle: Translation.tr("Render modifier names such as Ctrl, Alt, and Shift using symbolic glyphs.")
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
                    subtitle: Translation.tr("Use mouse and scroll glyphs in shortcut descriptions.")
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
                    collapsedText: Translation.tr("Cheat-sheet typography")
                    expandedText: Translation.tr("Hide cheat-sheet typography")
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
                        text: Translation.tr("Key label size")
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
                        text: Translation.tr("Description size")
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

    ContentSection {
        icon: "lock"
        title: Translation.tr("Lock & feedback")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Lock screen")
            subtitle: Translation.tr("Choose the lock provider, startup behavior, security rules, and Quickshell lock appearance.")
            iconName: "lock"

            FieldLabel {
                title: Translation.tr("Lock provider")
                subtitle: Translation.tr("Quickshell uses the built-in lock surface. Hyprlock launches the external Hyprlock process instead.")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                ChoiceChip {
                    label: Translation.tr("Quickshell")
                    iconName: "lock"
                    selected: !Config.options.lock.useHyprlock

                    onClicked: Config.options.lock.useHyprlock = false
                }

                ChoiceChip {
                    label: Translation.tr("Hyprlock")
                    iconName: "water_drop"
                    selected: Config.options.lock.useHyprlock

                    onClicked: Config.options.lock.useHyprlock = true
                }
            }

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
                    enabled: !Config.options.lock.useHyprlock
                    title: Translation.tr("Unlock login keyring")
                    subtitle: Config.options.lock.useHyprlock
                        ? Translation.tr("This integration is part of the built-in Quickshell lock flow.")
                        : Translation.tr("Unlock the user's keyring after successful Quickshell authentication.")
                    iconName: "key_vertical"
                    switchChecked:
                        Config.options.lock.security.unlockKeyring

                    onUserToggled: checked => {
                        Config.options.lock.security.unlockKeyring = checked
                    }
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Quickshell lock appearance")
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

                InfoBox {
                    visible: Config.options.lock.useHyprlock
                    iconName: "info"
                    text: Translation.tr("These appearance controls affect the built-in Quickshell lock screen and are not applied to Hyprlock.")
                }

                PreferenceSwitchRow {
                    enabled: !Config.options.lock.useHyprlock
                    title: Translation.tr("Center clock")
                    subtitle: Translation.tr("Place the lock-screen clock in the centered layout.")
                    iconName: "center_focus_weak"
                    switchChecked: Config.options.lock.centerClock

                    onUserToggled: checked => {
                        Config.options.lock.centerClock = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: !Config.options.lock.useHyprlock
                    title: Translation.tr("Show “Locked” label")
                    subtitle: Translation.tr("Display the lock-state text on the built-in lock screen.")
                    iconName: "info"
                    switchChecked: Config.options.lock.showLockedText

                    onUserToggled: checked => {
                        Config.options.lock.showLockedText = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: !Config.options.lock.useHyprlock
                    title: Translation.tr("Shape password characters")
                    subtitle: Translation.tr("Use varying Material-style shapes instead of ordinary password dots.")
                    iconName: "shapes"
                    switchChecked: Config.options.lock.materialShapeChars

                    onUserToggled: checked => {
                        Config.options.lock.materialShapeChars = checked
                    }
                }

                PreferenceSwitchRow {
                    enabled: !Config.options.lock.useHyprlock
                    title: Translation.tr("Blur wallpaper while locked")
                    subtitle: Translation.tr("Enable the additional Gaussian blur layer used by the built-in lock transition.")
                    iconName: "blur_on"
                    switchChecked: Config.options.lock.blur.enable

                    onUserToggled: checked => {
                        Config.options.lock.blur.enable = checked
                    }
                }

                ConfigSpinBox {
                    visible:
                        !Config.options.lock.useHyprlock
                        && Config.options.lock.blur.enable

                    Layout.fillWidth: true
                    icon: "loupe"
                    text: Translation.tr("Blur wallpaper zoom (%)")
                    value: Config.options.lock.blur.extraZoom * 100
                    from: 1
                    to: 150
                    stepSize: 2

                    onValueChanged: {
                        Config.options.lock.blur.extraZoom = value / 100
                    }
                }

                InfoBox {
                    visible:
                        !Config.options.lock.useHyprlock
                        && Config.options.lock.blur.enable

                    iconName: "speed"
                    text: Translation.tr("Lock-screen blur uses an additional GPU effect while the Quickshell lock surface is active.")
                }
            }
        }

        SettingsCard {
            title: Translation.tr("Transient feedback")
            subtitle: Translation.tr("Choose how long notification popups and the on-screen display remain visible.")
            iconName: "notifications"

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "notifications"
                    text: Translation.tr("Notification timeout (s)")
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
                    text: Translation.tr("OSD timeout (ms)")
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
    // TOOLS & OVERLAYS
    // =========================================================================

    ContentSection {
        icon: "select_window"
        title: Translation.tr("Tools & overlays")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Overlay behavior")
            subtitle: Translation.tr("Configure the shared overlay surface, then expand individual overlay tools only when needed.")
            iconName: "select_window"

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                PreferenceSwitchRow {
                    title: Translation.tr("Opening zoom animation")
                    subtitle: Translation.tr("Animate the overlay surface when it opens.")
                    iconName: "high_density"
                    switchChecked:
                        Config.options.overlay.openingZoomAnimation

                    onUserToggled: checked => {
                        Config.options.overlay.openingZoomAnimation = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Darken background")
                    subtitle: Translation.tr("Dim the rest of the screen while the overlay is open.")
                    iconName: "texture"
                    switchChecked: Config.options.overlay.darkenScreen

                    onUserToggled: checked => {
                        Config.options.overlay.darkenScreen = checked
                    }
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Crosshair overlay")
                expandedText: Translation.tr("Hide crosshair overlay")
                expanded: root.crosshairExpanded

                onClicked: {
                    root.crosshairExpanded = !root.crosshairExpanded
                }
            }

            ColumnLayout {
                visible: root.crosshairExpanded
                Layout.fillWidth: true
                spacing: 8

                FieldLabel {
                    title: Translation.tr("Valorant-format crosshair code")
                    subtitle: Translation.tr("Press Super+G to open the overlay and pin the configured crosshair.")
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Crosshair code")
                    text: Config.options.crosshair.code
                    wrapMode: TextEdit.Wrap

                    onTextChanged: {
                        Config.options.crosshair.code = text
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: "open_in_new"
                    mainText: Translation.tr("Open visual crosshair editor")

                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active

                    onClicked: {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", `https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`])
                    }

                    StyledToolTip {
                        text: "www.vcrdb.net"
                    }
                }
            }

            ExpandButton {
                collapsedText: Translation.tr("Floating image overlay")
                expandedText: Translation.tr("Hide floating image overlay")
                expanded: root.floatingImageExpanded

                onClicked: {
                    root.floatingImageExpanded = !root.floatingImageExpanded
                }
            }

            ColumnLayout {
                visible: root.floatingImageExpanded
                Layout.fillWidth: true
                spacing: 8

                FieldLabel {
                    title: Translation.tr("Image source")
                    subtitle: Translation.tr("Source used by the existing floating-image overlay.")
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Image URL or source")
                    text: Config.options.overlay.floatingImage.imageSource
                    wrapMode: TextEdit.Wrap

                    onTextChanged: {
                        Config.options.overlay.floatingImage.imageSource = text
                    }
                }
            }
        }

        SettingsCard {
            title: Translation.tr("Region selector")
            subtitle: Translation.tr("Customize screen-snipping suggestions and the Google Lens selection gesture.")
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
                    title: Translation.tr("Windows")
                    subtitle: Translation.tr("Suggest visible application windows.")
                    iconName: "select_window"
                    switchChecked:
                        Config.options.regionSelector.targetRegions.windows

                    onUserToggled: checked => {
                        Config.options.regionSelector.targetRegions.windows =
                            checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Layer surfaces")
                    subtitle: Translation.tr("Suggest compositor surfaces such as the navbar, dock, and other non-window layers.")
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

            FieldLabel {
                Layout.topMargin: 2
                title: Translation.tr("Google Lens selection")
                subtitle: Translation.tr("Choose the default gesture used for image-search selection.")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                ChoiceChip {
                    label: Translation.tr("Rectangle")
                    iconName: "activity_zone"
                    selected:
                        !Config.options.search.imageSearch.useCircleSelection

                    onClicked: {
                        Config.options.search.imageSearch.useCircleSelection =
                            false
                    }
                }

                ChoiceChip {
                    label: Translation.tr("Circle to Search")
                    iconName: "gesture"
                    selected:
                        Config.options.search.imageSearch.useCircleSelection

                    onClicked: {
                        Config.options.search.imageSearch.useCircleSelection =
                            true
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
                    title: Translation.tr("Rectangle aim lines")
                    subtitle: Translation.tr("Show guide lines while making a rectangular selection.")
                    iconName: "point_scan"
                    switchChecked:
                        Config.options.regionSelector.rect.showAimLines

                    onUserToggled: checked => {
                        Config.options.regionSelector.rect.showAimLines =
                            checked
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.wideBreakpoint ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "eraser_size_3"
                        text: Translation.tr("Circle stroke width")
                        value:
                            Config.options.regionSelector.circle.strokeWidth
                        from: 1
                        to: 20
                        stepSize: 1

                        onValueChanged: {
                            Config.options.regionSelector.circle.strokeWidth =
                                value
                        }
                    }

                    ConfigSpinBox {
                        Layout.fillWidth: true
                        icon: "screenshot_frame_2"
                        text: Translation.tr("Circle padding")
                        value: Config.options.regionSelector.circle.padding
                        from: 0
                        to: 100
                        stepSize: 5

                        onValueChanged: {
                            Config.options.regionSelector.circle.padding =
                                value
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // NAVIGATION & SIDEBARS
    // =========================================================================

    ContentSection {
        icon: "side_navigation"
        title: Translation.tr("Navigation & sidebars")
        Layout.fillWidth: true

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            SettingsCard {
                title: Translation.tr("Sidebar content")
                subtitle: Translation.tr("Choose what appears in the sidebars and how quick controls are arranged.")
                iconName: "side_navigation"

                PreferenceSwitchRow {
                    title: Translation.tr("Preload right sidebar")
                    subtitle: Translation.tr("Keep right-sidebar content loaded while closed for faster reopening. Uses extra RAM.")
                    iconName: "memory"
                    switchChecked: Config.options.sidebar.keepRightSidebarLoaded

                    onUserToggled: checked => {
                        Config.options.sidebar.keepRightSidebarLoaded = checked
                    }
                }

                FieldLabel {
                    title: Translation.tr("Quick-toggle layout")
                    subtitle: Translation.tr("Choose between the compact classic layout and the Android-style grid.")
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
                        label: Translation.tr("Android")
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

                PreferenceSwitchRow {
                    title: Translation.tr("Quick sliders")
                    subtitle: Translation.tr("Enable the sidebar slider area; choose which sliders are shown below.")
                    iconName: "tune"
                    switchChecked: Config.options.sidebar.quickSliders.enable

                    onUserToggled: checked => {
                        Config.options.sidebar.quickSliders.enable = checked
                    }
                }

                GridLayout {
                    visible: Config.options.sidebar.quickSliders.enable
                    Layout.fillWidth: true
                    columns: width >= 520 ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    PreferenceSwitchRow {
                        title: Translation.tr("Brightness")
                        subtitle: Translation.tr("Show the brightness slider.")
                        iconName: "brightness_6"
                        switchChecked:
                            Config.options.sidebar.quickSliders.showBrightness

                        onUserToggled: checked => {
                            Config.options.sidebar.quickSliders.showBrightness =
                                checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Volume")
                        subtitle: Translation.tr("Show the output-volume slider.")
                        iconName: "volume_up"
                        switchChecked:
                            Config.options.sidebar.quickSliders.showVolume

                        onUserToggled: checked => {
                            Config.options.sidebar.quickSliders.showVolume =
                                checked
                        }
                    }

                    PreferenceSwitchRow {
                        Layout.columnSpan: width >= 520 ? 2 : 1
                        title: Translation.tr("Microphone")
                        subtitle: Translation.tr("Show the microphone-input slider.")
                        iconName: "mic"
                        switchChecked:
                            Config.options.sidebar.quickSliders.showMic

                        onUserToggled: checked => {
                            Config.options.sidebar.quickSliders.showMic =
                                checked
                        }
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
                        title: Translation.tr("Brightness / volume scrolling")
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

                            title: Translation.tr("Hover exact corner as fallback")
                            subtitle: Translation.tr("In click mode, hovering the absolute screen corner can still open the sidebar.")
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
                            text: Translation.tr("Exact-corner edge offset")
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
                            title: Translation.tr("Visualize interaction region")
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
                                text: Translation.tr("Region width")
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
                                text: Translation.tr("Region height")
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
                title: Translation.tr("Enable overview")
                subtitle: Translation.tr("Allow the shell's workspace/window overview interface.")
                iconName: "check"
                switchChecked: Config.options.overview.enable

                onUserToggled: checked => {
                    Config.options.overview.enable = checked
                }
            }

            GridLayout {
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
                        text: Translation.tr("Window scale (%)")
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
                    Layout.columnSpan: width >= root.wideBreakpoint ? 2 : 1
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
                    Layout.columnSpan: width >= root.wideBreakpoint ? 2 : 1
                    Layout.fillWidth: true
                    columns: width >= root.wideBreakpoint ? 2 : 1
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

    ContentSection {
        icon: "text_format"
        title: Translation.tr("Typography")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Interface fonts")
            subtitle: Translation.tr("Use semantic font roles so general UI, numbers, code, reading, and expressive text can be tuned independently.")
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
