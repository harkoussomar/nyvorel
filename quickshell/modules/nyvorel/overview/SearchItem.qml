import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland


RippleButton {
    id: root


    property LauncherSearchResult entry
    property string query


    property bool entryShown:
        entry?.shown ?? true


    property string itemType:
        entry?.type ?? Translation.tr("App")


    property string itemName:
        entry?.name ?? ""


    property var iconType:
        entry?.iconType


    property string iconName:
        entry?.iconName ?? ""


    property var itemExecute:
        entry?.execute


    property var fontType: {
        switch (entry?.fontType) {
        case LauncherSearchResult.FontType.Monospace:
            return "monospace"

        case LauncherSearchResult.FontType.Normal:
            return "main"

        default:
            return "main"
        }
    }


    property string itemClickActionName:
        entry?.verb ?? "Open"


    property string bigText:
        entry?.iconType
        === LauncherSearchResult.IconType.Text
            ? entry?.iconName ?? ""
            : ""


    property string materialSymbol:
        entry?.iconType
        === LauncherSearchResult.IconType.Material
            ? entry?.iconName ?? ""
            : ""


    property string cliphistRawString:
        entry?.rawValue ?? ""


    property bool blurImage:
        entry?.blurImage ?? false

    // SEARCH-CLIPBOARD-V2
    readonly property bool listCurrent:
        ListView.isCurrentItem


    // ============================================================
    // Result classification
    // ============================================================

    readonly property bool isClipboardEntry:
        root.cliphistRawString !== ""
        && root.itemType.startsWith("#")


    readonly property var clipboardInfo:
        root.isClipboardEntry
            ? Cliphist.describeEntry(
                root.cliphistRawString
            )
            : ({
                kind: "Text",
                isImage: false,
                isLink: false,
                urls: []
            })


    readonly property bool clipboardIsImage:
        root.clipboardInfo.isImage === true


    readonly property list<string> urls:
        root.clipboardInfo.urls
            ? root.clipboardInfo.urls
            : []


    readonly property bool clipboardIsLink:
        root.clipboardInfo.isLink === true


    readonly property string clipboardKind:
        root.clipboardInfo.kind
            ? root.clipboardInfo.kind
            : "Text"


    readonly property string clipboardKindIcon:
        root.clipboardIsImage
            ? "image"
            : root.clipboardIsLink
                ? "link"
                : "notes"


    readonly property string normalSubtitle: {
        if (
            root.itemType
            === Translation.tr("App")
        ) {
            if (
                root.entry?.comment
                && root.entry.comment.length > 0
            ) {
                return root.entry.comment
            }


            if (
                root.entry?.genericName
                && root.entry.genericName.length > 0
            ) {
                return root.entry.genericName
            }


            return "Application"
        }


        return root.itemType
    }


    visible:
        root.entryShown


    property int horizontalMargin:
        8

    property int buttonHorizontalPadding:
        10

    property int buttonVerticalPadding:
        6

    property bool keyboardDown:
        false


    implicitHeight:
        contentLayout.implicitHeight
        + root.buttonVerticalPadding * 2


    buttonRadius:
        Appearance.rounding.normal


    // Much less aggressive than the previous large orange block.
    colBackground:
        root.keyboardDown
            ? Appearance.colors.colLayer2Active
            : root.focus
                ? Appearance.colors.colSecondaryContainer
                : root.hovered
                    ? Appearance.colors.colLayer2Hover
                    : ColorUtils.transparentize(
                        Appearance.colors.colLayer2,
                        1
                    )


    colBackgroundHover:
        Appearance.colors.colLayer2Hover


    colRipple:
        Appearance.colors.colLayer2Active


    // ============================================================
    // Fuzzy match highlighting
    // ============================================================

    property string highlightPrefix:
        `<u><font color="${Appearance.colors.colPrimary}">`


    property string highlightSuffix:
        `</font></u>`


    function highlightContent(
        content,
        query
    ) {
        if (
            !query
            || query.length === 0
            || content === query
            || root.fontType === "monospace"
        ) {
            return StringUtils.escapeHtml(
                content
            )
        }


        const contentLower =
            content.toLowerCase()

        const queryLower =
            query.toLowerCase()


        let result =
            ""

        let lastIndex =
            0

        let qIndex =
            0


        for (
            let i = 0;
            i < content.length
                && qIndex < query.length;
            i++
        ) {
            if (
                contentLower[i]
                === queryLower[qIndex]
            ) {
                if (i > lastIndex) {
                    result +=
                        StringUtils.escapeHtml(
                            content.slice(
                                lastIndex,
                                i
                            )
                        )
                }


                result +=
                    root.highlightPrefix
                    + StringUtils.escapeHtml(
                        content[i]
                    )
                    + root.highlightSuffix


                lastIndex =
                    i + 1

                qIndex++
            }
        }


        if (
            lastIndex
            < content.length
        ) {
            result +=
                StringUtils.escapeHtml(
                    content.slice(
                        lastIndex
                    )
                )
        }


        return result
    }


    readonly property string displayContent:
        root.highlightContent(
            root.itemName,
            root.query
        )


    // ============================================================
    // Clipboard image metadata
    //
    // Example source:
    //
    // [[ binary data 220 KiB png 1918x823 ]]
    //
    // becomes:
    //
    // PNG · 1918×823 · 220 KiB
    // ============================================================

    function imageMetadata() {
        const value =
            root.itemName ?? ""


        const match =
            value.match(
                /binary data\s+(.+?)\s+([a-zA-Z0-9]+)\s+(\d+)x(\d+)/i
            )


        if (!match)
            return "Clipboard image"


        return (
            match[2].toUpperCase()
            + " · "
            + match[3]
            + "×"
            + match[4]
            + " · "
            + match[1]
        )
    }


    // ============================================================
    // Interaction
    // ============================================================

    PointingHandInteraction {}


    background {
        anchors.fill:
            root

        anchors.leftMargin:
            root.horizontalMargin

        anchors.rightMargin:
            root.horizontalMargin
    }


    onClicked: {
        GlobalStates.overviewOpen =
            false


        if (root.itemExecute)
            root.itemExecute()
    }


    Keys.onPressed: event => {
        if (
            event.key === Qt.Key_Delete
            && event.modifiers
                === Qt.ShiftModifier
        ) {
            const deleteAction =
                root.entry.actions.find(
                    action =>
                        action.name
                        === Translation.tr("Delete")
                )


            if (deleteAction) {
                deleteAction.execute()
                event.accepted = true
            }


            return
        }


        if (
            event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter
        ) {
            root.keyboardDown =
                true

            root.clicked()

            event.accepted =
                true
        }
    }


    Keys.onReleased: event => {
        if (
            event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter
        ) {
            root.keyboardDown =
                false

            event.accepted =
                true
        }
    }


    // ============================================================
    // Small result action button
    // ============================================================

    component ResultActionButton: RippleButton {
        id: actionButton


        required property var actionData


        implicitWidth:
            30

        implicitHeight:
            30


        buttonRadius:
            height / 2


        colBackground:
            "transparent"


        colBackgroundHover:
            Appearance.colors.colLayer2Hover


        colRipple:
            Appearance.colors.colLayer2Active


        PointingHandInteraction {}


        contentItem:
            Item {
                anchors.fill:
                    parent


                Loader {
                    anchors.centerIn:
                        parent


                    active:
                        actionButton.actionData.iconType
                            === LauncherSearchResult.IconType.Material
                        || (
                            actionButton.actionData.iconName
                            ?? ""
                        ) === ""


                    sourceComponent:
                        MaterialSymbol {
                            text:
                                actionButton.actionData.iconName
                                || "more_horiz"

                            iconSize:
                                18

                            color:
                                Appearance.colors.colOnSurfaceVariant
                        }
                }


                Loader {
                    anchors.centerIn:
                        parent


                    active:
                        actionButton.actionData.iconType
                            === LauncherSearchResult.IconType.System
                        && (
                            actionButton.actionData.iconName
                            ?? ""
                        ) !== ""


                    sourceComponent:
                        IconImage {
                            source:
                                Quickshell.iconPath(
                                    actionButton.actionData.iconName
                                )

                            implicitSize:
                                18
                        }
                }
            }


        onClicked:
            actionButton.actionData.execute()


        StyledToolTip {
            text:
                actionButton.actionData.name
        }
    }


    // ============================================================
    // Components used by ordinary results
    // ============================================================

    Component {
        id: iconImageComponent


        IconImage {
            source:
                Quickshell.iconPath(
                    root.iconName,
                    "image-missing"
                )

            width:
                30

            height:
                30
        }
    }


    Component {
        id: materialSymbolComponent


        MaterialSymbol {
            text:
                root.materialSymbol

            iconSize:
                22

            color:
                Appearance.m3colors.m3onSurface
        }
    }


    Component {
        id: bigTextComponent


        StyledText {
            text:
                root.bigText

            font.pixelSize:
                Appearance.font.pixelSize.larger

            color:
                Appearance.m3colors.m3onSurface
        }
    }


    // ============================================================
    // Main result content
    // ============================================================

    ColumnLayout {
        id: contentLayout


        anchors {
            left:
                parent.left

            right:
                parent.right

            leftMargin:
                root.horizontalMargin
                + root.buttonHorizontalPadding

            rightMargin:
                root.horizontalMargin
                + root.buttonHorizontalPadding

            verticalCenter:
                parent.verticalCenter
        }


        spacing:
            0


        // ========================================================
        // Standard results
        // ========================================================

        RowLayout {
            visible:
                !root.isClipboardEntry


            Layout.fillWidth:
                true

            Layout.preferredHeight:
                48


            spacing:
                10


            Loader {
                id: iconLoader


                Layout.alignment:
                    Qt.AlignVCenter


                active:
                    true


                sourceComponent: {
                    switch (root.iconType) {
                    case LauncherSearchResult.IconType.Material:
                        return materialSymbolComponent

                    case LauncherSearchResult.IconType.Text:
                        return bigTextComponent

                    case LauncherSearchResult.IconType.System:
                        return iconImageComponent

                    default:
                        return null
                    }
                }
            }


            ColumnLayout {
                Layout.fillWidth:
                    true

                Layout.alignment:
                    Qt.AlignVCenter


                spacing:
                    -1


                RowLayout {
                    Layout.fillWidth:
                        true


                    StyledText {
                        Layout.fillWidth:
                            true


                        textFormat:
                            Text.StyledText


                        text:
                            root.displayContent


                        font {
                            pixelSize:
                                Appearance.font.pixelSize.small

                            family:
                                Appearance.font.family[
                                    root.fontType
                                ]

                            weight:
                                Font.Medium
                        }


                        color:
                            Appearance.m3colors.m3onSurface


                        elide:
                            Text.ElideRight
                    }
                }


                StyledText {
                    Layout.fillWidth:
                        true


                    visible:
                        root.normalSubtitle.length
                        > 0


                    text:
                        root.normalSubtitle


                    font.pixelSize:
                        Appearance.font.pixelSize.smaller


                    color:
                        Appearance.colors.colSubtext


                    elide:
                        Text.ElideRight
                }
            }


            StyledText {
                visible:
                    (
                        root.hovered
                        || root.focus
                    )
                    && root.itemClickActionName.length
                        > 0


                Layout.alignment:
                    Qt.AlignVCenter


                text:
                    "↵ "
                    + root.itemClickActionName


                font {
                    pixelSize:
                        Appearance.font.pixelSize.smaller

                    weight:
                        Font.Medium
                }


                color:
                    Appearance.colors.colSubtext
            }


            RowLayout {
                visible:
                    root.entry.actions
                    && root.entry.actions.length > 0


                Layout.alignment:
                    Qt.AlignVCenter


                spacing:
                    2


                Repeater {
                    model:
                        (
                            root.entry.actions
                            ?? []
                        ).slice(
                            0,
                            3
                        )


                    delegate:
                        ResultActionButton {
                            required property var modelData

                            actionData:
                                modelData
                        }
                }
            }
        }


        // ========================================================
        // Clipboard result
        // ========================================================

        ColumnLayout {
            visible:
                root.isClipboardEntry


            Layout.fillWidth:
                true


            spacing:
                7


            // ----------------------------------------------------
            // Clipboard header
            // ----------------------------------------------------

            RowLayout {
                Layout.fillWidth:
                    true

                Layout.preferredHeight:
                    30


                spacing:
                    7


                Rectangle {
                    implicitWidth:
                        clipboardKindRow.implicitWidth
                        + 14

                    implicitHeight:
                        25


                    radius:
                        height / 2


                    color:
                        Appearance.colors.colLayer2


                    Row {
                        id: clipboardKindRow

                        anchors.centerIn:
                            parent

                        spacing:
                            5


                        MaterialSymbol {
                            anchors.verticalCenter:
                                parent.verticalCenter

                            text:
                                root.clipboardKindIcon

                            iconSize:
                                14

                            color:
                                Appearance.colors.colSubtext
                        }


                        StyledText {
                            anchors.verticalCenter:
                                parent.verticalCenter

                            text:
                                root.clipboardKind

                            font {
                                pixelSize:
                                    Appearance.font.pixelSize.smaller

                                weight:
                                    Font.DemiBold
                            }

                            color:
                                Appearance.colors.colOnLayer2
                        }
                    }
                }


                Item {
                    Layout.fillWidth:
                        true
                }


                Loader {
                    visible:
                        !root.clipboardIsImage
                        && root.itemName
                            === Quickshell.clipboardText


                    active:
                        visible


                    sourceComponent:
                        Rectangle {
                            implicitWidth:
                                25

                            implicitHeight:
                                25

                            radius:
                                height / 2

                            color:
                                Appearance.colors.colPrimary


                            MaterialSymbol {
                                anchors.centerIn:
                                    parent

                                text:
                                    "check"

                                iconSize:
                                    15

                                color:
                                    Appearance.m3colors.m3onPrimary
                            }
                        }
                }


                RowLayout {
                    spacing:
                        2


                    Repeater {
                        model:
                            (
                                root.entry.actions
                                ?? []
                            ).slice(
                                0,
                                2
                            )


                        delegate:
                            ResultActionButton {
                                required property var modelData

                                actionData:
                                    modelData
                            }
                    }
                }
            }


            // ----------------------------------------------------
            // Image preview
            // ----------------------------------------------------

            Loader {
                active:
                    root.clipboardIsImage


                visible:
                    active


                Layout.fillWidth:
                    true


                sourceComponent:
                    ColumnLayout {
                        spacing:
                            6


                        CliphistImage {
                            Layout.fillWidth:
                                true


                            entry:
                                root.cliphistRawString


                            maxWidth:
                                parent.width


                            // Compact rows keep keyboard navigation calm.
                            // The selected image expands for inspection.
                            maxHeight:
                                root.listCurrent
                                    ? 144
                                    : 64


                            blur:
                                root.blurImage
                        }


                        StyledText {
                            Layout.fillWidth:
                                true


                            text:
                                root.imageMetadata()


                            font.pixelSize:
                                Appearance.font.pixelSize.smaller


                            color:
                                Appearance.colors.colSubtext


                            elide:
                                Text.ElideRight
                        }
                    }
            }


            // ----------------------------------------------------
            // Clipboard text / URL
            // ----------------------------------------------------

            RowLayout {
                visible:
                    !root.clipboardIsImage


                Layout.fillWidth:
                    true


                spacing:
                    8


                MaterialSymbol {
                    visible:
                        root.clipboardIsLink


                    Layout.alignment:
                        Qt.AlignTop


                    text:
                        "link"


                    iconSize:
                        18


                    color:
                        Appearance.colors.colSubtext
                }


                StyledText {
                    Layout.fillWidth:
                        true


                    text:
                        root.itemName


                    textFormat:
                        Text.PlainText


                    wrapMode:
                        Text.Wrap


                    maximumLineCount:
                        3


                    elide:
                        Text.ElideRight


                    font {
                        pixelSize:
                            Appearance.font.pixelSize.small

                        family:
                            Appearance.font.family[
                                root.fontType
                            ]
                    }


                    color:
                        Appearance.m3colors.m3onSurface
                }
            }


            Item {
                implicitHeight:
                    2
            }
        }
    }
}