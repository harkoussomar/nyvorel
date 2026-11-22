pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
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
    WlrLayershell.keyboardFocus: screen?.name === Hyprland.focusedMonitor?.name
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record }
    property var action: RegionSelection.SnipAction.Copy
    property string selectionMode: "region"
    signal dismiss()
    signal modeSelected(string mode)
    signal captureRequested(var request)
    signal recordingRequested(var args, int delay, string screenName)
    signal recordingModeRequested()
    signal systemAudioToggled()
    signal microphoneToggled()

    readonly property bool isScreenshot: action === RegionSelection.SnipAction.Copy || action === RegionSelection.SnipAction.Edit
    property bool recordingAvailable: true
    required property bool systemAudio
    required property bool microphone
    readonly property bool supportsCaptureOptions: isScreenshot || isRecording
    property bool precision: false
    property int delaySeconds: 0
    property var precisionRegion: null
    readonly property bool screenMode: selectionMode === "screen"
    readonly property bool canConfirm: screenMode || !!precisionRegion

    onSelectionModeChanged: {
        precisionRegion = null;
        dragging = false;
        draggingX = dragStartX;
        draggingY = dragStartY;
        dragDiffX = 0;
        dragDiffY = 0;
        clearTargetedRegion();
    }

    function cycleDelay() {
        delaySeconds = delaySeconds === 0 ? 3 : delaySeconds === 3 ? 5 : 0;
    }

    function togglePrecision() {
        precision = !precision;
        if (!precision)
            precisionRegion = null;
    }

    function confirmCapture(button = Qt.LeftButton) {
        if (screenMode) {
            snip({ x: 0, y: 0, width: screen.width, height: screen.height }, 0, button);
        } else if (precisionRegion) {
            snip(precisionRegion, 0, button);
        }
    }

    function moveSelection(box, dx, dy) {
        precisionRegion = {
            x: Math.max(0, Math.min(screen.width - box.width, box.x + dx)),
            y: Math.max(0, Math.min(screen.height - box.height, box.y + dy)),
            width: box.width,
            height: box.height
        };
    }

    function nudgeSelection(dx, dy, resize) {
        const box = precisionRegion;
        if (!box)
            return;
        if (!resize) {
            moveSelection(box, dx, dy);
            return;
        }
        precisionRegion = {
            x: box.x, y: box.y,
            width: Math.max(1, Math.min(screen.width - box.x, box.width + dx)),
            height: Math.max(1, Math.min(screen.height - box.y, box.height + dy))
        };
    }

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
        if (root.specialWorkspaceId !== 0) {
            const aOnSpecial = a.workspace?.id === root.specialWorkspaceId;
            const bOnSpecial = b.workspace?.id === root.specialWorkspaceId;
            if (aOnSpecial !== bOnSpecial)
                return aOnSpecial ? -1 : 1;
        }
        if (a.floating === b.floating) return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.85

    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor?.scale ?? 1
    readonly property real monitorOffsetX: hyprlandMonitor?.x ?? screen?.x ?? 0
    readonly property real monitorOffsetY: hyprlandMonitor?.y ?? screen?.y ?? 0
    readonly property var monitorState: HyprlandData.monitors.find(monitor => monitor.name === screen?.name)
    readonly property int activeWorkspaceId: monitorState?.activeWorkspace?.id ?? hyprlandMonitor?.activeWorkspace?.id ?? 0
    readonly property int specialWorkspaceId: monitorState?.specialWorkspace?.id ?? 0
    property string screenshotPath
    property bool screenshotHandedOff: false
    Component.onCompleted: {
        const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        root.screenshotPath = `${root.screenshotDir}/image-${encodeURIComponent(screen.name)}-${token}.png`;
        screenshotProc.exec(screenshotProc.captureCommand(root.screenshotPath));
    }
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: !!precisionRegion || dragDiffX !== 0 || dragDiffY !== 0
    property bool dragging: false
    property var imageRegions: []
    readonly property list<var> windowRegions:
        root.windows
            .filter(window => window.mapped && !window.hidden
                && (window.workspace?.id === root.activeWorkspaceId
                    || (root.specialWorkspaceId !== 0 && window.workspace?.id === root.specialWorkspaceId)
                    || (window.pinned && window.monitor === root.monitorState?.id)))
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
        const layersOfThisMonitor = root.layers[root.screen?.name]
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

    property bool enableWindowRegions: !screenMode && Config.options.regionSelector.targetRegions.windows
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !screenMode
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content && !screenMode
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
    property real targetedRegionCaptureOutset: 0 // SNIP-GEOMETRY-V2.3-LIVE
    // <<< SNIP-POLISH-V3 <<<
    function targetedRegionValid() {
        return root.targetedRegionWidth > 0 && root.targetedRegionHeight > 0
            && root.targetedRegionX < screen.width && root.targetedRegionY < screen.height
            && root.targetedRegionX + root.targetedRegionWidth > 0
            && root.targetedRegionY + root.targetedRegionHeight > 0;
    }
    function targetedBounds() {
        const outset = root.targetedRegionCaptureOutset;
        return {
            x: root.targetedRegionX - outset,
            y: root.targetedRegionY - outset,
            width: root.targetedRegionWidth + 2 * outset,
            height: root.targetedRegionHeight + 2 * outset
        };
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
        if (screenMode || precisionRegion)
            return;
        const target = TargetPolicy.bestTargetAt(
            x,
            y,
            root.registeredShellRegions,
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

    property real regionWidth: precisionRegion?.width ?? Math.abs(draggingX - dragStartX)
    property real regionHeight: precisionRegion?.height ?? Math.abs(draggingY - dragStartY)
    property real regionX: precisionRegion?.x ?? Math.min(dragStartX, draggingX)
    property real regionY: precisionRegion?.y ?? Math.min(dragStartY, draggingY)

    TempScreenshotProcess {
        id: screenshotProc
        running: false
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        stderr: StdioCollector { id: captureError }
        onExited: (exitCode, exitStatus) => {
            if ((exitCode !== 0 || exitStatus !== 0) && !root.isRecording) {
                console.warn(`[Region Selector] Screen capture failed (${exitCode}): ${captureError.text.trim()}`);
                Quickshell.execDetached(["notify-send", "-a", "Nyvorel", Translation.tr("Could not take a screenshot")]);
                root.dismiss();
                return;
            }
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
            root.visible = true;
        }
    }
    readonly property bool isRecording: action === RegionSelection.SnipAction.Record

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

    function getScreenshotAction(button) {
        switch(root.action) {
            case RegionSelection.SnipAction.Copy:
            case RegionSelection.SnipAction.Edit:
                return button === Qt.RightButton ? ScreenshotAction.Action.Edit : ScreenshotAction.Action.Copy;
            case RegionSelection.SnipAction.Search:
                return ScreenshotAction.Action.Search;
            case RegionSelection.SnipAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                root.dismiss();
                return;
        }
    }

    function snip(bounds, radius, button) {
        const x = Math.max(0, bounds.x);
        const y = Math.max(0, bounds.y);
        const width = Math.min(screen.width, bounds.x + bounds.width) - x;
        const height = Math.min(screen.height, bounds.y + bounds.height) - y;
        if (width <= 0 || height <= 0) {
            root.dismiss();
            return;
        }

        if (isRecording) {
            const args = screenMode
                ? ["--fullscreen", "--monitor", screen.name]
                : ["--region", `${Math.round(x + monitorOffsetX)},${Math.round(y + monitorOffsetY)} ${Math.round(width)}x${Math.round(height)}`, "--monitor", screen.name];
            if (systemAudio)
                args.push("--system-audio");
            if (microphone)
                args.push("--microphone");
            if (!recordingAvailable)
                return;
            recordingRequested(args, delaySeconds, screen.name);
            dismiss();
            return;
        }

        const screenshotAction = getScreenshotAction(button);
        if (screenshotAction === ScreenshotAction.Action.Copy) {
            root.screenshotHandedOff = true;
            root.captureRequested({
                screenName: root.screen.name,
                source: root.screenshotPath,
                x, y, width, height, radius,
                delay: root.delaySeconds
            });
            root.dismiss();
            return;
        }

        const command = ScreenshotAction.getCommand(
            x * monitorScale, y * monitorScale, width * monitorScale, height * monitorScale,
            screenshotPath, screenshotAction, Config.options.screenSnip.savePath, radius * monitorScale
        );
        snipProc.command = command;
        root.screenshotHandedOff = !root.isRecording;

        // Image post-processing
        snipProc.startDetached();
        root.dismiss();
    }

    Process {
        id: snipProc
    }

    Component.onDestruction: {
        if (!root.screenshotHandedOff && root.screenshotPath)
            Quickshell.execDetached(["rm", "-f", "--", root.screenshotPath]);
    }

    function handleKey(event) {
        const key = event.key;
        if (key === Qt.Key_Escape) {
            dismiss();
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            if (!canConfirm)
                return;
            confirmCapture();
        } else if (supportsCaptureOptions && key === Qt.Key_P && selectionMode === "region") {
            togglePrecision();
        } else if (supportsCaptureOptions && key === Qt.Key_D) {
            cycleDelay();
        } else if (supportsCaptureOptions && key === Qt.Key_V) {
            recordingModeRequested();
        } else if (key === Qt.Key_1) {
            modeSelected("region");
        } else if (supportsCaptureOptions && (key === Qt.Key_2 || key === Qt.Key_3)) {
            modeSelected("screen");
        } else if (precisionRegion && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(key)) {
            const step = event.modifiers & Qt.ControlModifier ? 10 : 1;
            nudgeSelection(key === Qt.Key_Left ? -step : key === Qt.Key_Right ? step : 0,
                key === Qt.Key_Up ? -step : key === Qt.Key_Down ? step : 0, !!(event.modifiers & Qt.ShiftModifier));
        } else {
            return;
        }
        event.accepted = true;
    }

    ScreencopyView {
        anchors.fill: parent
        live: false
        captureSource: root.screen

        id: previewSurface
        focus: root.visible
        Keys.onPressed: event => root.handleKey(event)


        MouseArea {
            id: mouseArea
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            acceptedButtons: root.isRecording ? Qt.LeftButton : Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            // Controls
            onPressed: (mouse) => {
                previewSurface.forceActiveFocus();
                root.precisionRegion = null;
                root.dragDiffX = 0;
                root.dragDiffY = 0;
                root.dragStartX = mouse.x;
                root.dragStartY = mouse.y;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.dragging = true;
                root.updateTargetedRegion(mouse.x, mouse.y);
            }
            onReleased: (mouse) => {
                if (root.screenMode) {
                    root.dragging = false;
                    root.confirmCapture(mouse.button);
                    return;
                }
                if (root.precision && root.supportsCaptureOptions && !root.screenMode
                    && mouse.button === Qt.LeftButton) {
                    if (root.regionWidth > 0 && root.regionHeight > 0)
                        root.precisionRegion = { x: root.regionX, y: root.regionY, width: root.regionWidth, height: root.regionHeight };
                    root.dragging = false;
                    return;
                }
                // A click selects the target beneath the pointer if there is one.
                if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                    if (root.targetedRegionValid()) {
                        root.snip(root.targetedBounds(), root.targetedRegionRadius, mouse.button);
                        return;
                    }
                }
                root.snip({ x: root.regionX, y: root.regionY,
                    width: root.regionWidth, height: root.regionHeight }, 0, mouse.button);
            }
            onPositionChanged: (mouse) => {
                root.updateTargetedRegion(mouse.x, mouse.y);
                if (!root.dragging || root.screenMode) return;
                root.draggingX = mouse.x;
                root.draggingY = mouse.y;
                root.dragDiffX = mouse.x - root.dragStartX;
                root.dragDiffY = mouse.y - root.dragStartY;
            }
            
            Loader {
                z: 2
                anchors.fill: parent
                active: !root.screenMode
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

            Rectangle {
                visible: root.screenMode && (mouseArea.containsMouse || root.screen?.name === Hyprland.focusedMonitor?.name)
                anchors.fill: parent
                color: "transparent"
                border.width: 2
                border.color: Appearance.colors.colPrimary
            }

            CursorGuide {
                visible: !root.supportsCaptureOptions
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
                    values: root.screenMode ? [] : root.registeredShellRegions
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

            MouseArea {
                z: 7
                x: root.regionX
                y: root.regionY
                width: root.regionWidth
                height: root.regionHeight
                enabled: !!root.precisionRegion
                visible: enabled
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property point pressPoint
                property var initialRegion

                onPressed: mouse => {
                    previewSurface.forceActiveFocus();
                    pressPoint = mapToItem(mouseArea, mouse.x, mouse.y);
                    initialRegion = root.precisionRegion;
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    const point = mapToItem(mouseArea, mouse.x, mouse.y);
                    root.moveSelection(initialRegion, point.x - pressPoint.x, point.y - pressPoint.y);
                }
            }

            Repeater {
                model: root.precisionRegion ? 4 : 0

                delegate: Rectangle {
                    id: handle

                    required property int index
                    readonly property bool onRight: index % 2 === 1
                    readonly property bool onBottom: index >= 2
                    width: 12
                    height: 12
                    x: root.regionX + (onRight ? root.regionWidth : 0) - width / 2
                    y: root.regionY + (onBottom ? root.regionHeight : 0) - height / 2
                    z: 8
                    radius: 3
                    color: Appearance.colors.colPrimary
                    border.color: Appearance.colors.colOnPrimary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -5
                        cursorShape: handle.onRight === handle.onBottom ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                        onPositionChanged: mouse => {
                            if (!pressed || !root.precisionRegion)
                                return;
                            const point = mapToItem(mouseArea, mouse.x, mouse.y);
                            const box = root.precisionRegion;
                            const left = handle.onRight ? box.x : Math.max(0, Math.min(box.x + box.width - 1, point.x));
                            const top = handle.onBottom ? box.y : Math.max(0, Math.min(box.y + box.height - 1, point.y));
                            const right = handle.onRight ? Math.min(root.screen.width, Math.max(box.x + 1, point.x)) : box.x + box.width;
                            const bottom = handle.onBottom ? Math.min(root.screen.height, Math.max(box.y + 1, point.y)) : box.y + box.height;
                            root.precisionRegion = { x: left, y: top, width: right - left, height: bottom - top };
                        }
                    }
                }
            }

            OptionsToolbar {
                id: captureToolbar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.min(22, parent.height / 20)
                availableWidth: parent.width - 24
                z: 11

                selectionMode: root.selectionMode
                captureOptions: root.supportsCaptureOptions
                recordingAvailable: root.recordingAvailable
                precision: root.precision
                delaySeconds: root.delaySeconds
                recording: root.isRecording
                systemAudio: root.systemAudio
                microphone: root.microphone
                canConfirm: root.canConfirm
                onSelectMode: mode => root.modeSelected(mode)
                onTogglePrecision: root.togglePrecision()
                onCycleDelay: root.cycleDelay()
                onToggleRecordingMode: root.recordingModeRequested()
                onToggleSystemAudio: root.systemAudioToggled()
                onToggleMicrophone: root.microphoneToggled()
                onConfirmCapture: root.confirmCapture()
            }
        }
    }
}
