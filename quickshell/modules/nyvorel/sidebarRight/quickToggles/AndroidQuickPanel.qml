import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Bluetooth

import qs.modules.nyvorel.sidebarRight.quickToggles.androidStyle


AbstractQuickPanel {
    id: root

    property bool editMode: false

    Layout.fillWidth: true

    property real spacing: 8
    property real padding: 8

    readonly property real baseCellHeight: 66

    readonly property int columns:
        Math.max(
            1,
            Config.options.sidebar.quickToggles.android.columns
        )


    readonly property real baseCellWidth: {
        const gaps =
            root.spacing
            * Math.max(
                0,
                root.columns - 1
            )

        const availableWidth =
            root.width
            - root.padding * 2
            - gaps

        return Math.max(
            0,
            availableWidth / root.columns
        )
    }


    implicitHeight:
        (
            editMode
                ? contentItem.implicitHeight
                : usedRows.implicitHeight
        )
        + root.padding * 2


    Behavior on implicitHeight {
        animation:
            Appearance.animation.elementMove
                .numberAnimation
                .createObject(this)
    }


    readonly property list<string> availableToggleTypes: [
        "network",
        "bluetooth",
        "idleInhibitor",
        "easyEffects",
        "nightLight",
        "darkMode",
        "cloudflareWarp",
        "gameMode",
        "screenSnip",
        "colorPicker",
        "onScreenKeyboard",
        "mic",
        "audio",
        "notifications",
        "powerProfile",
        "musicRecognition",
        "antiFlashbang"
    ]


    readonly property list<var> toggles:
        Config.ready
            ? Config.options.sidebar.quickToggles.android.toggles
            : []


    readonly property list<var> toggleRows:
        toggleRowsForList(toggles)


    readonly property list<var> unusedToggles: {
        const types =
            availableToggleTypes.filter(
                type =>
                    !toggles.some(
                        toggle =>
                            toggle
                            && toggle.type === type
                    )
            )

        return types.map(
            type => {
                return {
                    type: type,
                    size: 1
                }
            }
        )
    }


    readonly property list<var> unusedToggleRows:
        toggleRowsForList(unusedToggles)


    function toggleRowsForList(togglesList) {
        const rows = []

        let row = []
        let totalSize = 0

        for (
            let i = 0;
            i < togglesList.length;
            i++
        ) {
            const toggle = togglesList[i]

            if (!toggle)
                continue

            // One configured toggle occupies exactly one visible column.
            // The Settings value now means "tiles per row", not internal
            // span units.
            const size = 1

            if (
                totalSize > 0
                && totalSize + size > root.columns
            ) {
                rows.push(row)

                row = []
                totalSize = 0
            }

            row.push(toggle)
            totalSize += size
        }

        if (row.length > 0)
            rows.push(row)

        return rows
    }


    Column {
        id: contentItem

        anchors.fill: parent
        anchors.margins: root.padding

        spacing: 10


        Column {
            id: usedRows

            width: parent.width
            spacing: root.spacing


            Repeater {
                model:
                    ScriptModel {
                        values:
                            Array(root.toggleRows.length)
                    }

                delegate:
                    ButtonGroup {
                        id: toggleRow

                        required property int index

                        property var modelData:
                            root.toggleRows[index]

                        property int startingIndex: {
                            const rows = root.toggleRows

                            let sum = 0

                            for (
                                let i = 0;
                                i < index;
                                i++
                            ) {
                                sum += rows[i].length
                            }

                            return sum
                        }

                        spacing: root.spacing


                        Repeater {
                            model:
                                ScriptModel {
                                    values:
                                        toggleRow?.modelData
                                        ?? []

                                    objectProp: "type"
                                }

                            delegate:
                                AndroidToggleDelegateChooser {
                                    startingIndex:
                                        toggleRow.startingIndex

                                    editMode: root.editMode
                                    baseCellWidth: root.baseCellWidth
                                    baseCellHeight: root.baseCellHeight
                                    spacing: root.spacing

                                    onOpenAudioOutputDialog:
                                        root.openAudioOutputDialog()

                                    onOpenAudioInputDialog:
                                        root.openAudioInputDialog()

                                    onOpenBluetoothDialog:
                                        root.openBluetoothDialog()

                                    onOpenNightLightDialog:
                                        root.openNightLightDialog()

                                    onOpenWifiDialog:
                                        root.openWifiDialog()
                                }
                        }
                    }
            }
        }


        FadeLoader {
            shown: root.editMode

            anchors.left: parent.left
            anchors.right: parent.right

            anchors.leftMargin:
                root.baseCellHeight / 2

            anchors.rightMargin:
                root.baseCellHeight / 2

            sourceComponent:
                Rectangle {
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }
        }


        FadeLoader {
            shown: root.editMode

            sourceComponent:
                Column {
                    id: unusedRows

                    spacing: root.spacing


                    Repeater {
                        model:
                            ScriptModel {
                                values:
                                    Array(
                                        root.unusedToggleRows.length
                                    )
                            }

                        delegate:
                            ButtonGroup {
                                id: unusedToggleRow

                                required property int index

                                property var modelData:
                                    root.unusedToggleRows[index]

                                spacing: root.spacing


                                Repeater {
                                    model:
                                        ScriptModel {
                                            values:
                                                unusedToggleRow
                                                    ?.modelData
                                                ?? []

                                            objectProp: "type"
                                        }

                                    delegate:
                                        AndroidToggleDelegateChooser {
                                            startingIndex: -1
                                            editMode: root.editMode
                                            baseCellWidth: root.baseCellWidth
                                            baseCellHeight: root.baseCellHeight
                                            spacing: root.spacing
                                        }
                                }
                            }
                    }
                }
        }
    }
}
