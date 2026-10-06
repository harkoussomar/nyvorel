import QtQuick
import qs.modules.common

// Phase 3B expressive spatial primitive.
//
// Prism gets a restrained OutBack entrance. Other interface styles preserve
// their existing semantic duration and Bezier curve. Exits remain deterministic
// so LayerShell unmap timers cannot cut off a spring.
NumberAnimation {
    id: root

    enum Phase {
        Enter = 0,
        Exit
    }

    property int phase: MotionExpressiveAnim.Enter

    property int standardEnterDuration: 500
    property int standardExitDuration: 220
    // prism-v2-phase6: final Prism cadence follows the semantic spatial
    // tokens rather than the older long/bouncy experimental timing.
    property int expressiveEnterDuration: Appearance.prism.enterDuration
    property int expressiveExitDuration: Appearance.prism.exitDuration

    property var standardEnterCurve:
        Appearance.animationCurves.expressiveDefaultSpatial

    property var standardExitCurve:
        Appearance.animationCurves.expressiveFastEffects

    property real overshootAmount: 1.025

    readonly property bool expressive:
        Appearance.prismMode
        && Appearance.expressiveMotion
        && !Appearance.reducedMotion

    duration: {
        if (Appearance.reducedMotion)
            return 1

        let base
        if (root.phase === MotionExpressiveAnim.Exit) {
            base =
                root.expressive
                    ? root.expressiveExitDuration
                    : root.standardExitDuration
        } else {
            base =
                root.expressive
                    ? root.expressiveEnterDuration
                    : root.standardEnterDuration
        }

        return Math.max(
            1,
            Math.round(base * Appearance.motionScale)
        )
    }

    easing.type:
        root.expressive
        && root.phase === MotionExpressiveAnim.Enter
            ? Easing.OutBack
            : Easing.BezierSpline

    easing.overshoot:
        root.expressive
        && root.phase === MotionExpressiveAnim.Enter
            ? root.overshootAmount
            : 0

    easing.bezierCurve:
        root.phase === MotionExpressiveAnim.Exit
            ? root.standardExitCurve
            : root.standardEnterCurve
}
