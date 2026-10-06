import qs.services
import qs.modules.common
import qs.modules.nyvorel.onScreenDisplay

import QtQuick

OsdValueIndicator {
    id: root


    readonly property real volume:
        Audio.sink?.audio?.volume ?? 0


    readonly property bool isMuted:
        Audio.sink?.audio?.muted ?? false


    readonly property bool overAmplified:
        !root.isMuted
        && root.volume > 1


    value:
        root.volume


    muted:
        root.isMuted


    boosted:
        root.overAmplified


    name:
        Translation.tr("Volume")


    icon: {
        if (
            root.isMuted
            || root.volume <= 0
        ) {
            return "volume_off";
        }


        if (root.volume < 0.34) {
            return "volume_down";
        }


        if (root.overAmplified) {
            return "volume_up";
        }


        return "volume_up";
    }


    // =========================================================
    // Icon container
    // =========================================================

    iconBackgroundColor:
        root.isMuted

            ? Appearance.colors.colLayer3

            : root.overAmplified

                ? Appearance.colors.colErrorContainer

                : Appearance.colors.colPrimaryContainer


    // =========================================================
    // Icon
    // =========================================================

    iconForegroundColor:
        root.isMuted

            ? Appearance.colors.colSubtext

            : root.overAmplified

                ? Appearance.colors.colOnErrorContainer

                : Appearance.colors.colOnPrimaryContainer


    // =========================================================
    // Progress
    // =========================================================

    accentColor:
        root.overAmplified

            ? Appearance.colors.colError

            : Appearance.colors.colPrimary
}