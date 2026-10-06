import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property bool borderless:
        Config.options.bar.borderless

    // Compatibility property:
    // BarContent.qml assigns this property.
    // We intentionally do not render the date in this widget.
    property bool showDate: false

    property bool calendarOpen: false

    implicitWidth: timeText.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    StyledText {
        id: timeText

        anchors.centerIn: parent
        anchors.verticalCenterOffset:
            Appearance.inlayMode ? 1 : 0

        font.pixelSize:
            Appearance.inlayMode
                ? Appearance.font.pixelSize.small
                : Appearance.font.pixelSize.normal

        font.weight:
            Font.DemiBold

        color:
            Appearance.colors.colOnLayer1

        text:
            DateTime.time
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        onClicked:
            root.calendarOpen = !root.calendarOpen

        ClockWidgetPopup {
            hoverTarget: mouseArea
            showOnHover: false
            forceActive: root.calendarOpen
            dismissOnOutsideClick: true

            onDismissRequested:
                root.calendarOpen = false
        }
    }
}
