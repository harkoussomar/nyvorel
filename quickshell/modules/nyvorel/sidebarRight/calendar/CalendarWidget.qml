import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property int monthShift: 0
    property date now: new Date()
    property date selectedDate: new Date()
    property bool copied: false

    // Filled by the installer only when those capabilities exist.
    property string clipboardExecutable: "wl-copy"
    property string calendarExecutable: ""

    readonly property int dayCellSize: 34
    readonly property int cellGap: 5
    readonly property int gridWidth:
        dayCellSize * 7 + cellGap * 6

    readonly property date viewingDate:
        CalendarLayout.getDateInXMonthsTime(monthShift)

    readonly property var calendarLayout: {
        // Keep "today" state fresh if the popup survives midnight.
        const freshness = now;
        return CalendarLayout.getCalendarLayout(
            viewingDate,
            monthShift === 0
        );
    }

    readonly property string selectedIsoDate:
        formatIsoDate(selectedDate)
    readonly property int selectedDelta:
        daysBetween(now, selectedDate)
    readonly property int selectedWeek:
        isoWeek(selectedDate)
    readonly property int selectedDayOfYear:
        dayOfYear(selectedDate)
    readonly property int selectedYearLength:
        isLeapYear(selectedDate.getFullYear()) ? 366 : 365

    implicitWidth: gridWidth
    implicitHeight: calendarColumn.implicitHeight
    focus: true

    function midnight(date) {
        return new Date(
            date.getFullYear(),
            date.getMonth(),
            date.getDate()
        );
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate();
    }

    function daysBetween(a, b) {
        return Math.round(
            (midnight(b).getTime() - midnight(a).getTime())
            / 86400000
        );
    }

    function monthDifference(date) {
        return (date.getFullYear() - now.getFullYear()) * 12
            + date.getMonth()
            - now.getMonth();
    }

    function selectDate(date) {
        selectedDate = new Date(
            date.getFullYear(),
            date.getMonth(),
            date.getDate()
        );
        monthShift = monthDifference(selectedDate);
    }

    function moveSelection(days) {
        const next = new Date(selectedDate);
        next.setDate(next.getDate() + days);
        selectDate(next);
    }

    function shiftMonth(delta) {
        const targetShift = monthShift + delta;
        const targetMonth = CalendarLayout.getDateInXMonthsTime(
            targetShift
        );
        const maxDay = new Date(
            targetMonth.getFullYear(),
            targetMonth.getMonth() + 1,
            0
        ).getDate();
        const desiredDay = Math.min(selectedDate.getDate(), maxDay);

        monthShift = targetShift;
        selectedDate = new Date(
            targetMonth.getFullYear(),
            targetMonth.getMonth(),
            desiredDay
        );
    }

    function goToday() {
        now = new Date();
        selectedDate = new Date(now);
        monthShift = 0;
    }

    function pad2(value) {
        return value.toString().padStart(2, "0");
    }

    function formatIsoDate(date) {
        return date.getFullYear()
            + "-" + pad2(date.getMonth() + 1)
            + "-" + pad2(date.getDate());
    }

    function relativeLabel() {
        if (selectedDelta === 0)
            return Translation.tr("Today");
        if (selectedDelta === 1)
            return Translation.tr("Tomorrow");
        if (selectedDelta === -1)
            return Translation.tr("Yesterday");
        if (selectedDelta > 1)
            return Translation.tr("In %1 days").arg(selectedDelta);

        return Translation.tr("%1 days ago").arg(
            Math.abs(selectedDelta)
        );
    }

    function isLeapYear(year) {
        return year % 400 === 0
            || (year % 4 === 0 && year % 100 !== 0);
    }

    function dayOfYear(date) {
        const start = new Date(date.getFullYear(), 0, 0);
        return Math.floor((midnight(date) - start) / 86400000);
    }

    function isoWeek(date) {
        const d = new Date(Date.UTC(
            date.getFullYear(),
            date.getMonth(),
            date.getDate()
        ));
        const dayNumber = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - dayNumber);
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));

        return Math.ceil(
            (((d - yearStart) / 86400000) + 1) / 7
        );
    }

    function copySelectedDate() {
        if (clipboardExecutable.length === 0)
            return;

        Quickshell.execDetached([
            clipboardExecutable,
            selectedIsoDate
        ]);
        copied = true;
        copyFeedbackTimer.restart();
    }

    function openCalendar() {
        if (calendarExecutable.length === 0)
            return;

        Quickshell.execDetached([calendarExecutable]);
    }

    Keys.onPressed: event => {
        if (event.modifiers !== Qt.NoModifier)
            return;

        if (event.key === Qt.Key_PageDown) {
            shiftMonth(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
            shiftMonth(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            goToday();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            moveSelection(-7);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            moveSelection(7);
            event.accepted = true;
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Timer {
        id: copyFeedbackTimer
        interval: 1200
        repeat: false
        onTriggered: root.copied = false
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        onWheel: event => {
            if (event.angleDelta.y > 0)
                root.shiftMonth(-1);
            else if (event.angleDelta.y < 0)
                root.shiftMonth(1);

            event.accepted = true;
        }
    }

    ColumnLayout {
        id: calendarColumn

        width: root.gridWidth
        spacing: 8

        // ------------------------------------------------------
        // Month navigation
        // ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            CalendarHeaderButton {
                Layout.fillWidth: true
                clip: true

                buttonText:
                    `${root.monthShift !== 0 ? "• " : ""}`
                    + root.viewingDate.toLocaleDateString(
                        Qt.locale(),
                        "MMMM yyyy"
                    )
                tooltipText:
                    root.monthShift === 0
                        ? ""
                        : Translation.tr("Jump to today")
                accessibleName:
                    root.viewingDate.toLocaleDateString(
                        Qt.locale(),
                        "MMMM yyyy"
                    )

                onClicked: {
                    if (root.monthShift !== 0)
                        root.goToday();
                }
            }

            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Previous month")
                accessibleName: Translation.tr("Previous month")
                onClicked: root.shiftMonth(-1)

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -2

                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Next month")
                accessibleName: Translation.tr("Next month")
                onClicked: root.shiftMonth(1)

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -2

                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        // ------------------------------------------------------
        // Weekday labels -- labels, not fake disabled buttons.
        // ------------------------------------------------------
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: root.cellGap

            Repeater {
                model: CalendarLayout.weekDays

                delegate: Item {
                    implicitWidth: root.dayCellSize
                    implicitHeight: 22

                    StyledText {
                        anchors.fill: parent
                        text: Translation.tr(modelData.day)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // ------------------------------------------------------
        // Stable six-week grid. This avoids popup height jumps.
        // ------------------------------------------------------
        Repeater {
            model: 6

            delegate: RowLayout {
                id: weekRow

                property int weekIndex: index

                Layout.alignment: Qt.AlignHCenter
                spacing: root.cellGap

                Repeater {
                    model: 7

                    delegate: CalendarDayButton {
                        readonly property var cell:
                            root.calendarLayout[weekRow.weekIndex][index]

                        day: cell.day.toString()
                        dayState: cell.today
                        selected: root.sameDay(
                            cell.date,
                            root.selectedDate
                        )
                        accessibleName:
                            cell.date.toLocaleDateString(
                                Qt.locale(),
                                "dddd, MMMM d, yyyy"
                            )

                        onDateClicked:
                            root.selectDate(cell.date)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        // ------------------------------------------------------
        // Selected date: useful context instead of a passive grid.
        // ------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: selectedDateRow.implicitHeight + 16

            radius: Appearance.radius.card
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            RowLayout {
                id: selectedDateRow

                anchors {
                    fill: parent
                    margins: 8
                }
                spacing: 8

                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: height / 2
                    color: Appearance.colors.colSecondaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "calendar_today"
                        iconSize: 18
                        fill: 1
                        color:
                            Appearance.colors.colOnSecondaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.relativeLabel()
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text:
                            root.selectedDate.toLocaleDateString(
                                Qt.locale(),
                                "dddd, MMMM d, yyyy"
                            )
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text:
                            Translation.tr("Day %1 of %2")
                                .arg(root.selectedDayOfYear)
                                .arg(root.selectedYearLength)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                Rectangle {
                    implicitWidth: weekText.implicitWidth + 12
                    implicitHeight: 24
                    radius: height / 2
                    color: Appearance.colors.colLayer2

                    StyledText {
                        id: weekText
                        anchors.centerIn: parent
                        text:
                            Translation.tr("W%1")
                                .arg(root.selectedWeek)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        // ------------------------------------------------------
        // Useful actions. Capabilities are detected at install time;
        // unavailable actions are not shown as dead controls.
        // ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            CalendarActionButton {
                Layout.fillWidth: true
                iconName: "today"
                label: Translation.tr("Today")
                prominent:
                    !root.sameDay(root.selectedDate, root.now)
                onClicked: root.goToday()
            }

            CalendarActionButton {
                visible: root.clipboardExecutable.length > 0
                Layout.fillWidth: true
                iconName: root.copied ? "check" : "content_copy"
                label:
                    root.copied
                        ? Translation.tr("Copied")
                        : Translation.tr("Copy")
                accessibleName: Translation.tr("Copy selected date")
                onClicked: root.copySelectedDate()
            }

            CalendarActionButton {
                visible: root.calendarExecutable.length > 0
                Layout.fillWidth: true
                iconName: "open_in_new"
                label: Translation.tr("Open")
                accessibleName: Translation.tr("Open calendar application")
                onClicked: root.openCalendar()
            }
        }
    }
}
