import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../common/functions/WorkspaceNumbers.js" as WorkspaceNumbers

SettingsTabbedPage {
    id: root
    property var appearanceEditor: null
    sections: [
        { id: "layout", label: Translation.tr("Bar layout"), icon: "toolbar" },
        { id: "content", label: Translation.tr("Bar content"), icon: "dashboard_customize" },
        { id: "tray", label: Translation.tr("System tray"), icon: "shelf_auto_hide" },
        { id: "workspaces", label: Translation.tr("Workspaces"), icon: "workspaces" }
    ]

    // Page-local layout metrics only. Corner geometry always comes from
    // Appearance.radius.* so this page follows the global radius system.
    readonly property int wideBreakpoint: 620
    readonly property int sectionGap: 12
    readonly property int rowGap: 8
    readonly property int controlHeight: 42
    readonly property int compactControlHeight: 38

    readonly property string workspaceNumberStyle: WorkspaceNumbers.style(Config.options.bar.workspaces.numberMap)

    function currentBarPosition(): int {
        return (root.appearanceEditor?.draftBarBottom ? 1 : 0)
            | (root.appearanceEditor?.draftBarVertical ? 2 : 0)
    }

    function setBarPosition(value: int): void {
        root.appearanceEditor?.applyBarPosition(["top", "bottom", "left", "right"][value])
    }

    function setWorkspaceNumberStyle(style: string): void {
        if (style !== root.workspaceNumberStyle)
            Config.options.bar.workspaces.numberMap = WorkspaceNumbers.preset(style)
    }

    // -------------------------------------------------------------------------
    // Reusable page-local primitives
    // -------------------------------------------------------------------------

    component SettingGroup: ColumnLayout {
        id: group

        required property string title
        property string subtitle: ""
        property string iconName: ""
        default property alias content: groupControls.data

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: root.sectionGap

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                visible: group.iconName.length > 0
                text: group.iconName
                iconSize: 20
                color: Appearance.colors.colPrimary
            }

            FieldLabel {
                title: group.title
                subtitle: group.subtitle
            }
        }

        ColumnLayout {
            id: groupControls

            Layout.fillWidth: true
            spacing: root.rowGap
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

        activeFocusOnTab: true
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
                activeFocusOnTab: false
                Accessible.ignored: true

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

        enabled: root.appearanceEditor?.initialized ?? false
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

    Loader {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        sourceComponent: {
            switch (root.currentSection) {
            case "content": return contentSection
            case "tray": return traySection
            case "workspaces": return workspacesSection
            default: return layoutSection
            }
        }
    }

    Component {
        id: layoutSection

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            FieldLabel {
                title: Translation.tr("Screen edge")
                subtitle: Translation.tr("Choose which screen edge holds the bar.")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 520 ? 4 : 2
                uniformCellWidths: true
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

            FieldLabel {
                Layout.topMargin: 2
                title: Translation.tr("Bar style")
                subtitle: Translation.tr("Choose how the bar meets the screen edge.")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                ChoiceChip {
                    enabled: root.appearanceEditor?.initialized ?? false
                    label: Translation.tr("Rounded edge")
                    iconName: "line_curve"
                    description: Translation.tr("Join the bar to the screen edge with rounded transitions.")
                    selected: root.appearanceEditor?.draftBarCornerStyle === 0

                    onClicked: root.appearanceEditor.draftBarCornerStyle = 0
                }

                ChoiceChip {
                    enabled: root.appearanceEditor?.initialized ?? false
                    label: Translation.tr("Floating")
                    iconName: "page_header"
                    description: Translation.tr("Add an outer gap, rounded bar geometry, and a border.")
                    selected: root.appearanceEditor?.draftBarCornerStyle === 1

                    onClicked: root.appearanceEditor.draftBarCornerStyle = 1
                }

                ChoiceChip {
                    enabled: root.appearanceEditor?.initialized ?? false
                    label: Translation.tr("Straight edge")
                    iconName: "toolbar"
                    description: Translation.tr("Use a rectangular bar flush with the screen edge.")
                    selected: root.appearanceEditor?.draftBarCornerStyle === 2

                    onClicked: root.appearanceEditor.draftBarCornerStyle = 2
                }
            }

            FieldLabel {
                Layout.topMargin: 2
                title: Translation.tr("Widget groups")
                subtitle: Translation.tr("Add a background behind each group of widgets.")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                ChoiceChip {
                    enabled: root.appearanceEditor?.initialized ?? false
                    label: Translation.tr("Pills")
                    iconName: "location_chip"
                    selected: !root.appearanceEditor?.draftBarBorderless

                    onClicked: root.appearanceEditor.draftBarBorderless = false
                }

                ChoiceChip {
                    enabled: root.appearanceEditor?.initialized ?? false
                    label: Translation.tr("Ungrouped")
                    iconName: "split_scene"
                    selected: root.appearanceEditor?.draftBarBorderless ?? false

                    onClicked: root.appearanceEditor.draftBarBorderless = true
                }
            }
            PreferenceSwitchRow {
                enabled: root.appearanceEditor?.initialized
                    && root.appearanceEditor.draftBarCornerStyle === 1
                    && root.appearanceEditor.draftBarShowBackground
                title: Translation.tr("Floating bar shadow")
                subtitle: enabled
                    ? Translation.tr("Add a shadow around the floating bar.")
                    : Translation.tr("Requires a floating bar with its background enabled.")
                iconName: "shadow"
                switchChecked: root.appearanceEditor?.draftBarFloatStyleShadow ?? false
                onUserToggled: checked => root.appearanceEditor.draftBarFloatStyleShadow = checked
            }

            PreferenceSwitchRow {
                enabled: root.appearanceEditor?.initialized ?? false
                title: Translation.tr("Bar background")
                subtitle: Translation.tr("Show the surface behind the bar contents.")
                iconName: "toolbar"
                switchChecked: root.appearanceEditor?.draftBarShowBackground ?? false
                onUserToggled: checked => root.appearanceEditor.draftBarShowBackground = checked
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            FieldLabel {
                title: Translation.tr("Interaction")
            }

            PreferenceSwitchRow {
                title: Translation.tr("Auto-hide bar")
                subtitle: Translation.tr("Reveal the bar by moving the pointer to its screen edge.")
                iconName: "shelf_auto_hide"
                switchChecked: Config.options.bar.autoHide.enable

                onUserToggled: checked => {
                    Config.options.bar.autoHide.enable = checked
                }
            }

            PreferenceSwitchRow {
                title: Translation.tr("Open previews on click")
                subtitle: Translation.tr("Use a click to open weather details and workspace previews.")
                iconName: "ads_click"
                switchChecked: Config.options.bar.tooltips.clickToShow

                onUserToggled: checked => {
                    Config.options.bar.tooltips.clickToShow = checked
                }
            }
        }
    }

    Component {
        id: contentSection

        ColumnLayout {
            spacing: 16

            SettingGroup {
                title: Translation.tr("Information & indicators")
                subtitle: Translation.tr("Choose which information appears in the bar.")
                iconName: "notifications"

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.wideBreakpoint ? 2 : 1
                    uniformCellWidths: true
                    uniformCellHeights: true
                    columnSpacing: root.rowGap
                    rowSpacing: root.rowGap

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
                        title: Translation.tr("Weather")
                        subtitle: Translation.tr("Show the current weather and temperature when the bar has room.")
                        iconName: "cloud"
                        switchChecked: Config.options.bar.weather.enable

                        onUserToggled: checked => {
                            Config.options.bar.weather.enable = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Clock")
                        subtitle: Translation.tr("Show the current time directly in the bar.")
                        iconName: "schedule"
                        switchChecked: Config.options.bar.visibility.clock

                        onUserToggled: checked => {
                            Config.options.bar.visibility.clock = checked
                        }
                    }
                    PreferenceSwitchRow {
                        title: Translation.tr("CPU and memory")
                        subtitle: Translation.tr("Show CPU and RAM usage when the bar has room.")
                        iconName: "monitoring"
                        switchChecked: Config.options.bar.visibility.resources

                        onUserToggled: checked => {
                            Config.options.bar.visibility.resources = checked
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            SettingGroup {
                title: Translation.tr("Quick actions")
                subtitle: Translation.tr("Choose which utility actions appear in the bar.")
                iconName: "widgets"

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.wideBreakpoint ? 2 : 1
                    uniformCellWidths: true
                    uniformCellHeights: true
                    columnSpacing: 8
                    rowSpacing: 8

                    PreferenceSwitchRow {
                        title: Translation.tr("Screenshot")
                        subtitle: Translation.tr("Open the capture controls in Photo mode.")
                        iconName: "content_cut"
                        switchChecked: Config.options.bar.utilButtons.showScreenSnip

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showScreenSnip = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Color picker")
                        subtitle: Translation.tr("Show the on-screen color sampling action.")
                        iconName: "colorize"
                        switchChecked: Config.options.bar.utilButtons.showColorPicker

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showColorPicker = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Keyboard")
                        subtitle: Translation.tr("Switch layouts and open the virtual keyboard from one bar control.")
                        iconName: "keyboard"
                        switchChecked: Config.options.bar.utilButtons.showKeyboardLayout
                            || Config.options.bar.utilButtons.showKeyboardToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showKeyboardToggle = checked
                            Config.options.bar.utilButtons.showKeyboardLayout = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Microphone mute")
                        subtitle: Translation.tr("Show the microphone mute toggle.")
                        iconName: "mic"
                        switchChecked: Config.options.bar.utilButtons.showMicToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showMicToggle = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Light and dark mode")
                        subtitle: Translation.tr("Show the light/dark appearance toggle.")
                        iconName: "dark_mode"
                        switchChecked: Config.options.bar.utilButtons.showDarkModeToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showDarkModeToggle = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Keep awake")
                        subtitle: Translation.tr("Show a quick toggle that prevents automatic idle / sleep.")
                        iconName: "coffee"
                        switchChecked: Config.options.bar.utilButtons.showKeepAwakeToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showKeepAwakeToggle = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Night light")
                        subtitle: Translation.tr("Show a quick display-warmth / night-light toggle.")
                        iconName: "brightness_4"
                        switchChecked: Config.options.bar.utilButtons.showNightLightToggle

                        onUserToggled: checked => {
                            Config.options.bar.utilButtons.showNightLightToggle = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Screen recording")
                        subtitle: Translation.tr("Open the capture controls in Video mode.")
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

    Component {
        id: traySection

        SettingGroup {
            title: Translation.tr("Tray options")
            subtitle: Translation.tr("Choose which tray icons are pinned and how they look.")
            iconName: "shelf_auto_hide"

            PreferenceSwitchRow {
                title: Translation.tr("Show unlisted apps in the bar")
                subtitle: Translation.tr("Move apps on the pinned list to overflow and show the other apps directly.")
                    + "  " + Translation.tr("%1 in bar · %2 in overflow")
                        .arg(TrayService.pinnedItems.length)
                        .arg(TrayService.unpinnedItems.length)
                iconName: "keep"
                switchChecked: Config.options.tray.invertPinnedItems

                onUserToggled: checked => {
                    Config.options.tray.invertPinnedItems = checked
                }
            }

            PreferenceSwitchRow {
                title: Translation.tr("Monochrome app icons")
                subtitle: Translation.tr("Show tray and workspace icons in grayscale while preserving their detail.")
                iconName: "colors"
                switchChecked: Config.monochromeAppIcons

                onUserToggled: checked => {
                    Config.options.tray.monochromeIcons = checked
                    Config.options.bar.workspaces.monochromeIcons = checked
                }
            }
        }
    }

    Component {
        id: workspacesSection

        SettingGroup {
            title: Translation.tr("Workspace appearance")
            subtitle: Translation.tr("The bar shows the group containing your active workspace. Smaller bars may show fewer workspaces per group.")
            iconName: "workspaces"

            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "view_column"
                text: Translation.tr("Workspaces per group")
                value: Config.options.bar.workspaces.shown
                from: 1
                to: 30
                stepSize: 1

                onValueChanged: {
                    Config.options.bar.workspaces.shown = value
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                uniformCellWidths: true
                uniformCellHeights: true
                columnSpacing: 8
                rowSpacing: 8

                PreferenceSwitchRow {
                    title: Translation.tr("Show workspace numbers")
                    subtitle: root.workspaceNumberStyle === "decimal"
                        ? Translation.tr("Show a number on workspaces without an app icon.")
                        : Translation.tr("Keep numbers visible even when a workspace has an app icon.")
                    iconName: "counter_1"
                    switchChecked: Config.options.bar.workspaces.alwaysShowNumbers

                    onUserToggled: checked => {
                        Config.options.bar.workspaces.alwaysShowNumbers = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("Show workspace app icons")
                    subtitle: Translation.tr("Show the main application icon for occupied workspaces.")
                    iconName: "award_star"
                    switchChecked: Config.options.bar.workspaces.showAppIcons

                    onUserToggled: checked => {
                        Config.options.bar.workspaces.showAppIcons = checked
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                FieldLabel {
                    title: Translation.tr("Workspace number style")
                    subtitle: Translation.tr("Format workspace numbers in the bar.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("Decimal")
                        iconName: "timer_10"
                        description: "1, 2, 3"
                        selected: root.workspaceNumberStyle === "decimal"

                        onClicked: root.setWorkspaceNumberStyle("decimal")
                    }

                    ChoiceChip {
                        label: Translation.tr("Chinese numerals")
                        iconName: "square_dot"
                        description: "一, 二, 三"
                        selected: root.workspaceNumberStyle === "han"

                        onClicked: root.setWorkspaceNumberStyle("han")
                    }

                    ChoiceChip {
                        label: Translation.tr("Roman numerals")
                        iconName: "account_balance"
                        description: "I, II, III"
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
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
