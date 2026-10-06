import qs.services
import qs.modules.common
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root


    required property int count

    required property bool expanded


    property bool showNewLabel:
        false


    property real fontSize:
        Appearance
            ?.font
            .pixelSize
            .small
        ?? 12


    property real iconSize:
        Appearance
            ?.font
            .pixelSize
            .normal
        ?? 16


    implicitHeight:
        fontSize + 8


    implicitWidth:
        Math.max(
            contentItem.implicitWidth + 10,
            30
        )


    Layout.alignment:
        Qt.AlignVCenter


    Layout.fillHeight:
        false


    buttonRadius:
        Appearance.rounding.full


    colBackground:
        ColorUtils.mix(
            Appearance
                ?.colors
                .colLayer2,

            Appearance
                ?.colors
                .colLayer2Hover,

            0.5
        )


    colBackgroundHover:
        Appearance
            ?.colors
            .colLayer2Hover
        ?? "#E5DFED"


    colRipple:
        Appearance
            ?.colors
            .colLayer2Active
        ?? "#D6CEE2"


    contentItem:
        Item {
            anchors.centerIn:
                parent


            implicitWidth:
                contentRow.implicitWidth


            implicitHeight:
                contentRow.implicitHeight


            RowLayout {
                id: contentRow


                anchors.centerIn:
                    parent


                spacing:
                    3


                StyledText {
                    Layout.leftMargin:
                        4


                    visible:
                        root.count > 1


                    text:
                        root.showNewLabel

                            ? `${root.count} new`

                            : `${root.count}`


                    font.pixelSize:
                        root.fontSize


                    font.weight:
                        Font.Medium


                    color:
                        Appearance
                            .colors
                            .colOnLayer2
                }


                MaterialSymbol {
                    text:
                        "keyboard_arrow_down"


                    iconSize:
                        root.iconSize


                    color:
                        Appearance
                            .colors
                            .colOnLayer2


                    rotation:
                        root.expanded
                            ? 180
                            : 0


                    Behavior on rotation {
                        MotionAnim {
                            type: MotionAnim.FastEffects
                        }
                    }
                }
            }
        }
}