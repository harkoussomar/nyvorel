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
            Appearance.inlayMode
                ? Appearance.inlay.exitDuration
                : Appearance.prismMode
                    ? Appearance.prism.exitDuration
                    : 190
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

    property var focusedScreen:
        Quickshell.screens.find(
            screen =>
                screen.name
                === Hyprland.focusedMonitor?.name
        )

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


                Connections {
                    target: root

                    function onFocusedScreenChanged(): void {
                        osdRoot.screen =
                            root.focusedScreen
                    }
                }


                // glass-system-v2.3b-shape
                Region {
                    id: glassOsdVisibleMask
                    item:
                        (
                            root.osdShown
                            || root.osdClosing
                        )
                            ? osdValuesWrapper
                            : null
                }
                HyprlandWindow.visibleMask:
                    Config.options.appearance.transparency.enable
                        ? glassOsdVisibleMask
                        : null

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


                implicitWidth:
                    columnLayout.implicitWidth

                implicitHeight:
                    columnLayout.implicitHeight

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
                                    ? (Appearance.inlayMode
                                        ? 1
                                        : Appearance.prismMode ? 0.985 : 0.975)
                                    : (Appearance.inlayMode
                                        ? 1
                                        : Appearance.prismMode
                                            ? Appearance.prism.enterScale
                                            : 0.94)

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
                                        ? (Appearance.inlayMode
                                            ? Math.round(Appearance.inlay.enterDistance * 0.5)
                                            : Appearance.prismMode
                                                ? Math.round(Appearance.prism.enterDistance * 0.5)
                                                : 10)
                                        : (Appearance.inlayMode
                                            ? Appearance.inlay.enterDistance
                                            : Appearance.prismMode
                                                ? Appearance.prism.enterDistance
                                                : 20)

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
                                    visible: !Appearance.inlayMode
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
                                        Appearance.inlayMode ? 0 : Appearance.rounding.normal

                                    border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
                                    border.color: Appearance.inlayMode ? Appearance.inlay.borderFocus : "transparent"


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
