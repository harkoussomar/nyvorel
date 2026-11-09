import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Rectangle {
    id: root
    readonly property var screen: root.QsWindow?.window?.screen
    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.screen)
        ?? Brightness.monitors.find(monitor => monitor.screen.name === Hyprland.focusedMonitor?.name)
        ?? Brightness.monitors[0]
    readonly property real brightnessValue: brightnessMonitor?.brightness ?? 0
    readonly property real volumeValue: Audio.sink?.audio?.volume ?? 0

    radius: 13
    color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.62)
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 15
        spacing: 9
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 25
            StyledText {
                Layout.fillWidth: true
                text: "Levels"
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }
            StyledText {
                text: "DISPLAY / AUDIO"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.letterSpacing: 1.1
                font.weight: Font.DemiBold
            }
        }
        LevelRing {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: "Brightness"
            symbol: "light_mode"
            value: root.brightnessValue
            enabled: !!root.brightnessMonitor?.ready
            onAdjusted: value => root.brightnessMonitor?.setBrightness(value)
        }
        LevelRing {
            Layout.fillWidth: true
            Layout.fillHeight: true
            label: "Volume"
            symbol: "volume_up"
            value: root.volumeValue
            enabled: !!Audio.sink?.audio
            onAdjusted: value => {
                if (Audio.sink?.audio)
                    Audio.sink.audio.volume = value
            }
        }
    }

    component LevelRing: Rectangle {
        id: gauge
        required property string label
        required property string symbol
        required property real value
        signal adjusted(real value)
        implicitHeight: 88
        radius: 10
        color: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 14
            spacing: 12
            layoutDirection: Qt.RightToLeft
            Item {
                Layout.preferredWidth: 88
                Layout.fillHeight: true
                Canvas {
                    id: ringCanvas
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 2, parent.height - 8, 82)
                    height: width
                    antialiasing: true
                    onPaint: {
                        const ctx = getContext("2d")
                        const c = width / 2
                        const radius = c - 5
                        const start = 0.75 * Math.PI
                        const sweep = 1.5 * Math.PI
                        ctx.clearRect(0, 0, width, height)
                        ctx.lineWidth = 5
                        ctx.lineCap = "round"
                        ctx.strokeStyle = String(Appearance.colors.colSecondaryContainer)
                        ctx.beginPath()
                        ctx.arc(c, c, radius, start, start + sweep)
                        ctx.stroke()
                        if (gauge.value > 0) {
                            ctx.strokeStyle = String(Appearance.colors.colPrimary)
                            ctx.beginPath()
                            ctx.arc(c, c, radius, start, start + sweep * Math.min(1, Math.max(0, gauge.value)))
                            ctx.stroke()
                        }
                    }
                    Connections {
                        target: gauge
                        function onValueChanged() { ringCanvas.requestPaint() }
                    }
                    Connections {
                        target: Appearance.colors
                        function onColPrimaryChanged() { ringCanvas.requestPaint() }
                        function onColSecondaryContainerChanged() { ringCanvas.requestPaint() }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: gauge.enabled
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        function adjustFromPointer(x, y) {
                            const degrees = Math.atan2(y - height / 2, x - width / 2) * 180 / Math.PI
                            const progress = (degrees - 135 + 360) % 360
                            gauge.adjusted(Math.max(0, Math.min(1, progress > 270 ? (progress < 315 ? 1 : 0) : progress / 270)))
                        }
                        onPressed: mouse => adjustFromPointer(mouse.x, mouse.y)
                        onPositionChanged: mouse => {
                            if (pressed) adjustFromPointer(mouse.x, mouse.y)
                        }
                        onWheel: wheel => gauge.adjusted(Math.max(0, Math.min(1, gauge.value + (wheel.angleDelta.y > 0 ? 0.03 : -0.03))))
                    }
                }
                StyledText {
                    anchors.centerIn: parent
                    text: gauge.enabled ? `${Math.round(gauge.value * 100)}%` : "—"
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                layoutDirection: Qt.LeftToRight
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    layoutDirection: Qt.LeftToRight
                    spacing: 6
                    MaterialSymbol {
                        text: gauge.symbol
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: gauge.label
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: gauge.enabled ? "Drag the ring or scroll to adjust" : "Unavailable"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }
        }
    }
}
