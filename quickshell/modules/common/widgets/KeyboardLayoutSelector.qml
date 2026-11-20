import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property bool openUpward: false
    property bool compact: false
    property bool showCompositorDefault: true
    implicitHeight: compact ? 40 : 42
    Layout.fillWidth: true

    Component.onCompleted: KeyboardLayout.load()

    function choices(query: string): var {
        const available = KeyboardLayout.filteredChoices(query).filter(choice =>
            root.showCompositorDefault || choice.value !== "auto")
        if (!root.compact || query.trim().length > 0)
            return available

        const quick = [...new Set([KeyboardLayout.currentCode, "us", "gb", "it", "fr", "de", "es"].filter(Boolean))]
        const featured = quick.map(code => available.find(choice => choice.value === code)).filter(Boolean)
        return featured.concat(available.filter(choice => !quick.includes(choice.value)))
    }

    function choose(code: string): void {
        if (code !== KeyboardLayout.currentCode)
            KeyboardLayout.select(code)
        chooser.close()
    }

    function openPicker(): void {
        if (!KeyboardLayout.catalogueReady || KeyboardLayout.busy)
            return
        KeyboardLayout.refresh()
        searchField.text = ""
        chooser.open()
        positionPicker()
    }

    function positionPicker(): void {
        const overlay = chooser.parent
        if (!overlay)
            return
        const anchor = root.mapToItem(overlay, 0, 0)
        const below = anchor.y + root.height + 6
        const above = anchor.y - chooser.height - 6
        const preferredY = root.openUpward || below + chooser.height > overlay.height - 12
            ? above : below
        chooser.x = Math.max(12, Math.min(anchor.x + root.width - chooser.width,
            overlay.width - chooser.width - 12))
        chooser.y = Math.max(12, Math.min(preferredY,
            overlay.height - chooser.height - 12))
    }

    RippleButton {
        anchors.fill: parent
        activeFocusOnTab: true
        enabled: KeyboardLayout.catalogueReady && !KeyboardLayout.busy
        Accessible.name: Translation.tr("Keyboard layout") + ": " + Translation.tr(KeyboardLayout.currentDisplay)
        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: root.openPicker()

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            MaterialSymbol {
                text: "keyboard"
                iconSize: 18
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: KeyboardLayout.busy
                    ? Translation.tr("Applying layout…") : Translation.tr(KeyboardLayout.currentDisplay)
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: 18
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    Popup {
        id: chooser
        parent: Overlay.overlay
        readonly property int maxHeight: Math.max(0, (parent?.height ?? 454) - 24)
        readonly property int rowHeight: root.compact ? 40 : 48
        readonly property int visibleRows: Math.min(6, Math.max(1, Math.floor(
            (maxHeight - 2 * padding - 48 + layoutList.spacing) / (rowHeight + layoutList.spacing))))

        width: Math.min(root.compact ? 300 : 370, Math.max(0, (parent?.width ?? 394) - 24))
        height: root.compact
            ? Math.min(maxHeight, 2 * padding + 48
                + Math.max(1, Math.min(layoutList.count, visibleRows)) * (rowHeight + layoutList.spacing)
                - layoutList.spacing)
            : Math.min(430, maxHeight)
        padding: 10
        focus: true
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: Appearance.radius.card
            color: Qt.rgba(
                Appearance.m3colors.m3surfaceContainerHigh.r,
                Appearance.m3colors.m3surfaceContainerHigh.g,
                Appearance.m3colors.m3surfaceContainerHigh.b, 1)
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }

        contentItem: ColumnLayout {
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                visible: !root.compact
                text: Translation.tr("Choose keyboard layout")
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.compact
                text: "Current: " + Translation.tr(KeyboardLayout.currentDisplay)
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                placeholderText: Translation.tr("Search layouts and variants…")
                color: Appearance.colors.colOnLayer0
                placeholderTextColor: Appearance.colors.colSubtext
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
                background: Rectangle {
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1Base
                    border.width: searchField.activeFocus ? 2 : 1
                    border.color: searchField.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                }
                onAccepted: {
                    const matches = root.choices(searchField.text)
                    if (matches.length === 1)
                        root.choose(matches[0].value)
                }
            }

            ListView {
                id: layoutList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.choices(searchField.text)
                ScrollBar.vertical: StyledScrollBar {
                    policy: root.compact && layoutList.count > chooser.visibleRows
                        ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                    topPadding: root.compact ? 2 : Appearance.rounding.normal
                    bottomPadding: topPadding
                }

                delegate: ItemDelegate {
                    id: layoutChoice
                    required property var modelData
                    width: layoutList.width - (root.compact && layoutList.count <= chooser.visibleRows ? 0 : 8)
                    implicitHeight: chooser.rowHeight
                    highlighted: root.showCompositorDefault
                        ? Config.options.language.keyboardLayout === modelData.value
                        : KeyboardLayout.currentCode === modelData.value
                    Accessible.name: modelData.displayName
                    Accessible.selected: highlighted
                    onClicked: root.choose(modelData.value)

                    background: Rectangle {
                        radius: Appearance.radius.control
                        color: layoutChoice.highlighted
                            ? Appearance.colors.colSecondaryContainer
                            : layoutChoice.hovered
                                ? Appearance.colors.colLayer2Hover
                                : "transparent"
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: layoutChoice.modelData.value === "auto"
                                    ? Translation.tr("Use Hyprland setting")
                                    : layoutChoice.modelData.displayName
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: !root.compact
                                text: layoutChoice.modelData.value === "auto"
                                    ? "Restore the layout from Hyprland's config"
                                    : layoutChoice.modelData.value
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                elide: Text.ElideRight
                            }
                        }
                        MaterialSymbol {
                            visible: layoutChoice.highlighted
                            text: "check"
                            iconSize: 17
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                footer: StyledText {
                    visible: layoutList.count === 0
                    width: layoutList.width
                    text: Translation.tr("No installed XKB layout matches this search.")
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.compact
                text: "Input methods such as Pinyin need a separate IME."
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                wrapMode: Text.Wrap
            }
        }

        onOpened: {
            root.positionPicker()
            searchField.forceActiveFocus()
        }
    }
}
