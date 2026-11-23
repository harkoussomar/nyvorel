pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.nyvorel.background.widgets
import qs.modules.nyvorel.background.widgets.clock
import qs.modules.nyvorel.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        readonly property bool fullscreen: !!monitor && Hyprland.workspaces.values.some(workspace =>
            workspace.active && workspace.monitor?.name === monitor.name
            && workspace.toplevels.values.some(window => window.wayland?.fullscreen))
        visible: GlobalStates.screenLocked || !fullscreen || !Config.options.background.hideWhenFullscreen

        // Fall back to the session's regular workspace when locking or opening a special workspace.
        readonly property int activeWorkspaceId: {
            const id = monitor?.activeWorkspace?.id ?? 1
            return id >= 1 && id <= 100 ? id : 1
        }
        readonly property var workspaceIds: HyprlandData.workspaces.filter(workspace =>
            workspace.monitor === monitor?.name).map(workspace => workspace.id)
        readonly property int firstWorkspaceId: Math.min(activeWorkspaceId, ...workspaceIds)
        readonly property int lastWorkspaceId: Math.max(activeWorkspaceId, ...workspaceIds)
        // Wallpaper
        readonly property string previewWallpaper:
            !GlobalStates.screenLocked && GlobalStates.wallpaperPickerScreenName === screen?.name
                ? GlobalStates.wallpaperPreviewPath : ""
        property bool wallpaperIsVideo: !previewWallpaper
            && /\.(mp4|webm|mkv|avi|mov)$/i.test(Config.options.background.wallpaperPath)
        property string wallpaperPath: previewWallpaper || (wallpaperIsVideo
            ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath)
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real wallpaperToScreenRatio: Math.min(
            wallpaperWidth / Math.max(1, modelData.width), wallpaperHeight / Math.max(1, modelData.height))
        readonly property bool hasParallax: Config.options.background.parallax.enableWorkspace
            || Config.options.background.parallax.enableSidebar
        readonly property real effectiveWallpaperScale: hasParallax
            ? Math.max(1, Math.min(1.5, Config.options.background.parallax.workspaceZoom)) : 1
        property int wallpaperWidth: Math.max(1, modelData.width)
        property int wallpaperHeight: Math.max(1, modelData.height)
        readonly property real movableXSpace: Math.max(0, (wallpaper.width - modelData.width) / 2)
        readonly property real movableYSpace: Math.max(0, (wallpaper.height - modelData.height) / 2)
        readonly property bool verticalParallax: Config.options.background.parallax.vertical
            || (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth)
        // Colors
        // Lock-background identity. Fluid keeps the exact configured blur/zoom.
        // Default stays restrained.
        property bool shouldBlur:
            GlobalStates.screenLocked
            && Config.options.lock.blur.enable
            && !false
        property real lockBlurRadius:
            Appearance.fluidMode
                ? Config.options.lock.blur.radius
                : Math.min(Config.options.lock.blur.radius, 30)
        property real lockZoom:
            Appearance.fluidMode
                ? Config.options.lock.blur.extraZoom
                : 1 + (Config.options.lock.blur.extraZoom - 1) * 0.25
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: bgRoot.readWallpaperSize()
        Component.onCompleted: bgRoot.readWallpaperSize()

        function readWallpaperSize() {
            if (getWallpaperSizeProc.running || !bgRoot.wallpaperPath)
                return;
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-ping", "-format", "%w %h", path]
            onExited: {
                if (path !== bgRoot.wallpaperPath)
                    Qt.callLater(bgRoot.readWallpaperSize)
            }
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    if (getWallpaperSizeProc.path !== bgRoot.wallpaperPath || !bgRoot.screen)
                        return;
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    if (!(width > 0 && height > 0))
                        return;
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;
                }
            }
        }

        Item {
            anchors.fill: parent
            clip: true

            // Wallpaper
            WallpaperImage {
                id: wallpaper
                visible: opacity > 0 && !blurLoader.active
                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
                cache: false
                smooth: false
                readonly property int chunkSize: Math.max(1, Config.options.bar.workspaces.shown)
                readonly property int lower: Math.floor((bgRoot.firstWorkspaceId - 1) / chunkSize) * chunkSize + 1
                readonly property int upper: Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                readonly property real workspacePosition: (bgRoot.activeWorkspaceId - lower) / Math.max(1, upper - lower)
                readonly property bool moveWithWorkspace: Config.options.background.parallax.enableWorkspace
                    && !GlobalStates.screenLocked && !bgRoot.previewWallpaper
                readonly property bool moveWithSidebar: Config.options.background.parallax.enableSidebar
                    && !GlobalStates.screenLocked && !bgRoot.previewWallpaper
                readonly property real sidebarTravel: moveWithSidebar ? 0.15 : 0
                readonly property real workspaceX: moveWithWorkspace && !bgRoot.verticalParallax
                    ? sidebarTravel + (1 - 2 * sidebarTravel) * workspacePosition : 0.5
                property real valueX: workspaceX
                    + sidebarTravel * (GlobalStates.sidebarRightOpen - GlobalStates.sidebarLeftOpen)
                property real valueY: moveWithWorkspace && bgRoot.verticalParallax ? workspacePosition : 0.5
                property real effectiveValueX: Math.max(0, Math.min(1, valueX))
                property real effectiveValueY: Math.max(0, Math.min(1, valueY))
                x: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                y: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
                wallpaperPath: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                fallbackResolution: Math.max(1024, Math.min(4096, 1024 * Math.ceil(
                    Math.max(bgRoot.screen.width, bgRoot.screen.height) * (bgRoot.monitor?.scale ?? 1) / 1024)))
                fillMode: Image.PreserveAspectCrop
                Behavior on x { MotionAnim { type: MotionAnim.SlowSpatial } }
                Behavior on y { MotionAnim { type: MotionAnim.SlowSpatial } }
                sourceSize {
                    width: bgRoot.screen.width * bgRoot.effectiveWallpaperScale * (bgRoot.monitor?.scale ?? 1)
                    height: bgRoot.screen.height * bgRoot.effectiveWallpaperScale * (bgRoot.monitor?.scale ?? 1)
                }
                width: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                height: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            }

            Loader {
                id: blurLoader
                active: bgRoot.shouldBlur || scaleAnim.running
                anchors.fill: wallpaper
                scale: GlobalStates.screenLocked ? bgRoot.lockZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: wallpaper
                    radius: GlobalStates.screenLocked ? bgRoot.lockBlurRadius : 0
                    samples: radius * 2 + 1

                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors.fill: parent
                readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                readonly property real offsetX: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered ? 0
                    : (wallpaper.x + bgRoot.movableXSpace) * parallaxFactor
                readonly property real offsetY: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered ? 0
                    : (wallpaper.y + bgRoot.movableYSpace) * parallaxFactor
                transform: Translate {
                    x: widgetCanvas.offsetX
                    y: widgetCanvas.offsetY
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                        viewportOffsetX: widgetCanvas.offsetX
                        viewportOffsetY: widgetCanvas.offsetY
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                        viewportOffsetX: widgetCanvas.offsetX
                        viewportOffsetY: widgetCanvas.offsetY
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
            }
        }
    }
}
