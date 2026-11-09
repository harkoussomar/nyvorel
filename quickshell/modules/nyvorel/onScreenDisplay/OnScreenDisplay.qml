import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland


Scope {
    id: root

    // osd-material-stability-v1
    readonly property bool osdLogicalOpen:
        GlobalStates.osdVolumeOpen

    // motion-phase2c-v1
    property bool osdMapped:
        Config.options.appearance.transparency.enable

    property bool osdShown: false
    property bool osdClosing: false

    onOsdLogicalOpenChanged: {
        if (root.osdLogicalOpen) {
            root.focusedScreenName = Hyprland.focusedMonitor?.name ?? ""
            osdExitTimer.stop()
            root.osdMapped = true
            root.osdClosing = false

            Qt.callLater(() => {
                if (root.osdLogicalOpen)
                    root.osdShown = true
            })
        } else {
            root.osdClosing = true
            root.osdShown = false
            osdExitTimer.restart()
        }
    }

    Component.onCompleted: {
        if (root.osdLogicalOpen) {
            root.focusedScreenName = Hyprland.focusedMonitor?.name ?? ""
            root.osdMapped = true
            Qt.callLater(() => {
                if (root.osdLogicalOpen)
                    root.osdShown = true
            })
        }
    }

    Timer {
        id: osdExitTimer
        interval:
              190
        repeat: false

        onTriggered: {
            if (!root.osdLogicalOpen) {
                root.osdClosing = false

                if (!Config.options.appearance.transparency.enable)
                    root.osdMapped = false
            }
        }
    }

    property string protectionMessage: ""

    property string focusedScreenName: Hyprland.focusedMonitor?.name ?? ""
    readonly property var focusedScreen:
        Quickshell.screens.find(screen => screen.name === root.focusedScreenName)
        ?? Quickshell.screens[0] ?? null

    property string currentIndicator:
        "volume"

    property var indicators: [
        {
            "id": "volume",
            "sourceUrl": "indicators/VolumeIndicator.qml"
        },
        {
            "id": "brightness",
            "sourceUrl": "indicators/BrightnessIndicator.qml"
        }
    ]


    function triggerOsd(): void {
        root.focusedScreenName = Hyprland.focusedMonitor?.name ?? ""
        GlobalStates.osdVolumeOpen = true
        osdTimeout.restart()
    }


    Timer {
        id: osdTimeout

        interval:
            Config.options.osd.timeout

        repeat: false
        running: false

        onTriggered: {
            GlobalStates.osdVolumeOpen = false
            root.protectionMessage = ""
        }
    }


    Connections {
        target: Brightness

        function onBrightnessChanged(): void {
            root.protectionMessage = ""
            root.currentIndicator = "brightness"
            root.triggerOsd()
        }

        function onBrightnessLimitHit(): void {
            root.protectionMessage = ""
            root.currentIndicator = "brightness"
            root.triggerOsd()
        }
    }


    Connections {
        target:
            Audio.sink?.audio ?? null

        function onVolumeChanged(): void {
            if (!Audio.ready)
                return

            root.currentIndicator = "volume"
            root.triggerOsd()
        }

        function onMutedChanged(): void {
            if (!Audio.ready)
                return

            root.currentIndicator = "volume"
            root.triggerOsd()
        }
    }


    Connections {
        target: Audio

        function onSinkProtectionTriggered(
            reason
        ): void {
            root.protectionMessage = reason
            root.currentIndicator = "volume"
            root.triggerOsd()
        }
    }


    Loader {
        id: osdLoader

        active:
            root.osdMapped

        sourceComponent:
            PanelWindow {
                id: osdRoot

                color: "transparent"
                screen: root.focusedScreen


                // This small surface needs no compositor visible mask. A mask
                // based on animated content can lag a resize and cut the card.

                WlrLayershell.namespace:
                    "quickshell:onScreenDisplay"

                WlrLayershell.layer:
                    WlrLayer.Overlay


                // Always bottom-center, regardless of navbar position.
                anchors {
                    bottom: true
                }


                mask:
                    Region {
                        item:
                            (
                                root.osdShown
                                || root.osdClosing
                            )
                                ? osdValuesWrapper
                                : null
                    }

                exclusionMode:
                    ExclusionMode.Ignore

                exclusiveZone: 0


                margins {
                    bottom: 58
                }


                // Keep the Wayland surface at its full resting size from its
                // first frame. Loader content is initially 0x0 during startup.
                // 300x58 is the value indicator card; the remaining space is
                // its shadow, wrapper safety margins, and entrance travel.
                implicitWidth:
                    Math.max(
                        columnLayout.implicitWidth,
                        300 + Appearance.sizes.elevationMargin * 4 + 16
                    )

                implicitHeight:
                    Math.max(
                        columnLayout.implicitHeight,
                        58 + Appearance.sizes.elevationMargin * 4 + 16 + 20
                    )

                visible:
                    osdLoader.active


                ColumnLayout {
                    id: columnLayout

                    anchors.horizontalCenter:
                        parent.horizontalCenter


                    Item {
                        id: osdValuesWrapper

                        // phase2c-osd-crop-fix-v2
                        // Reserve enough bounds for:
                        //   1) StyledRectangularShadow spread around the indicator
                        //   2) the 20px entrance / 10px exit translate motion
                        // so the OSD never gets visibly clipped by the window mask.
                        readonly property real clipPadding:
                            Appearance.sizes.elevationMargin

                        // Extra mask/window breathing room for the rectangular
                        // shadow. This expands the bounds without changing the
                        // card's resting screen position.
                        readonly property real shadowSafetyPadding: 8

                        readonly property real motionPadding: 20

                        visible:
                            opacity > 0.001

                        opacity:
                            root.osdShown ? 1 : 0

                        scale:
                            root.osdShown
                                ? 1
                                : root.osdClosing
                                    ? (0.975)
                                    : (0.94)

                        implicitHeight:
                            contentColumnLayout.implicitHeight
                            + clipPadding * 2
                            + shadowSafetyPadding * 2
                            + motionPadding

                        implicitWidth:
                            contentColumnLayout.implicitWidth
                            + clipPadding * 2
                            + shadowSafetyPadding * 2

                        clip: false

                        transform: Translate {
                            id: osdPresentationShift

                            y:
                                root.osdShown
                                    ? 0
                                    : root.osdClosing
                                        ? (10)
                                        : (20)

                            Behavior on y {
                                MotionAnim {
                                    type:
                                        root.osdClosing
                                            ? MotionAnim.FastEffects
                                            : MotionAnim.FastSpatial
                                }
                            }
                        }

                        Behavior on opacity {
                            MotionAnim {
                                type: MotionAnim.FastEffects
                            }
                        }

                        Behavior on scale {
                            MotionAnim {
                                type:
                                    root.osdClosing
                                        ? MotionAnim.FastEffects
                                        : MotionAnim.FastSpatial
                            }
                        }


                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true

                            onEntered:
                                GlobalStates.osdVolumeOpen =
                                    false
                        }


                        Column {
                            id: contentColumnLayout

                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right

                            anchors.leftMargin:
                                osdValuesWrapper.clipPadding
                                + osdValuesWrapper.shadowSafetyPadding
                            anchors.rightMargin:
                                osdValuesWrapper.clipPadding
                                + osdValuesWrapper.shadowSafetyPadding

                            // The PanelWindow is bottom anchored. Increasing the
                            // wrapper by 16px would otherwise move the card up.
                            // Adding the same 16px here keeps the card exactly
                            // where v1 placed it while expanding only the mask.
                            anchors.topMargin:
                                osdValuesWrapper.clipPadding
                                + osdValuesWrapper.shadowSafetyPadding * 2

                            spacing: 6


                            Loader {
                                id: osdIndicatorLoader

                                source: {
                                    const indicator =
                                        root.indicators.find(
                                            candidate =>
                                                candidate.id
                                                === root.currentIndicator
                                        )

                                    return indicator?.sourceUrl
                                        ?? ""
                                }
                            }


                            Item {
                                id: protectionMessageWrapper

                                anchors.horizontalCenter:
                                    parent.horizontalCenter

                                implicitHeight:
                                    protectionMessageBackground
                                        .implicitHeight

                                implicitWidth:
                                    protectionMessageBackground
                                        .implicitWidth

                                opacity:
                                    root.protectionMessage !== ""
                                        ? 1
                                        : 0

                                visible:
                                    opacity > 0

                                Behavior on opacity {
                                    MotionAnim {
                                        type: MotionAnim.FastEffects
                                    }
                                }


                                StyledRectangularShadow {
                                    visible: !false
                                    target:
                                        protectionMessageBackground
                                }


                                Rectangle {
                                    id: protectionMessageBackground

                                    anchors.centerIn: parent

                                    color:
                                        Appearance.m3colors.m3error

                                    property real padding: 10

                                    implicitHeight:
                                        protectionMessageRowLayout
                                            .implicitHeight
                                        + padding * 2

                                    implicitWidth:
                                        protectionMessageRowLayout
                                            .implicitWidth
                                        + padding * 2

                                    radius:
                                        Appearance.rounding.normal

                                    border.width: 0
                                    border.color: "transparent"


                                    RowLayout {
                                        id: protectionMessageRowLayout

                                        anchors.centerIn: parent


                                        MaterialSymbol {
                                            text: "dangerous"

                                            iconSize:
                                                Appearance.font
                                                    .pixelSize
                                                    .hugeass

                                            color:
                                                Appearance.m3colors
                                                    .m3onError
                                        }


                                        StyledText {
                                            horizontalAlignment:
                                                Text.AlignHCenter

                                            color:
                                                Appearance.m3colors
                                                    .m3onError

                                            wrapMode:
                                                Text.Wrap

                                            text:
                                                root.protectionMessage
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
    }


    IpcHandler {
        target: "osdVolume"

        function trigger(): void {
            root.triggerOsd()
        }

        function hide(): void {
            GlobalStates.osdVolumeOpen = false
        }

        function toggle(): void {
            GlobalStates.osdVolumeOpen =
                !GlobalStates.osdVolumeOpen
        }
    }


    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed:
            root.triggerOsd()
    }


    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed:
            GlobalStates.osdVolumeOpen = false
    }
}
