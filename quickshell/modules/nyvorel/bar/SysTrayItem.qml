import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

MouseArea {
    id: root
    required property SystemTrayItem item
    property bool axiomMode: false
    property bool targetMenuOpen: false

    signal menuOpened(qsWindow: var)
    signal menuClosed()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: root.axiomMode ? 23 : 20
    implicitHeight: root.axiomMode ? 23 : 20
    onPressed: (event) => {
        switch (event.button) {
        case Qt.LeftButton:
            item.activate();
            break;
        case Qt.RightButton:
            if (item.hasMenu) menu.open();
            break;
        }
        event.accepted = true;
    }
    onEntered: {
        tooltip.text = TrayService.getTooltipForItem(root.item);
    }

    Loader {
        id: menu
        function open() {
            menu.active = true;
        }
        active: false
        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open();
            trayItemMenuHandle: root.item.menu
            anchor {
                window: root.QsWindow.window
                rect.x: root.x + (Config.options.bar.vertical ? 0 : QsWindow.window?.width)
                rect.y: root.y + (Config.options.bar.vertical ? QsWindow.window?.height : 0)
                rect.height: root.height
                rect.width: root.width
                edges: Config.options.bar.bottom ? (Edges.Top | Edges.Left) : (Edges.Bottom | Edges.Right)
                gravity: Config.options.bar.bottom ? (Edges.Top | Edges.Left) : (Edges.Bottom | Edges.Right)
            }
            onMenuOpened: (window) => root.menuOpened(window);
            onMenuClosed: {
                root.menuClosed();
                menu.active = false;
            }
        }
    }

    // Axiom integration: real application icons sit directly on Fluid.
    // No framed tray tile; existing mouse target and menu behavior remain.
    // Keep the horizontal underline; it reads as a stray dot in the vertical rail.
    Rectangle {
        visible: root.axiomMode && !Config.options.bar.vertical
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -3
        width: 3
        height: 2
        color: Appearance.barVisual.axiomBatteryAccent
        z: 2
    }

    IconImage {
        id: trayIcon
        visible: !Config.monochromeAppIcons
        source: root.item.icon
        anchors.centerIn: parent
        width: root.axiomMode ? Appearance.barVisual.axiomTrayIconSize : parent.width
        height: root.axiomMode ? Appearance.barVisual.axiomTrayIconSize : parent.height
    }

    Loader {
        active: Config.monochromeAppIcons
        anchors.fill: trayIcon
        sourceComponent: Desaturate {
            anchors.fill: parent
            source: trayIcon
            desaturation: 1.0
        }
    }

    PopupToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
    }

}
