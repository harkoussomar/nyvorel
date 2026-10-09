import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Quickshell
import Quickshell.Hyprland


Rectangle {
    id: root

    property var screen:
        root.QsWindow.window?.screen

    property var brightnessMonitor:
        Brightness.getMonitorForScreen(
            root.screen
        )


    radius:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.prism.radiusCard
                : Appearance.rounding.normal
    color:
        (Appearance.prismMode || Appearance.inlayMode)
            ? "transparent"
            : Appearance.colors.colLayer1

    implicitHeight:
        controlsColumn.implicitHeight
        + ((Appearance.prismMode || Appearance.inlayMode) ? 0 : 24)

    implicitWidth:
        controlsColumn.implicitWidth
        + ((Appearance.prismMode || Appearance.inlayMode) ? 0 : 28)


    function volumeIcon() {
        const audio = Audio.sink?.audio

        if (!audio)
            return "volume_up"

        if (audio.muted || audio.volume <= 0)
            return "volume_off"

        if (audio.volume < 0.34)
            return "volume_down"

        return "volume_up"
    }


    ColumnLayout {
        id: controlsColumn

        anchors.fill: parent
        anchors.leftMargin: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 14
        anchors.rightMargin: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 14
        anchors.topMargin: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 12
        anchors.bottomMargin: (Appearance.prismMode || Appearance.inlayMode) ? 0 : 12

        spacing: 14


        Loader {
            Layout.fillWidth: true

            active:
                Config.options.sidebar.quickSliders.showBrightness
                && !!root.brightnessMonitor

            visible: active

            sourceComponent:
                ControlSlider {
                    label: Translation.tr("Brightness")
                    materialSymbol: "light_mode"

                    currentValue:
                        root.brightnessMonitor?.brightness
                        ?? 0

                    onUserMoved: value => {
                        root.brightnessMonitor
                            ?.setBrightness(value)
                    }
                }
        }


        Loader {
            Layout.fillWidth: true

            active:
                Config.options.sidebar.quickSliders.showVolume
                && !!Audio.sink?.audio

            visible: active

            sourceComponent:
                ControlSlider {
                    label: Translation.tr("Volume")
                    materialSymbol: root.volumeIcon()

                    currentValue:
                        Audio.sink?.audio?.volume
                        ?? 0

                    onUserMoved: value => {
                        if (Audio.sink?.audio)
                            Audio.sink.audio.volume = value
                    }
                }
        }


        Loader {
            Layout.fillWidth: true

            active:
                Config.options.sidebar.quickSliders.showMic
                && !!Audio.source?.audio

            visible: active

            sourceComponent:
                ControlSlider {
                    label: Translation.tr("Microphone")

                    materialSymbol:
                        Audio.source?.audio?.muted
                            ? "mic_off"
                            : "mic"

                    currentValue:
                        Audio.source?.audio?.volume
                        ?? 0

                    onUserMoved: value => {
                        if (Audio.source?.audio)
                            Audio.source.audio.volume = value
                    }
                }
        }
    }


    component ControlSlider: ColumnLayout {
        id: control

        required property string label
        required property string materialSymbol
        required property real currentValue

        signal userMoved(real value)

        spacing: 7


        RowLayout {
            Layout.fillWidth: true
            spacing: 8


            MaterialSymbol {
                text: control.materialSymbol
                iconSize: 19
                fill: 1
                color:
                    Appearance.inlayMode
                        ? Appearance.inlay.borderFocus
                        : Appearance.prismMode
                            ? Appearance.prism.focusBorder
                            : Appearance.colors.colPrimary
            }


            StyledText {
                Layout.fillWidth: true

                text: control.label

                font.pixelSize:
                    Appearance.font.pixelSize.small

                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }


            StyledText {
                text:
                    `${Math.round(
                        Math.max(
                            0,
                            control.currentValue
                        ) * 100
                    )}%`

                font.pixelSize:
                    Appearance.font.pixelSize.small

                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
        }


        StyledSlider {
            Layout.fillWidth: true

            configuration:
                (Appearance.prismMode || Appearance.inlayMode)
                    ? StyledSlider.Configuration.S
                    : StyledSlider.Configuration.M

            highlightColor:
                Appearance.inlayMode
                    ? Appearance.inlay.selectedFill
                    : Appearance.prismMode
                        ? Appearance.prism.focusBorder
                        : Appearance.colors.colPrimary
            trackColor:
                Appearance.inlayMode
                    ? Appearance.inlay.insetFill
                    : Appearance.prismMode
                        ? Appearance.prism.borderSubtle
                        : Appearance.colors.colSecondaryContainer
            handleColor:
                Appearance.inlayMode
                    ? Appearance.inlay.borderFocus
                    : Appearance.prismMode
                        ? Appearance.prism.focusBorder
                        : Appearance.colors.colPrimary

            stopIndicatorValues: []

            value: control.currentValue

            onMoved:
                control.userMoved(value)
        }
    }
}
