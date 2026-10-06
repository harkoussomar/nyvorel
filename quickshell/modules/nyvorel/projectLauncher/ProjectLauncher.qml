import qs
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Scope {
    id: root

    readonly property bool open:
        GlobalStates.exclusiveSurfaceActive("projects")

    // Caelestia-style presentation lifecycle: keep the layer mapped long
    // enough for the visual surface to finish its exit animation.
    property bool launcherMapped: false
    property bool launcherShown: false
    property bool closing: false

    // phase4e-consolidated-surface-deformation-v1
    // phase4c-prism-production-deformation-v1
    //
    // Phase 4C production calibration.
    // The Phase 4B.2 runtime audit proved whole-card visual ownership is the
    // correct deformation layer. This keeps that architecture and reduces the
    // exaggerated verification values to a restrained production profile.
    // Layout/capture geometry is unchanged. Fluid/Mica/default, Reduced Motion,
    // and Prism-with-expressive-disabled resolve to the normal resting surface.
    // prism-v2-phase5: spatial motion replaces the old rubber/non-uniform deformation.
    readonly property bool prismSurfaceDeformationEnabled:
        false

    property real prismSurfaceScaleX: 1
    property real prismSurfaceScaleY: 1
    property real prismSurfaceRadiusScale: 1

    function resetPrismSurfaceDeformation(): void {
        prismSurfaceDeformAnimation.stop()

        root.prismSurfaceScaleX = 1
        root.prismSurfaceScaleY = 1
        root.prismSurfaceRadiusScale = 1
    }

    function kickPrismSurfaceDeformation(): void {
        prismSurfaceDeformAnimation.stop()

        if (!root.prismSurfaceDeformationEnabled) {
            root.resetPrismSurfaceDeformation()
            return
        }

        // Production entry: restrained inward compression with a short
        // material-radius breath. The whole visual card participates.
        root.prismSurfaceScaleX = Appearance.surfaceDeformation.compactStartX
        root.prismSurfaceScaleY = Appearance.surfaceDeformation.compactStartY
        root.prismSurfaceRadiusScale = Appearance.surfaceDeformation.compactRadiusStart

        prismSurfaceDeformAnimation.restart()
    }

    onPrismSurfaceDeformationEnabledChanged: {
        if (!root.prismSurfaceDeformationEnabled)
            root.resetPrismSurfaceDeformation()
    }

    onOpenChanged: {
        if (root.open)
            root.beginLauncherOpen()
        else
            root.beginLauncherClose()
        Qt.callLater(() => root.syncShellCaptureRegion())
    }
    property var projects: []
    property var tools: ({ code: false, kitty: false, zed: false })
    property int currentIndex: 0
    property var preview: null
    property bool listLoading: false
    property bool previewLoading: false
    property string errorText: ""

    readonly property string helperPath: Quickshell.shellPath("modules/nyvorel/projectLauncher/nyvorel-projects.py")
    readonly property string query:
        searchInput.text.trim().toLowerCase()

    readonly property var filteredProjects:
        projects.filter(project =>
            root.query.length === 0
            || (
                project.name
                + " "
                + project.group
                + " "
                + project.displayPath
            ).toLowerCase().indexOf(root.query) !== -1
        )

    readonly property var categories: {
        const found = []

        for (const project of root.filteredProjects) {
            if (
                project.group
                && !found.includes(project.group)
            ) {
                found.push(project.group)
            }
        }

        return found
    }

    readonly property var navigationItems: {
        const rows = []

        for (const category of root.categories) {
            const categoryProjects =
                root.filteredProjects.filter(
                    project =>
                        project.group === category
                )

            if (!categoryProjects.length)
                continue

            rows.push({
                kind: "section",
                category: category,
                label: root.categoryLabel(category),
                icon: root.categoryIcon(category),
                count: categoryProjects.length
            })

            for (const project of categoryProjects) {
                rows.push({
                    kind: "project",
                    project: project
                })
            }
        }

        return rows
    }

    readonly property var currentProject:
        filteredProjects.length
            ? filteredProjects[
                Math.max(
                    0,
                    Math.min(
                        currentIndex,
                        filteredProjects.length - 1
                    )
                )
            ]
            : null

    function categoryLabel(value): string {
        const category =
            String(value || "")

        if (category.toLowerCase() === "oss")
            return "OSS"

        return category
            .replace(/[-_]/g, " ")
            .replace(
                /\b\w/g,
                character =>
                    character.toUpperCase()
            )
    }

    function categoryIcon(value): string {
        switch (
            String(value || "").toLowerCase()
        ) {
        case "personal":
            return "person"

        case "work":
            return "work"

        case "oss":
        case "open-source":
        case "opensource":
            return "public"

        case "test":
        case "tests":
            return "science"

        case "school":
        case "university":
        case "learning":
            return "school"

        case "client":
        case "clients":
            return "business_center"

        case "archive":
            return "archive"

        default:
            return "folder_special"
        }
    }

    function stackIsFramework(name): bool {
        return [
            "Next.js",
            "React",
            "Vue",
            "Nuxt",
            "Svelte",
            "SvelteKit",
            "Angular",
            "Astro",
            "NestJS",
            "FastAPI",
            "Django",
            "Flask"
        ].includes(String(name))
    }

    // Native Nyvorel visual system.
    readonly property color bg: Appearance.colors.colLayer0
    readonly property color pane: Appearance.colors.colLayer1
    readonly property color selected: Appearance.colors.colSecondaryContainer
    readonly property color subtle: Appearance.colors.colLayer2Hover
    readonly property color text: Appearance.m3colors.m3onSurface
    readonly property color text2: Appearance.colors.colOnLayer1
    readonly property color accent: Appearance.colors.colPrimary
    readonly property color outline: Appearance.colors.colLayer0Border
    readonly property color muted: Appearance.colors.colSubtext
    readonly property color green: Appearance.colors.colPrimary
    readonly property color red: Appearance.colors.colError
    readonly property string mono: Appearance.font.family.monospace

    function syncShellCaptureRegion(): void {
        if (
            !root.open
            || !win.screen
            || card.width <= 0
            || card.height <= 0
        ) {
            GlobalStates.clearCaptureRegion("projects")
            return
        }

        // >>> SNIP-TARGETING-V3 projectLauncher >>>
        //
        // `win` is a full-screen overlay. Its card coordinates are already
        // monitor-local, so adding the monitor reserved top edge shifts the
        // target down by the navbar height. Scene mapping also tracks the
        // launcher's presentation transforms.
        const topLeft =
            card.mapToItem(null, 0, 0)
        const bottomRight =
            card.mapToItem(
                null,
                card.width,
                card.height
            )

        const captureX =
            Math.min(topLeft.x, bottomRight.x)
        const captureY =
            Math.min(topLeft.y, bottomRight.y)
        const captureWidth =
            Math.abs(bottomRight.x - topLeft.x)
        const captureHeight =
            Math.abs(bottomRight.y - topLeft.y)

        GlobalStates.registerCaptureRegion(
            "projects",
            win.screen.name,
            captureX,
            captureY,
            captureWidth,
            captureHeight,
            150,
            "Project Launcher",
            4
        )
        // <<< SNIP-TARGETING-V3 projectLauncher <<<
    }

    function openLauncher(): void {
        if (root.open)
            return

        GlobalStates.openExclusiveSurface("projects")

        errorText = ""
        searchInput.text = ""
        currentIndex = 0
        preview = null
        refreshProjects()

        Qt.callLater(() => searchInput.forceActiveFocus())
        Qt.callLater(() => root.syncShellCaptureRegion())
    }

    function closeLauncher(): void {
        if (!root.open)
            return

        GlobalStates.closeExclusiveSurface(
            "projects",
            false
        )

        // Keep the visible content stable while the exit choreography runs.
        // Cleanup happens after the layer is unmapped.
        GlobalStates.clearCaptureRegion("projects")
    }

    function toggle(): void {
        if (open) closeLauncher(); else openLauncher();
    }

    function beginLauncherOpen(): void {
        launcherCloseUnmapTimer.stop()
        root.closing = false

        if (!root.launcherMapped) {
            root.launcherShown = false
            root.launcherMapped = true
            launcherOpenKickTimer.restart()
            return
        }

        root.launcherShown = true
    }

    function beginLauncherClose(): void {
        launcherOpenKickTimer.stop()

        // Keep close/unmap deterministic. The specialized material deformation
        // is entrance-only and is reset before the existing 220ms exit path.
        root.resetPrismSurfaceDeformation()

        if (!root.launcherMapped)
            return

        root.closing = true
        root.launcherShown = false
        launcherCloseUnmapTimer.restart()
    }

    Timer {
        id: launcherOpenKickTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (root.open && root.launcherMapped) {
                root.closing = false
                root.kickPrismSurfaceDeformation()
                root.launcherShown = true
            }
        }
    }

    // Phase 4C production deformation.
    // Keep the verified whole-card ownership, but reduce amplitude and shorten
    // the secondary material motion so it accents the entrance rather than
    // competing with the existing lift/scale/opacity choreography.
    ParallelAnimation {
        id: prismSurfaceDeformAnimation

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "prismSurfaceScaleX"
                to: Appearance.surfaceDeformation.compactMiddleX
                duration: Math.max(
                    1,
                    Math.round(
                        Appearance.surfaceDeformation.compactXCompressMs
                        * Appearance.motionScale
                    )
                )
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance
                        .animationCurves
                        .expressiveFastSpatial
            }

            NumberAnimation {
                target: root
                property: "prismSurfaceScaleX"
                to: 1
                duration: Math.max(
                    1,
                    Math.round(
                        Appearance.surfaceDeformation.compactXSettleMs
                        * Appearance.motionScale
                    )
                )
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance
                        .animationCurves
                        .expressiveDefaultEffects
            }
        }

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "prismSurfaceScaleY"
                to: Appearance.surfaceDeformation.compactMiddleY
                duration: Math.max(
                    1,
                    Math.round(
                        Appearance.surfaceDeformation.compactYCompressMs
                        * Appearance.motionScale
                    )
                )
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance
                        .animationCurves
                        .expressiveFastSpatial
            }

            NumberAnimation {
                target: root
                property: "prismSurfaceScaleY"
                to: 1
                duration: Math.max(
                    1,
                    Math.round(
                        Appearance.surfaceDeformation.compactYSettleMs
                        * Appearance.motionScale
                    )
                )
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance
                        .animationCurves
                        .expressiveDefaultSpatial
            }
        }

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "prismSurfaceRadiusScale"
                to: Appearance.surfaceDeformation.compactRadiusMiddle
                duration: Math.max(
                    1,
                    Math.round(
                        Appearance.surfaceDeformation.compactRadiusCompressMs
                        * Appearance.motionScale
                    )
                )
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance
                        .animationCurves
                        .expressiveFastEffects
            }

            NumberAnimation {
                target: root
                property: "prismSurfaceRadiusScale"
                to: 1
                duration: Math.max(
                    1,
                    Math.round(
                        Appearance.surfaceDeformation.compactRadiusSettleMs
                        * Appearance.motionScale
                    )
                )
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance
                        .animationCurves
                        .expressiveDefaultEffects
            }
        }
    }

    Timer {
        id: launcherCloseUnmapTimer
        interval: 260 // motion-calibrated-v1
        repeat: false
        onTriggered: {
            if (!root.open) {
                searchInput.text = ""
                root.preview = null
                root.launcherMapped = false
                root.closing = false
            }
        }
    }

    Component.onCompleted: {
        if (root.open)
            root.beginLauncherOpen()
    }

    function refreshProjects(): void {
        if (!open) return;
        listLoading = true;
        listProcess.exec(["python3", helperPath, "list"]);
    }

    function requestPreview(): void {
        preview = null;
        if (!open || currentProject === null) return;
        previewDebounce.restart();
    }

    function refreshPreviewNow(): void {
        if (!open || currentProject === null) return;
        previewLoading = true;
        previewProcess.exec(["python3", helperPath, "preview", currentProject.path]);
    }

    function ensureCurrentVisible(): void {
        if (
            !root.currentProject
            || !scroll
        )
            return

        const index =
            root.navigationItems.findIndex(
                row =>
                    row.kind === "project"
                    && row.project
                    && row.project.path
                        === root.currentProject.path
            )

        if (index >= 0) {
            scroll.positionViewAtIndex(
                index,
                ListView.Contain
            )
        }
    }

    function moveSelection(delta: int): void {
        const count =
            root.filteredProjects.length

        if (!count)
            return

        root.currentIndex =
            (
                root.currentIndex
                + delta
                + count
            ) % count

        root.requestPreview()

        Qt.callLater(
            root.ensureCurrentVisible
        )
    }

    function selectProject(project): void {
        if (!project)
            return

        for (
            let index = 0;
            index < root.filteredProjects.length;
            ++index
        ) {
            if (
                root.filteredProjects[index].path
                    === project.path
            ) {
                root.currentIndex =
                    index

                root.preview =
                    null

                root.requestPreview()

                Qt.callLater(
                    root.ensureCurrentVisible
                )

                return
            }
        }
    }

    function launch(action: string): void {
        if (currentProject === null) return;
        const p = currentProject.path;
        if (action === "code" && tools.code) {
            Quickshell.execDetached(["code", p]);
            closeLauncher();
        } else if (action === "terminal" && tools.kitty) {
            Quickshell.execDetached(["kitty", "-1", "--directory", p]);
            closeLauncher();
        } else if (action === "zed" && tools.zed) {
            Quickshell.execDetached(["zed", p]);
            closeLauncher();
        }
    }

    function handleKey(event): void {
        if (event.key === Qt.Key_Escape) {
            closeLauncher(); event.accepted = true; return;
        }
        if (event.key === Qt.Key_Up) {
            moveSelection(-1); event.accepted = true; return;
        }
        if (event.key === Qt.Key_Down) {
            moveSelection(1); event.accepted = true; return;
        }
        if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier) !== 0) {
            refreshProjects();
            requestPreview();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if ((event.modifiers & Qt.ControlModifier) !== 0) launch("terminal");
            else if ((event.modifiers & Qt.AltModifier) !== 0) launch("zed");
            else launch("code");
            event.accepted = true;
        }
    }

    GlobalShortcut {
        name: "projectsToggle"
        description: "Open project command center"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "projects"
        function toggle(): void { root.toggle(); }
        function open(): void { root.openLauncher(); }
        function close(): void { root.closeLauncher(); }
        function refresh(): void { root.refreshProjects(); root.requestPreview(); }
    }

    Process {
        id: listProcess
        stdout: StdioCollector {
            onStreamFinished: {
                root.listLoading = false;
                try {
                    const d = JSON.parse(this.text);
                    if (d.error) { root.errorText = d.error; return; }
                    const old = root.currentProject ? root.currentProject.path : "";
                    root.projects = d.projects || [];
                    root.tools = d.tools || ({ code: false, kitty: false, zed: false });
                    root.currentIndex = 0;
                    if (old) {
                        for (let i = 0; i < root.filteredProjects.length; ++i)
                            if (root.filteredProjects[i].path === old) { root.currentIndex = i; break; }
                    }
                    root.requestPreview();
                } catch (e) {
                    root.errorText = "Could not read project list.";
                }
            }
        }
    }

    Process {
        id: previewProcess
        stdout: StdioCollector {
            onStreamFinished: {
                root.previewLoading = false;
                try {
                    const d = JSON.parse(this.text);
                    if (d.error) { root.errorText = d.error; return; }
                    if (root.currentProject && d.path === root.currentProject.path) {
                        root.preview = d;
                        root.errorText = "";
                    }
                } catch (e) {}
            }
        }
    }

    Timer { id: previewDebounce; interval: 90; onTriggered: root.refreshPreviewNow() }
    Timer { interval: 4000; repeat: true; running: root.open; onTriggered: root.refreshPreviewNow() }
    Timer { interval: 30000; repeat: true; running: root.open; onTriggered: root.refreshProjects() }

    // ============================================================
    // Native footer hint
    // ============================================================

    component FooterHint: Row {
        id: footerHint

        required property string keyText
        required property string label

        property bool available: true

        visible:
            available

        spacing:
            7


        KeyboardKey {
            anchors.verticalCenter:
                parent.verticalCenter

            key:
                footerHint.keyText

            pixelSize:
                Appearance.font.pixelSize.smaller

            borderColor:
                Appearance.colors.colOutlineVariant

            keyColor:
                Appearance.colors.colLayer1
        }


        StyledText {
            anchors.verticalCenter:
                parent.verticalCenter

            text:
                footerHint.label

            color:
                Appearance.colors.colSubtext

            font {
                family:
                    root.mono

                pixelSize:
                    Appearance.font.pixelSize.smaller
            }
        }
    }

    // Backup & Recovery visual grammar: section label outside its content surface.
    component Section: RowLayout {
        id: section

        property string title: ""
        property string detail: ""
        property string iconName: ""

        Layout.fillWidth: true
        spacing: 7

        MaterialSymbol {
            visible: section.iconName.length > 0
            text: section.iconName
            iconSize: 15
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            text: section.title
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
        }

        StyledText {
            visible: section.detail.length > 0
            text: section.detail
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }


    PanelWindow {
        id: win

        onScreenChanged:
            Qt.callLater(() => root.syncShellCaptureRegion())
        visible:
            root.launcherMapped

        color:
            "transparent"

        aboveWindows:
            true

        focusable:
            true

        exclusionMode:
            ExclusionMode.Ignore


        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }


        // glass-system-v2.4-project-mask-padding
        Item {
            id: glassProjectMaskBounds
            x: card.x - 6
            y: card.y - 6
            width: card.width + 12
            height: card.height + 12
            visible: false
        }
        // glass-system-v2.3b-shape
        Region {
            id: glassProjectVisibleMask
            item: glassProjectMaskBounds
        }
        HyprlandWindow.visibleMask:
            Config.options.appearance.transparency.enable
                ? glassProjectVisibleMask
                : null

        WlrLayershell.namespace:
            "quickshell:projectLauncher"

        WlrLayershell.layer:
            WlrLayer.Overlay

        // project-launcher-snip-focus-v1
        //
        // Project Launcher owns keyboard focus normally, but Region Selector
        // must temporarily receive it while the launcher remains visible.
        WlrLayershell.keyboardFocus:
            GlobalStates.regionSelectorOpen
                ? WlrKeyboardFocus.None
                : (
                    root.open && !root.closing
                        ? WlrKeyboardFocus.Exclusive
                        : WlrKeyboardFocus.None
                )


        onVisibleChanged: {
            if (visible) {
                Qt.callLater(() => {
                    searchInput.forceActiveFocus()
                })
            }
        }


        // ========================================================
        // Transparent click-away layer.
        //
        // No dark scrim: preserve the wallpaper/environment.
        // ========================================================

        Rectangle {
            anchors.fill:
                parent

            color:
                "transparent"


            MouseArea {
                anchors.fill:
                    parent
                enabled: root.open && !root.closing

                onClicked:
                    root.closeLauncher()
            }
        }


        // ========================================================
        // Main command center
        // ========================================================

        Rectangle {
            id: card

            onXChanged: root.syncShellCaptureRegion()
            onYChanged: root.syncShellCaptureRegion()
            onWidthChanged: root.syncShellCaptureRegion()
            onHeightChanged: root.syncShellCaptureRegion()
            onScaleChanged: root.syncShellCaptureRegion()
            anchors.centerIn: parent

            // Transient launcher: deliberately smaller than Appearance Studio.
            width: Math.min(
                1040,
                win.width - (win.width < 1140 ? 40 : 80)
            )
            height: Math.min(
                670,
                win.height - (win.height < 760 ? 40 : 80)
            )

            // The card remains the authoritative geometry/content container.
            // The material stays separate for color/border/radius ownership;
            // Phase 4B.2 deformation itself is applied to the whole card.
            color: "transparent"
            radius: Appearance.radius.modal
            border.width: 0
            border.color: "transparent"
            // Prism's modal surface owns an external shadow; keep clipping for
            // every established interface while allowing that elevation to render.
            clip: !Appearance.prismMode && !Appearance.inlayMode

            // Caelestia-style entrance: visibility resolves quickly while the
            // spatial motion continues settling. Resting geometry is unchanged.
            transformOrigin: Item.Center
            opacity: root.launcherShown ? 1 : 0
            scale:
                root.launcherShown
                    ? 1
                    : (
                        root.closing
                            ? (Appearance.inlayMode ? 1 : 0.985)
                            : (Appearance.inlayMode
                                ? 1
                                : Appearance.prismMode ? Appearance.prism.enterScale : 0.970)
                    )

            transform: [
                Translate {
                    id: projectLauncherLift

                    y:
                        root.launcherShown
                            ? 0
                            : (
                                root.closing
                                    ? (Appearance.inlayMode ? 0 : 18)
                                    : (Appearance.inlayMode
                                        ? Appearance.inlay.enterDistance
                                        : Appearance.prismMode ? Appearance.prism.enterDistance * 2 : 34)
                            )

                    onYChanged:
                        root.syncShellCaptureRegion()

                    Behavior on y {
                        MotionExpressiveAnim {
                            phase:
                                root.closing
                                    ? MotionExpressiveAnim.Exit
                                    : MotionExpressiveAnim.Enter
                        }
                    }
                },

                // phase4c-prism-production-deformation-v1
                // Whole-card ownership was proven by the Phase 4B.2 runtime
                // audit. Only the production amplitude/timing changes here.
                Scale {
                    id: projectLauncherDeformationScale

                    origin.x:
                        card.width
                        / 2

                    origin.y:
                        card.height
                        / 2

                    xScale:
                        root.prismSurfaceScaleX

                    yScale:
                        root.prismSurfaceScaleY

                    onXScaleChanged:
                        root.syncShellCaptureRegion()

                    onYScaleChanged:
                        root.syncShellCaptureRegion()
                }
            ]

            Behavior on opacity {
                MotionAnim {
                    type:
                        root.closing
                            ? MotionAnim.FastEffects
                            : MotionAnim.DefaultEffects
                    duration: root.closing ? 180 : 200
                }
            }

            Behavior on scale {
                MotionExpressiveAnim {
                    phase:
                        root.closing
                            ? MotionExpressiveAnim.Exit
                            : MotionExpressiveAnim.Enter
                }
            }

            // prism-v2-phase5: modal elevation belongs to the surface, not to
            // elastic deformation of its entire content tree.
            PrismSurface {
                visible:
                    Appearance.prismMode

                anchors.fill:
                    parent

                depth:
                    Appearance.prism.depthModal

                surfaceRadius:
                    Appearance.prism.radiusModal

                elevated:
                    true

                borderWidth:
                    1
            }

            Rectangle {
                id: projectLauncherMaterialSurface

                anchors.fill:
                    parent

                color:
                    Appearance.prismMode
                        ? "transparent"
                        : Appearance.inlayMode
                            ? Appearance.inlay.surfaceFill
                            : Appearance.colors.colLayer0Base

                radius:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.prismMode
                            ? Appearance.prism.radiusModal
                            : Appearance.radius.modal

                border.width:
                    Appearance.prismMode
                        ? 0
                        : Appearance.inlayMode
                            ? Appearance.inlay.borderWidth
                            : 1

                border.color:
                    Appearance.inlayMode
                        ? Appearance.inlay.borderControl
                        : Appearance.colors.colLayer0Border

                antialiasing:
                    true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => mouse.accepted = true
            }

            // ========================================================
            // Header
            // ========================================================

            Item {
                id: header

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    leftMargin: 16
                    rightMargin: 12
                }

                height: 70

                Rectangle {
                    id: headerIcon

                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }

                    width: 42
                    height: 42
                    radius: Appearance.radius.card
                    color: Appearance.colors.colSecondaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "folder_open"
                        iconSize: 22
                        fill: 1
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                RowLayout {
                    id: headerActions

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }

                    spacing: 4

                    StyledText {
                        text: root.listLoading
                            ? "Refreshing…"
                            : root.query.length
                                ? `${root.filteredProjects.length} / ${root.projects.length} projects`
                                : `${root.projects.length} project${root.projects.length === 1 ? "" : "s"}`

                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }

                    Item { width: 4; height: 1 }

                    // Normalized to the Battery dialog action-button DNA.
                    Rectangle {
                        id: refreshProjectsButton
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: height / 2
                        activeFocusOnTab: true

                        Accessible.role: Accessible.Button
                        Accessible.name: "Refresh projects"
                        Accessible.focusable: true
                        Accessible.focused: refreshProjectsButton.activeFocus
                        Accessible.onPressAction: {
                            root.refreshProjects()
                            root.requestPreview()
                            searchInput.forceActiveFocus()
                        }

                        Keys.onPressed: event => {
                            if (
                                event.key === Qt.Key_Space
                                || event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter
                            ) {
                                root.refreshProjects()
                                root.requestPreview()
                                searchInput.forceActiveFocus()
                                event.accepted = true
                            }
                        }

                        color:
                            refreshProjectsArea.containsMouse || refreshProjectsButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Qt.rgba(
                                    Appearance.colors.colOnSurfaceVariant.r,
                                    Appearance.colors.colOnSurfaceVariant.g,
                                    Appearance.colors.colOnSurfaceVariant.b,
                                    0.07
                                )

                        border.width: 1
                        border.color:
                            refreshProjectsArea.containsMouse || refreshProjectsButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 19
                            color:
                                refreshProjectsArea.containsMouse || refreshProjectsButton.activeFocus
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnSurfaceVariant
                        }

                        MouseArea {
                            id: refreshProjectsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.refreshProjects()
                                root.requestPreview()
                                searchInput.forceActiveFocus()
                            }
                        }
                    }

                    Rectangle {
                        id: closeProjectsButton
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: height / 2
                        activeFocusOnTab: true

                        Accessible.role: Accessible.Button
                        Accessible.name: "Close Projects"
                        Accessible.focusable: true
                        Accessible.focused: closeProjectsButton.activeFocus
                        Accessible.onPressAction: root.closeLauncher()

                        Keys.onPressed: event => {
                            if (
                                event.key === Qt.Key_Space
                                || event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter
                            ) {
                                root.closeLauncher()
                                event.accepted = true
                            }
                        }

                        color:
                            closeProjectsArea.containsMouse || closeProjectsButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Qt.rgba(
                                    Appearance.colors.colOnSurfaceVariant.r,
                                    Appearance.colors.colOnSurfaceVariant.g,
                                    Appearance.colors.colOnSurfaceVariant.b,
                                    0.07
                                )

                        border.width: 1
                        border.color:
                            closeProjectsArea.containsMouse || closeProjectsButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer0Border

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 19
                            color:
                                closeProjectsArea.containsMouse || closeProjectsButton.activeFocus
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnSurfaceVariant
                        }

                        MouseArea {
                            id: closeProjectsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeLauncher()
                        }
                    }
                }

                ColumnLayout {
                    anchors {
                        left: headerIcon.right
                        leftMargin: 12
                        right: headerActions.left
                        rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }

                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: "Projects"
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight

                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.large
                            weight: Font.DemiBold
                            variableAxes: Appearance.font.variableAxes.title
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Jump back into your workspace"
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }
            }

            Rectangle {
                id: headerRule
                anchors {
                    left: parent.left
                    right: parent.right
                    top: header.bottom
                }
                height: 1
                color: Appearance.colors.colLayer0Border
            }

            // ========================================================
            // Search
            // ========================================================

            Rectangle {
                id: searchBox

                anchors {
                    top: headerRule.bottom
                    left: parent.left
                    right: parent.right
                    leftMargin: 20
                    rightMargin: 20
                }

                height: 42
                radius: Appearance.radius.control
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: searchInput.activeFocus
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer0Border

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 9
                    }

                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: 18
                        color: searchInput.activeFocus
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchInput

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        placeholderText: "Search projects, categories or paths…"
                        color: Appearance.colors.colOnLayer1
                        placeholderTextColor: Appearance.colors.colSubtext
                        selectionColor: Appearance.colors.colSecondaryContainer
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer

                        renderType: Text.NativeRendering

                        leftPadding: 0
                        rightPadding: 0
                        topPadding: 0
                        bottomPadding: 0

                        font.pixelSize: Appearance.font.pixelSize.small

                        background: Item {}

                        Accessible.name: "Search projects"

                        onTextChanged: {
                            root.currentIndex = 0
                            root.requestPreview()

                            if (scroll)
                                scroll.positionViewAtBeginning()
                        }

                        Keys.onPressed: event => root.handleKey(event)
                    }

                    RippleButton {
                        visible: searchInput.text.length > 0

                        implicitWidth: 28
                        implicitHeight: 28

                        activeFocusOnTab: true
                        Accessible.name: "Clear project search"

                        buttonRadius: Appearance.radius.full
                        buttonRadiusPressed: Appearance.radius.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active

                        onClicked: {
                            searchInput.text = ""
                            searchInput.forceActiveFocus()
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // ========================================================
            // Main workspace
            // ========================================================

            Item {
                id: body

                anchors {
                    top: searchBox.bottom
                    left: parent.left
                    right: parent.right
                    bottom: footerRule.top
                    topMargin: 12
                    bottomMargin: 10
                    leftMargin: 16
                    rightMargin: 16
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 14

                    // ------------------------------------------------
                    // Compact project navigator
                    // ------------------------------------------------

                    Rectangle {
                        id: navigationPane

                        Layout.preferredWidth: 260
                        Layout.minimumWidth: 240
                        Layout.maximumWidth: 270
                        Layout.fillHeight: true

                        radius: Appearance.radius.sidebar
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        clip: true

                        ListView {
                            id: scroll

                            anchors {
                                fill: parent
                                margins: 8
                            }

                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.navigationItems

                            delegate: Item {
                                id: navItem

                                required property var modelData

                                readonly property var project:
                                    navItem.modelData.kind === "project"
                                        ? navItem.modelData.project
                                        : null

                                readonly property bool current:
                                    navItem.project
                                    && root.currentProject
                                    && navItem.project.path === root.currentProject.path

                                width: ListView.view.width
                                height: navItem.modelData.kind === "section" ? 24 : 37

                                RowLayout {
                                    visible: navItem.modelData.kind === "section"

                                    anchors {
                                        fill: parent
                                        leftMargin: 5
                                        rightMargin: 3
                                    }

                                    spacing: 6

                                    MaterialSymbol {
                                        text: navItem.modelData.icon || "folder_special"
                                        iconSize: 13
                                        color: Appearance.colors.colSubtext
                                    }

                                    StyledText {
                                        Layout.fillWidth: true

                                        text: navItem.modelData.label || ""
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight

                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.6
                                    }

                                    StyledText {
                                        text: String(navItem.modelData.count || 0)
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                    }
                                }

                                Rectangle {
                                    visible: navItem.modelData.kind === "project"

                                    anchors {
                                        fill: parent
                                        topMargin: 1
                                        bottomMargin: 1
                                    }

                                    radius: Appearance.radius.control

                                    color: navItem.current
                                        ? Appearance.colors.colLayer2Base
                                        : projectMouse.containsMouse
                                            ? Appearance.colors.colLayer2Hover
                                            : "transparent"

                                    border.width: 0

                                    Behavior on color {
                                        MotionColorAnim {
                                            type: MotionColorAnim.FastEffects
                                        }
                                    }

                                    RowLayout {
                                        anchors {
                                            fill: parent
                                            leftMargin: 10
                                            rightMargin: 10
                                        }

                                        spacing: 9

                                        Rectangle {
                                            Layout.preferredWidth: 3
                                            Layout.preferredHeight: 22
                                            radius: Appearance.radius.full
                                            color: navItem.current
                                                ? Appearance.colors.colPrimary
                                                : "transparent"
                                        }

                                        MaterialSymbol {
                                            text: "folder"
                                            iconSize: 18
                                            fill: navItem.current ? 1 : 0
                                            color: navItem.current || projectMouse.containsMouse
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colSubtext
                                        }

                                        StyledText {
                                            Layout.fillWidth: true

                                            text: navItem.project
                                                ? navItem.project.name
                                                : ""

                                            color: Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight

                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: navItem.current
                                                ? Font.DemiBold
                                                : Font.Normal
                                        }
                                    }

                                    MouseArea {
                                        id: projectMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            root.selectProject(navItem.project)
                                            searchInput.forceActiveFocus()
                                        }

                                        onDoubleClicked: root.launch("code")
                                    }
                                }
                            }

                            Column {
                                visible: root.listLoading && root.projects.length === 0
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "progress_activity"
                                    iconSize: 26
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Discovering projects…"
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }

                            Column {
                                visible: !root.listLoading && root.filteredProjects.length === 0
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.errorText.length ? "error" : "folder_off"
                                    iconSize: 26
                                    color: root.errorText.length
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colSubtext
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    text: root.errorText.length
                                        ? "Projects unavailable"
                                        : root.query.length
                                            ? "No matching projects"
                                            : "No projects found"

                                    color: root.errorText.length
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colSubtext

                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    // ------------------------------------------------
                    // Project context — deliberately not another big card
                    // ------------------------------------------------

                    Item {
                        id: inspectorPane

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            visible: root.currentProject === null
                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 46
                                height: 46
                                radius: Appearance.radius.card
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "folder_open"
                                    iconSize: 22
                                    color: Appearance.colors.colPrimary
                                }
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Select a project"
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Choose a project from the navigator"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }

                        ColumnLayout {
                            visible: root.currentProject !== null

                            anchors {
                                fill: parent
                                topMargin: 3
                                bottomMargin: 1
                                leftMargin: 2
                                rightMargin: 2
                            }

                            spacing: 10

                            // Identity is content, not a giant nested card.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true

                                        text: root.currentProject
                                            ? root.currentProject.name
                                            : ""

                                        color: Appearance.colors.colOnLayer0
                                        elide: Text.ElideRight

                                        font {
                                            family: Appearance.font.family.title
                                            pixelSize: Appearance.font.pixelSize.larger
                                            weight: Font.DemiBold
                                            variableAxes: Appearance.font.variableAxes.title
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true

                                        text: root.preview
                                            ? root.preview.displayPath || ""
                                            : root.currentProject
                                                ? root.currentProject.displayPath || ""
                                                : ""

                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideMiddle

                                        font {
                                            family: root.mono
                                            pixelSize: Appearance.font.pixelSize.smallest
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.leftMargin: 1

                                text: root.preview
                                    ? root.preview.description
                                    : "Loading project details…"

                                color: Appearance.colors.colOnLayer1
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            Section {
                                title: "Project"
                            }

                            // Stack + repository share one compact context card.
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: contextColumn.implicitHeight + 24

                                radius: Appearance.radius.card
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                ColumnLayout {
                                    id: contextColumn

                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                        margins: 12
                                    }

                                    spacing: 9

                                    RowLayout {
                                        Layout.fillWidth: true

                                        StyledText {
                                            text: "Stack"
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            visible: root.preview && root.preview.stack

                                            text: root.preview
                                                ? `${root.preview.stack.length} detected`
                                                : ""

                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                        }

                                        Item { Layout.fillWidth: true }
                                    }

                                    Flow {
                                        id: stackFlow

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.max(
                                            26,
                                            stackFlow.childrenRect.height
                                        )

                                        spacing: 6

                                        Repeater {
                                            model: root.preview && root.preview.stack
                                                ? root.preview.stack.slice(0, 5)
                                                : []

                                            delegate: Rectangle {
                                                id: stackChip

                                                required property var modelData

                                                implicitWidth: stackChipRow.implicitWidth + 14
                                                implicitHeight: 25

                                                radius: Appearance.radius.full
                                                color: Appearance.colors.colLayer2Base
                                                border.width: 1
                                                border.color: Appearance.colors.colLayer0Border

                                                Row {
                                                    id: stackChipRow
                                                    anchors.centerIn: parent
                                                    spacing: 5

                                                    StyledText {
                                                        text: stackChip.modelData.icon
                                                        color: root.stackIsFramework(stackChip.modelData.name)
                                                            ? Appearance.colors.colPrimary
                                                            : Appearance.colors.colSubtext

                                                        font {
                                                            family: root.mono
                                                            pixelSize: Appearance.font.pixelSize.smallest
                                                        }
                                                    }

                                                    StyledText {
                                                        text: stackChip.modelData.name
                                                        color: Appearance.colors.colOnLayer2
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: Font.Medium
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            visible: root.preview
                                                && root.preview.stack
                                                && root.preview.stack.length > 5

                                            implicitWidth: moreStackText.implicitWidth + 14
                                            implicitHeight: 25

                                            radius: Appearance.radius.full
                                            color: Appearance.colors.colLayer2Base
                                            border.width: 1
                                            border.color: Appearance.colors.colLayer0Border

                                            StyledText {
                                                id: moreStackText
                                                anchors.centerIn: parent

                                                text: root.preview
                                                    ? `+${root.preview.stack.length - 5}`
                                                    : ""

                                                color: Appearance.colors.colSubtext
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Appearance.colors.colLayer0Border
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            implicitWidth: 32
                                            implicitHeight: 32
                                            radius: Appearance.radius.control
                                            color: Appearance.colors.colLayer2Base

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: root.preview
                                                    && root.preview.git
                                                    && root.preview.git.isRepo
                                                        ? "account_tree"
                                                        : "folder"

                                                iconSize: 17
                                                color: root.preview
                                                    && root.preview.git
                                                    && root.preview.git.isRepo
                                                        ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colSubtext
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 1

                                            StyledText {
                                                Layout.fillWidth: true

                                                text: !root.preview
                                                    ? "Reading repository status…"
                                                    : root.preview.git && root.preview.git.isRepo
                                                        ? root.preview.git.branch
                                                        : "No Git repository"

                                                color: Appearance.colors.colOnLayer1
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.DemiBold
                                            }

                                            StyledText {
                                                visible: root.preview
                                                    && root.preview.git
                                                    && root.preview.git.isRepo

                                                Layout.fillWidth: true

                                                text: {
                                                    if (!root.preview || !root.preview.git)
                                                        return ""

                                                    const git = root.preview.git
                                                    const sync = []

                                                    if (git.ahead)
                                                        sync.push(`↑${git.ahead}`)

                                                    if (git.behind)
                                                        sync.push(`↓${git.behind}`)

                                                    const status = git.clean
                                                        ? "Working tree clean"
                                                        : `${git.changed} changed`

                                                    return sync.length
                                                        ? `${status} · ${sync.join(" ")}`
                                                        : status
                                                }

                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                            }
                                        }

                                        Rectangle {
                                            visible: root.preview
                                                && root.preview.git
                                                && root.preview.git.isRepo

                                            implicitWidth: gitStateText.implicitWidth + 14
                                            implicitHeight: 25

                                            radius: Appearance.radius.full
                                            color: root.preview
                                                && root.preview.git
                                                && root.preview.git.clean
                                                    ? Appearance.colors.colSecondaryContainer
                                                    : Appearance.colors.colLayer2Base

                                            border.width: 0

                                            StyledText {
                                                id: gitStateText
                                                anchors.centerIn: parent

                                                text: root.preview
                                                    && root.preview.git
                                                    && root.preview.git.clean
                                                        ? "Clean"
                                                        : root.preview
                                                            && root.preview.git
                                                            ? `${root.preview.git.changed} changed`
                                                            : ""

                                                color: root.preview
                                                    && root.preview.git
                                                    && root.preview.git.clean
                                                        ? Appearance.colors.colOnSecondaryContainer
                                                        : Appearance.colors.colOnLayer2

                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }
                            }

                            StyledText {
                                visible: root.errorText.length > 0
                                Layout.fillWidth: true
                                text: root.errorText
                                color: Appearance.colors.colError
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }

                            Section {
                                visible: root.preview
                                    && root.preview.tree
                                    && root.preview.tree.length > 0
                                title: "Project structure"
                                detail: root.preview && root.preview.tree
                                    ? `${Math.min(root.preview.tree.length, 8)} of ${root.preview.tree.length}`
                                    : ""
                            }

                            Rectangle {
                                visible: root.preview
                                    && root.preview.tree
                                    && root.preview.tree.length > 0

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 148
                                Layout.maximumHeight: 218

                                radius: Appearance.radius.card
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                ColumnLayout {
                                    anchors {
                                        fill: parent
                                        margins: 12
                                    }

                                    spacing: 8

                                    GridLayout {
                                        id: structureGrid
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        columns: 2
                                        columnSpacing: 8
                                        rowSpacing: 6

                                        Repeater {
                                            model: root.preview && root.preview.tree
                                                ? root.preview.tree.slice(0, 8)
                                                : []

                                            delegate: Rectangle {
                                                id: structureItem
                                                required property var modelData

                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 31

                                                radius: Appearance.radius.control
                                                color: Appearance.colors.colLayer2Base

                                                RowLayout {
                                                    anchors {
                                                        fill: parent
                                                        leftMargin: 8
                                                        rightMargin: 8
                                                    }

                                                    spacing: 6

                                                    MaterialSymbol {
                                                        text: structureItem.modelData.isDir
                                                            ? "folder"
                                                            : "description"

                                                        iconSize: 15
                                                        color: structureItem.modelData.isDir
                                                            ? Appearance.colors.colPrimary
                                                            : Appearance.colors.colSubtext
                                                    }

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: structureItem.modelData.name || ""
                                                        color: Appearance.colors.colOnLayer2
                                                        elide: Text.ElideRight

                                                        font {
                                                            family: root.mono
                                                            pixelSize: Appearance.font.pixelSize.smallest
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                Layout.fillHeight: true
                            }

                            // Launcher actions stay compact; Enter remains the primary flow.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 7

                                Item { Layout.fillWidth: true }

                                RippleButton {
                                    visible: root.tools.code

                                    implicitWidth: 190
                                    implicitHeight: 40

                                    activeFocusOnTab: true
                                    Accessible.name: "Open selected project in VS Code"

                                    buttonRadius: Appearance.radius.control
                                    buttonRadiusPressed: Appearance.radius.control

                                    colBackground: Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    colRipple: Appearance.colors.colSecondaryContainerActive

                                    onClicked: root.launch("code")

                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "code"
                                            iconSize: 17
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }

                                        StyledText {
                                            text: "Open in VS Code"
                                            color: Appearance.colors.colOnSecondaryContainer
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                        }

                                        KeyboardKey {
                                            key: "↵"
                                            pixelSize: Appearance.font.pixelSize.smallest
                                            borderColor: Appearance.colors.colOutlineVariant
                                            keyColor: Appearance.colors.colSecondaryContainer
                                        }
                                    }
                                }

                                RippleButton {
                                    visible: root.tools.kitty

                                    implicitWidth: 40
                                    implicitHeight: 40

                                    activeFocusOnTab: true
                                    Accessible.name: "Open selected project in terminal"

                                    buttonRadius: Appearance.radius.control
                                    buttonRadiusPressed: Appearance.radius.control
                                    colBackground: Appearance.colors.colLayer1Base
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    colRipple: Appearance.colors.colLayer2Active

                                    onClicked: root.launch("terminal")

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "terminal"
                                        iconSize: 17
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }

                                RippleButton {
                                    visible: root.tools.zed

                                    implicitWidth: 40
                                    implicitHeight: 40

                                    activeFocusOnTab: true
                                    Accessible.name: "Open selected project in Zed"

                                    buttonRadius: Appearance.radius.control
                                    buttonRadiusPressed: Appearance.radius.control
                                    colBackground: Appearance.colors.colLayer1Base
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    colRipple: Appearance.colors.colLayer2Active

                                    onClicked: root.launch("zed")

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "edit_square"
                                        iconSize: 17
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ========================================================
            // Keyboard footer
            // ========================================================

            Rectangle {
                id: footerRule

                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: footer.top
                    leftMargin: 20
                    rightMargin: 20
                }

                height: 1
                color: Appearance.colors.colLayer0Border
            }

            Item {
                id: footer

                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 20
                    rightMargin: 20
                }

                height: 44

                RowLayout {
                    anchors.fill: parent
                    spacing: 14

                    FooterHint {
                        keyText: "↑↓"
                        label: "Navigate"
                    }

                    FooterHint {
                        keyText: "Enter"
                        label: "Open"
                        available: root.tools.code
                    }

                    FooterHint {
                        keyText: "Ctrl+Enter"
                        label: "Terminal"
                        available: root.tools.kitty
                    }

                    FooterHint {
                        keyText: "Alt+Enter"
                        label: "Zed"
                        available: root.tools.zed
                    }

                    Item { Layout.fillWidth: true }

                    FooterHint {
                        keyText: "Esc"
                        label: "Close"
                    }
                }
            }
}


    }
}
