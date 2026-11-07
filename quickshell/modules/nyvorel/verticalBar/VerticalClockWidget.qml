import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.nyvorel.bar as Bar

Item {
    id: root
    property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""
    property bool borderless: Config.options.bar.borderless
    readonly property bool calendarOpen: GlobalStates.isBarPopupOpen("calendar", root.barScreenName)
    implicitHeight: clockColumn.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    ColumnLayout {
        id: clockColumn
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: DateTime.time.split(/[: ]/)
            delegate: StyledText {
                required property string modelData
                Layout.alignment: Qt.AlignHCenter
                font.family: Appearance.barLayout.axiomComponents ? Appearance.font.family.monospace : Appearance.font.family.main
                font.pixelSize: Appearance.barLayout.axiomComponents ? Appearance.barVisual.axiomTextSize - 1
                    : modelData.match(/am|pm/i)
                        ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.large
                color: Appearance.barLayout.axiomComponents ? Appearance.barVisual.axiomValue : Appearance.colors.colOnLayer1
                text: modelData.padStart(2, "0")
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.toggleBarPopup("calendar", root.barScreenName)

        Bar.ClockWidgetPopup {
            hoverTarget: mouseArea
            showOnHover: false
            forceActive: root.calendarOpen
            dismissOnOutsideClick: true
            onDismissRequested: GlobalStates.closeBarPopup("calendar", root.barScreenName)
        }
    }
}
