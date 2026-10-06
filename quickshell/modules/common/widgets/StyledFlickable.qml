import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root

    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    // Qt 6.9+: desktop users normally scroll with wheel/touchpad/scrollbar.
    // Disabling mouse-button dragging prevents accidental content drags while
    // preserving touch flicking and wheel/trackpad scrolling.
    acceptedButtons: Qt.NoButton

    property real touchpadScrollFactor:
        Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor:
        Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold:
        Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

    // Coarse mouse-wheel events get a short eased animation. Precision
    // touchpad events stay 1:1 with the gesture so they never feel "behind".
    property real scrollTargetY: 0
    readonly property int wheelAnimationDuration: 135

    function clampedContentY(value: real): real {
        const maxY = Math.max(0, root.contentHeight - root.height)
        return Math.max(0, Math.min(value, maxY))
    }

    function syncScrollTarget(): void {
        if (!wheelAnimation.running)
            root.scrollTargetY = root.contentY
    }

    ScrollBar.vertical: StyledScrollBar {}

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        // Preserve the existing user preference: when disabled, Flickable
        // handles wheel/trackpad scrolling natively.
        visible:
            Config?.options.interactions.scrolling.fasterTouchpadScroll ?? false

        onWheel: function(event) {
            const pixelY = event.pixelDelta.y
            const angleY = event.angleDelta.y

            if (pixelY === 0 && angleY === 0) {
                event.accepted = false
                return
            }

            // High-resolution touchpads can provide pixelDelta. Use it
            // directly: adding animation here makes the surface trail behind
            // the user's fingers.
            if (pixelY !== 0) {
                wheelAnimation.stop()

                const precisionScale =
                    Math.max(0.01, root.touchpadScrollFactor / 100.0)
                const nextY = root.clampedContentY(
                    root.contentY - pixelY * precisionScale
                )

                root.contentY = nextY
                root.scrollTargetY = nextY
                event.accepted = true
                return
            }

            const threshold = Math.max(1, root.mouseScrollDeltaThreshold)
            const normalizedDelta = angleY / threshold

            // Fine angle deltas are characteristic of precision wheels and
            // many Wayland touchpads. Keep them direct and continuous.
            if (Math.abs(angleY) < threshold) {
                wheelAnimation.stop()

                const nextY = root.clampedContentY(
                    root.contentY
                    - normalizedDelta * root.touchpadScrollFactor
                )

                root.contentY = nextY
                root.scrollTargetY = nextY
                event.accepted = true
                return
            }

            // Traditional wheel notch: accumulate the destination so rapid
            // wheel input remains responsive, but animate the visible motion
            // from the current rendered position.
            const base = wheelAnimation.running
                ? root.scrollTargetY
                : root.contentY

            root.scrollTargetY = root.clampedContentY(
                base - normalizedDelta * root.mouseScrollFactor
            )

            wheelAnimation.stop()
            wheelAnimation.from = root.contentY
            wheelAnimation.to = root.scrollTargetY
            wheelAnimation.start()

            event.accepted = true
        }
    }

    NumberAnimation {
        id: wheelAnimation

        target: root
        property: "contentY"
        duration: root.wheelAnimationDuration
        easing.type: Easing.OutCubic
    }

    // Dragging, scrollbar movement, native flicks, and programmatic movement
    // stay authoritative. The wheel target only follows once the custom
    // wheel animation is no longer driving contentY.
    onContentYChanged: root.syncScrollTarget()
}
