const weekDays = [
    { day: "Mo" },
    { day: "Tu" },
    { day: "We" },
    { day: "Th" },
    { day: "Fr" },
    { day: "Sa" },
    { day: "Su" }
];

function getDateInXMonthsTime(offset) {
    const now = new Date();

    if (offset === 0)
        return now;

    return new Date(now.getFullYear(), now.getMonth() + offset, 1);
}

function sameCalendarDay(a, b) {
    return a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate();
}

function getCalendarLayout(viewingDate, highlightToday) {
    const view = viewingDate || new Date();
    const year = view.getFullYear();
    const month = view.getMonth();
    const firstOfMonth = new Date(year, month, 1);

    // JavaScript: Sunday=0. Calendar UI: Monday=0.
    const firstWeekday = (firstOfMonth.getDay() + 6) % 7;
    const today = new Date();
    const calendar = [];

    for (let week = 0; week < 6; ++week) {
        const row = [];

        for (let weekday = 0; weekday < 7; ++weekday) {
            const cellIndex = week * 7 + weekday;
            const cellDate = new Date(
                year,
                month,
                1 - firstWeekday + cellIndex
            );
            const currentMonth = cellDate.getMonth() === month
                && cellDate.getFullYear() === year;
            const isToday = highlightToday
                && sameCalendarDay(cellDate, today);

            row.push({
                day: cellDate.getDate(),
                date: cellDate,
                currentMonth: currentMonth,
                today: isToday ? 1 : (currentMonth ? 0 : -1)
            });
        }

        calendar.push(row);
    }

    return calendar;
}
