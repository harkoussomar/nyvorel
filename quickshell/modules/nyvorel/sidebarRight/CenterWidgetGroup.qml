import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.nyvorel.sidebarRight.notifications
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    radius:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.prism.radiusCard
                : Appearance.rounding.normal
    color:
        (Appearance.prismMode || Appearance.inlayMode)
            ? "transparent"
            : Appearance.colors.colLayer1

    NotificationList {
        anchors.fill: parent
        anchors.margins: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 5
    }
}
