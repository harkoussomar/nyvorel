import QtQuick
import qs.modules.common

// Color/effect counterpart to MotionAnim.
ColorAnimation {
    id: root

    enum Type {
        FastEffects = 0,
        DefaultEffects,
        SlowEffects,
        Standard,
        Emphasized
    }

    property int type: MotionColorAnim.DefaultEffects

    duration: {
        if (Appearance.reducedMotion)
            return 1

        let base = Appearance.animationCurves.expressiveDefaultEffectsDuration
        switch (type) {
        case MotionColorAnim.FastEffects:
            base = Appearance.animationCurves.expressiveFastEffectsDuration
            break
        case MotionColorAnim.DefaultEffects:
            base = Appearance.animationCurves.expressiveDefaultEffectsDuration
            break
        case MotionColorAnim.SlowEffects:
            base = Appearance.animationCurves.expressiveSlowEffectsDuration
            break
        case MotionColorAnim.Standard:
        case MotionColorAnim.Emphasized:
            base = 400
            break
        }
        return Math.max(1, Math.round(base * Appearance.motionScale))
    }

    easing.type: Easing.BezierSpline
    easing.bezierCurve: {
        switch (type) {
        case MotionColorAnim.FastEffects:
            return Appearance.animationCurves.expressiveFastEffects
        case MotionColorAnim.DefaultEffects:
            return Appearance.animationCurves.expressiveDefaultEffects
        case MotionColorAnim.SlowEffects:
            return Appearance.animationCurves.expressiveSlowEffects
        case MotionColorAnim.Emphasized:
            return Appearance.animationCurves.emphasized
        default:
            return Appearance.animationCurves.standard
        }
    }
}
