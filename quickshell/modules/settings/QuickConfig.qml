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
    maxContentWidth: 960
    horizontalPadding: width < 760 ? 16 : 24

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
    signal appearanceStudioOpened()
    property var activeAppearance: ({})
    property string requestedMode: ""
    property string requestedScheme: ""
    property string appearanceError: ""
    readonly property bool appearanceBusy:
        statusProc.running || applyProc.running || studioOpenProc.running
    readonly property string appearanceBackend:
        FileUtils.trimFileProtocol(
            Quickshell.shellPath("scripts/system/nyvorel-appearance-studio")
        )

    readonly property bool showExtendedColorStyles:
        colorStylesExpanded || isExtendedPalette(Config.options.appearance.palette.type)

    function setThemeMode(dark: bool): void {
        requestAppearance(dark ? "dark" : "light", "")
    }

    function setPaletteType(value: string): void {
        if (Config.options.appearance.palette.type === value)
            return
        requestAppearance("", value)
    }

    function requestAppearance(mode: string, scheme: string): void {
        if (root.appearanceBusy)
            return
        root.requestedMode = mode
        root.requestedScheme = scheme
        root.appearanceError = ""
        statusProc.running = true
    }

    function applyRequestedAppearance(): void {
        const active = root.activeAppearance
        const source = active.source ?? "wallpaper"
        let seed = active.seed ?? ""
        const palette = active.customPalette
        if (palette && palette.primary && palette.secondary
                && palette.tertiary && palette.neutral) {
            seed = "ii4:" + [palette.primary, palette.secondary,
                palette.tertiary, palette.neutral].join("|")
        }

        applyProc.command = [root.appearanceBackend, "apply",
            "--source", source,
            "--mode", root.requestedMode || active.mode || "dark",
            "--scheme", root.requestedScheme || active.scheme || "auto",
            "--preset", active.preset ?? "",
            "--seed", seed,
            "--wallpaper", active.wallpaper ?? ""]
        applyProc.running = true
    }

    function isExtendedPalette(value: string): bool {
        return value === "scheme-content"
            || value === "scheme-fidelity"
            || value === "scheme-fruit-salad"
            || value === "scheme-tonal-spot"
    }

    Process {
        id: statusProc
        command: [root.appearanceBackend, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    if (!result.ok || !result.active) {
                        root.appearanceError = result.error ?? "Could not read the current appearance."
                        return
                    }
                    root.activeAppearance = result.active
                    root.applyRequestedAppearance()
                } catch (error) {
                    root.appearanceError = "Could not read the current appearance."
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.appearanceError)
                root.appearanceError = "Appearance Studio is unavailable."
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    if (!result.ok)
                        root.appearanceError = result.error ?? "Appearance could not be applied."
                } catch (error) {
                    root.appearanceError = "Appearance could not be applied."
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.appearanceError)
                root.appearanceError = "Appearance could not be applied."
            if (exitCode === 0 && !root.appearanceError)
                Config.reload()
        }
    }

    Process {
        id: studioOpenProc
        command: ["qs", "ipc", "-c", "nyvorel", "--any-display",
            "call", "appearanceStudio", "open"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.appearanceStudioOpened()
            else
                root.appearanceError = "Could not open Appearance Studio. Check that the Nyvorel shell is running."
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

        enabled: !root.appearanceBusy

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
                Layout.preferredWidth: wallpaperGrid.columns === 2
                    ? wallpaperGrid.width * 0.42
                    : wallpaperGrid.width
                implicitHeight: root.wallpaperPreviewHeight

                radius:
                     Appearance.radius.card
                color:
                     Appearance.colors.colLayer2
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
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: wallpaperGrid.columns === 2
                    ? wallpaperGrid.width * 0.56
                    : wallpaperGrid.width
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
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    QuickChoiceButton {
                        Layout.fillWidth: true
                        enabled: !root.appearanceBusy
                        label: Translation.tr("Light")
                        iconName: "light_mode"
                        selected: !Appearance.m3colors.darkmode
                        description: Translation.tr("Use the light color variant.")
                        onClicked: root.setThemeMode(false)
                    }

                    QuickChoiceButton {
                        Layout.fillWidth: true
                        enabled: !root.appearanceBusy
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
                    materialIcon: "palette"
                    mainText: Translation.tr("Open Appearance Studio")

                    onClicked: {
                        root.appearanceError = ""
                        studioOpenProc.running = true
                    }

                    StyledToolTip {
                        text: Translation.tr("Choose a wallpaper or build a custom theme.")
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.appearanceBusy || root.appearanceError.length > 0
            text: root.appearanceBusy
                ? Translation.tr("Applying appearance…")
                : root.appearanceError
            color: root.appearanceError.length > 0
                ? Appearance.m3colors.m3error
                : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
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
                    font.pixelSize: Appearance.font.pixelSize.smaller
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
                 Appearance.radius.card
            color:
                 Appearance.colors.colLayer2
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
                        font.pixelSize: Appearance.font.pixelSize.smaller
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

}
