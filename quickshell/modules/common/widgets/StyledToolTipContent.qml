import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property string text
    property bool shown: false
    property real horizontalPadding: 10
    property real verticalPadding: 5
    property alias font: tooltipTextObject.font
    implicitWidth: tooltipTextObject.implicitWidth + 2 * root.horizontalPadding
    implicitHeight: tooltipTextObject.implicitHeight + 2 * root.verticalPadding

    property bool isVisible: backgroundRectangle.implicitHeight > 0

    Rectangle {
        id: backgroundRectangle
        anchors {
            bottom: root.bottom
            horizontalCenter: root.horizontalCenter
        }
        color:
            Appearance?.inlayMode === true
                ? Appearance.inlay.controlFill
                : Appearance?.prismMode === true
                    ? Appearance.prism.transientFill
                    : (Appearance?.colors.colTooltip ?? "#3C4043")
        radius:
            Appearance?.inlayMode === true
                ? 0
                : Appearance?.prismMode === true
                    ? Appearance.prism.radiusControl
                    : (Appearance?.rounding.verysmall ?? 7)
        border.width:
            Appearance?.inlayMode === true
                ? Appearance.inlay.borderWidth
                : Appearance?.prismMode === true ? 1 : 0
        border.color:
            Appearance?.inlayMode === true
                ? Appearance.inlay.borderControl
                : Appearance?.prismMode === true
                    ? Appearance.prism.borderStrong
                    : "transparent"
        opacity: shown ? 1 : 0
        scale:
            shown
                ? 1
                : (Appearance?.inlayMode === true
                    ? 1
                    : Appearance?.prismMode === true && !Appearance.reducedMotion ? 0.98 : 1)
        implicitWidth: shown ? (tooltipTextObject.implicitWidth + 2 * root.horizontalPadding) : 0
        implicitHeight: shown ? (tooltipTextObject.implicitHeight + 2 * root.verticalPadding) : 0
        clip: true

        Behavior on implicitWidth {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }

        StyledText {
            id: tooltipTextObject
            anchors.centerIn: parent
            text: root.text
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 14
            font.hintingPreference: Font.PreferNoHinting // Prevent shaky text
            color:
                Appearance?.inlayMode === true
                    ? Appearance.colors.colOnLayer1
                    : Appearance?.prismMode === true
                        ? Appearance.colors.colOnLayer2
                        : (Appearance?.colors.colOnTooltip ?? "#FFFFFF")
            wrapMode: Text.Wrap
        }
    }   
}

