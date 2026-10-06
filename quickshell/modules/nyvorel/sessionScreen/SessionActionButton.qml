import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button

    property string buttonIcon
    property string buttonText
    property bool keyboardDown: false
    property real size: 120

    // prism-v2-phase7: Prism session actions stay architectural rather than
    // morphing into circles. State is carried by tone + accent foreground.
    buttonRadius:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.prism.radiusInteractive
                : ((button.focus || button.down) ? size / 2 : Appearance.rounding.verylarge)
    colBackground:
        Appearance.inlayMode
            ? ((button.keyboardDown || button.focus)
                ? Appearance.inlay.selectedFill
                : Appearance.inlay.controlFill)
            : Appearance.prismMode
                ? ((button.keyboardDown || button.focus)
                    ? Appearance.prism.persistentActiveFill
                    : Appearance.prism.interactiveFill)
                : (button.keyboardDown
                    ? Appearance.colors.colSecondaryContainerActive
                    : button.focus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSecondaryContainer)
    colBackgroundHover:
        Appearance.inlayMode
            ? Appearance.inlay.hoverFill
            : Appearance.prismMode
                ? Appearance.prism.persistentHoverFill
                : Appearance.colors.colPrimary
    colRipple:
        Appearance.inlayMode
            ? Appearance.inlay.pressedFill
            : Appearance.prismMode
                ? Appearance.prism.persistentActiveFill
                : Appearance.colors.colPrimaryActive
    property color colText:
        Appearance.inlayMode
            ? ((button.down || button.keyboardDown || button.focus || button.hovered)
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer0)
            : Appearance.prismMode
                ? ((button.down || button.keyboardDown || button.focus || button.hovered)
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnLayer0)
                : ((button.down || button.keyboardDown || button.focus || button.hovered)
                    ? Appearance.m3colors.m3onPrimary
                    : Appearance.colors.colOnLayer0)

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

    background.implicitHeight: size
    background.implicitWidth: size

    Behavior on buttonRadius {
        MotionAnim {
            type: MotionAnim.FastSpatial
            duration: 220
        }
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = true
            button.clicked()
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = false
            event.accepted = true;
        }
    }

    contentItem: MaterialSymbol {
        id: icon
        anchors.fill: parent
        color: button.colText
        horizontalAlignment: Text.AlignHCenter
        iconSize: 45
        text: buttonIcon
    }

    StyledToolTip {
        text: buttonText
    }

}
