import qs.services
import qs.modules.common
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts
import qs.modules.nyvorel.bar

StyledPopup {
    id: root
    irisAnimation: Appearance.barLayout.axiomComponents

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        implicitWidth: Math.max(header.implicitWidth, gridLayout.implicitWidth)
        spacing: 5

        // Header
        ColumnLayout {
            id: header
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                MaterialSymbol {
                    fill: 0
                    font.weight: Font.Medium
                    text: "location_on"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: Weather.ready ? Weather.data.city : Translation.tr("Weather")
                    font {
                        weight: Font.Medium
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
            StyledText {
                id: temp
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                text: Weather.ready
                    ? Weather.data.condition + " · " + Weather.data.temp + " · "
                        + Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike)
                    : Weather.loading ? Translation.tr("Checking current conditions…")
                        : Weather.error || Translation.tr("Weather unavailable")
            }
        }

        // Metrics grid
        GridLayout {
            id: gridLayout
            visible: Weather.ready
            columns: 2
            rowSpacing: 5
            columnSpacing: 5
            uniformCellWidths: true

            WeatherCard {
                title: Translation.tr("UV peak today")
                symbol: "wb_sunny"
                value: Weather.data.uv
            }
            WeatherCard {
                title: Translation.tr("Wind")
                symbol: "air"
                value: `(${Weather.data.windDir}) ${Weather.data.wind}`
            }
            WeatherCard {
                title: Translation.tr("Precipitation")
                symbol: "rainy_light"
                value: Weather.data.precip
            }
            WeatherCard {
                title: Translation.tr("Humidity")
                symbol: "humidity_low"
                value: Weather.data.humidity
            }
            WeatherCard {
                title: Translation.tr("Visibility")
                symbol: "visibility"
                value: Weather.data.visib
            }
            WeatherCard {
                title: Translation.tr("Pressure")
                symbol: "readiness_score"
                value: Weather.data.press
            }
            WeatherCard {
                title: Translation.tr("Sunrise")
                symbol: "wb_twilight"
                value: Weather.data.sunrise
            }
            WeatherCard {
                title: Translation.tr("Sunset")
                symbol: "bedtime"
                value: Weather.data.sunset
            }
        }

        // Footer: last refresh
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Weather.ready && Weather.error
                ? Translation.tr("Last update failed · showing previous conditions")
                : Weather.ready
                ? Translation.tr("%1 · observed %2 · checked %3")
                    .arg(Weather.locationSource)
                    .arg(Weather.data.observedAt)
                    .arg(Weather.data.lastRefresh)
                : Weather.error
                    ? Translation.tr("Check your connection or choose a city in Settings") : ""
            font {
                weight: Font.Medium
                pixelSize: Appearance.font.pixelSize.smaller
            }
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
