import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts


Item {
    id: root

    required property real value
    required property string icon
    required property string name

    property bool muted: false
    property bool boosted: false

    property color accentColor:
        root.boosted
            ? Appearance.colors.colTertiary
            : Appearance.colors.colPrimary

    property color iconBackgroundColor:
        root.muted
            ? Appearance.colors.colLayer3
            : Appearance.colors.colPrimaryContainer

    property color iconForegroundColor:
        root.muted
            ? Appearance.colors.colSubtext
            : Appearance.colors.colOnPrimaryContainer


    readonly property real visualValue:
        root.muted
            ? 0
            : Math.max(
                0,
                Math.min(
                    1,
                    root.value
                )
            )

    readonly property string displayValue:
        root.muted
            ? Translation.tr("Muted")
            : `${Math.round(
                Math.max(
                    0,
                    root.value
                ) * 100
            )}%`


    // Compact macOS-like HUD with an exact percentage.
    property real cardWidth:
        (Appearance.prismMode || Appearance.inlayMode) ? 288 : 300
    property real cardHeight:
        (Appearance.prismMode || Appearance.inlayMode) ? 56 : 58

    implicitWidth:
        root.cardWidth
        + Appearance.sizes.elevationMargin * 2

    implicitHeight:
        root.cardHeight
        + Appearance.sizes.elevationMargin * 2


    // osd-value-stable-material-v1


    opacity: 1
    scale: 1


    StyledRectangularShadow {
        visible: !Appearance.prismMode && !Appearance.inlayMode
        target: card
    }

    PrismSurface {
        visible: Appearance.prismMode
        anchors.fill: card
        depth: Appearance.prism.depthTransient
        surfaceRadius: Appearance.prism.radiusTransient
    }


    Rectangle {
        id: card

        anchors.fill: parent
        anchors.margins:
            Appearance.sizes.elevationMargin

        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight

        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusTransient
                    : 22

        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.inlayMode
                    ? Appearance.inlay.surfaceFill
                    : Appearance.colors.colLayer0

        border.width:
            Appearance.prismMode
                ? 0
                : Appearance.inlayMode
                    ? Appearance.inlay.borderWidth
                    : 1

        border.color:
            Appearance.inlayMode
                ? Appearance.inlay.borderControl
                : Appearance.colors.colLayer0Border


        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 14
            anchors.topMargin: 9
            anchors.bottomMargin: 9

            spacing: 11


            Rectangle {
                Layout.alignment: Qt.AlignVCenter

                implicitWidth: 38
                implicitHeight: 38
                radius: Appearance.inlayMode ? 0 : 14

                color:
                    Appearance.inlayMode
                        ? Appearance.inlay.controlFill
                        : Appearance.prismMode
                            ? Appearance.prism.interactiveFill
                            : root.iconBackgroundColor

                border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
                border.color: Appearance.inlayMode ? Appearance.inlay.borderControl : "transparent"


                MaterialSymbol {
                    anchors.centerIn: parent

                    text: root.icon
                    iconSize: 22

                    fill:
                        root.muted
                            ? 0
                            : 1

                    color:
                        Appearance.prismMode && !root.muted
                            ? Appearance.colors.colPrimary
                            : root.iconForegroundColor

                    renderType:
                        Text.QtRendering
                }
            }


            Rectangle {
                id: progressTrack

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                implicitHeight: Appearance.prismMode ? 6 : 8
                radius: Appearance.inlayMode ? 0 : implicitHeight / 2

                color:
                    Appearance.inlayMode
                        ? Appearance.inlay.insetFill
                        : Appearance.prismMode
                            ? Appearance.prism.borderSubtle
                            : Appearance.colors.colLayer3

                border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
                border.color: Appearance.inlayMode ? Appearance.inlay.borderSection : "transparent"

                clip: true


                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    width:
                        progressTrack.width
                        * root.visualValue

                    radius:
                        progressTrack.radius

                    color:
                        root.accentColor


                    Behavior on width {
                        MotionAnim {
                            type: MotionAnim.FastEffects
                        }
                    }
                }
            }


            StyledText {
                Layout.alignment: Qt.AlignVCenter

                Layout.preferredWidth:
                    root.muted
                        ? 52
                        : 42

                horizontalAlignment:
                    Text.AlignRight

                text:
                    root.displayValue

                font.pixelSize:
                    Appearance.font.pixelSize.small

                font.weight:
                    Font.DemiBold

                color:
                    root.muted
                        ? Appearance.colors.colSubtext
                        : Appearance.colors.colOnLayer0
            }
        }
    }
}
