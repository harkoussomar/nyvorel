pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound } 
    enum SelectionMode { RectCorners, Circle }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    signal dismiss()

    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.4)
    property color brightText: Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0
    property color brightSecondary: Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary
    property color brightTertiary: Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary)
    property color selectionBorderColor: ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: "#ff000000"
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating) return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.85

    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor.scale
    readonly property real monitorOffsetX: hyprlandMonitor.x
    readonly property real monitorOffsetY: hyprlandMonitor.y
    property int activeWorkspaceId: hyprlandMonitor.activeWorkspace?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions:
        root.windows
            .filter(
                window =>
                    window.workspace.id
                    === root.activeWorkspaceId
            )
            .map(window => {
                return {
                    at: [
                        window.at[0]
                            - root.monitorOffsetX,
                        window.at[1]
                            - root.monitorOffsetY
                    ],
                    size: [
                        window.size[0],
                        window.size[1]
                    ],
                    class: window.class,
                    title: window.title,
                    floating: window.floating,
                    source: "window",
                    confidence: 1.0,
                    shape: "rounded-rect"
                }
            })

    readonly property list<var> layerRegions: {
        const layersOfThisMonitor = root.layers[root.hyprlandMonitor.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers)
            return []

        return topLayers
            .filter(layer => {
                const namespace = layer.namespace ?? ""

                if (
                    namespace.includes(":regionSelector")
                    || namespace.includes(":screenshot")
                    || namespace.includes(":screenCorners")
                    || namespace.includes(":overlay")
                ) {
                    return false
                }

                return ShellSurfacePolicy.layerIsLogicallyVisible(
                    namespace
                )
            })
            .map(layer => ({
                at: [
                    layer.x - root.monitorOffsetX,
                    layer.y - root.monitorOffsetY
                ],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
                source: "layer",
                confidence: 0.90,
                shape: "rect"
            }))
    }

    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0

    // >>> SNIP-POLISH-V3 >>>
    property real targetedRegionRadius: 0
    property string targetedRegionShape: "rect"
    property string targetedRegionSource: ""
    property real targetedRegionConfidence: 0
    property bool autoTargetCapture: false
    property real targetedRegionCaptureOutset: 0 // SNIP-GEOMETRY-V2.3-LIVE
    // <<< SNIP-POLISH-V3 <<<
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }
    function setRegionToTargeted() {
        const outset = Math.max(0, root.targetedRegionCaptureOutset)

        root.regionX = Math.max(0, root.targetedRegionX - outset)
        root.regionY = Math.max(0, root.targetedRegionY - outset)

        const right = Math.min(
            root.screen.width,
            root.targetedRegionX + root.targetedRegionWidth + outset
        )
        const bottom = Math.min(
            root.screen.height,
            root.targetedRegionY + root.targetedRegionHeight + outset
        )

        root.regionWidth = Math.max(1, right - root.regionX)
        root.regionHeight = Math.max(1, bottom - root.regionY)
        root.autoTargetCapture = true
    }

    function captureRadiusForRegion(region) {
        if (!region)
            return 0

        if (region.radius !== undefined)
            return Math.max(0, region.radius)

        const registryId = region.registryId ?? ""
        if (registryId)
            return ShellSurfacePolicy.radiusForRegistryId(registryId)

        if (region.source === "window")
            return Appearance.rounding.windowRounding

        return 0
    }

    function setTargetedRegion(region) {
        root.targetedRegionX = region.at[0]
        root.targetedRegionY = region.at[1]
        root.targetedRegionWidth = region.size[0]
        root.targetedRegionHeight = region.size[1]
        root.targetedRegionRadius =
            root.captureRadiusForRegion(region)
        root.targetedRegionShape = region.shape ?? "rect"
        root.targetedRegionSource = region.source ?? ""
        root.targetedRegionConfidence = region.confidence ?? region.score ?? 0
        root.targetedRegionCaptureOutset =
            Math.max(0, region.captureOutset ?? 0)
    }

    function clearTargetedRegion() {
        root.targetedRegionX = -1
        root.targetedRegionY = -1
        root.targetedRegionWidth = 0
        root.targetedRegionHeight = 0
        root.targetedRegionRadius = 0
        root.targetedRegionShape = "rect"
        root.targetedRegionSource = ""
        root.targetedRegionConfidence = 0
        root.targetedRegionCaptureOutset = 0
    }


    // >>> SHELL-CAPTURE-REGISTRY-V1 >>>
    readonly property list<var> registeredShellRegions: {
        const result = []
        const registry = GlobalStates.captureRegions ?? ({})

        for (const id in registry) {
            const region = registry[id]

            if (
                !region
                || !root.screen
                || region.screenName !== root.screen.name
                || region.width <= 0
                || region.height <= 0
            ) {
                continue
            }

            result.push({
                at: [region.x, region.y],
                size: [region.width, region.height],
                class: region.label || id,
                title: region.label || id,
                priority: region.priority ?? 100,
                registryId: id,
                namespace:
                    ShellSurfacePolicy.namespaceForRegistryId(id),
                captureOutset: region.captureOutset ?? 0,
                radius:
                    region.radius
                    ?? ShellSurfacePolicy.radiusForRegistryId(id),
                shape:
                    region.shape
                    ?? ShellSurfacePolicy.shapeForRegistryId(id),
                confidence: region.confidence ?? 1.0,
                source: "shell-registry"
            })
        }

        return result
    }

    // >>> SNIP-EXACT-TARGETS-V2 >>>
    //
    // A shell component with exact registered geometry is authoritative.
    // Do not also draw/hit-test its larger compositor layer, otherwise
    // Region Selector shows two frames for one surface.

    readonly property list<var> layerRegionsWithoutExactShell: {
        const exactNamespaces =
            root.registeredShellRegions
                .map(region => region.namespace ?? "")
                .filter(namespace => namespace.length > 0)

        return root.layerRegions.filter(
            layer =>
                !exactNamespaces.includes(
                    layer.namespace ?? ""
                )
        )
    }
    // <<< SNIP-EXACT-TARGETS-V2 <<<



    function updateTargetedRegion(x, y) {
        const target = TargetPolicy.bestTargetAt(
            x,
            y,
            root.isCircleSelection ? [] : root.registeredShellRegions,
            root.imageRegions,
            root.windowRegions,
            root.layerRegionsWithoutExactShell,
            root.enableContentRegions,
            root.enableWindowRegions,
            root.enableLayerRegions,
            root.screen.width,
            root.screen.height
        )

        if (target)
            root.setTargetedRegion(target)
        else
            root.clearTargetedRegion()
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)

    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (root.enableContentRegions) {
                root.contentDetectionRequestId =
                    `${root.screen.name}:${Date.now()}`
                ContentDetectionService.detect(
                    root.contentDetectionRequestId,
                    root.screenshotPath,
                    root.screen.width,
                    root.screen.height,
                    root.falsePositivePreventionRatio
                )
            }
            root.preparationDone = !checkRecordingProc.running;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["pgrep", "-f", "(^|/)gpu-screen-recorder( |$)"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running
            root.recordingShouldStop = (exitCode === 0);
        }
    }
    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            root.dismiss();
            return;
        }
        root.visible = true;
    }

    property string contentDetectionRequestId: ""

    Connections {
        target: ContentDetectionService

        function onCompleted(requestId, regions) {
            if (requestId !== root.contentDetectionRequestId)
                return

            root.imageRegions = RegionFunctions.filterImageRegions(
                regions,
                root.windowRegions
            )
        }

        function onFailed(requestId, message) {
            if (requestId !== root.contentDetectionRequestId)
                return

            console.warn(
                `[Region Selector] Content detection failed: ${message}`
            )
            root.imageRegions = []
        }
    }

    function getScreenshotAction() {
        switch(root.action) {
            case RegionSelection.SnipAction.Copy:
                return ScreenshotAction.Action.Copy;
            case RegionSelection.SnipAction.Edit:
                return ScreenshotAction.Action.Edit;
            case RegionSelection.SnipAction.Search:
                return ScreenshotAction.Action.Search;
            case RegionSelection.SnipAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            case RegionSelection.SnipAction.Record:
                return ScreenshotAction.Action.Record;
            case RegionSelection.SnipAction.RecordWithSound:
                return ScreenshotAction.Action.RecordWithSound;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                root.dismiss();
                return;
        }
    }

    function snip() {
        // Validity check
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
        }

        // Clamp region to screen bounds
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));

        // Adjust action
        if (root.action === RegionSelection.SnipAction.Copy || root.action === RegionSelection.SnipAction.Edit) {
            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        }
        
        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //
            Config.options.screenSnip.savePath : "";
        var screenshotAction = root.getScreenshotAction();
        const command = ScreenshotAction.getCommand(
            root.regionX * root.monitorScale, //
            root.regionY * root.monitorScale, //
            root.regionWidth * root.monitorScale,// 
            root.regionHeight * root.monitorScale, //
            root.screenshotPath, //
            screenshotAction, //
            screenshotDir,
            root.autoTargetCapture
                ? root.targetedRegionRadius
                    * root.monitorScale
                : 0
        )
        snipProc.command = command;

        // Image post-processing
        snipProc.startDetached();
        root.dismiss();
    }

    Process {
        id: snipProc
    }

    ScreencopyView {
        anchors.fill: parent
        live: false
        captureSource: root.screen

        focus: root.visible
        Keys.onPressed: (event) => { // Esc to close
            if (event.key === Qt.Key_Escape) {
                root.dismiss();
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            // Controls
            onPressed: (mouse) => {
                root.autoTargetCapture = false
                root.dragStartX = mouse.x;
                root.dragStartY = mouse.y;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.dragging = true;
                root.mouseButton = mouse.button;
            }
            onReleased: (mouse) => {
                // Detect if it was a click -> Try to select targeted region
                if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                    if (root.targetedRegionValid()) {
                        root.setRegionToTargeted();
                    }
                }
                // Circle dragging?
                else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                    const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                    const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
                    const maxX = Math.max(...dragPoints.map(p => p.x));
                    const minX = Math.min(...dragPoints.map(p => p.x));
                    const maxY = Math.max(...dragPoints.map(p => p.y));
                    const minY = Math.min(...dragPoints.map(p => p.y));
                    root.regionX = minX - padding;
                    root.regionY = minY - padding;
                    root.regionWidth = maxX - minX + padding * 2;
                    root.regionHeight = maxY - minY + padding * 2;
                }
                root.snip();
            }
            onPositionChanged: (mouse) => {
                root.updateTargetedRegion(mouse.x, mouse.y);
                if (!root.dragging) return;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.dragDiffX = mouse.x - root.dragStartX;
                root.dragDiffY = mouse.y - root.dragStartY;
                root.points.push({ x: mouse.x, y: mouse.y });
            }
            
            Loader {
                z: 2
                anchors.fill: parent
                active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
                sourceComponent: RectCornersSelectionDetails {
                    regionX: root.regionX
                    regionY: root.regionY
                    regionWidth: root.regionWidth
                    regionHeight: root.regionHeight
                    mouseX: mouseArea.mouseX
                    mouseY: mouseArea.mouseY
                    color: root.selectionBorderColor
                    overlayColor: root.overlayColor
                }
            }

            Loader {
                z: 2
                anchors.fill: parent
                active: root.selectionMode === RegionSelection.SelectionMode.Circle
                sourceComponent: CircleSelectionDetails {
                    color: root.selectionBorderColor
                    overlayColor: root.overlayColor
                    points: root.points
                }
            }

            CursorGuide {
                z: 9999
                x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
                y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
                action: root.action
                selectionMode: root.selectionMode
            }

            // >>> SHELL-REGION-VISUALS-V1 >>>
            //
            // Shell-owned modal cards are not normal Hyprland clients.
            // Their exact QML rectangles come from CaptureRegionRegistry.
            // Render those rectangles explicitly so detection is visible,
            // just like native Settings/window detection.
            Repeater {
                model: ScriptModel {
                    values:
                        root.isCircleSelection
                            ? []
                            : root.registeredShellRegions
                }

                delegate: TargetRegion {
                    z: 5

                    required property var modelData

                    visible:
                        !root.draggedAway
                        && targeted

                    clientDimensions: modelData
                    showIcon: false

                    targeted:
                        !root.draggedAway
                        && (
                            root.targetedRegionX
                                === modelData.at[0]
                            && root.targetedRegionY
                                === modelData.at[1]
                            && root.targetedRegionWidth
                                === modelData.size[0]
                            && root.targetedRegionHeight
                                === modelData.size[1]
                        )

                    opacity:
                        root.draggedAway
                            ? 0
                            : root.targetRegionOpacity

                    borderColor:
                        root.windowBorderColor

                    fillColor:
                        targeted
                            ? root.windowFillColor
                            : "transparent"

                    text:
                        modelData.title
                        || modelData.class
                        || "Shell surface"

                    radius:
                        Appearance.radius.modal
                }
            }
            // <<< SHELL-REGION-VISUALS-V1 <<<

            // Window regions
            Repeater {
                model: ScriptModel {
                    values: root.enableWindowRegions ? root.windowRegions : []
                }
                delegate: TargetRegion {
                    z: 2
                    required property var modelData

                    visible:
                        !root.draggedAway
                        && targeted
                    clientDimensions: modelData
                    showIcon: true
                    targeted: !root.draggedAway &&
                        (root.targetedRegionX === modelData.at[0] 
                        && root.targetedRegionY === modelData.at[1]
                        && root.targetedRegionWidth === modelData.size[0]
                        && root.targetedRegionHeight === modelData.size[1])

                    opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.class}`
                    radius: Appearance.rounding.windowRounding
                }
            }

            // Layer regions
            Repeater {
                model: ScriptModel {
                    values: root.enableLayerRegions ? root.layerRegionsWithoutExactShell : []
                }
                delegate: TargetRegion {
                    z: 3
                    required property var modelData

                    visible:
                        !root.draggedAway
                        && targeted
                    clientDimensions: modelData
                    targeted: !root.draggedAway &&
                        (root.targetedRegionX === modelData.at[0] 
                        && root.targetedRegionY === modelData.at[1]
                        && root.targetedRegionWidth === modelData.size[0]
                        && root.targetedRegionHeight === modelData.size[1])

                    opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                    borderColor: root.windowBorderColor
                    fillColor: targeted ? root.windowFillColor : "transparent"
                    text: `${modelData.namespace}`
                    radius: Appearance.rounding.windowRounding
                }
            }

            // Content regions
            Repeater {
                model: ScriptModel {
                    values: root.enableContentRegions ? root.imageRegions : []
                }
                delegate: TargetRegion {
                    z: 4
                    required property var modelData
                    clientDimensions: modelData
                    targeted: !root.draggedAway &&
                        (root.targetedRegionX === modelData.at[0] 
                        && root.targetedRegionY === modelData.at[1]
                        && root.targetedRegionWidth === modelData.size[0]
                        && root.targetedRegionHeight === modelData.size[1])

                    visible:
                        !root.draggedAway
                        && targeted

                    opacity:
                        targeted
                            ? root.contentRegionOpacity
                            : 0

                    borderColor: root.imageBorderColor
                    fillColor: targeted ? root.imageFillColor : "transparent"
                    text: Translation.tr("Content region")
                    radius: modelData.radius ?? 0
                }
            }

            // Controls
            Row {
                id: regionSelectionControls
                z: 10
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: -height
                }
                opacity: 0
                Connections {
                    target: root
                    function onVisibleChanged() {
                        if (!visible) return;
                        regionSelectionControls.anchors.bottomMargin = 8;
                        regionSelectionControls.opacity = 1;
                    }
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.bottomMargin {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                spacing: 6

                OptionsToolbar {
                    Synchronizer on action {
                        property alias source: root.action
                    }
                    Synchronizer on selectionMode {
                        property alias source: root.selectionMode
                    }
                    onDismiss: root.dismiss();
                }
                Item {
                    anchors {
                        verticalCenter: parent.verticalCenter
                    }
                    implicitWidth: closeFab.implicitWidth
                    implicitHeight: closeFab.implicitHeight
                    StyledRectangularShadow {
                        target: closeFab
                        radius: closeFab.buttonRadius
                    }
                    FloatingActionButton {
                        id: closeFab
                        baseSize: 48
                        iconText: "close"
                        onClicked: root.dismiss();
                        StyledToolTip {
                            text: Translation.tr("Close")
                        }
                        colBackground: Appearance.colors.colTertiaryContainer
                        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                        colRipple: Appearance.colors.colTertiaryContainerActive
                        colOnBackground: Appearance.colors.colOnTertiaryContainer
                    }
                }
            }
            
        }
    }
}
