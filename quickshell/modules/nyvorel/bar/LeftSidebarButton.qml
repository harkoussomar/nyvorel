import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    property bool showPing: false

    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool animeEnabled: Config.options.policies.weeb !== 0
    visible: true

    property real buttonPadding: 5
    implicitWidth: distroIcon.width + buttonPadding * 2
    implicitHeight: distroIcon.height + buttonPadding * 2
    // Axiom / Fluid: compact precision hover surface.
    buttonRadius: Appearance.barLayout.axiomComponents
        ? Appearance.rounding.small : Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: "transparent"
    colBackgroundToggledHover: "transparent"
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.isBarPopupOpen("operations", root.QsWindow?.window?.screen?.name)

    // nyvorel-phase1b-ripple-click-contract
    onClicked: {
        GlobalStates.toggleBarPopup("operations", root.QsWindow?.window?.screen?.name);
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    Item {
        id: distroIcon
        anchors.centerIn: parent
        width: Config.options.bar.topLeftIcon === "nyvorel" ? 26 : 20
        height: Config.options.bar.topLeftIcon === "nyvorel" ? 26 : 20

        Loader {
            anchors.centerIn: parent
            width: 22
            height: 22
            active: Config.options.bar.topLeftIcon === "nyvorel"
            sourceComponent: IconImage {
                anchors.fill: parent
                rotation: root.toggled ? 16 : 0
                Behavior on rotation {
                    NumberAnimation {
                        duration: Appearance.reducedMotion ? 0 : 280
                        easing.type: Easing.OutCubic
                    }
                }
                source: "file://" + Quickshell.shellPath(
                    Appearance.m3colors.darkmode
                        ? "assets/icons/nyvorel.svg"
                        : "assets/icons/nyvorel-app.svg"
                )
                backer.sourceSize: Qt.size(88, 88)
                backer.smooth: true
                mipmap: true
            }
        }

        Loader {
            anchors.fill: parent
            active: Config.options.bar.topLeftIcon !== "nyvorel"
            sourceComponent: CustomIcon {
                anchors.fill: parent
                source: Config.options.bar.topLeftIcon === "distro"
                    ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
                colorize: true
                color: Appearance.colors.colOnLayer0
            }
        }

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
