import QtQuick
import QtQuick.Effects
import qs.modules.common

// prism-v2-phase2a: isolated Prism elevation primitive.
// It is intentionally Prism-only so Fluid's proven shadow/material path stays untouched.
Item {
    id: root

    property int depth: Appearance.prism.depthPersistent
    property real surfaceRadius: Appearance.prism.radiusPersistent
    property bool elevated: true
    property int borderWidth: 1
    property real surfaceOpacity: 1.0
    // prism-v2-phase2b: state is expressed at the owning surface level.
    property bool hovered: false
    property bool active: false

    readonly property color baseFill:
        depth >= Appearance.prism.depthModal
            ? Appearance.prism.modalFill
            : depth >= Appearance.prism.depthTransient
                ? Appearance.prism.transientFill
                : depth >= Appearance.prism.depthInteractive
                    ? Appearance.prism.interactiveFill
                    : Appearance.prism.persistentFill

    readonly property color resolvedFill:
        depth === Appearance.prism.depthPersistent && active
            ? Appearance.prism.persistentActiveFill
            : depth === Appearance.prism.depthPersistent && hovered
                ? Appearance.prism.persistentHoverFill
                : baseFill

    readonly property color resolvedBorder:
        active
            ? Appearance.prism.focusBorder
            : depth >= Appearance.prism.depthInteractive
                ? Appearance.prism.borderStrong
                : Appearance.prism.borderSubtle

    readonly property color resolvedShadow:
        depth >= Appearance.prism.depthModal
            ? Appearance.prism.shadowModal
            : depth >= Appearance.prism.depthTransient
                ? Appearance.prism.shadowTransient
                : depth >= Appearance.prism.depthInteractive
                    ? Appearance.prism.shadowInteractive
                    : Appearance.prism.shadowPersistent

    readonly property int resolvedShadowBlur:
        depth >= Appearance.prism.depthModal
            ? Appearance.prism.shadowBlurModal
            : depth >= Appearance.prism.depthTransient
                ? Appearance.prism.shadowBlurTransient
                : depth >= Appearance.prism.depthInteractive
                    ? Appearance.prism.shadowBlurInteractive
                    : Appearance.prism.shadowBlurPersistent

    readonly property int resolvedShadowOffset:
        depth >= Appearance.prism.depthModal
            ? Appearance.prism.shadowOffsetModal
            : depth >= Appearance.prism.depthTransient
                ? Appearance.prism.shadowOffsetTransient
                : depth >= Appearance.prism.depthInteractive
                    ? Appearance.prism.shadowOffsetInteractive
                    : Appearance.prism.shadowOffsetPersistent

    // prism-v2-phase2a1: a wide, quiet ambient shadow establishes the
    // persistent plane without turning the islands into glowing pills.
    RectangularShadow {
        visible: root.elevated
        anchors.fill: surface
        radius: surface.radius
        blur: Math.round(root.resolvedShadowBlur * 1.55)
        offset: Qt.vector2d(0, root.resolvedShadowOffset + 2)
        spread: 0
        color: Qt.rgba(
            root.resolvedShadow.r,
            root.resolvedShadow.g,
            root.resolvedShadow.b,
            root.resolvedShadow.a * 0.42
        )
        cached: true
    }

    RectangularShadow {
        visible: root.elevated
        anchors.fill: surface
        radius: surface.radius
        blur: root.resolvedShadowBlur
        offset: Qt.vector2d(0, root.resolvedShadowOffset)
        spread: 0
        color: root.resolvedShadow
        cached: true
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.surfaceRadius
        color: root.resolvedFill
        opacity: root.surfaceOpacity
        border.width: root.borderWidth
        border.color: root.resolvedBorder
        antialiasing: true

        Behavior on color {
            MotionColorAnim {
                type: MotionColorAnim.FastEffects
            }
        }
    }
}
