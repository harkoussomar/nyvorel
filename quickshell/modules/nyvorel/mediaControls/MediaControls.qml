pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: filterDuplicatePlayers(realPlayers)
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
    property list<real> visualizerPoints: []

    // motion-phase2c-v1
    property bool mediaControlsMapped: false
    property bool mediaControlsShown: false
    property bool mediaControlsClosing: false

    function openMediaControlsPresentation(): void {
        mediaControlsCloseTimer.stop()
        root.mediaControlsMapped = true
        root.mediaControlsClosing = false

        Qt.callLater(() => {
            if (GlobalStates.mediaControlsOpen)
                root.mediaControlsShown = true
        })
    }

    function closeMediaControlsPresentation(): void {
        if (!root.mediaControlsMapped)
            return

        root.mediaControlsClosing = true
        root.mediaControlsShown = false
        mediaControlsCloseTimer.restart()
    }

    Component.onCompleted: {
        if (GlobalStates.mediaControlsOpen)
            root.openMediaControlsPresentation()
    }

    Connections {
        target: GlobalStates

        function onMediaControlsOpenChanged(): void {
            if (GlobalStates.mediaControlsOpen)
                root.openMediaControlsPresentation()
            else
                root.closeMediaControlsPresentation()
        }
    }

    Timer {
        id: mediaControlsCloseTimer
        interval: 230
        repeat: false

        onTriggered: {
            if (!GlobalStates.mediaControlsOpen) {
                root.mediaControlsMapped = false
                root.mediaControlsClosing = false
            }
        }
    }

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Find duplicates by trackTitle prefix
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (p1.position - p2.position <= 2 && p1.length - p2.length <= 2)) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    Process {
        id: cavaProc
        running: mediaControlsLoader.active
        onRunningChanged: {
            if (!cavaProc.running) {
                root.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                // Parse `;`-separated values into the visualizerPoints array
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }

    Loader {
        id: mediaControlsLoader
        active: root.mediaControlsMapped
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: playerColumnLayout.implicitHeight
            color: "transparent"
            // glass-system-v2.3b-shape
            Region {
                id: glassMediaVisibleMask
                item: playerColumnLayout
            }
            HyprlandWindow.visibleMask:
                Config.options.appearance.transparency.enable
                    ? glassMediaVisibleMask
                    : null

            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: !Config.options.bar.bottom || Config.options.bar.vertical
                bottom: Config.options.bar.bottom && !Config.options.bar.vertical
                left: !(Config.options.bar.vertical && Config.options.bar.bottom)
                right: Config.options.bar.vertical && Config.options.bar.bottom
            }
            margins {
                top: Config.options.bar.vertical ? ((panelWindow.screen.height / 2) - widgetHeight * 1.5) : Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
                left: Config.options.bar.vertical ? Appearance.sizes.barHeight : ((panelWindow.screen.width / 2) - (osdWidth / 2) - widgetWidth)
                right: Appearance.sizes.barHeight
            }

            mask: Region {
                item: playerColumnLayout
            }

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.mediaControlsOpen = false;
                }
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                opacity: root.mediaControlsShown ? 1 : 0
                scale:
                    root.mediaControlsShown
                        ? 1
                        : (
                            root.mediaControlsClosing
                                ? 0.988
                                : (Appearance.prismMode ? 0.965 : 0.975)
                        )

                transform: Translate {
                    id: mediaControlsPresentationShift

                    readonly property real distance:
                        root.mediaControlsClosing
                            ? 14
                            : (Appearance.prismMode ? 34 : 28)

                    x:
                        root.mediaControlsShown
                            ? 0
                            : (
                                Config.options.bar.vertical
                                    ? (
                                        Config.options.bar.bottom
                                            ? distance
                                            : -distance
                                    )
                                    : 0
                            )

                    y:
                        root.mediaControlsShown
                            ? 0
                            : (
                                !Config.options.bar.vertical
                                    ? (
                                        Config.options.bar.bottom
                                            ? distance
                                            : -distance
                                    )
                                    : 0
                            )

                    Behavior on x {
                        MotionExpressiveAnim {
                            phase:
                                root.mediaControlsClosing
                                    ? MotionExpressiveAnim.Exit
                                    : MotionExpressiveAnim.Enter

                            standardEnterDuration: 350
                            standardExitDuration: 150
                            expressiveEnterDuration: 430
                            expressiveExitDuration: 150

                            standardEnterCurve:
                                Appearance.animationCurves.expressiveFastSpatial

                            standardExitCurve:
                                Appearance.animationCurves.expressiveFastEffects

                            overshootAmount: 1.05
                        }
                    }

                    Behavior on y {
                        MotionExpressiveAnim {
                            phase:
                                root.mediaControlsClosing
                                    ? MotionExpressiveAnim.Exit
                                    : MotionExpressiveAnim.Enter

                            standardEnterDuration: 350
                            standardExitDuration: 150
                            expressiveEnterDuration: 430
                            expressiveExitDuration: 150

                            standardEnterCurve:
                                Appearance.animationCurves.expressiveFastSpatial

                            standardExitCurve:
                                Appearance.animationCurves.expressiveFastEffects

                            overshootAmount: 1.05
                        }
                    }
                }

                Behavior on opacity {
                    MotionAnim {
                        type:
                            root.mediaControlsClosing
                                ? MotionAnim.FastEffects
                                : MotionAnim.DefaultEffects
                    }
                }

                Behavior on scale {
                    MotionExpressiveAnim {
                        phase:
                            root.mediaControlsClosing
                                ? MotionExpressiveAnim.Exit
                                : MotionExpressiveAnim.Enter

                        standardEnterDuration: 350
                        standardExitDuration: 150
                        expressiveEnterDuration: 430
                        expressiveExitDuration: 150

                        standardEnterCurve:
                            Appearance.animationCurves.expressiveFastSpatial

                        standardExitCurve:
                            Appearance.animationCurves.expressiveFastEffects

                        overshootAmount: 1.05
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: PlayerControl {
                        required property MprisPlayer modelData
                        player: modelData
                        visualizerPoints: root.visualizerPoints
                        implicitWidth: root.widgetWidth
                        implicitHeight: root.widgetHeight
                        radius: root.popupRounding
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.mediaControlsOpen =
                !GlobalStates.mediaControlsOpen

            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll()
        }

        function close(): void {
            GlobalStates.mediaControlsOpen = false
        }

        function open(): void {
            GlobalStates.mediaControlsOpen = true
            Notifications.timeoutAll()
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
