import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// A small spatial map of the windows in one workspace. Geometry and capture
// sources match the existing overview; the parent creates this only on hover.
Item {
    id: root

    required property int workspaceId
    property var monitorData: null
    property var windows: []
    property var foregroundWindow: null

    readonly property real monitorWidth: Math.max(1, Number(root.monitorData?.width) || 1920)
    readonly property real monitorHeight: Math.max(1, Number(root.monitorData?.height) || 1080)
    readonly property real previewScale: Math.min(330 / monitorWidth, 210 / monitorHeight)
    implicitWidth: Math.round(monitorWidth * previewScale)
    implicitHeight: Math.round(monitorHeight * previewScale)

    function projectClient(client, planeWidth, planeHeight) {
        const monitorWidth = Math.max(1, Number(root.monitorData?.width) || 1920)
        const monitorHeight = Math.max(1, Number(root.monitorData?.height) || 1080)
        const monitorX = Number(root.monitorData?.x) || 0
        const monitorY = Number(root.monitorData?.y) || 0
        const left = Math.max(0, Math.min(monitorWidth,
            (Number(client?.at?.[0]) || 0) - monitorX))
        const top = Math.max(0, Math.min(monitorHeight,
            (Number(client?.at?.[1]) || 0) - monitorY))
        const right = Math.max(left, Math.min(monitorWidth,
            (Number(client?.at?.[0]) || 0) - monitorX
                + (Number(client?.size?.[0]) || 0)))
        const bottom = Math.max(top, Math.min(monitorHeight,
            (Number(client?.at?.[1]) || 0) - monitorY
                + (Number(client?.size?.[1]) || 0)))
        return {
            x: left / monitorWidth * planeWidth,
            y: top / monitorHeight * planeHeight,
            width: Math.max(5, (right - left) / monitorWidth * planeWidth),
            height: Math.max(5, (bottom - top) / monitorHeight * planeHeight)
        }
    }

    Item {
        id: monitorPlane
        anchors.fill: parent
        clip: true

        Repeater {
            model: root.windows

            Rectangle {
                id: windowTile
                required property var modelData
                readonly property var clientRect: root.projectClient(
                    modelData, monitorPlane.width, monitorPlane.height)
                readonly property bool foreground:
                    modelData.address === root.foregroundWindow?.address
                readonly property var toplevel: ToplevelManager.toplevels.values.find(
                    item => `0x${item.HyprlandToplevel?.address}` === modelData.address) ?? null

                x: clientRect.x
                y: clientRect.y
                width: clientRect.width
                height: clientRect.height
                color: "transparent"
                clip: true

                ScreencopyView {
                    id: windowCapture
                    anchors.fill: parent
                    captureSource: windowTile.toplevel
                    live: true
                    paintCursor: false
                    constraintSize: Qt.size(320, 180)
                }

                Rectangle {
                    anchors.centerIn: parent
                    visible: parent.width >= 45 && parent.height >= 38
                    width: Math.min(35, parent.width * 0.32)
                    height: width
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer0
                    opacity: windowCapture.hasContent ? 0.88 : 1

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: parent.width * 0.68
                        source: Quickshell.iconPath(
                            AppSearch.guessIcon(windowTile.modelData.class),
                            "image-missing")
                        backer.sourceSize: Qt.size(64, 64)
                        backer.smooth: true
                        mipmap: true
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: windowTile.foreground ? 2 : 1
                    border.color: windowTile.foreground
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.windows.length === 0
        text: Translation.tr("Empty workspace")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }
}
