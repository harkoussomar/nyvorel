import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property alias color: bell.color
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    implicitWidth: bell.implicitWidth + (badge.visible && showUnreadCount
        ? badge.implicitWidth - 4 : 0)
    implicitHeight: Math.max(bell.implicitHeight, badge.visible ? badge.implicitHeight : 0)
    Accessible.name: Notifications.unread > 0
        ? Translation.tr("Unread notifications: %1").arg(Notifications.unread)
        : Translation.tr("Notifications")

    MaterialSymbol {
        id: bell
        anchors.verticalCenter: parent.verticalCenter
        text: Notifications.silent ? "notifications_paused" : "notifications"
        iconSize: Appearance.barVisual.axiomIconSize
        color: Appearance.colors.colOnLayer0
    }

    Rectangle {
        id: badge
        visible: !Notifications.silent && Notifications.unread > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: root.showUnreadCount ? 0 : 1
        anchors.topMargin: root.showUnreadCount ? 0 : 3
        radius: Appearance.rounding.full
        color: root.showUnreadCount ? Appearance.colors.colPrimaryContainer : Appearance.barVisual.axiomBatteryAccent
        implicitHeight: root.showUnreadCount ? Math.max(12, count.implicitHeight + 2) : 8
        implicitWidth: root.showUnreadCount ? Math.max(implicitHeight, count.implicitWidth + 6) : 8
        width: implicitWidth
        height: implicitHeight

        StyledText {
            id: count
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnPrimaryContainer
            text: Notifications.unread > 99 ? "99+" : String(Notifications.unread)
        }
    }
}
