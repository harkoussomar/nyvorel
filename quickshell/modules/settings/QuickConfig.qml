import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    forceWidth: true

    // Local layout metrics. Corner geometry intentionally comes only from the
    // global semantic radius system: Appearance.radius.*.
    readonly property int wideBreakpoint: 760
    readonly property int sectionSpacing: 14
    readonly property int cardPadding: 14
    readonly property int controlHeight: 44
    readonly property int compactControlHeight: 38
    readonly property int wallpaperPreviewHeight: 188
    readonly property int wallpaperDecodeWidth: 720
    readonly property int wallpaperDecodeHeight: 420

    property bool colorStylesExpanded: false

    readonly property string configFilePath:
        FileUtils.trimFileProtocol(`${Directories.config}/nyvorel/config.json`)

    readonly property bool showExtendedColorStyles:
        colorStylesExpanded || isExtendedPalette(Config.options.appearance.palette.type)

    function setThemeMode(dark: bool): void {
        Quickshell.execDetached([
            "bash",
            "-c",
            `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`
        ])
    }

    function setPaletteType(value: string): void {
        if (Config.options.appearance.palette.type === value)
            return

        Config.options.appearance.palette.type = value
        Quickshell.execDetached([
            "bash",
            "-c",
            `${Directories.wallpaperSwitchScriptPath} --noswitch`
        ])
    }

    function isExtendedPalette(value: string): bool {
        return value === "scheme-content"
            || value === "scheme-fidelity"
            || value === "scheme-fruit-salad"
            || value === "scheme-tonal-spot"
    }

    function currentBarPosition(): int {
        return (Config.options.bar.bottom ? 1 : 0)
            | (Config.options.bar.vertical ? 2 : 0)
    }

    function setBarPosition(value: int): void {
        Config.options.bar.bottom = (value & 1) !== 0
        Config.options.bar.vertical = (value & 2) !== 0
    }

    Process {
        id: randomWallProc

        property string status: ""
        property string scriptPath:
            `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`

        command: [
            "bash",
            "-c",
            FileUtils.trimFileProtocol(randomWallProc.scriptPath)
        ]

        stdout: SplitParser {
            onRead: data => {
                randomWallProc.status = data.trim()
            }
        }
    }

    // Reusable compact selector for the Quick page.
    // Selected states use Primary Container rather than the full Primary fill,
    // keeping the accent meaningful instead of making every active option loud.
    component QuickChoiceButton: RippleButton {
        id: choice

        required property string label
        required property string iconName

        property string description: ""
        property bool selected: false
        property bool compact: false

        toggled: selected
        implicitHeight: compact ? root.compactControlHeight : root.controlHeight
        implicitWidth: Math.max(104, choiceContent.implicitWidth + 28)

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control

        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.description: description

        contentItem: RowLayout {
            id: choiceContent

            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 7

            MaterialSymbol {
                text: choice.iconName
                iconSize: 18
                fill: choice.selected ? 1 : 0
                color: choice.selected
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer2
            }

            StyledText {
                text: choice.label
                color: choice.selected
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: choice.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }

        StyledToolTip {
            visible: choice.description.length > 0
            text: choice.description
        }
    }

    component PaletteChip: RippleButton {
        id: chip

        required property string label
        required property string value

        property string description: ""
        property string iconName: "palette"

        readonly property bool selected:
            Config.options.appearance.palette.type === value

        toggled: selected
        implicitHeight: root.compactControlHeight
        implicitWidth: Math.max(86, chipContent.implicitWidth + 26)

        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control

        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.description: description

        onClicked: root.setPaletteType(value)

        contentItem: RowLayout {
            id: chipContent

            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
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
                    : Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: chip.selected ? Font.DemiBold : Font.Normal
            }
        }

        StyledToolTip {
            visible: chip.description.length > 0
            text: chip.description
        }
    }

    // -------------------------------------------------------------------------
    // Wallpaper & appearance
    // -------------------------------------------------------------------------

    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Wallpaper & appearance")
        Layout.fillWidth: true

        GridLayout {
            id: wallpaperGrid

            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 16
            rowSpacing: 14

            // Wallpaper is the main visual anchor of the page.
            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 280
                implicitHeight: root.wallpaperPreviewHeight

                radius:
                    Appearance.prismMode
                        ? Appearance.prism.radiusPersistent
                        : Appearance.radius.card
                color:
                    Appearance.prismMode
                        ? "transparent"
                        : Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                StyledImage {
                    id: wallpaperPreview

                    anchors.fill: parent
                    source: Config.options.background.wallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    cache: false

                    // Bound the decoded image instead of loading a full-size
                    // wallpaper into memory for a small preview.
                    sourceSize: Qt.size(
                        root.wallpaperDecodeWidth,
                        root.wallpaperDecodeHeight
                    )

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: ShaderEffectSource {
                            width: wallpaperPreview.width
                            height: wallpaperPreview.height

                            sourceItem: Rectangle {
                                width: wallpaperPreview.width
                                height: wallpaperPreview.height
                                radius: Appearance.radius.card
                            }
                        }
                    }
                }

                // Subtle edge definition remains visible even on bright images.
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.radius.card
                    color: "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    implicitWidth: currentWallpaperLabel.implicitWidth + 18
                    implicitHeight: 28

                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            text: "wallpaper"
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            id: currentWallpaperLabel
                            text: Translation.tr("Current wallpaper")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 260
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    StyledText {
                        text: Translation.tr("Theme")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Choose the interface brightness without changing the wallpaper.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    QuickChoiceButton {
                        Layout.fillWidth: true
                        label: Translation.tr("Light")
                        iconName: "light_mode"
                        selected: !Appearance.m3colors.darkmode
                        description: Translation.tr("Use the light color variant.")
                        onClicked: root.setThemeMode(false)
                    }

                    QuickChoiceButton {
                        Layout.fillWidth: true
                        label: Translation.tr("Dark")
                        iconName: "dark_mode"
                        selected: Appearance.m3colors.darkmode
                        description: Translation.tr("Use the dark color variant.")
                        onClicked: root.setThemeMode(true)
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    implicitHeight: root.controlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: "wallpaper"
                    mainText: Translation.tr("Change wallpaper")

                    onClicked: {
                        Quickshell.execDetached(
                            `${Directories.wallpaperSwitchScriptPath}`
                        )
                    }

                    StyledToolTip {
                        text: Translation.tr("Pick a wallpaper image from your system.")
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    visible: Config.options.policies.weeb === 1
                    spacing: 8

                    RippleButtonWithIcon {
                        enabled: !randomWallProc.running
                        implicitHeight: root.compactControlHeight
                        buttonRadius: Appearance.radius.control
                        materialIcon: "ifl"
                        mainText: randomWallProc.running
                            ? Translation.tr("Loading…")
                            : Translation.tr("Konachan")

                        onClicked: {
                            randomWallProc.scriptPath =
                                `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`
                            randomWallProc.running = true
                        }

                        StyledToolTip {
                            text: Translation.tr("Random SFW anime wallpaper from Konachan.")
                        }
                    }

                    RippleButtonWithIcon {
                        enabled: !randomWallProc.running
                        implicitHeight: root.compactControlHeight
                        buttonRadius: Appearance.radius.control
                        materialIcon: "shuffle"
                        mainText: randomWallProc.running
                            ? Translation.tr("Loading…")
                            : Translation.tr("osu! seasonal")

                        onClicked: {
                            randomWallProc.scriptPath =
                                `${Directories.scriptPath}/colors/random/random_osu_wall.sh`
                            randomWallProc.running = true
                        }

                        StyledToolTip {
                            text: Translation.tr("Random osu! seasonal wallpaper.")
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                StyledText {
                    text: Translation.tr("Color style")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Choose how the interface derives colors from your wallpaper.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                PaletteChip {
                    label: Translation.tr("Auto")
                    value: "auto"
                    iconName: "auto_awesome"
                    description: Translation.tr("Let the theme generator choose the most suitable strategy.")
                }

                PaletteChip {
                    label: Translation.tr("Expressive")
                    value: "scheme-expressive"
                    iconName: "colors"
                    description: Translation.tr("More vivid and characterful color relationships.")
                }

                PaletteChip {
                    label: Translation.tr("Neutral")
                    value: "scheme-neutral"
                    iconName: "contrast"
                    description: Translation.tr("Restrained colors with lower visual intensity.")
                }

                PaletteChip {
                    label: Translation.tr("Monochrome")
                    value: "scheme-monochrome"
                    iconName: "tonality"
                    description: Translation.tr("A minimal, mostly single-hue treatment.")
                }

                PaletteChip {
                    label: Translation.tr("Rainbow")
                    value: "scheme-rainbow"
                    iconName: "gradient"
                    description: Translation.tr("A broader spread of hues across the interface.")
                }

                RippleButtonWithIcon {
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: root.showExtendedColorStyles
                        ? "expand_less"
                        : "expand_more"
                    mainText: root.showExtendedColorStyles
                        ? Translation.tr("Fewer styles")
                        : Translation.tr("More styles")

                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active

                    onClicked: {
                        root.colorStylesExpanded = !root.colorStylesExpanded
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: root.showExtendedColorStyles
                spacing: 8

                PaletteChip {
                    label: Translation.tr("Content")
                    value: "scheme-content"
                    iconName: "image"
                    description: Translation.tr("Stay closer to the wallpaper's source colors.")
                }

                PaletteChip {
                    label: Translation.tr("Fidelity")
                    value: "scheme-fidelity"
                    iconName: "colorize"
                    description: Translation.tr("Preserve the source color relationships more faithfully.")
                }

                PaletteChip {
                    label: Translation.tr("Fruit Salad")
                    value: "scheme-fruit-salad"
                    iconName: "palette"
                    description: Translation.tr("A playful split-color palette.")
                }

                PaletteChip {
                    label: Translation.tr("Tonal Spot")
                    value: "scheme-tonal-spot"
                    iconName: "blur_on"
                    description: Translation.tr("Balanced Material-style tonal color groups.")
                }
            }
        }

        // Compact setting row instead of a large orphaned label/toggle pair.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: transparencyRow.implicitHeight + root.cardPadding * 2

            radius:
                Appearance.prismMode
                    ? Appearance.prism.radiusPersistent
                    : Appearance.radius.card
            color:
                Appearance.prismMode
                    ? "transparent"
                    : Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            RowLayout {
                id: transparencyRow

                anchors.fill: parent
                anchors.margins: root.cardPadding
                spacing: 12

                MaterialSymbol {
                    text: "ev_shadow"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Transparency")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Let the wallpaper subtly show through shell surfaces.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }

                StyledSwitch {
                    checked: Config.options.appearance.transparency.enable

                    // Use the explicit user-interaction signal instead of a
                    // property-change signal to avoid feedback cascades.
                    onToggled: {
                        Config.options.appearance.transparency.enable = checked
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Bar & screen
    // -------------------------------------------------------------------------

    ContentSection {
        icon: "screenshot_monitor"
        title: Translation.tr("Bar & screen")
        Layout.fillWidth: true

        GridLayout {
            Layout.fillWidth: true
            columns: width >= root.wideBreakpoint ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: barCardColumn.implicitHeight + root.cardPadding * 2

                radius:
                    Appearance.prismMode
                        ? Appearance.prism.radiusPersistent
                        : Appearance.radius.card
                color:
                    Appearance.prismMode
                        ? "transparent"
                        : Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                ColumnLayout {
                    id: barCardColumn

                    anchors.fill: parent
                    anchors.margins: root.cardPadding
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "toolbar"
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: Translation.tr("Bar")
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Choose where the main bar sits and how it is shaped.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        text: Translation.tr("Position")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Top")
                            iconName: "arrow_upward"
                            selected: root.currentBarPosition() === 0
                            onClicked: root.setBarPosition(0)
                        }

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Left")
                            iconName: "arrow_back"
                            selected: root.currentBarPosition() === 2
                            onClicked: root.setBarPosition(2)
                        }

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Bottom")
                            iconName: "arrow_downward"
                            selected: root.currentBarPosition() === 1
                            onClicked: root.setBarPosition(1)
                        }

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Right")
                            iconName: "arrow_forward"
                            selected: root.currentBarPosition() === 3
                            onClicked: root.setBarPosition(3)
                        }
                    }

                    StyledText {
                        Layout.topMargin: 2
                        text: Translation.tr("Style")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Compact")
                            iconName: "line_curve"
                            selected: Config.options.bar.cornerStyle === 0
                            description: Translation.tr("Shape the bar closely around its content.")
                            onClicked: Config.options.bar.cornerStyle = 0
                        }

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Floating")
                            iconName: "page_header"
                            selected: Config.options.bar.cornerStyle === 1
                            description: Translation.tr("Float the bar away from the screen edge.")
                            onClicked: Config.options.bar.cornerStyle = 1
                        }

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Full width")
                            iconName: "toolbar"
                            selected: Config.options.bar.cornerStyle === 2
                            description: Translation.tr("Use a straight full-width bar.")
                            onClicked: Config.options.bar.cornerStyle = 2
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: screenCardColumn.implicitHeight + root.cardPadding * 2

                radius:
                    Appearance.prismMode
                        ? Appearance.prism.radiusPersistent
                        : Appearance.radius.card
                color:
                    Appearance.prismMode
                        ? "transparent"
                        : Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                ColumnLayout {
                    id: screenCardColumn

                    anchors.fill: parent
                    anchors.margins: root.cardPadding
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "rounded_corner"
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: Translation.tr("Screen corners")
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Control when simulated rounded screen corners are visible.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        text: Translation.tr("Corner treatment")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Off")
                            iconName: "close"
                            selected: Config.options.appearance.fakeScreenRounding === 0
                            onClicked: Config.options.appearance.fakeScreenRounding = 0
                        }

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Always")
                            iconName: "check"
                            selected: Config.options.appearance.fakeScreenRounding === 1
                            onClicked: Config.options.appearance.fakeScreenRounding = 1
                        }

                        QuickChoiceButton {
                            compact: true
                            label: Translation.tr("Except fullscreen")
                            iconName: "fullscreen_exit"
                            selected: Config.options.appearance.fakeScreenRounding === 2
                            onClicked: Config.options.appearance.fakeScreenRounding = 2
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Advanced / config file
    // -------------------------------------------------------------------------

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: advancedRow.implicitHeight + root.cardPadding * 2

        radius:
            Appearance.prismMode
                ? Appearance.prism.radiusPersistent
                : Appearance.radius.card
        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.colors.colLayer1
        border.width: 1
        border.color:
            Appearance.prismMode
                ? Appearance.prism.borderSubtle
                : Appearance.colors.colLayer0Border

        RowLayout {
            id: advancedRow

            anchors.fill: parent
            anchors.margins: root.cardPadding
            spacing: 12

            MaterialSymbol {
                text: "tune"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: Translation.tr("Advanced settings")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Quick settings shows the controls you are most likely to change. Everything else remains available in config.json.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                }
            }

            Flow {
                Layout.maximumWidth: 320
                spacing: 8

                RippleButtonWithIcon {
                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: "edit"
                    mainText: Translation.tr("Open config")

                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive

                    onClicked: {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/system/nyvorel-app-launch"), "--open", root.configFilePath])
                    }
                }

                RippleButtonWithIcon {
                    id: copyPathButton

                    property bool justCopied: false

                    implicitHeight: root.compactControlHeight
                    buttonRadius: Appearance.radius.control
                    materialIcon: justCopied ? "check" : "content_copy"
                    mainText: justCopied
                        ? Translation.tr("Path copied")
                        : Translation.tr("Copy path")

                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active

                    onClicked: {
                        Quickshell.clipboardText = root.configFilePath
                        justCopied = true
                        revertTextTimer.restart()
                    }

                    Timer {
                        id: revertTextTimer
                        interval: 1500
                        onTriggered: copyPathButton.justCopied = false
                    }
                }
            }
        }
    }
}
