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
            ? chip.implicitWidth
            : 0

    implicitHeight:
        Appearance.sizes.baseBarHeight


    Behavior on implicitWidth {
        MotionAnim {
            type: MotionAnim.FastSpatial
            duration: 220
        }
    }


    Rectangle {
        id: chip

        anchors.verticalCenter:
            parent.verticalCenter

        implicitWidth:
            content.implicitWidth
            + (Appearance.fluidMode
                ? 8
                : Appearance.inlayMode
                    ? 8
                    : 16)

        implicitHeight:
            28

        radius:
            Appearance.inlayMode ? 0 : Appearance.rounding.full

        color:
            mouseArea.containsMouse
                ? (Appearance.inlayMode ? "transparent" : Appearance.colors.colLayer2Hover)
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
                    (Appearance.fluidMode || Appearance.inlayMode) ? 4 : 8
                rightMargin:
                    (Appearance.fluidMode || Appearance.inlayMode) ? 4 : 8

                topMargin: 4
                bottomMargin: 5
            }

            spacing:
                Appearance.inlayMode
                    ? Appearance.spacing.xs
                    : Appearance.fluidMode
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
                    Appearance.inlayMode ? 4 : (Appearance.fluidMode ? 5 : 9)
                rightMargin:
                    Appearance.inlayMode ? 4 : (Appearance.fluidMode ? 5 : 9)
                bottomMargin: 3
            }

            height:
                2

            radius:
                Appearance.inlayMode ? 0 : 1

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
                    Appearance.inlayMode ? 0 : parent.radius

                color:
                    root.accent


                Behavior on width {
                    NumberAnimation {
                        duration: 220

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