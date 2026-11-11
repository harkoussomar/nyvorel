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
    implicitWidth: root.vertical ? 30 : rowLayout.implicitWidth + 10 * 2
    implicitHeight: root.vertical ? 30 : Appearance.sizes.barHeight

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton)
            GlobalStates.toggleBarPopup("weather", root.barScreenName)
    }

    onPressed: {
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

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent

        MaterialSymbol {
            fill: 0
            text: Weather.ready
                ? (Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud") : "cloud"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            visible: !root.vertical
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: Weather.ready ? Weather.data.temp : "--°"
            Layout.alignment: Qt.AlignVCenter
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
