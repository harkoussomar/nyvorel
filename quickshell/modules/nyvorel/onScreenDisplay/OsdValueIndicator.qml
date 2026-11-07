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
        (false) ? 288 : 300
    property real cardHeight:
        (false) ? 56 : 58

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
        visible: true
        target: card
    }



    Rectangle {
        id: card

        anchors.fill: parent
        anchors.margins:
            Appearance.sizes.elevationMargin

        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight

        radius:
              22

        color:
              Appearance.colors.colLayer0

        border.width:
              1

        border.color:
             Appearance.colors.colLayer0Border


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
                radius: 14

                color:
                      root.iconBackgroundColor

                border.width: 0
                border.color: "transparent"


                MaterialSymbol {
                    anchors.centerIn: parent

                    text: root.icon
                    iconSize: 22

                    fill:
                        root.muted
                            ? 0
                            : 1

                    color:
                        false && !root.muted
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

                implicitHeight: 8
                radius: implicitHeight / 2

                color:
                      Appearance.colors.colLayer3

                border.width: 0
                border.color: "transparent"

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
