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
    readonly property bool outputIssue: (!copied && !saved) || (capture?.mode === "both" && (!copied || !saved))
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
    implicitWidth: Math.min(400, Math.max(1, (screen?.width ?? 432) - 32))
    implicitHeight: content.implicitHeight + Appearance.spacing.xl * 2
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

    CaptureSurface {
        anchors.fill: parent

        HoverHandler { id: hover }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Appearance.spacing.xl
            spacing: Appearance.spacing.md

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.md

                MaterialSymbol {
                    text: root.outputIssue ? "info" : "check_circle"
                    iconSize: 18
                    color: root.outputIssue ? Appearance.material.error : Appearance.material.accent
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    elide: Text.ElideRight
                    color: Appearance.material.textPrimary
                    font.weight: Font.DemiBold
                }
                CaptureButton {
                    iconName: "close"
                    text: Translation.tr("Close preview")
                    showLabel: false
                    Layout.preferredWidth: 36
                    onClicked: root.dismissed()
                }
            }

            Image {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(160, Math.round(root.width * 0.44))
                visible: status !== Image.Error
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                sourceSize.width: 800
                sourceSize.height: 320
                source: root.capture?.path ? "file://" + encodeURI(root.capture.path) : ""
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Appearance.spacing.sm
                rowSpacing: Appearance.spacing.sm
                uniformCellWidths: true

                Repeater {
                    model: [
                        { key: "annotate", icon: "edit", label: Translation.tr("Annotate"), available: true },
                        { key: "copy", icon: "content_copy", label: Translation.tr("Copy image"), available: !root.copied },
                        { key: "ocr", icon: "text_select_start", label: Translation.tr("Copy text"), available: true },
                        { key: "folder", icon: "folder_open", label: Translation.tr("Open folder"), available: root.saved },
                        { key: "lens", icon: "image_search", label: Translation.tr("Google Lens"), available: true }
                    ]
                    delegate: CaptureButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: modelData.available
                        framed: true
                        showLabel: root.width >= 286
                        highlighted: modelData.key === "annotate"
                        iconName: modelData.icon
                        text: modelData.label
                        onClicked: root.actionRequested(modelData.key)
                    }
                }
            }
        }
    }
}
