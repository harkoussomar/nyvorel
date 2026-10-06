import qs.modules.common
import qs.modules.common.widgets
import qs.services

import qs.modules.nyvorel.sidebarRight.calendar

import QtQuick
import QtQuick.Layouts


StyledPopup {
    id: root

    popupRadius:
        Appearance.radius.popup

    popupColor:
        Appearance.colors.colLayer0


    ColumnLayout {
        id: columnLayout

        anchors.centerIn: parent
        spacing: 10


        RowLayout {
            Layout.fillWidth: true
            spacing: 10


            Rectangle {
                implicitWidth: 38
                implicitHeight: 38
                radius: Appearance.radius.control

                color:
                    Appearance.colors.colPrimaryContainer


                MaterialSymbol {
                    anchors.centerIn: parent

                    text: "calendar_month"
                    fill: 1
                    iconSize: 22

                    color:
                        Appearance.colors.colOnPrimaryContainer
                }
            }


            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0


                StyledText {
                    Layout.fillWidth: true

                    text: DateTime.time

                    font.pixelSize:
                        Appearance.font.pixelSize.large

                    font.weight:
                        Font.DemiBold

                    color:
                        Appearance.colors.colOnLayer0
                }


                StyledText {
                    Layout.fillWidth: true

                    text:
                        Qt.locale().toString(
                            DateTime.clock.date,
                            "dddd, MMMM d, yyyy"
                        )

                    font.pixelSize:
                        Appearance.font.pixelSize.small

                    color:
                        Appearance.colors.colSubtext
                }
            }
        }


        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1

            color:
                Appearance.colors.colLayer0Border
        }


        CalendarWidget {
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
