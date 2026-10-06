import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button

    property string day: ""
    property int dayState: 0
    property bool selected: false
    property string accessibleName: day

    readonly property bool isToday: dayState === 1
    readonly property bool isOutsideMonth: dayState === -1

    signal dateClicked()

    Layout.fillWidth: false
    Layout.fillHeight: false

    implicitWidth: 34
    implicitHeight: 34

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName

    toggled: isToday || selected

    buttonRadius:
        (isToday || selected)
            ? height / 2
            : Appearance.radius.control
    buttonRadiusPressed: buttonRadius

    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    colBackgroundToggled:
        isToday
            ? Appearance.colors.colPrimary
            : Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover:
        isToday
            ? Appearance.colors.colPrimaryHover
            : Appearance.colors.colSecondaryContainerHover
    colRippleToggled:
        isToday
            ? Appearance.colors.colPrimaryActive
            : Appearance.colors.colSecondaryContainerActive

    onClicked: button.dateClicked()

    contentItem: StyledText {
        anchors.fill: parent

        text: button.day
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.weight:
            button.isToday || button.selected
                ? Font.DemiBold
                : Font.Normal

        color:
            button.isToday
                ? Appearance.colors.colOnPrimary
                : button.selected
                    ? Appearance.colors.colOnSecondaryContainer
                    : button.isOutsideMonth
                        ? Appearance.colors.colOutlineVariant
                        : Appearance.colors.colOnLayer1

        Behavior on color {
            animation:
                Appearance.animation.elementMoveFast
                    .colorAnimation.createObject(this)
        }
    }
}
