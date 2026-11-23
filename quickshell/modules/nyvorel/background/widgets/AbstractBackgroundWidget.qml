import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property real wallpaperScale
    property real viewportOffsetX: 0
    property real viewportOffsetY: 0
    property bool visibleWhenLocked: false
    readonly property var configEntry: Config.options.background.widgets[configEntryName]
    readonly property string placementStrategy: configEntry.placementStrategy
    property var automaticCenter: null
    readonly property bool automatic: placementStrategy !== "free" && automaticCenter !== null
    readonly property real targetX: clampX(automatic ? automaticCenter.x - width / 2 : configEntry.x)
    readonly property real targetY: clampY(automatic ? automaticCenter.y - height / 2 : configEntry.y)
    property real displayX: targetX
    property real displayY: targetY
    property point pressPosition: Qt.point(0, 0)

    x: displayX
    y: displayY
    visible: opacity > 0
    opacity: GlobalStates.screenLocked && !visibleWhenLocked ? 0 : 1
    scale: draggable && containsPress ? 1.05 : 1

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    function clampX(value): real {
        return Math.max(-viewportOffsetX, Math.min(value, screenWidth - width - viewportOffsetX))
    }
    function clampY(value): real {
        return Math.max(-viewportOffsetY, Math.min(value, screenHeight - height - viewportOffsetY))
    }
    function restorePositionBindings(): void {
        root.x = Qt.binding(() => root.displayX)
        root.y = Qt.binding(() => root.displayY)
    }

    draggable: placementStrategy === "free" && !GlobalStates.screenLocked
    drag.minimumX: -viewportOffsetX
    drag.maximumX: Math.max(drag.minimumX, screenWidth - width - viewportOffsetX)
    drag.minimumY: -viewportOffsetY
    drag.maximumY: Math.max(drag.minimumY, screenHeight - height - viewportOffsetY)
    animateXPos: !containsPress && !Appearance.reducedMotion
    animateYPos: !containsPress && !Appearance.reducedMotion
    onPressed: root.pressPosition = Qt.point(root.x, root.y)
    onReleased: {
        if (root.draggable && (root.x !== root.pressPosition.x || root.y !== root.pressPosition.y)) {
            configEntry.x = root.x
            configEntry.y = root.y
        }
        root.restorePositionBindings()
    }
    onCanceled: root.restorePositionBindings()

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property color colText: GlobalStates.screenLocked && Config.options.lock.blur.enable
        ? Appearance.colors.colOnLayer0
        : ColorUtils.colorWithLightness(Appearance.colors.colPrimary, dominantColor.hslLightness < 0.5 ? 0.8 : 0.12)

    readonly property string wallpaperPath: /\.(mp4|webm|mkv|avi|mov)$/i.test(Config.options.background.wallpaperPath)
        ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    readonly property real analysisScale: Math.min(1, 960 / Math.max(1, screenWidth, screenHeight))
    readonly property string analysisKey: Config.ready && visible && wallpaperPath && screenWidth > 0 && screenHeight > 0
        && width > 0 && height > 0 && (placementStrategy !== "free" || needsColText)
        ? JSON.stringify([wallpaperPath, placementStrategy, screenWidth, screenHeight,
            wallpaperScale, Math.round(width), Math.round(height)]) : ""

    onWallpaperPathChanged: root.automaticCenter = null
    onPlacementStrategyChanged: root.automaticCenter = null
    onAnalysisKeyChanged: {
        if (analysisKey)
            placementTimer.restart()
    }
    Component.onCompleted: {
        if (analysisKey)
            placementTimer.start()
    }

    Timer {
        id: placementTimer
        interval: 180
        onTriggered: {
            if (placement.running || !root.analysisKey)
                return
            const scale = root.analysisScale
            const zoom = Math.max(1, root.wallpaperScale)
            const width = Math.max(1, Math.round(root.screenWidth * scale))
            const height = Math.max(1, Math.round(root.screenHeight * scale))
            const margin = 14 * scale / zoom
            placement.key = root.analysisKey
            placement.exec([
                FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/images/least-busy-region-venv.sh")),
                "--screen-width", String(width), "--screen-height", String(height),
                "--width", String(Math.max(1, Math.round(root.width * scale / zoom))),
                "--height", String(Math.max(1, Math.round(root.height * scale / zoom))),
                "--horizontal-padding", String(Math.floor(width * (1 - 1 / zoom) / 2 + margin)),
                "--vertical-padding", String(Math.floor(height * (1 - 1 / zoom) / 2 + margin)),
                ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : []),
                "--", FileUtils.trimFileProtocol(root.wallpaperPath)
            ])
        }
    }

    Process {
        id: placement
        property string key
        stdout: StdioCollector { id: result }
        onExited: code => {
            if (key !== root.analysisKey) {
                if (root.analysisKey)
                    placementTimer.restart()
                return
            }
            if (code !== 0)
                return
            let region
            try { region = JSON.parse(result.text) } catch (_) { return }
            if (!Number.isFinite(region.center_x) || !Number.isFinite(region.center_y))
                return
            if (typeof region.dominant_color === "string" && /^#[0-9a-f]{6}$/i.test(region.dominant_color))
                root.dominantColor = region.dominant_color
            const scale = root.analysisScale
            const zoom = root.wallpaperScale
            root.automaticCenter = Qt.point(
                (region.center_x / scale - root.screenWidth / 2) * zoom + root.screenWidth / 2,
                (region.center_y / scale - root.screenHeight / 2) * zoom + root.screenHeight / 2)
        }
    }
}
