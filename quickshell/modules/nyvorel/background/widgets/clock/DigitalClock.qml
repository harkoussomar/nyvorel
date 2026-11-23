pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: clockColumn
    spacing: 4

    property bool isVertical: Config.options.background.widgets.clock.digital.vertical
    property color colText: Appearance.colors.colOnSecondaryContainer
    property var textHorizontalAlignment: Text.AlignHCenter
    readonly property bool uses12HourTime: /AP|ap/.test(Config.options.time.format)
    readonly property string stackedHour: Qt.locale().toString(DateTime.clock.date,
        uses12HourTime ? "hh AP" : "hh").split(/\s/)[0]
    readonly property string stackedMinute: Qt.locale().toString(DateTime.clock.date, "mm")

    // Time
    ClockText {
        id: timeTextTop
        text: clockColumn.isVertical ? clockColumn.stackedHour : DateTime.time
        color: clockColumn.colText
        horizontalAlignment: clockColumn.isVertical ? Text.AlignHCenter : clockColumn.textHorizontalAlignment
        font {
            pixelSize: Config.options.background.widgets.clock.digital.font.size
            weight: Config.options.background.widgets.clock.digital.font.weight
            family: Config.options.background.widgets.clock.digital.font.family
            variableAxes: ({
                    "wdth": Config.options.background.widgets.clock.digital.font.width,
                    "ROND": Config.options.background.widgets.clock.digital.font.roundness
                })
        }
    }

    Loader {
        Layout.topMargin: -Math.round(timeTextTop.font.pixelSize * 0.4)
        Layout.fillWidth: true
        active: clockColumn.isVertical
        visible: active
        sourceComponent: ClockText {
            id: timeTextBottom
            text: clockColumn.stackedMinute
            color: clockColumn.colText
            horizontalAlignment: clockColumn.textHorizontalAlignment
            font {
                pixelSize: timeTextTop.font.pixelSize
                weight: timeTextTop.font.weight
                family: timeTextTop.font.family
                variableAxes: timeTextTop.font.variableAxes
            }
        }
    }

    // Date
    ClockText {
        visible: Config.options.background.widgets.clock.digital.showDate
        Layout.topMargin: -Math.min(20, Math.round(timeTextTop.font.pixelSize * 0.22))
        Layout.fillWidth: true
        text: DateTime.longDate
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }

    // Quote
    ClockText {
        visible: Config.options.background.widgets.clock.quote.enable && Config.options.background.widgets.clock.quote.text.length > 0
        Layout.maximumWidth: 420
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.normal
        text: Config.options.background.widgets.clock.quote.text
        animateChange: false
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }
}
