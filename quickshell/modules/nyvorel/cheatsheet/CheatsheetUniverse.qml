pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

Item {
    id: root
    property bool viewActive: false
    property bool motionPaused: false
    property bool moonHovered: false
    property bool moonPinned: false
    property bool infoHovered: false
    property string hoveredPlanet: ""
    property string selectedPlanet: ""
    property real orbitTime: 0
    readonly property bool infoVisible: moonHovered || moonPinned || infoHovered
    readonly property var planets: [
        { name: "Mercury", file: "mercury.png", ring: 0, angle: -37, size: 54, period: 42, reverse: false },
        { name: "Venus", file: "venus.png", ring: 0, angle: 143, size: 65, period: 42, reverse: false },
        { name: "Earth", file: "earth.png", ring: 1, angle: 215, size: 76, period: 63, reverse: true },
        { name: "Mars", file: "mars.png", ring: 1, angle: 35, size: 62, period: 63, reverse: true },
        { name: "Jupiter", file: "jupiter.png", ring: 2, angle: 100, size: 114, period: 85, reverse: false },
        { name: "Saturn", file: "saturn.png", ring: 2, angle: 280, size: 160, period: 85, reverse: false },
        { name: "Uranus", file: "uranus.png", ring: 3, angle: 185, size: 79, period: 112, reverse: true },
        { name: "Neptune", file: "neptune.png", ring: 3, angle: 5, size: 79, period: 112, reverse: true }
    ]
    readonly property var rings: [
        { x: 0.10, y: 0.16 },
        { x: 0.19, y: 0.24 },
        { x: 0.30, y: 0.33 },
        { x: 0.43, y: 0.43 }
    ]

    Timer {
        interval: 33
        repeat: true
        running: root.viewActive && !root.motionPaused
                 && root.hoveredPlanet === "" && !Appearance.reducedMotion
        onTriggered: root.orbitTime += interval / 1000
    }

    Rectangle {
        id: scene
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: "transparent"
        clip: true

        Canvas {
            id: starfield
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const ink = Appearance.colors.colOnLayer0
                const rgb = Math.round(ink.r * 255) + ","
                    + Math.round(ink.g * 255) + ","
                    + Math.round(ink.b * 255)
                let seed = 21341
                for (let i = 0; i < 76; ++i) {
                    seed = (seed * 1664525 + 1013904223) >>> 0
                    const x = (seed / 4294967296) * width
                    seed = (seed * 1664525 + 1013904223) >>> 0
                    const y = (seed / 4294967296) * height
                    const alpha = i % 9 === 0 ? 0.50 : 0.18
                    ctx.fillStyle = "rgba(" + rgb + "," + alpha + ")"
                    ctx.beginPath()
                    ctx.arc(x, y, i % 11 === 0 ? 1.4 : 0.65, 0, Math.PI * 2)
                    ctx.fill()
                }
                // Keep every planet path; only the decorative halo around the moon is omitted.
                for (let i = 0; i < root.rings.length; ++i) {
                    const orbit = root.rings[i]
                    ctx.save()
                    ctx.translate(width / 2, height / 2)
                    ctx.scale(width * orbit.x, height * orbit.y)
                    ctx.beginPath()
                    ctx.arc(0, 0, 1, 0, Math.PI * 2)
                    ctx.restore()
                    ctx.lineWidth = 1
                    ctx.strokeStyle = "rgba(" + rgb + "," + (i === 3 ? 0.22 : 0.15) + ")"
                    ctx.stroke()
                }
            }
        }
        Connections {
            target: Appearance.colors
            function onColOnLayer0Changed() { starfield.requestPaint() }
        }

        Image {
            id: moon
            width: Math.min(92, scene.height * 0.16)
            height: width
            anchors.centerIn: parent
            rotation: root.orbitTime * 360 / 72
            source: Qt.resolvedUrl("../../../assets/planets/nyvorel-moon-3d.png")
            sourceSize.width: 512
            sourceSize.height: 512
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            mipmap: true
            scale: root.infoVisible ? 1.045 : 1
            Behavior on scale {
                enabled: !Appearance.reducedMotion
                NumberAnimation { duration: Appearance.barMotion.statusDuration; easing.type: Easing.OutCubic }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                Accessible.role: Accessible.Button
                Accessible.name: "Nyvorel shell and system information"
                onEntered: {
                    infoHideTimer.stop()
                    root.moonHovered = true
                }
                onExited: infoHideTimer.start()
                onClicked: root.moonPinned = !root.moonPinned
            }
        }

        Timer {
            id: infoHideTimer
            interval: 220
            onTriggered: {
                if (!root.infoHovered && !root.moonPinned)
                    root.moonHovered = false
            }
        }

        Rectangle {
            id: moonInfo
            z: 5
            x: Math.min(scene.width - width - 16, moon.x + moon.width + 24)
            y: Math.max(65, Math.min(scene.height - height - 35, moon.y - 32))
            width: 310
            height: 215
            radius: Appearance.radius.card
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            opacity: root.infoVisible ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                NumberAnimation { duration: Appearance.barMotion.statusDuration; easing.type: Easing.OutCubic }
            }

            Rectangle {
                x: 17
                y: 19
                width: 4
                height: 26
                radius: 2
                color: Appearance.colors.colPrimary
            }
            StyledText {
                x: 32
                y: 17
                text: "NYVOREL"
                color: Appearance.colors.colOnLayer0
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }
            StyledText {
                x: 33
                y: 39
                text: "YOUR DESKTOP, YOUR WAY"
                color: Appearance.colors.colOnLayer1Inactive
                font.pixelSize: 9
                font.letterSpacing: 1.2
            }

            Rectangle {
                x: 17
                y: 65
                width: parent.width - 34
                height: 1
                color: Appearance.colors.colLayer0Border
            }

            StyledText {
                x: 18
                y: 79
                text: "SHELL"
                color: Appearance.colors.colOnLayer1Inactive
                font.pixelSize: 9
                font.letterSpacing: 1.1
            }
            StyledText {
                x: 18
                y: 97
                text: "Quickshell on " + (SystemInfo.desktopEnvironment || "Hyprland")
                color: Appearance.colors.colOnLayer0
                font.pixelSize: 12
            }
            StyledText {
                x: 18
                y: 130
                text: "SYSTEM"
                color: Appearance.colors.colOnLayer1Inactive
                font.pixelSize: 9
                font.letterSpacing: 1.1
            }
            StyledText {
                x: 18
                y: 148
                width: parent.width - 36
                text: SystemInfo.distroName + " · " + SystemInfo.windowingSystem
                color: Appearance.colors.colOnLayer0
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Rectangle {
                x: 18
                y: 185
                width: 6
                height: 6
                radius: 3
                color: Appearance.colors.colPrimary
            }
            StyledText {
                x: 32
                y: 180
                text: (Appearance.fluidMode ? "Fluid" : "Material")
                    + " · " + (Appearance.m3colors.darkmode ? "Dark" : "Light")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: 10
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    infoHideTimer.stop()
                    root.infoHovered = true
                }
                onExited: {
                    root.infoHovered = false
                    if (!root.moonPinned)
                        root.moonHovered = false
                }
            }
        }

        Repeater {
            model: root.planets
            delegate: Item {
                id: body
                required property var modelData
                readonly property var orbit: root.rings[modelData.ring]
                readonly property real degrees: modelData.angle
                    + (modelData.reverse ? -1 : 1) * root.orbitTime * 360 / modelData.period
                readonly property real radians: degrees * Math.PI / 180
                width: modelData.size
                height: modelData.file === "saturn.png" ? modelData.size * 0.70 : modelData.size
                x: scene.width / 2 + Math.cos(radians) * scene.width * orbit.x - width / 2
                y: scene.height / 2 + Math.sin(radians) * scene.height * orbit.y - height / 2
                z: bodyMouse.containsMouse ? 3 : 1

                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl("../../../assets/planets/" + body.modelData.file)
                    sourceSize.width: Math.ceil(body.width * 2)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    mipmap: true
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height + 5
                    width: label.implicitWidth + 16
                    height: 24
                    radius: 6
                    color: Appearance.colors.colLayer1
                    border.color: Appearance.colors.colLayer0Border
                    visible: bodyMouse.containsMouse
                    StyledText {
                        id: label
                        anchors.centerIn: parent
                        text: body.modelData.name
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: bodyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoveredPlanet = body.modelData.name
                    onExited: root.hoveredPlanet = ""
                    onClicked: root.selectedPlanet = body.modelData.name
                }
            }
        }

        StyledText {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 19
            text: root.selectedPlanet === "" ? "SELECT A PLANET" : root.selectedPlanet.toUpperCase()
            color: Appearance.colors.colOnLayer1
            font.pixelSize: 10
            font.letterSpacing: 1.6
        }

        Rectangle {
            id: pauseButton
            width: pauseText.implicitWidth + 22
            height: 29
            radius: 6
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 15
            color: pauseMouse.containsMouse
                ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
            border.color: Appearance.colors.colLayer0Border
            Accessible.role: Accessible.Button
            Accessible.name: root.motionPaused ? "Resume universe motion" : "Pause universe motion"
            StyledText {
                id: pauseText
                anchors.centerIn: parent
                text: root.motionPaused ? "▶  Resume motion" : "Ⅱ  Pause motion"
                color: Appearance.colors.colOnLayer1
                font.pixelSize: 11
            }
            MouseArea {
                id: pauseMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.motionPaused = !root.motionPaused
            }
        }
    }
}
