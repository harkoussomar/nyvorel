import qs
import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.modules.nyvorel.bar as Bar

MouseArea {
    id: root
    property string barScreenName: root.QsWindow?.window?.screen?.name ?? ""
    property bool alwaysShowAllResources: false
    readonly property bool popupPinned: GlobalStates.isBarPopupOpen("resources", root.barScreenName)
    implicitHeight: columnLayout.implicitHeight
    implicitWidth: columnLayout.implicitWidth
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: GlobalStates.toggleBarPopup("resources", root.barScreenName)

    ColumnLayout {
        id: columnLayout
        spacing: Appearance.barLayout.axiomComponents ? 5 : 10
        anchors.fill: parent

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "swap_horiz"
            visible: !Appearance.barLayout.axiomComponents || (ResourceUsage.swapUsedPercentage * 100 >= Config.options.bar.resources.swapWarningThreshold)
            percentage: ResourceUsage.swapUsedPercentage
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: Appearance.barLayout.axiomComponents ? "developer_board" : "planner_review"
            percentage: ResourceUsage.cpuUsage
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }

    }

    Bar.ResourcesPopup {
        hoverTarget: root
        showOnHover: false
        forceActive: root.popupPinned
        onCloseRequested: GlobalStates.closeBarPopup("resources", root.barScreenName)
    }
}
