import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.nyvorel.sidebarRight.calendar
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io

StyledPopup {
    id: root
    irisAnimation: Appearance.barLayout.axiomComponents
    popupRadius: Appearance.radius.popup
    popupColor: root.surface
    contentMargin: 13
    dismissOnOutsideClick: true

    readonly property real screenWidth: root.QsWindow && root.QsWindow.window
        && root.QsWindow.window.screen ? root.QsWindow.window.screen.width : 900
    readonly property real screenHeight: root.QsWindow && root.QsWindow.window
        && root.QsWindow.window.screen ? root.QsWindow.window.screen.height : 900
    readonly property real panelWidth: Math.min(390, Math.max(292, screenWidth - 56))
    readonly property real panelMaxHeight: Math.max(280, screenHeight
        - (Config.options.bar.vertical ? 52 : Appearance.sizes.barHeight) - 64)
    readonly property color surface: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill,
        Appearance.colors.colLayer1, 0.62)
    readonly property color inset: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill,
        Appearance.colors.colLayer1, 0.82)
    readonly property color stroke: Appearance.colors.colLayer0Border
    readonly property color ink: Appearance.colors.colOnLayer0
    readonly property color muted: Appearance.colors.colSubtext
    readonly property color accent: Appearance.colors.colPrimary

    property var plans: []
    property string draft: ""
    property string errorText: ""
    property string pendingAction: ""
    property bool busy: false
    readonly property var markedDates: {
        const dates = {}
        for (const plan of root.plans) {
            if (!plan.done)
                dates[plan.date] = (dates[plan.date] ?? 0) + 1
        }
        return dates
    }

    function requestCalendar(args) {
        if (root.busy) return
        root.busy = true
        root.pendingAction = args[0]
        calendarProcess.command = [Quickshell.shellPath("scripts/system/nyvorel-operations"),
            "calendar"].concat(args)
        calendarProcess.running = true
    }
    function addPlan() {
        const title = root.draft.trim()
        if (title.length > 0 && !root.busy)
            root.requestCalendar(["add", calendar.selectedIsoDate, title])
    }

    property var calendarProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(this.text)
                    if (!Array.isArray(result.items)) throw new Error("Invalid plans response")
                    root.plans = result.items
                    root.errorText = ""
                    if (root.pendingAction === "add") root.draft = ""
                } catch (error) {
                    root.errorText = String(error)
                }
            }
        }
        stderr: StdioCollector { id: calendarError }
        onExited: (code, status) => {
            root.busy = false
            if (code !== 0)
                root.errorText = calendarError.text.trim() || Translation.tr("Could not save plans")
        }
    }
    property var loadTimer: Timer {
        interval: 1
        repeat: false
        running: root.active
        onTriggered: root.requestCalendar(["list"])
    }

    Controls.ScrollView {
        id: scrollView
        anchors.centerIn: parent
        implicitWidth: root.panelWidth
        implicitHeight: Math.min(content.implicitHeight, root.panelMaxHeight)
        contentWidth: availableWidth
        clip: content.implicitHeight > root.panelMaxHeight
        padding: 0
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        Controls.ScrollBar.vertical.policy: content.implicitHeight > root.panelMaxHeight
            ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff

        ColumnLayout {
            id: content
            width: scrollView.availableWidth
            spacing: 12

            StyledText {
                Layout.leftMargin: 2
                text: DateTime.time
                font.pixelSize: 28
                font.weight: Font.DemiBold
                color: root.ink
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: calendar.implicitHeight + 24
                radius: 12
                color: root.inset
                border.width: 1
                border.color: root.stroke
                CalendarWidget {
                    id: calendar
                    anchors.centerIn: parent
                    showSelectedDetails: false
                    markedDates: root.markedDates
                }
            }

            Rectangle {
                id: agendaCard
                Layout.fillWidth: true
                implicitHeight: agendaContent.implicitHeight + 28
                radius: 12
                color: root.inset
                border.width: 1
                border.color: root.stroke
                readonly property var itemsForDate: root.plans
                    .filter(plan => plan.date === calendar.selectedIsoDate)
                    .sort((a, b) => Number(a.done) - Number(b.done) || a.id - b.id)
                readonly property int openCount: itemsForDate.filter(plan => !plan.done).length

                ColumnLayout {
                    id: agendaContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            StyledText {
                                text: Translation.tr("PLANS")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.0
                                color: root.muted
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: calendar.selectedDate.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: root.ink
                                elide: Text.ElideRight
                            }
                        }
                        StyledText {
                            visible: agendaCard.openCount > 0
                            text: Translation.tr("%1 open").arg(agendaCard.openCount)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.muted
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        Controls.TextField {
                            id: planField
                            Layout.fillWidth: true
                            implicitHeight: 38
                            text: root.draft
                            onTextEdited: root.draft = text
                            placeholderText: Translation.tr("Add a plan for this day")
                            maximumLength: 120
                            enabled: !root.busy
                            color: root.ink
                            placeholderTextColor: root.muted
                            font.pixelSize: Appearance.font.pixelSize.small
                            onAccepted: root.addPlan()
                            background: Rectangle {
                                radius: 8
                                color: root.surface
                                border.width: 1
                                border.color: planField.activeFocus ? root.accent : root.stroke
                            }
                        }
                        Rectangle {
                            id: addButton
                            implicitWidth: 38
                            implicitHeight: 38
                            radius: 8
                            enabled: root.draft.trim().length > 0 && !root.busy
                            opacity: enabled ? 1 : 0.45
                            color: root.accent
                            activeFocusOnTab: enabled
                            Accessible.role: Accessible.Button
                            Accessible.name: Translation.tr("Add plan")
                            Accessible.onPressAction: root.addPlan()
                            Keys.onReturnPressed: root.addPlan()
                            Keys.onSpacePressed: root.addPlan()
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "add"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimary
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.addPlan()
                            }
                        }
                    }

                    StyledText {
                        visible: root.errorText.length > 0
                        Layout.fillWidth: true
                        text: root.errorText
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        visible: agendaCard.itemsForDate.length === 0 && root.errorText.length === 0
                        Layout.fillWidth: true
                        text: Translation.tr("No plans for this day")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.muted
                    }

                    Repeater {
                        model: agendaCard.itemsForDate
                        delegate: Rectangle {
                            id: planRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: 8
                            color: root.surface
                            border.width: 1
                            border.color: root.stroke
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 9
                                Rectangle {
                                    id: checkButton
                                    implicitWidth: 19
                                    implicitHeight: 19
                                    radius: 6
                                    color: planRow.modelData.done ? root.accent : "transparent"
                                    border.width: 1
                                    border.color: planRow.modelData.done ? root.accent : root.muted
                                    enabled: !root.busy
                                    activeFocusOnTab: enabled
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: Translation.tr("Complete %1").arg(planRow.modelData.title)
                                    Accessible.checked: planRow.modelData.done
                                    Accessible.onPressAction: root.requestCalendar(["toggle", String(planRow.modelData.id)])
                                    Keys.onReturnPressed: root.requestCalendar(["toggle", String(planRow.modelData.id)])
                                    Keys.onSpacePressed: root.requestCalendar(["toggle", String(planRow.modelData.id)])
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: planRow.modelData.done
                                        text: "check"
                                        iconSize: 15
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.requestCalendar(["toggle", String(planRow.modelData.id)])
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: planRow.modelData.title
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: planRow.modelData.done ? root.muted : root.ink
                                    font.strikeout: planRow.modelData.done
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    radius: 7
                                    color: "transparent"
                                    enabled: !root.busy
                                    activeFocusOnTab: enabled
                                    Accessible.role: Accessible.Button
                                    Accessible.name: Translation.tr("Delete %1").arg(planRow.modelData.title)
                                    Accessible.onPressAction: root.requestCalendar(["delete", String(planRow.modelData.id)])
                                    Keys.onReturnPressed: root.requestCalendar(["delete", String(planRow.modelData.id)])
                                    Keys.onSpacePressed: root.requestCalendar(["delete", String(planRow.modelData.id)])
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 16
                                        color: root.muted
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.requestCalendar(["delete", String(planRow.modelData.id)])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
