import QtQuick
import qs.modules.common

// Semantic animation primitive inspired by Caelestia's Anim.qml.
// Components declare motion intent instead of hard-coding timing/easing.
NumberAnimation {
    id: root

    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: MotionAnim.DefaultSpatial

    duration: {
        if (Appearance.reducedMotion)
            return 1

        let base = 500
        switch (type) {
        case MotionAnim.StandardSmall: base = 200; break
        case MotionAnim.Standard: base = 400; break
        case MotionAnim.StandardLarge: base = 600; break
        case MotionAnim.StandardExtraLarge: base = 1000; break
        case MotionAnim.EmphasizedSmall: base = 200; break
        case MotionAnim.Emphasized: base = 400; break
        case MotionAnim.EmphasizedLarge: base = 600; break
        case MotionAnim.EmphasizedExtraLarge: base = 1000; break
        case MotionAnim.FastSpatial: base = Appearance.animationCurves.expressiveFastSpatialDuration; break
        case MotionAnim.DefaultSpatial: base = Appearance.animationCurves.expressiveDefaultSpatialDuration; break
        case MotionAnim.SlowSpatial: base = Appearance.animationCurves.expressiveSlowSpatialDuration; break
        case MotionAnim.FastEffects: base = Appearance.animationCurves.expressiveFastEffectsDuration; break
        case MotionAnim.DefaultEffects: base = Appearance.animationCurves.expressiveDefaultEffectsDuration; break
        case MotionAnim.SlowEffects: base = Appearance.animationCurves.expressiveSlowEffectsDuration; break
        }
        return Math.max(1, Math.round(base * Appearance.motionScale))
    }

    easing.type: Easing.BezierSpline
    easing.bezierCurve: {
        switch (type) {
        case MotionAnim.FastSpatial:
            return Appearance.animationCurves.expressiveFastSpatial
        case MotionAnim.DefaultSpatial:
            return Appearance.animationCurves.expressiveDefaultSpatial
        case MotionAnim.SlowSpatial:
            return Appearance.animationCurves.expressiveSlowSpatial
        case MotionAnim.FastEffects:
            return Appearance.animationCurves.expressiveFastEffects
        case MotionAnim.DefaultEffects:
            return Appearance.animationCurves.expressiveDefaultEffects
        case MotionAnim.SlowEffects:
            return Appearance.animationCurves.expressiveSlowEffects
        case MotionAnim.EmphasizedSmall:
        case MotionAnim.Emphasized:
        case MotionAnim.EmphasizedLarge:
        case MotionAnim.EmphasizedExtraLarge:
            return Appearance.animationCurves.emphasized
        default:
            return Appearance.animationCurves.standard
        }
    }
}
