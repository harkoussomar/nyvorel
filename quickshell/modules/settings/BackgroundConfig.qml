import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Page-local spacing/sizing only. All corner geometry uses the project's
    // semantic Appearance.radius.* system.
    readonly property int wideBreakpoint: 700
    readonly property int cardPadding: 14
    readonly property int sectionGap: 12
    readonly property int rowGap: 8
    readonly property int controlHeight: 42
    readonly property int compactControlHeight: 38

    property string clockEditorStyle:
        Config.options.background.widgets.clock.showOnlyWhenLocked
            ? Config.options.background.widgets.clock.styleLocked
            : Config.options.background.widgets.clock.style

    property bool digitalTypographyExpanded: false
    property bool cookieHandsExpanded: false
    property bool cookieAdvancedExpanded: false

    readonly property bool hourMarksAvailable:
        Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots"
        || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"

    readonly property bool middleDigitsAvailable:
        Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers"

    function setDialStyle(value: string): void {
        if (Config.options.background.widgets.clock.cookie.dialNumberStyle === value)
            return

        Config.options.background.widgets.clock.cookie.dialNumberStyle = value

        // Preserve the original page semantics: these dependent options are
        // forcibly disabled when the selected dial cannot support them.
        if (value !== "dots" && value !== "full")
            Config.options.background.widgets.clock.cookie.hourMarks = false

        if (value === "numbers")
            Config.options.background.widgets.clock.cookie.timeIndicators = false
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

    component PlacementSelector: ColumnLayout {
        id: placement

        required property string currentValue

        signal selected(string value)

        Layout.fillWidth: true
        spacing: 7

        FieldLabel {
            title: Translation.tr("Placement")
            subtitle: Translation.tr("Choose whether the widget is positioned manually or placed using wallpaper-region analysis.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            ChoiceChip {
                label: Translation.tr("Manual")
                iconName: "drag_pan"
                description: Translation.tr("Drag the widget to position it yourself.")
                selected: placement.currentValue === "free"
                onClicked: placement.selected("free")
            }

            ChoiceChip {
                label: Translation.tr("Quiet area")
                iconName: "category"
                description: Translation.tr("Automatically place the widget in the least visually busy wallpaper region.")
                selected: placement.currentValue === "leastBusy"
                onClicked: placement.selected("leastBusy")
            }

            ChoiceChip {
                label: Translation.tr("Detailed area")
                iconName: "shapes"
                description: Translation.tr("Automatically place the widget in the busiest wallpaper region.")
                selected: placement.currentValue === "mostBusy"
                onClicked: placement.selected("mostBusy")
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

    // Lightweight, non-runtime preview. It mirrors the important digital
    // typography/layout options without instantiating the desktop widget.
    component DigitalClockPreview: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 150

        radius: Appearance.radius.card
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Config.options.background.widgets.clock.digital.vertical ? -4 : 3

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Config.options.background.widgets.clock.digital.vertical
                    ? DateTime.time.split(":")[0].padStart(2, "0")
                    : DateTime.time
                color: Appearance.colors.colOnLayer1
                font.family: Config.options.background.widgets.clock.digital.font.family
                font.weight: Config.options.background.widgets.clock.digital.font.weight
                font.pixelSize: Math.max(
                    22,
                    Math.min(
                        46,
                        Config.options.background.widgets.clock.digital.font.size * 0.45
                    )
                )
                font.styleName: ""
                font.variableAxes: ({
                    "wdth": Config.options.background.widgets.clock.digital.font.width,
                    "ROND": Config.options.background.widgets.clock.digital.font.roundness
                })
            }

            StyledText {
                visible: Config.options.background.widgets.clock.digital.vertical
                Layout.alignment: Qt.AlignHCenter
                text: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
                color: Appearance.colors.colOnLayer1
                font.family: Config.options.background.widgets.clock.digital.font.family
                font.weight: Config.options.background.widgets.clock.digital.font.weight
                font.pixelSize: Math.max(
                    22,
                    Math.min(
                        46,
                        Config.options.background.widgets.clock.digital.font.size * 0.45
                    )
                )
                font.styleName: ""
                font.variableAxes: ({
                    "wdth": Config.options.background.widgets.clock.digital.font.width,
                    "ROND": Config.options.background.widgets.clock.digital.font.roundness
                })
            }

            StyledText {
                visible: Config.options.background.widgets.clock.digital.showDate
                Layout.alignment: Qt.AlignHCenter
                text: DateTime.longDate
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledText {
                visible:
                    Config.options.background.widgets.clock.quote.enable
                    && Config.options.background.widgets.clock.quote.text.length > 0
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 380
                text: Config.options.background.widgets.clock.quote.text
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }
    }

    // A deliberately lightweight Cookie preview. It shows dial/hands/date
    // choices without loading the production CookieClock or its GPU effects.
    component CookieClockPreview: Rectangle {
        id: preview

        Layout.fillWidth: true
        implicitHeight: 190

        radius: Appearance.radius.card
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        Item {
            id: dial

            anchors.centerIn: parent
            width: 136
            height: 136

            Rectangle {
                anchors.fill: parent
                radius: Appearance.radius.full
                color: Appearance.colors.colPrimaryContainer
                border.width: Config.options.background.widgets.clock.cookie.dialNumberStyle === "full" ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }

            Repeater {
                model:
                    Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots"
                    || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"
                        ? 12
                        : 0

                delegate: Rectangle {
                    required property int index

                    width: 5
                    height: 5
                    radius: Appearance.radius.full
                    color: Appearance.colors.colOnPrimaryContainer

                    x: dial.width / 2
                        + Math.cos((index / 12) * Math.PI * 2 - Math.PI / 2) * 52
                        - width / 2

                    y: dial.height / 2
                        + Math.sin((index / 12) * Math.PI * 2 - Math.PI / 2) * 52
                        - height / 2
                }
            }

            StyledText {
                visible: Config.options.background.widgets.clock.cookie.dialNumberStyle === "numbers"
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 8
                text: "12"
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }

            StyledText {
                visible: Config.options.background.widgets.clock.cookie.dialNumberStyle === "numbers"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 9
                text: "3"
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }

            StyledText {
                visible: Config.options.background.widgets.clock.cookie.dialNumberStyle === "numbers"
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 7
                text: "6"
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }

            StyledText {
                visible: Config.options.background.widgets.clock.cookie.dialNumberStyle === "numbers"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 9
                text: "9"
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }

            StyledText {
                visible: Config.options.background.widgets.clock.cookie.timeIndicators
                anchors.centerIn: parent
                text: DateTime.time
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
            }

            Rectangle {
                visible: Config.options.background.widgets.clock.cookie.hourHandStyle !== "hide"
                width: 5
                height: 34
                radius: Appearance.radius.full
                color: Appearance.colors.colPrimary
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                transformOrigin: Item.Bottom
                rotation: 35
            }

            Rectangle {
                visible: Config.options.background.widgets.clock.cookie.minuteHandStyle !== "hide"
                width:
                    Config.options.background.widgets.clock.cookie.minuteHandStyle === "bold"
                        ? 6
                        : Config.options.background.widgets.clock.cookie.minuteHandStyle === "thin"
                            ? 2
                            : 4
                height: 48
                radius: Appearance.radius.full
                color: Appearance.colors.colTertiary
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                transformOrigin: Item.Bottom
                rotation: 120
            }

            Rectangle {
                visible: Config.options.background.widgets.clock.cookie.secondHandStyle !== "hide"
                width: 2
                height: 54
                radius: Appearance.radius.full
                color: Appearance.colors.colPrimary
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                transformOrigin: Item.Bottom
                rotation: 210
            }

            Rectangle {
                visible: Config.options.background.widgets.clock.cookie.dateStyle !== "hide"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14

                implicitWidth: dateLabel.implicitWidth + 12
                implicitHeight: 24

                radius: Config.options.background.widgets.clock.cookie.dateStyle === "rect"
                    ? Appearance.radius.control
                    : Appearance.radius.full

                color: Config.options.background.widgets.clock.cookie.dateStyle === "bubble"
                    ? Appearance.colors.colSecondaryContainer
                    : "transparent"

                border.width: Config.options.background.widgets.clock.cookie.dateStyle === "border" ? 1 : 0
                border.color: Appearance.colors.colOnPrimaryContainer

                StyledText {
                    id: dateLabel
                    anchors.centerIn: parent
                    text: Qt.locale().toString(DateTime.clock.date, "ddd dd")
                    color: Config.options.background.widgets.clock.cookie.dateStyle === "bubble"
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10

            implicitWidth: sidesLabel.implicitWidth + 16
            implicitHeight: 26

            radius: Appearance.radius.control
            color: Appearance.colors.colLayer2

            StyledText {
                id: sidesLabel
                anchors.centerIn: parent
                text: Translation.tr("%1 sides").arg(
                    Config.options.background.widgets.clock.cookie.sides
                )
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }
    }

    // =========================================================================
    // BACKGROUND MOTION
    // =========================================================================

    ContentSection {
        icon: "sync_alt"
        title: Translation.tr("Background motion")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Parallax")
            subtitle: Translation.tr("Control how the wallpaper moves in response to workspace and sidebar changes.")
            iconName: "motion_photos_on"

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                PreferenceSwitchRow {
                    title: Translation.tr("Force vertical direction")
                    subtitle: Translation.tr("Use vertical workspace parallax rather than the normal horizontal direction.")
                    iconName: "swap_vert"
                    switchChecked: Config.options.background.parallax.vertical

                    onUserToggled: checked => {
                        Config.options.background.parallax.vertical = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("React to workspace changes")
                    subtitle: Translation.tr("Move the wallpaper as the active workspace changes.")
                    iconName: "workspaces"
                    switchChecked: Config.options.background.parallax.enableWorkspace

                    onUserToggled: checked => {
                        Config.options.background.parallax.enableWorkspace = checked
                    }
                }

                PreferenceSwitchRow {
                    title: Translation.tr("React to sidebars")
                    subtitle: Translation.tr("Offset the wallpaper when shell sidebars are shown.")
                    iconName: "side_navigation"
                    switchChecked: Config.options.background.parallax.enableSidebar

                    onUserToggled: checked => {
                        Config.options.background.parallax.enableSidebar = checked
                    }
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "loupe"
                    text: Translation.tr("Parallax zoom (%)")
                    value: Config.options.background.parallax.workspaceZoom * 100
                    from: 100
                    to: 150
                    stepSize: 1

                    onValueChanged: {
                        Config.options.background.parallax.workspaceZoom = value / 100
                    }
                }
            }
        }
    }

    // =========================================================================
    // DESKTOP CLOCK
    // =========================================================================

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Desktop clock")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Clock widget")
            subtitle: Translation.tr("Choose when the desktop clock appears, where it is placed, and which style is used.")
            iconName: "clock_loader_40"

            PreferenceSwitchRow {
                title: Translation.tr("Show desktop clock")
                subtitle: Config.options.background.widgets.clock.enable
                    ? Translation.tr("The background clock widget is enabled.")
                    : Translation.tr("Clock settings remain configurable while the widget is hidden.")
                iconName: "schedule"
                switchChecked: Config.options.background.widgets.clock.enable

                onUserToggled: checked => {
                    Config.options.background.widgets.clock.enable = checked
                }
            }

            PlacementSelector {
                currentValue: Config.options.background.widgets.clock.placementStrategy

                onSelected: value => {
                    Config.options.background.widgets.clock.placementStrategy = value
                }
            }

            PreferenceSwitchRow {
                title: Translation.tr("Only show on lock screen")
                subtitle: Translation.tr("Hide the clock on the desktop and show it only while the screen is locked.")
                iconName: "lock_clock"
                switchChecked: Config.options.background.widgets.clock.showOnlyWhenLocked

                onUserToggled: checked => {
                    Config.options.background.widgets.clock.showOnlyWhenLocked = checked

                    if (checked)
                        root.clockEditorStyle =
                            Config.options.background.widgets.clock.styleLocked
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= root.wideBreakpoint ? 2 : 1
                columnSpacing: 12
                rowSpacing: 10

                ColumnLayout {
                    visible: !Config.options.background.widgets.clock.showOnlyWhenLocked
                    Layout.fillWidth: true
                    spacing: 6

                    FieldLabel {
                        title: Translation.tr("Desktop style")
                        subtitle: Translation.tr("Style used while the session is unlocked.")
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        ChoiceChip {
                            label: Translation.tr("Digital")
                            iconName: "timer_10"
                            selected:
                                Config.options.background.widgets.clock.style === "digital"

                            onClicked: {
                                Config.options.background.widgets.clock.style = "digital"
                                root.clockEditorStyle = "digital"
                            }
                        }

                        ChoiceChip {
                            label: Translation.tr("Cookie")
                            iconName: "cookie"
                            selected:
                                Config.options.background.widgets.clock.style === "cookie"

                            onClicked: {
                                Config.options.background.widgets.clock.style = "cookie"
                                root.clockEditorStyle = "cookie"
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    FieldLabel {
                        title: Translation.tr("Lock-screen style")
                        subtitle: Translation.tr("Style used when the screen is locked.")
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        ChoiceChip {
                            label: Translation.tr("Digital")
                            iconName: "timer_10"
                            selected:
                                Config.options.background.widgets.clock.styleLocked === "digital"

                            onClicked: {
                                Config.options.background.widgets.clock.styleLocked = "digital"
                                root.clockEditorStyle = "digital"
                            }
                        }

                        ChoiceChip {
                            label: Translation.tr("Cookie")
                            iconName: "cookie"
                            selected:
                                Config.options.background.widgets.clock.styleLocked === "cookie"

                            onClicked: {
                                Config.options.background.widgets.clock.styleLocked = "cookie"
                                root.clockEditorStyle = "cookie"
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            title: Translation.tr("Style editor")
            subtitle: Translation.tr("Edit Digital and Cookie styles without exposing every option at once.")
            iconName: "palette"

            Flow {
                Layout.fillWidth: true
                spacing: 8

                ChoiceChip {
                    label: Translation.tr("Digital")
                    iconName: "timer_10"
                    selected: root.clockEditorStyle === "digital"
                    onClicked: root.clockEditorStyle = "digital"
                }

                ChoiceChip {
                    label: Translation.tr("Cookie")
                    iconName: "cookie"
                    selected: root.clockEditorStyle === "cookie"
                    onClicked: root.clockEditorStyle = "cookie"
                }
            }

            // -----------------------------------------------------------------
            // DIGITAL EDITOR
            // -----------------------------------------------------------------

            ColumnLayout {
                visible: root.clockEditorStyle === "digital"
                Layout.fillWidth: true
                spacing: 10

                DigitalClockPreview {}

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.wideBreakpoint ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    PreferenceSwitchRow {
                        title: Translation.tr("Vertical time")
                        subtitle: Translation.tr("Stack hours and minutes vertically.")
                        iconName: "vertical_distribute"
                        switchChecked:
                            Config.options.background.widgets.clock.digital.vertical

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.digital.vertical = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Animate time changes")
                        subtitle: Translation.tr("Animate the clock text when the displayed time changes.")
                        iconName: "animation"
                        switchChecked:
                            Config.options.background.widgets.clock.digital.animateChange

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.digital.animateChange = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Show date")
                        subtitle: Translation.tr("Display the long date under the digital clock.")
                        iconName: "date_range"
                        switchChecked:
                            Config.options.background.widgets.clock.digital.showDate

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.digital.showDate = checked
                        }
                    }

                    PreferenceSwitchRow {
                        enabled: !Config.options.background.widgets.clock.digital.vertical
                        title: Translation.tr("Adaptive alignment")
                        subtitle: Config.options.background.widgets.clock.digital.vertical
                            ? Translation.tr("Vertical clocks are always centered.")
                            : Translation.tr("Align date and quote left, center, or right based on the widget position.")
                        iconName: "format_align_center"
                        switchChecked:
                            Config.options.background.widgets.clock.digital.adaptiveAlignment

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.digital.adaptiveAlignment = checked
                        }
                    }
                }

                ExpandButton {
                    collapsedText: Translation.tr("Typography")
                    expandedText: Translation.tr("Hide typography")
                    expanded: root.digitalTypographyExpanded

                    onClicked: {
                        root.digitalTypographyExpanded =
                            !root.digitalTypographyExpanded
                    }
                }

                ColumnLayout {
                    visible: root.digitalTypographyExpanded
                    Layout.fillWidth: true
                    spacing: 10

                    FieldLabel {
                        title: Translation.tr("Font")
                        subtitle: Translation.tr("Width and roundness require a compatible variable font, such as Google Sans Flex.")
                    }

                    MaterialTextArea {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Font family")
                        text: Config.options.background.widgets.clock.digital.font.family
                        wrapMode: TextEdit.Wrap

                        onTextChanged: {
                            Config.options.background.widgets.clock.digital.font.family = text
                        }
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Font weight")
                        buttonIcon: "format_bold"
                        value: Config.options.background.widgets.clock.digital.font.weight
                        usePercentTooltip: false
                        from: 1
                        to: 1000
                        stopIndicatorValues: [350]

                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.weight = value
                        }
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Font size")
                        buttonIcon: "format_size"
                        value: Config.options.background.widgets.clock.digital.font.size
                        usePercentTooltip: false
                        from: 50
                        to: 700
                        stopIndicatorValues: [90]

                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.size = value
                        }
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Font width")
                        buttonIcon: "fit_width"
                        value: Config.options.background.widgets.clock.digital.font.width
                        usePercentTooltip: false
                        from: 25
                        to: 125
                        stopIndicatorValues: [100]

                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.width = value
                        }
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Font roundness")
                        buttonIcon: "line_curve"
                        value: Config.options.background.widgets.clock.digital.font.roundness
                        usePercentTooltip: false
                        from: 0
                        to: 100

                        onValueChanged: {
                            Config.options.background.widgets.clock.digital.font.roundness = value
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // COOKIE EDITOR
            // -----------------------------------------------------------------

            ColumnLayout {
                visible: root.clockEditorStyle === "cookie"
                Layout.fillWidth: true
                spacing: 10

                CookieClockPreview {}

                FieldLabel {
                    title: Translation.tr("Shape")
                    subtitle: Translation.tr("Control the Cookie outline and its main dial treatment.")
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "add_triangle"
                    text: Translation.tr("Sides")
                    value: Config.options.background.widgets.clock.cookie.sides
                    from: 0
                    to: 40
                    stepSize: 1

                    onValueChanged: {
                        Config.options.background.widgets.clock.cookie.sides = value
                    }
                }

                FieldLabel {
                    Layout.topMargin: 2
                    title: Translation.tr("Dial")
                    subtitle: Translation.tr("Choose the markers drawn around or inside the Cookie clock.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("None")
                        iconName: "block"
                        selected:
                            Config.options.background.widgets.clock.cookie.dialNumberStyle === "none"

                        onClicked: root.setDialStyle("none")
                    }

                    ChoiceChip {
                        label: Translation.tr("Dots")
                        iconName: "graph_6"
                        selected:
                            Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots"

                        onClicked: root.setDialStyle("dots")
                    }

                    ChoiceChip {
                        label: Translation.tr("Full")
                        iconName: "history_toggle_off"
                        selected:
                            Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"

                        onClicked: root.setDialStyle("full")
                    }

                    ChoiceChip {
                        label: Translation.tr("Numbers")
                        iconName: "counter_1"
                        selected:
                            Config.options.background.widgets.clock.cookie.dialNumberStyle === "numbers"

                        onClicked: root.setDialStyle("numbers")
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= root.wideBreakpoint ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 8

                    PreferenceSwitchRow {
                        enabled: root.hourMarksAvailable
                        title: Translation.tr("Hour marks")
                        subtitle: root.hourMarksAvailable
                            ? Translation.tr("Show hour marks around Dots or Full dials.")
                            : Translation.tr("Available only with Dots or Full dial styles.")
                        iconName: "brightness_7"
                        switchChecked:
                            Config.options.background.widgets.clock.cookie.hourMarks

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.cookie.hourMarks = checked
                        }
                    }

                    PreferenceSwitchRow {
                        enabled: root.middleDigitsAvailable
                        title: Translation.tr("Digits in the middle")
                        subtitle: root.middleDigitsAvailable
                            ? Translation.tr("Show the current time inside the Cookie clock.")
                            : Translation.tr("Unavailable with the Numbers dial style.")
                        iconName: "timer_10"
                        switchChecked:
                            Config.options.background.widgets.clock.cookie.timeIndicators

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.cookie.timeIndicators = checked
                        }
                    }
                }

                FieldLabel {
                    Layout.topMargin: 2
                    title: Translation.tr("Date style")
                    subtitle: Translation.tr("Choose how the date is integrated into the Cookie clock.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    ChoiceChip {
                        label: Translation.tr("Off")
                        iconName: "block"
                        selected:
                            Config.options.background.widgets.clock.cookie.dateStyle === "hide"

                        onClicked: Config.options.background.widgets.clock.cookie.dateStyle = "hide"
                    }

                    ChoiceChip {
                        label: Translation.tr("Bubble")
                        iconName: "bubble_chart"
                        selected:
                            Config.options.background.widgets.clock.cookie.dateStyle === "bubble"

                        onClicked: Config.options.background.widgets.clock.cookie.dateStyle = "bubble"
                    }

                    ChoiceChip {
                        label: Translation.tr("Border")
                        iconName: "rotate_right"
                        selected:
                            Config.options.background.widgets.clock.cookie.dateStyle === "border"

                        onClicked: Config.options.background.widgets.clock.cookie.dateStyle = "border"
                    }

                    ChoiceChip {
                        label: Translation.tr("Rectangle")
                        iconName: "rectangle"
                        selected:
                            Config.options.background.widgets.clock.cookie.dateStyle === "rect"

                        onClicked: Config.options.background.widgets.clock.cookie.dateStyle = "rect"
                    }
                }

                ExpandButton {
                    collapsedText: Translation.tr("Clock hands")
                    expandedText: Translation.tr("Hide clock hands")
                    expanded: root.cookieHandsExpanded

                    onClicked: {
                        root.cookieHandsExpanded = !root.cookieHandsExpanded
                    }
                }

                ColumnLayout {
                    visible: root.cookieHandsExpanded
                    Layout.fillWidth: true
                    spacing: 8

                    FieldLabel {
                        title: Translation.tr("Hour hand")
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        ChoiceChip {
                            label: Translation.tr("Off")
                            iconName: "block"
                            selected:
                                Config.options.background.widgets.clock.cookie.hourHandStyle === "hide"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.hourHandStyle = "hide"
                        }

                        ChoiceChip {
                            label: Translation.tr("Classic")
                            iconName: "radio"
                            selected:
                                Config.options.background.widgets.clock.cookie.hourHandStyle === "classic"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.hourHandStyle = "classic"
                        }

                        ChoiceChip {
                            label: Translation.tr("Hollow")
                            iconName: "circle"
                            selected:
                                Config.options.background.widgets.clock.cookie.hourHandStyle === "hollow"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.hourHandStyle = "hollow"
                        }

                        ChoiceChip {
                            label: Translation.tr("Fill")
                            iconName: "eraser_size_5"
                            selected:
                                Config.options.background.widgets.clock.cookie.hourHandStyle === "fill"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.hourHandStyle = "fill"
                        }
                    }

                    FieldLabel {
                        title: Translation.tr("Minute hand")
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        ChoiceChip {
                            label: Translation.tr("Off")
                            iconName: "block"
                            selected:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle === "hide"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle = "hide"
                        }

                        ChoiceChip {
                            label: Translation.tr("Classic")
                            iconName: "radio"
                            selected:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle === "classic"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle = "classic"
                        }

                        ChoiceChip {
                            label: Translation.tr("Thin")
                            iconName: "line_end"
                            selected:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle === "thin"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle = "thin"
                        }

                        ChoiceChip {
                            label: Translation.tr("Medium")
                            iconName: "eraser_size_2"
                            selected:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle === "medium"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle = "medium"
                        }

                        ChoiceChip {
                            label: Translation.tr("Bold")
                            iconName: "eraser_size_4"
                            selected:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle === "bold"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.minuteHandStyle = "bold"
                        }
                    }

                    FieldLabel {
                        title: Translation.tr("Second hand")
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        ChoiceChip {
                            label: Translation.tr("Off")
                            iconName: "block"
                            selected:
                                Config.options.background.widgets.clock.cookie.secondHandStyle === "hide"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.secondHandStyle = "hide"
                        }

                        ChoiceChip {
                            label: Translation.tr("Classic")
                            iconName: "radio"
                            selected:
                                Config.options.background.widgets.clock.cookie.secondHandStyle === "classic"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.secondHandStyle = "classic"
                        }

                        ChoiceChip {
                            label: Translation.tr("Line")
                            iconName: "line_end"
                            selected:
                                Config.options.background.widgets.clock.cookie.secondHandStyle === "line"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.secondHandStyle = "line"
                        }

                        ChoiceChip {
                            label: Translation.tr("Dot")
                            iconName: "adjust"
                            selected:
                                Config.options.background.widgets.clock.cookie.secondHandStyle === "dot"
                            onClicked:
                                Config.options.background.widgets.clock.cookie.secondHandStyle = "dot"
                        }
                    }
                }

                ExpandButton {
                    collapsedText: Translation.tr("Advanced Cookie settings")
                    expandedText: Translation.tr("Hide advanced Cookie settings")
                    expanded: root.cookieAdvancedExpanded

                    onClicked: {
                        root.cookieAdvancedExpanded = !root.cookieAdvancedExpanded
                    }
                }

                ColumnLayout {
                    visible: root.cookieAdvancedExpanded
                    Layout.fillWidth: true
                    spacing: 8

                    PreferenceSwitchRow {
                        title: Translation.tr("Automatic styling with Gemini")
                        subtitle: Translation.tr("Uses a downscaled wallpaper image with Gemini to categorize the wallpaper and apply a Cookie preset. Requires your Gemini API key; avoid wallpapers containing sensitive information.")
                        iconName: "wand_stars"
                        switchChecked:
                            Config.options.background.widgets.clock.cookie.aiStyling

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.cookie.aiStyling = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Smoother legacy shape")
                        subtitle: Translation.tr("Use the older sine-wave Cookie shape. It is softer and more consistent across side counts, but morphs less dramatically.")
                        iconName: "airwave"
                        switchChecked:
                            Config.options.background.widgets.clock.cookie.useSineCookie

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.cookie.useSineCookie = checked
                        }
                    }

                    PreferenceSwitchRow {
                        title: Translation.tr("Continuous rotation")
                        subtitle: Translation.tr("Keep the Cookie clock rotating continuously.")
                        iconName: "autoplay"
                        switchChecked:
                            Config.options.background.widgets.clock.cookie.constantlyRotate

                        onUserToggled: checked => {
                            Config.options.background.widgets.clock.cookie.constantlyRotate = checked
                        }
                    }

                    InfoBox {
                        visible:
                            Config.options.background.widgets.clock.cookie.constantlyRotate
                        warning: true
                        iconName: "speed"
                        text: Translation.tr("High GPU usage: continuous Cookie rotation is intentionally expensive and can be impractical on integrated graphics.")
                    }
                }
            }
        }

        SettingsCard {
            title: Translation.tr("Quote")
            subtitle: Translation.tr("Optionally show a short quote with either clock style.")
            iconName: "format_quote"

            PreferenceSwitchRow {
                title: Translation.tr("Show quote")
                subtitle: Config.options.background.widgets.clock.quote.enable
                    ? Translation.tr("The quote is shown when the text below is not empty.")
                    : Translation.tr("Turn this on to add text beneath the clock.")
                iconName: "format_quote"
                switchChecked: Config.options.background.widgets.clock.quote.enable

                onUserToggled: checked => {
                    Config.options.background.widgets.clock.quote.enable = checked
                }
            }

            MaterialTextArea {
                visible: Config.options.background.widgets.clock.quote.enable
                Layout.fillWidth: true
                placeholderText: Translation.tr("Quote text")
                text: Config.options.background.widgets.clock.quote.text
                wrapMode: TextEdit.Wrap

                onTextChanged: {
                    Config.options.background.widgets.clock.quote.text = text
                }
            }
        }
    }

    // =========================================================================
    // DESKTOP WEATHER
    // =========================================================================

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Desktop weather")
        Layout.fillWidth: true

        SettingsCard {
            title: Translation.tr("Weather widget")
            subtitle: Translation.tr("Show weather on the desktop and choose how the widget is positioned.")
            iconName: "partly_cloudy_day"

            PreferenceSwitchRow {
                title: Translation.tr("Show desktop weather")
                subtitle: Translation.tr("Display the existing desktop weather widget on the wallpaper canvas.")
                iconName: "cloud"
                switchChecked: Config.options.background.widgets.weather.enable

                onUserToggled: checked => {
                    Config.options.background.widgets.weather.enable = checked
                }
            }

            PlacementSelector {
                currentValue:
                    Config.options.background.widgets.weather.placementStrategy

                onSelected: value => {
                    Config.options.background.widgets.weather.placementStrategy = value
                }
            }
        }
    }
}
