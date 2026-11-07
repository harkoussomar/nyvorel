import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property string iconName
    required property string label
    required property double percentage

    property int warningThreshold: 100
    property bool axiomMode: false
    property bool shown: true

    readonly property real normalizedValue:
        Math.max(
            0,
            Math.min(
                1,
                root.percentage
            )
        )

    readonly property bool warning:
        root.percentage * 100
        >= root.warningThreshold

    readonly property color accent:
        root.warning
            ? Appearance.colors.colError
            : Appearance.colors.colPrimary


    visible:
        root.shown

    implicitWidth:
        root.shown
            ? (root.axiomMode ? axiomMetric.implicitWidth : chip.implicitWidth)
            : 0

    // nyvorel-phase3b-component-plane: use the shared 40px semantic height.
    implicitHeight:
        Appearance.barLayout.persistentHeight


    Behavior on implicitWidth {
        MotionAnim {
            type: MotionAnim.FastSpatial
            duration: Appearance.barMotion.statusDuration
        }
    }


    // Nyvorel / Axiom: themed utilization ring, readable icon and value.
    // Live ResourceUsage bindings and ResourcesPopup remain unchanged.
    Row {
        id: axiomMetric
        visible: root.axiomMode && root.shown
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter
        height: 32

        CircularProgress {
            id: utilizationRing
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: Appearance.barVisual.axiomRingSize
            lineWidth: 2
            gapAngle: 0
            value: root.normalizedValue
            enableAnimation: false
            colPrimary: root.warning ? Appearance.colors.colError
                : root.label === "RAM" ? Appearance.barVisual.axiomRamAccent
                : Appearance.barVisual.axiomCpuAccent
            colSecondary: Appearance.barVisual.axiomBatteryTrack

            MaterialSymbol {
                anchors.centerIn: parent
                // Material Symbols' visible glyph sits slightly above its text box center.
                // Correct its optical baseline without moving the 24px ring itself.
                anchors.verticalCenterOffset: 1
                text: root.iconName
                iconSize: Appearance.barVisual.axiomIconSize - 2
                fill: 0
                color: utilizationRing.colPrimary
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.normalizedValue * 100) + "%"
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.barVisual.axiomTextSize
            font.weight: Font.DemiBold
            color: root.warning ? Appearance.colors.colError
                : Appearance.barVisual.axiomValue
        }
    }

    Rectangle {
        id: chip
        visible: !root.axiomMode

        anchors.verticalCenter:
            parent.verticalCenter

        implicitWidth:
            content.implicitWidth
            + (Appearance.fluidMode
                ? 8
                : 16)

        implicitHeight:
            28

        radius:
            Appearance.rounding.full

        color:
            mouseArea.containsMouse
                ? (Appearance.colors.colLayer2Hover)
                : "transparent"


        Behavior on color {
            MotionColorAnim {
                type: MotionColorAnim.FastEffects
            }
        }


        RowLayout {
            id: content

            anchors {
                fill: parent

                leftMargin:
                    (Appearance.fluidMode) ? 4 : 8
                rightMargin:
                    (Appearance.fluidMode) ? 4 : 8

                topMargin: 4
                bottomMargin: 5
            }

            spacing:
                 Appearance.fluidMode
                    ? 4
                    : 5


            MaterialSymbol {
                Layout.alignment:
                    Qt.AlignVCenter

                text:
                    root.iconName

                iconSize:
                    16

                fill:
                    1

                color:
                    root.accent
            }


            StyledText {
                Layout.alignment:
                    Qt.AlignVCenter

                text:
                    root.label

                font.pixelSize:
                    Appearance.font.pixelSize.small

                font.weight:
                    Font.Medium

                color:
                    Appearance.colors.colSubtext
            }


            StyledText {
                Layout.alignment:
                    Qt.AlignVCenter

                text:
                    `${Math.round(
                        root.normalizedValue
                        * 100
                    )}%`

                font.pixelSize:
                    Appearance.font.pixelSize.small

                font.weight:
                    Font.DemiBold

                color:
                    root.warning
                        ? Appearance.colors.colError
                        : Appearance.colors.colOnLayer1
            }
        }


        // -----------------------------------------------------
        // Tiny utilization line
        // -----------------------------------------------------

        Rectangle {
            id: track

            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom

                leftMargin:
                    (Appearance.fluidMode? 5 : 9)
                rightMargin:
                    (Appearance.fluidMode? 5 : 9)
                bottomMargin: 3
            }

            height:
                2

            radius:
                1

            color:
                Appearance.colors.colLayer3


            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }

                width:
                    parent.width
                    * root.normalizedValue

                radius:
                    parent.radius

                color:
                    root.accent


                Behavior on width {
                    NumberAnimation {
                        duration: Appearance.barMotion.statusDuration

                        easing.type:
                            Easing.OutCubic
                    }
                }


                Behavior on color {
                    MotionColorAnim {
                        type: MotionColorAnim.FastEffects
                    }
                }
            }
        }
    }


    MouseArea {
        id: mouseArea

        anchors.fill:
            chip

        hoverEnabled:
            true

        acceptedButtons:
            Qt.NoButton
    }
}