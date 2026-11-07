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

    property real buttonPadding: Config.options.bar.topLeftIcon === "nyvorel" ? 6 : 5
    implicitWidth: distroIcon.width + buttonPadding * 2
    implicitHeight: distroIcon.height + buttonPadding * 2
    // Axiom / Fluid: compact precision hover surface.
    buttonRadius: Appearance.barLayout.axiomComponents
        ? Appearance.rounding.small : Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarLeftOpen

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
        width: Config.options.bar.topLeftIcon === "nyvorel"
            ? brandName.implicitWidth : 20
        height: Config.options.bar.topLeftIcon === "nyvorel" ? 24 : 20

        StyledText {
            id: brandName
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Config.options.bar.topLeftIcon === "nyvorel"
            text: "Nyvorel"
            color: Appearance.colors.colOnLayer0
            font.pixelSize: 14
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
        }

        Rectangle {
            visible: brandName.visible
            anchors.left: brandName.left
            anchors.bottom: parent.bottom
            width: 23
            height: 2
            radius: 1
            color: Appearance.colors.colPrimary
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
