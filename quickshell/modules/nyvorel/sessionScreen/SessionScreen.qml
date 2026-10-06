import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property var focusedScreen:
        Quickshell.screens.find(
            s => s.name === Hyprland.focusedMonitor?.name
        )

    // phase2e-session-presentation-v1
    // Separate requested state from mapped state so exit motion can finish.
    property bool sessionMapped: false
    property bool sessionShown: false
    property bool sessionClosing: false

    function openSessionPresentation() {
        sessionCloseTimer.stop()
        root.sessionMapped = true
        root.sessionClosing = false

        Qt.callLater(() => {
            if (GlobalStates.sessionOpen)
                root.sessionShown = true
        })
    }

    function closeSessionPresentation() {
        if (!root.sessionMapped)
            return

        root.sessionClosing = true
        root.sessionShown = false
        sessionCloseTimer.restart()
    }

    Component.onCompleted: {
        if (GlobalStates.sessionOpen)
            root.openSessionPresentation()
    }

    Connections {
        target: GlobalStates

        function onSessionOpenChanged() {
            if (GlobalStates.sessionOpen)
                root.openSessionPresentation()
            else
                root.closeSessionPresentation()
        }
    }

    Timer {
        id: sessionCloseTimer
        interval: 260
        repeat: false

        onTriggered: {
            if (!GlobalStates.sessionOpen) {
                root.sessionMapped = false
                root.sessionClosing = false
            }
        }
    }

    Loader {
        id: sessionLoader
        active: root.sessionMapped
        onActiveChanged: {
            if (sessionLoader.active)
                SessionWarnings.refresh();
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    GlobalStates.sessionOpen = false;
                }
            }
        }

        sourceComponent: PanelWindow { // Session menu
            id: sessionRoot
            visible: sessionLoader.active

            property string subtitle

            function syncShellCaptureRegion(): void {
                const paddingX = 28
                const paddingY = 22

                if (
                    !GlobalStates.sessionOpen
                    || !sessionRoot.screen
                    || contentColumn.width <= 0
                    || contentColumn.height <= 0
                ) {
                    GlobalStates.clearCaptureRegion("session")
                    return
                }

                GlobalStates.registerCaptureRegion(
                    "session",
                    sessionRoot.screen.name,
                    Math.max(0, contentColumn.x - paddingX),
                    Math.max(0, contentColumn.y - paddingY),
                    Math.min(
                        sessionRoot.width,
                        contentColumn.width + paddingX * 2
                    ),
                    Math.min(
                        sessionRoot.height,
                        contentColumn.height + paddingY * 2
                    ),
                    155,
                    "Session Screen"
                )
            }

            onVisibleChanged:
                Qt.callLater(
                    () => sessionRoot.syncShellCaptureRegion()
                )

            onScreenChanged:
                Qt.callLater(
                    () => sessionRoot.syncShellCaptureRegion()
                )

            Connections {
                target: GlobalStates

                function onSessionOpenChanged() {
                    Qt.callLater(
                        () => sessionRoot.syncShellCaptureRegion()
                    )
                }
            }

            Component.onDestruction:
                GlobalStates.clearCaptureRegion("session")

            function hide() {
                GlobalStates.sessionOpen = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            // session-snip-blur-v1
            WlrLayershell.keyboardFocus:
                (
                    GlobalStates.regionSelectorOpen
                    || !root.sessionShown
                )
                    ? WlrKeyboardFocus.None
                    : WlrKeyboardFocus.Exclusive
            // Fluid session substrate matches Kitty exactly: #101315 at 60%
            // opacity. Other interface styles keep the existing session tint.
            color:
                Appearance.inlayMode
                    ? Appearance.inlay.baseFill
                    : Appearance.fluidMode
                        ? ColorUtils.transparentize("#101315", 0.40)
                        : ColorUtils.transparentize(
                            Appearance.m3colors.m3background,
                            Appearance.m3colors.darkmode ? 0.72 : 0.62
                        )

            anchors {
                top: true
                left: true
                right: true
            }

            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0

            // prism-v2-phase7: Session is a focused depth-4 object above the
            // dimmed canvas. The legacy full-screen substrate remains untouched.
            PrismSurface {
                visible: Appearance.prismMode && root.sessionMapped
                anchors.centerIn: parent
                width: contentColumn.width + 56
                height: contentColumn.height + 48
                depth: Appearance.prism.depthModal
                surfaceRadius: Appearance.prism.radiusModal
                elevated: true
                opacity: contentColumn.opacity
                scale: contentColumn.scale
                transformOrigin: Item.Center
                transform: Translate { y: sessionContentShift.y }
            }

            MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                onClicked: {
                    sessionRoot.hide();
                }
            }

            ColumnLayout { // Content column
                id: contentColumn

                anchors.centerIn: parent
                spacing: 15

                // phase2e-session-opacity-hotfix-v1
                // PanelWindow has no opacity property in Quickshell.
                // Fade the visual content Item instead while keeping the
                // mapped/shown lifecycle and spatial choreography intact.
                opacity:
                    root.sessionShown ? 1 : 0

                Behavior on opacity {
                    MotionAnim {
                        type:
                            root.sessionClosing
                                ? MotionAnim.FastEffects
                                : MotionAnim.DefaultEffects
                        duration: root.sessionClosing ? 180 : 200
                    }
                }

                scale:
                    Appearance.inlayMode
                        ? 1
                        : root.sessionShown
                            ? 1
                            : (
                                root.sessionClosing
                                    ? 0.985
                                    : (Appearance.prismMode ? Appearance.prism.enterScale : 0.970)
                            )

                transform: Translate {
                    id: sessionContentShift

                    y:
                        root.sessionShown
                            ? 0
                            : (
                                root.sessionClosing
                                    ? (Appearance.inlayMode ? Appearance.inlay.enterDistance : 18)
                                    : (Appearance.inlayMode
                                        ? Appearance.inlay.enterDistance
                                        : Appearance.prismMode ? Appearance.prism.enterDistance * 2 : 34)
                            )

                    Behavior on y {
                        MotionExpressiveAnim {
                            phase:
                                root.sessionClosing
                                    ? MotionExpressiveAnim.Exit
                                    : MotionExpressiveAnim.Enter
                        }
                    }
                }

                Behavior on scale {
                    MotionExpressiveAnim {
                        phase:
                            root.sessionClosing
                                ? MotionExpressiveAnim.Exit
                                : MotionExpressiveAnim.Enter
                    }
                }

                onXChanged:
                    sessionRoot.syncShellCaptureRegion()
                onYChanged:
                    sessionRoot.syncShellCaptureRegion()
                onWidthChanged:
                    sessionRoot.syncShellCaptureRegion()
                onHeightChanged:
                    sessionRoot.syncShellCaptureRegion()

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        sessionRoot.hide();
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 0
                    StyledText {
                        // Title
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        text: Translation.tr("Session")
                    }

                    StyledText {
                        // Small instruction
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: Translation.tr("Arrow keys to navigate, Enter to select\nEsc or click anywhere to cancel")
                    }
                }

                GridLayout {
                    columns: 4
                    columnSpacing: 15
                    rowSpacing: 15

                    SessionActionButton {
                        id: sessionLock
                        focus: sessionRoot.visible
                        buttonIcon: "lock"
                        buttonText: Translation.tr("Lock")
                        onClicked: {
                            Session.lock();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.right: sessionSleep
                        KeyNavigation.down: sessionHibernate
                    }
                    SessionActionButton {
                        id: sessionSleep
                        buttonIcon: "dark_mode"
                        buttonText: Translation.tr("Sleep")
                        onClicked: {
                            Session.suspend();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionLock
                        KeyNavigation.right: sessionLogout
                        KeyNavigation.down: sessionShutdown
                    }
                    SessionActionButton {
                        id: sessionLogout
                        buttonIcon: "logout"
                        buttonText: Translation.tr("Logout")
                        onClicked: {
                            Session.logout();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionSleep
                        KeyNavigation.right: sessionTaskManager
                        KeyNavigation.down: sessionReboot
                    }
                    SessionActionButton {
                        id: sessionTaskManager
                        buttonIcon: "browse_activity"
                        buttonText: Translation.tr("Task Manager")
                        onClicked: {
                            Session.launchTaskManager();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionLogout
                        KeyNavigation.down: sessionFirmwareReboot
                    }

                    SessionActionButton {
                        id: sessionHibernate
                        buttonIcon: "downloading"
                        buttonText: Translation.tr("Hibernate")
                        onClicked: {
                            Session.hibernate();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionLock
                        KeyNavigation.right: sessionShutdown
                    }
                    SessionActionButton {
                        id: sessionShutdown
                        buttonIcon: "power_settings_new"
                        buttonText: Translation.tr("Shutdown")
                        onClicked: {
                            Session.poweroff();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionHibernate
                        KeyNavigation.right: sessionReboot
                        KeyNavigation.up: sessionSleep
                    }
                    SessionActionButton {
                        id: sessionReboot
                        buttonIcon: "restart_alt"
                        buttonText: Translation.tr("Reboot")
                        onClicked: {
                            Session.reboot();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionShutdown
                        KeyNavigation.right: sessionFirmwareReboot
                        KeyNavigation.up: sessionLogout
                    }
                    SessionActionButton {
                        id: sessionFirmwareReboot
                        buttonIcon: "settings_applications"
                        buttonText: Translation.tr("Reboot to firmware settings")
                        onClicked: {
                            Session.rebootToFirmware();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionTaskManager
                        KeyNavigation.left: sessionReboot
                    }
                }

                DescriptionLabel {
                    Layout.alignment: Qt.AlignHCenter
                    text: sessionRoot.subtitle
                }
            }

            ColumnLayout {
                anchors {
                    top: contentColumn.bottom
                    topMargin: 10
                    horizontalCenter: contentColumn.horizontalCenter
                }
                spacing: 10

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.downloadRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("There might be a download in progress. Check your Downloads folder.")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.packageManagerRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("Your package manager is running")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }
            }
        }
    }

    component DescriptionLabel: Rectangle {
        id: descriptionLabel
        property string text
        property color textColor: Appearance.colors.colOnTooltip
        color: Appearance.inlayMode ? Appearance.inlay.controlFill : Appearance.colors.colTooltip
        clip: true
        radius: Appearance.inlayMode ? 0 : Appearance.rounding.normal
        border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
        border.color: Appearance.inlayMode ? Appearance.inlay.borderControl : "transparent"
        implicitHeight: descriptionLabelText.implicitHeight + 10 * 2
        implicitWidth: descriptionLabelText.implicitWidth + 15 * 2

        Behavior on implicitWidth {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }

        StyledText {
            id: descriptionLabelText
            anchors.centerIn: parent
            color: descriptionLabel.textColor
            text: descriptionLabel.text
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }

        function close(): void {
            GlobalStates.sessionOpen = false;
        }

        function open(): void {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = false;
        }
    }
}
