pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import Quickshell
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false
    readonly property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""
    readonly property bool popupPinned: GlobalStates.isBarPopupOpen("weather", root.barScreenName)
    implicitWidth: root.vertical ? Math.max(30, weatherLayout.implicitWidth) : weatherLayout.implicitWidth + 10 * 2
    implicitHeight: root.vertical ? Math.max(30, weatherLayout.implicitHeight + 4)
        : Appearance.barLayout.persistentHeight

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    Component.onDestruction: {
        if (root.popupPinned)
            GlobalStates.closeBarPopup("weather", root.barScreenName)
    }

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton)
            GlobalStates.toggleBarPopup("weather", root.barScreenName)
    }

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton) {
            Weather.getData();
            Quickshell.execDetached(["notify-send", 
                Translation.tr("Weather"), 
                Translation.tr("Refreshing (manually triggered)")
                , "-a", "Shell"
            ])
            mouse.accepted = false
        }
    }

    GridLayout {
        id: weatherLayout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        rowSpacing: 1

        MaterialSymbol {
            fill: 0
            text: Weather.ready
                ? (Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud") : "cloud"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
            Layout.alignment: Qt.AlignCenter
        }

        StyledText {
            font.pixelSize: root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: Weather.ready ? Weather.data.temp : "--°"
            Layout.alignment: Qt.AlignCenter
        }
    }

    WeatherPopup {
        id: weatherPopup
        hoverTarget: root
        showOnHover: !Config.options.bar.tooltips.clickToShow
        forceActive: root.popupPinned
        dismissOnOutsideClick: true
        onDismissRequested: GlobalStates.closeBarPopup("weather", root.barScreenName)
    }
}
