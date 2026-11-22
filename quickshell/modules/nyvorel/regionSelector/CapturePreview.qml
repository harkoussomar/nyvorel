pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

PanelWindow {
    id: root

    required property var capture
    property bool shown: false
    signal actionRequested(string action)
    signal dismissed()

    readonly property bool copied: !!capture?.copied
    readonly property bool saved: !!capture?.savedPath
    readonly property string statusText: {
        if (copied && saved)
            return Translation.tr("Copied and saved");
        if (copied)
            return capture?.mode === "both" ? Translation.tr("Copied · Save failed") : Translation.tr("Copied to clipboard");
        if (saved)
            return capture?.mode === "both" ? Translation.tr("Saved · Copy failed") : Translation.tr("Screenshot saved");
        return Translation.tr("Screenshot ready · Output failed");
    }

    visible: shown && !!capture?.path
    implicitWidth: Math.max(240, Math.min(430, (screen?.width ?? 462) - 32))
    implicitHeight: content.implicitHeight + 20
    anchors { bottom: true; right: true }
    margins { bottom: 16; right: 16 }
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:capturePreview"

    Timer {
        interval: 13000
        running: root.shown && !hover.hovered
        onTriggered: root.dismissed()
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.radius.bar
        color: Appearance.m3colors.m3surfaceContainer
        border.color: Appearance.m3colors.m3outlineVariant

        HoverHandler { id: hover }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 10
            spacing: 7

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                radius: Appearance.radius.control
                color: Appearance.m3colors.m3surfaceContainerLowest
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 4
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    source: root.capture?.path ? "file://" + encodeURI(root.capture.path) : ""
                }
            }

            RowLayout {
                Layout.fillWidth: true

                MaterialSymbol {
                    text: root.copied || root.saved ? "check_circle" : "info"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    elide: Text.ElideRight
                    color: Appearance.m3colors.m3onSurface
                }
                CaptureButton {
                    iconName: "close"
                    text: Translation.tr("Close preview")
                    showLabel: false
                    onClicked: root.dismissed()
                }
            }

            Flow {
                id: actions
                Layout.fillWidth: true
                spacing: 4
                readonly property bool compact: width < 370

                CaptureButton {
                    iconName: "edit"
                    text: Translation.tr("Annotate")
                    showLabel: !actions.compact
                    onClicked: root.actionRequested("annotate")
                }
                CaptureButton {
                    iconName: "text_select_start"
                    text: Translation.tr("Copy text")
                    showLabel: !actions.compact
                    onClicked: root.actionRequested("ocr")
                }
                CaptureButton {
                    visible: root.saved
                    iconName: "folder_open"
                    text: Translation.tr("Open folder")
                    showLabel: !actions.compact
                    onClicked: root.actionRequested("folder")
                }
                CaptureButton {
                    visible: !root.copied
                    iconName: "content_copy"
                    text: Translation.tr("Copy image")
                    showLabel: !actions.compact
                    onClicked: root.actionRequested("copy")
                }
                CaptureButton {
                    iconName: "image_search"
                    text: Translation.tr("Google Lens")
                    showLabel: !actions.compact
                    onClicked: root.actionRequested("lens")
                }
            }
        }
    }
}
