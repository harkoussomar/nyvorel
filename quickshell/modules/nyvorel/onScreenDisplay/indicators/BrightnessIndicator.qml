import qs.services
import qs.modules.common
import qs.modules.nyvorel.onScreenDisplay

import QtQuick

import Quickshell
import Quickshell.Hyprland

OsdValueIndicator {
    id: root


    property var focusedScreen:
        Quickshell.screens.find(
            (screen) =>
                screen.name
                === Hyprland
                    .focusedMonitor
                    ?.name
        )


    property var brightnessMonitor:
        Brightness.getMonitorForScreen(
            root.focusedScreen
        )


    readonly property real brightnessValue:
        root.brightnessMonitor
            ?.brightness
            ?? 0.5


    value:
        root.brightnessValue


    name:
        Translation.tr("Brightness")


    icon: {
        // Keep a recognizable night-light state.
        if (Hyprsunset.active) {
            return "routine";
        }

        if (root.brightnessValue < 0.34) {
            return "brightness_5";
        }

        if (root.brightnessValue < 0.67) {
            return "brightness_6";
        }

        return "brightness_7";
    }


    iconBackgroundColor:
        Appearance.colors.colPrimaryContainer


    iconForegroundColor:
        Appearance.colors.colOnPrimaryContainer


    accentColor:
        Appearance.colors.colPrimary
}