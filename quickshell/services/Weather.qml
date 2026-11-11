pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning
import qs.modules.common

Singleton {
    id: root

    readonly property int fetchInterval: Math.max(60000,
        Config.options.bar.weather.fetchInterval * 60000)
    readonly property string city: Config.options.bar.weather.city.trim()
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    readonly property bool gpsActive: Config.options.bar.weather.enableGPS

    property var location: ({ valid: false, lat: 0, lon: 0 })
    property bool ready: false
    property bool loading: false
    property bool refreshQueued: false
    property string error: ""
    property string locationSource: ""
    property string requestedName: ""
    property string requestedSource: ""
    property var data: ({
        uv: "—", humidity: "—", sunrise: "—", sunset: "—",
        windDir: "", wCode: "113", city: "Weather", wind: "—",
        precip: "—", visib: "—", press: "—", temp: "—",
        tempFeelsLike: "—", lastRefresh: "—", observedAt: "—",
        condition: ""
    })

    onCityChanged: root.getData()
    onUseUSCSChanged: root.getData()
    onGpsActiveChanged: {
        if (gpsActive) positionSource.start()
        else positionSource.stop()
        root.getData()
    }

    function fail(message) {
        root.error = message
        root.loading = false
    }

    function finishRequest() {
        root.loading = false
        if (root.refreshQueued) {
            root.refreshQueued = false
            Qt.callLater(root.getData)
        }
    }

    function cardinal(degrees) {
        const directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return directions[Math.round(Number(degrees) / 45) % 8] || "N"
    }

    function legacyWeatherCode(code) {
        const value = Number(code)
        if (value === 0) return "113"
        if (value <= 2) return "116"
        if (value === 3) return "122"
        if (value <= 48) return "143"
        if (value <= 57) return "266"
        if (value <= 67) return "302"
        if (value <= 77) return "332"
        if (value <= 86) return "353"
        return "389"
    }

    function conditionName(code) {
        const value = Number(code)
        if (value === 0) return "Clear"
        if (value <= 2) return "Partly cloudy"
        if (value === 3) return "Cloudy"
        if (value <= 48) return "Fog"
        if (value <= 67) return "Rain"
        if (value <= 77) return "Snow"
        if (value <= 86) return "Showers"
        return "Thunderstorm"
    }

    function formatNumber(value, digits) {
        if (value === null || value === undefined || value === "") return "—"
        const number = Number(value)
        return Number.isFinite(number) ? number.toFixed(digits) : "—"
    }

    function acceptForecast(payload) {
        const current = payload?.current
        if (!current || !Number.isFinite(Number(current.temperature_2m))
            || !current.time)
            throw new Error("Weather provider returned no current conditions")

        const degrees = root.useUSCS ? "°F" : "°C"
        const windUnit = root.useUSCS ? "mph" : "km/h"
        const precipitationUnit = root.useUSCS ? "in" : "mm"
        const visibility = current.visibility == null ? NaN : Number(current.visibility)
        const pressure = current.surface_pressure == null ? NaN : Number(current.surface_pressure)
        const sunrise = payload.daily?.sunrise?.[0] || ""
        const sunset = payload.daily?.sunset?.[0] || ""
        root.data = {
            uv: root.formatNumber(payload.daily?.uv_index_max?.[0], 1),
            humidity: root.formatNumber(current.relative_humidity_2m, 0) + "%",
            sunrise: sunrise ? sunrise.slice(-5) : "—",
            sunset: sunset ? sunset.slice(-5) : "—",
            windDir: root.cardinal(current.wind_direction_10m),
            wCode: root.legacyWeatherCode(current.weather_code),
            city: root.requestedName,
            wind: root.formatNumber(current.wind_speed_10m, 1) + " " + windUnit,
            precip: root.formatNumber(current.precipitation, 1) + " " + precipitationUnit,
            visib: Number.isFinite(visibility)
                ? root.formatNumber(visibility / (root.useUSCS ? 1609.344 : 1000), 1)
                    + (root.useUSCS ? " mi" : " km") : "—",
            press: Number.isFinite(pressure)
                ? root.useUSCS ? root.formatNumber(pressure * 0.02953, 2) + " inHg"
                    : root.formatNumber(pressure, 0) + " hPa" : "—",
            temp: root.formatNumber(current.temperature_2m, 0) + degrees,
            tempFeelsLike: root.formatNumber(current.apparent_temperature, 0) + degrees,
            lastRefresh: new Date().toLocaleTimeString(),
            observedAt: current.time.slice(11),
            condition: root.conditionName(current.weather_code)
        }
        root.locationSource = root.requestedSource
        root.ready = true
        root.error = ""
    }

    function fetchForecast(lat, lon, name, source) {
        if (!Number.isFinite(Number(lat)) || !Number.isFinite(Number(lon))) {
            root.fail("Weather location is unavailable")
            return
        }
        root.requestedName = name || "Current location"
        root.requestedSource = source
        const unitParams = root.useUSCS
            ? "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch"
            : ""
        const url = "https://api.open-meteo.com/v1/forecast?latitude="
            + encodeURIComponent(lat) + "&longitude=" + encodeURIComponent(lon)
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,wind_direction_10m,surface_pressure,visibility"
            + "&daily=sunrise,sunset,uv_index_max&timezone=auto&forecast_days=1"
            + unitParams
        forecastProc.exec(["curl", "--fail", "--silent", "--show-error",
            "--location", "--max-time", "12", url])
    }

    function getData() {
        if (forecastProc.running || geocodeProc.running || locateProc.running) {
            root.refreshQueued = true
            return
        }
        root.loading = true
        root.error = ""
        if (root.gpsActive && root.location.valid) {
            root.fetchForecast(root.location.lat, root.location.lon,
                "Current location", "GPS")
        } else if (root.city.length > 0) {
            const url = "https://geocoding-api.open-meteo.com/v1/search?name="
                + encodeURIComponent(root.city) + "&count=1&language=en&format=json"
            geocodeProc.exec(["curl", "--fail", "--silent", "--show-error",
                "--location", "--max-time", "12", url])
        } else {
            // This is explicitly approximate; a GPS fix will replace it.
            locateProc.exec(["curl", "--fail", "--silent", "--show-error",
                "--location", "--max-time", "12", "https://wttr.in/?format=j1"])
        }
    }

    Component.onCompleted: {
        if (gpsActive) positionSource.start()
        root.getData()
    }

    Process {
        id: geocodeProc
        property bool parsed: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text).results?.[0]
                    if (!result) throw new Error("City was not found")
                    geocodeProc.parsed = true
                    root.fetchForecast(result.latitude, result.longitude,
                        result.name + (result.country ? ", " + result.country : ""), "City")
                } catch (error) { root.fail(String(error)) }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !geocodeProc.parsed)
                root.fail("Could not look up the weather city")
            geocodeProc.parsed = false
            if (!forecastProc.running) root.finishRequest()
        }
    }

    Process {
        id: locateProc
        property bool parsed: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const place = JSON.parse(text).nearest_area?.[0]
                    if (!place) throw new Error("Approximate location unavailable")
                    locateProc.parsed = true
                    if (root.gpsActive && root.location.valid)
                        root.fetchForecast(root.location.lat, root.location.lon,
                            "Current location", "GPS")
                    else
                        root.fetchForecast(place.latitude, place.longitude,
                            place.areaName?.[0]?.value || "Approximate location", "Approximate IP location")
                } catch (error) { root.fail(String(error)) }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !locateProc.parsed)
                root.fail("Could not determine an approximate weather location")
            locateProc.parsed = false
            if (!forecastProc.running) root.finishRequest()
        }
    }

    Process {
        id: forecastProc
        property bool parsed: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.acceptForecast(JSON.parse(text))
                    forecastProc.parsed = true
                } catch (error) { root.fail(String(error)) }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !forecastProc.parsed)
                root.fail("Could not refresh current weather")
            forecastProc.parsed = false
            root.finishRequest()
        }
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval
        onPositionChanged: {
            if (!position.latitudeValid || !position.longitudeValid) return
            root.location = ({ valid: true,
                lat: position.coordinate.latitude,
                lon: position.coordinate.longitude })
            root.getData()
        }
    }

    Timer {
        interval: root.fetchInterval
        repeat: true
        running: true
        onTriggered: root.getData()
    }
}
