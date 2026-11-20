pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.nyvorel.background.widgets
import qs.modules.nyvorel.background.widgets.clock
import qs.modules.nyvorel.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: panelRoot
        required property var modelData

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        WallpaperImage {
            anchors.fill: parent
            sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                Math.ceil(height * Screen.devicePixelRatio))
            fallbackResolution: Math.max(1024, Math.min(4096, 1024 * Math.ceil(
                Math.max(width, height) * Screen.devicePixelRatio / 1024)))
            wallpaperPath: !GlobalStates.screenLocked && GlobalStates.wallpaperPickerScreenName === panelRoot.screen?.name
                && GlobalStates.wallpaperPreviewPath
                ? GlobalStates.wallpaperPreviewPath
                : Config.options.background.wallpaperPath
            fillMode: Image.PreserveAspectCrop
        }
    }
}
