import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""

    property bool borderless:
        Config.options.bar.borderless

    // Compatibility property:
    // BarContent.qml assigns this property.
    // We intentionally do not render the date in this widget.
    property bool showDate: false
    property bool axiomMode: false

    readonly property bool calendarOpen: GlobalStates.isBarPopupOpen("calendar", root.barScreenName)

    implicitWidth: timeText.implicitWidth
    // nyvorel-phase3b-component-plane: outer floating insets are not
    // part of this clock's interactive control plane.
    implicitHeight: Appearance.barLayout.persistentHeight

    StyledText {
        id: timeText

        anchors.centerIn: parent
        anchors.verticalCenterOffset:
            0

        font.family: root.axiomMode
            ? Appearance.font.family.monospace : Appearance.font.family.main
        font.pixelSize:
            root.axiomMode ? Appearance.barVisual.axiomTextSize
                : Appearance.font.pixelSize.normal

        font.weight:
            Font.DemiBold

        color:
            Appearance.colors.colOnLayer1

        text:
            root.axiomMode
                ? Qt.locale().toString(DateTime.clock.date, "hh:mm AP")
                : DateTime.time
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        onClicked:
            GlobalStates.toggleBarPopup("calendar", root.barScreenName)

        ClockWidgetPopup {
            hoverTarget: mouseArea
            showOnHover: false
            forceActive: root.calendarOpen
            dismissOnOutsideClick: true

            onDismissRequested:
                GlobalStates.closeBarPopup("calendar", root.barScreenName)
        }
    }
}
