import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Io

Rectangle {
    id: root
    property string entry
    property real maxWidth
    property real maxHeight
    property bool blur: false
    property string blurText: "Image hidden"
    readonly property bool supportsEffects: GraphicsInfo.api !== GraphicsInfo.Software

    property string imageDecodePath: Directories.cliphistDecode
    property string imageDecodeFilePath
    property string source

    property int entryNumber: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/^(\d+)\t/);
        return match ? parseInt(match[1]) : 0;
    }
    property int imageWidth: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/(\d+)x(\d+)/);
        return match ? parseInt(match[1]) : 0;
    }
    property int imageHeight: {
        if (!root.entry)
            return 0;
        const match = root.entry.match(/(\d+)x(\d+)/);
        return match ? parseInt(match[2]) : 0;
    }
    property real scale: {
        return Math.min(root.maxWidth / imageWidth, root.maxHeight / imageHeight, 1);
    }

    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.small
    implicitHeight: imageHeight * scale
    implicitWidth: imageWidth * scale

    Component.onCompleted: {
        if (root.entryNumber <= 0)
            return;
        // The entry can change during teardown. Keep ownership of the file
        // created at startup even when another delegate renders the same entry.
        const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        root.imageDecodeFilePath = `${root.imageDecodePath}/${root.entryNumber}-${token}`;
        decodeImageProcess.running = true;
    }

    Process {
        id: decodeImageProcess
        command: ["bash", "-o", "pipefail", "-c", `
            umask 077
            mkdir -p -- "$1" || exit 1
            trap 'rm -f -- "$4.tmp"' EXIT
            if [[ "$2" == *cliphist* ]]; then
                printf '%s' "$3" | "$2" decode
            else
                "$2" decode "$3"
            fi >"$4.tmp" && test -s "$4.tmp" && mv -- "$4.tmp" "$4"
        `, "nyvorel-clipboard-preview", root.imageDecodePath, Cliphist.cliphistBinary,
            String(root.entryNumber), root.imageDecodeFilePath]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.source = imageDecodeFilePath;
            } else {
                console.error("[CliphistImage] Failed to decode image for entry", root.entryNumber);
                root.source = "";
            }
        }
    }

    Component.onDestruction: {
        if (root.imageDecodeFilePath)
            Quickshell.execDetached(["rm", "-f", "--", root.imageDecodeFilePath, root.imageDecodeFilePath + ".tmp"]);
    }

    layer.enabled: root.supportsEffects
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: image.width
            height: image.height
            radius: root.radius
        }
    }

    StyledImage {
        id: image
        anchors.fill: parent

        source: root.source ? Qt.resolvedUrl(root.source) : ""
        visible: opacity > 0 && !root.blur
        fillMode: Image.PreserveAspectFit
        antialiasing: true
        asynchronous: true

        width: root.imageWidth * root.scale
        height: root.imageHeight * root.scale
        sourceSize.width: width
        sourceSize.height: height
    }

    Loader {
        id: blurLoader
        active: root.blur && root.supportsEffects
        anchors.fill: image
        sourceComponent: GaussianBlur {
            source: image
            radius: 35
            samples: radius * 2 + 1
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.blur
        color: root.supportsEffects ? Qt.alpha(Appearance.m3colors.m3surfaceContainer, 0.65)
            : Appearance.m3colors.m3surfaceContainer

        Column {
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "visibility_off"
                iconSize: 24
                color: Appearance.m3colors.m3onSurface
            }
            StyledText {
                width: parent.width
                text: root.blurText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
