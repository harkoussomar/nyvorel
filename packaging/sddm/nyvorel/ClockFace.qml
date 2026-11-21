pragma ComponentBehavior: Bound

import QtQuick
import "widgets" as Shared

Item {
    id: clock

    required property date time
    required property color faceColor
    required property color dialColor
    required property color hourColor
    required property color minuteColor
    required property color dayColor
    required property color dayTextColor
    required property color monthColor
    required property color monthTextColor
    readonly property real hour: (time.getHours() % 12) + time.getMinutes() / 60

    implicitWidth: 230
    implicitHeight: implicitWidth
    Accessible.role: Accessible.StaticText
    Accessible.name: Qt.formatTime(time, Qt.locale(), Locale.ShortFormat)
        + ", " + Qt.formatDate(time, Qt.locale(), Locale.LongFormat)

    Shared.MaterialCookie {
        anchors.fill: parent
        sides: 11
        color: clock.faceColor
    }

    Repeater {
        model: 12

        Rectangle {
            required property int index
            readonly property real angle: index * Math.PI / 6
            readonly property real distance: clock.width * 0.378

            width: clock.width * 0.052
            height: width
            x: (clock.width - width) / 2 + Math.sin(angle) * distance
            y: (clock.height - height) / 2 - Math.cos(angle) * distance
            radius: width / 2
            color: clock.dialColor
        }
    }

    Hand {
        angle: clock.time.getMinutes() * 6
        length: clock.width * 0.41
        thickness: clock.width * 0.052
        color: clock.minuteColor
    }

    Hand {
        angle: clock.hour * 30
        length: clock.width * 0.31
        thickness: clock.width * 0.086
        color: clock.hourColor
    }

    Rectangle {
        anchors.centerIn: parent
        width: clock.width * 0.027
        height: width
        radius: width / 2
        color: clock.faceColor
    }

    DateBadge {
        anchors.left: parent.left
        anchors.top: parent.top
        label: Qt.locale().toString(clock.time, "d")
        shape: Shared.MaterialShape.Shape.Pentagon
        color: clock.dayColor
        labelColor: clock.dayTextColor
    }

    DateBadge {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        label: Qt.locale().toString(clock.time, "MM")
        shape: Shared.MaterialShape.Shape.Pill
        color: clock.monthColor
        labelColor: clock.monthTextColor
    }

    component Hand: Item {
        id: hand

        required property real angle
        required property real length
        required property real thickness
        required property color color
        anchors.fill: parent
        rotation: angle

        Rectangle {
            x: (parent.width - width) / 2
            y: parent.height / 2 - height + width / 2
            width: hand.thickness
            height: hand.length
            radius: width / 2
            color: hand.color
        }
    }

    component DateBadge: Shared.MaterialShape {
        id: badge

        required property string label
        required property color labelColor
        implicitSize: clock.width * 0.278

        Text {
            anchors.centerIn: parent
            text: badge.label
            color: badge.labelColor
            font.family: "Space Grotesk"
            font.pixelSize: Math.round(badge.width * 0.47)
            font.weight: Font.Black
        }
    }
}
