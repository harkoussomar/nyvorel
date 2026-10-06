import QtQuick
import qs.modules.common

AnchorAnimation {
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
        SlowSpatial
    }

    property int type: MotionAnchorAnim.DefaultSpatial

    duration: {
        if (Appearance.reducedMotion)
            return 1

        let base = 500
        switch (type) {
        case MotionAnchorAnim.StandardSmall: base = 200; break
        case MotionAnchorAnim.Standard: base = 400; break
        case MotionAnchorAnim.StandardLarge: base = 600; break
        case MotionAnchorAnim.StandardExtraLarge: base = 1000; break
        case MotionAnchorAnim.EmphasizedSmall: base = 200; break
        case MotionAnchorAnim.Emphasized: base = 400; break
        case MotionAnchorAnim.EmphasizedLarge: base = 600; break
        case MotionAnchorAnim.EmphasizedExtraLarge: base = 1000; break
        case MotionAnchorAnim.FastSpatial: base = Appearance.animationCurves.expressiveFastSpatialDuration; break
        case MotionAnchorAnim.DefaultSpatial: base = Appearance.animationCurves.expressiveDefaultSpatialDuration; break
        case MotionAnchorAnim.SlowSpatial: base = Appearance.animationCurves.expressiveSlowSpatialDuration; break
        }
        return Math.max(1, Math.round(base * Appearance.motionScale))
    }

    easing.type: Easing.BezierSpline
    easing.bezierCurve: {
        switch (type) {
        case MotionAnchorAnim.FastSpatial:
            return Appearance.animationCurves.expressiveFastSpatial
        case MotionAnchorAnim.DefaultSpatial:
            return Appearance.animationCurves.expressiveDefaultSpatial
        case MotionAnchorAnim.SlowSpatial:
            return Appearance.animationCurves.expressiveSlowSpatial
        case MotionAnchorAnim.EmphasizedSmall:
        case MotionAnchorAnim.Emphasized:
        case MotionAnchorAnim.EmphasizedLarge:
        case MotionAnchorAnim.EmphasizedExtraLarge:
            return Appearance.animationCurves.emphasized
        default:
            return Appearance.animationCurves.standard
        }
    }
}
