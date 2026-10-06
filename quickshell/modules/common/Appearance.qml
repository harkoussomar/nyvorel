import QtQuick
import Quickshell
import qs.modules.common.functions
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property QtObject m3colors
    property QtObject animation
    property QtObject animationCurves
    // phase3d-motion-preferences-v1
    // Persistent semantic-motion controls. Clamp the duration scale here so
    // every semantic primitive receives one safe, authoritative value.
    readonly property real motionScale:
        Math.max(
            0.5,
            Math.min(1.5, Config.options.appearance.motion.scale)
        )

    readonly property bool reducedMotion:
        Config.options.appearance.motion.reduced

    readonly property bool expressiveMotion:
        Config.options.appearance.motion.expressive

    // phase4e-surface-deformation-policy-v1
    //
    // Single source of truth for Phase 4 expressive surface deformation.
    // Opt-in scope is intentionally narrow: focused modal/transient surfaces.
    // Edge sidebars, notifications, OSD, media controls, dense settings,
    // session/lock surfaces and overview stay outside this effect by design.
    property QtObject surfaceDeformation: QtObject {
        readonly property bool enabled:
            root.prismMode
            && root.expressiveMotion
            && !root.reducedMotion

        // Compact modal profile — Project Launcher.
        readonly property real compactStartX: 0.978
        readonly property real compactStartY: 0.992
        readonly property real compactMiddleX: 0.992
        readonly property real compactMiddleY: 0.978
        readonly property real compactRadiusStart: 1.08
        readonly property real compactRadiusMiddle: 0.96

        readonly property int compactXCompressMs: 120
        readonly property int compactXSettleMs: 220
        readonly property int compactYCompressMs: 105
        readonly property int compactYSettleMs: 235
        readonly property int compactRadiusCompressMs: 110
        readonly property int compactRadiusSettleMs: 230

        // Large modal profile — Appearance Studio / Backup / Arch Remote.
        readonly property real largeStartX: 0.984
        readonly property real largeStartY: 0.994
        readonly property real largeMiddleX: 0.995
        readonly property real largeMiddleY: 0.983
        readonly property real largeRadiusStart: 1.055
        readonly property real largeRadiusMiddle: 0.975

        readonly property int largeXCompressMs: 110
        readonly property int largeXSettleMs: 210
        readonly property int largeYCompressMs: 100
        readonly property int largeYSettleMs: 220
        readonly property int largeRadiusCompressMs: 105
        readonly property int largeRadiusSettleMs: 215
    }

    property QtObject colors
    // phase6b-semantic-material-system-v1
    property QtObject material
    // inlay-v2-foundation: Inlay owns a semantic matte-material token layer.
    property QtObject inlay
    // prism-v2-foundation: Prism owns a semantic spatial token layer.
    // Nothing consumes this object yet; Phase 1 is intentionally render-neutral.
    property QtObject prism
    property QtObject spacing
    property QtObject rounding
    property QtObject radius
    property QtObject font
    property QtObject sizes
    property string syntaxHighlightingTheme

    // Runtime invalidation bridge for semantic geometry.
    // Settings writes through these helpers so existing QML consumers update
    // immediately, while Config remains the persistent source of truth.
    property int radiusRevision: 0

    function touchSemanticRadius() {
        radiusRevision++
    }

    function semanticRadiusFollowsGlobal(role) {
        const revision = radiusRevision
        const entry = Config.options.appearance.geometry.radius[role]
        return entry?.followGlobal ?? false
    }

    function semanticRadiusStoredValue(role) {
        const revision = radiusRevision
        if (role === "global")
            return Math.max(0, Math.round(Config.options.appearance.geometry.radius.global))
        const entry = Config.options.appearance.geometry.radius[role]
        return Math.max(0, Math.round(entry?.value ?? 0))
    }

    function semanticRadiusResolvedValue(role) {
        const revision = radiusRevision
        const radiusConfig = Config.options.appearance.geometry.radius
        const globalValue = Math.max(0, Math.round(radiusConfig.global))
        if (role === "global")
            return globalValue
        const entry = radiusConfig[role]
        return entry?.followGlobal ? globalValue : Math.max(0, Math.round(entry?.value ?? 0))
    }

    function setSemanticRadiusGlobal(value) {
        const v = Math.max(0, Math.min(48, Math.round(value)))
        if (Config.options.appearance.geometry.radius.global === v) {
            touchSemanticRadius()
            return
        }
        Config.options.appearance.geometry.radius.global = v
        touchSemanticRadius()
    }

    function setSemanticRadiusValue(role, value) {
        const entry = Config.options.appearance.geometry.radius[role]
        if (!entry)
            return
        const v = Math.max(0, Math.min(48, Math.round(value)))
        entry.value = v
        touchSemanticRadius()
    }

    function setSemanticRadiusFollowGlobal(role, enabled) {
        const entry = Config.options.appearance.geometry.radius[role]
        if (!entry)
            return
        entry.followGlobal = enabled
        touchSemanticRadius()
    }

    // Transparency. The quadratic functions were derived from analysis of hand-picked transparency values.
    ColorQuantizer {
        id: wallColorQuant
        property string wallpaperPath: Config.options.background.wallpaperPath
        property bool wallpaperIsVideo: wallpaperPath.endsWith(".mp4") || wallpaperPath.endsWith(".webm") || wallpaperPath.endsWith(".mkv") || wallpaperPath.endsWith(".avi") || wallpaperPath.endsWith(".mov")
        source: Qt.resolvedUrl(wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath)
        depth: 0 // 2^0 = 1 color
        rescaleSize: 10
    }
    property real wallpaperVibrancy: (wallColorQuant.colors[0]?.hslSaturation + wallColorQuant.colors[0]?.hslLightness) / 2
    property real autoBackgroundTransparency: { // y = 0.5768x^2 - 0.759x + 0.2896
        let x = wallpaperVibrancy
        let y = 0.5768 * (x * x) - 0.759 * (x) + 0.2896
        return Math.max(0, Math.min(0.22, y)) - 0.12 * (m3colors.darkmode ? 0 : 1)
    }
    property real autoContentTransparency: 0.9
    property real backgroundTransparency: Config?.options.appearance.transparency.enable ? Config?.options.appearance.transparency.automatic ? autoBackgroundTransparency : Config?.options.appearance.transparency.backgroundTransparency : 0
    property real contentTransparency: Config?.options.appearance.transparency.enable
        ? Config?.options.appearance.transparency.automatic ? autoContentTransparency : Config?.options.appearance.transparency.contentTransparency
        : 0

    // inlay-v2-foundation
    // Inlay is an explicitly selected matte interface: fully opaque, sharp and
    // border-defined. The legacy Mica signature/identity remains accepted only
    // as a migration bridge so older saved configurations keep working.
    readonly property bool legacyInlaySignature:
        configuredInterfaceStyle.length === 0
        && !Config.options.appearance.transparency.enable
        && !Config.options.appearance.transparency.automatic
        && Config.options.appearance.extraBackgroundTint
    readonly property bool inlayMode:
        configuredInterfaceStyle === "inlay"
        || configuredInterfaceStyle === "mica"
        || legacyInlaySignature

    // Internal compatibility alias. Existing material plumbing is migrated in
    // later Inlay phases without changing Fluid, Prism or Default rendering.
    readonly property bool micaMode: inlayMode

    // prism-v2-foundation
    // Interface identity is now explicit. Fine-tuning opacity/radius/etc. must not
    // silently turn Prism off, and unrelated opaque profiles must not become Prism.
    // The legacy signature is retained only for pre-migration configs whose marker
    // is still empty; the installer migrates the current live config immediately.
    readonly property string configuredInterfaceStyle:
        String(Config.options.appearance.interfaceStyle ?? "").toLowerCase()
    readonly property bool legacyPrismSignature:
        configuredInterfaceStyle.length === 0
        && !Config.options.appearance.transparency.enable
        && !Config.options.appearance.transparency.automatic
        && !Config.options.appearance.extraBackgroundTint
    readonly property bool prismMode:
        configuredInterfaceStyle === "prism" || legacyPrismSignature

    // fluid-interface-v1
    // Caelestia base=0.6 / layers=0.2 translated into II transparency.
    readonly property bool fluidMode:
        Config.options.appearance.transparency.enable
        && !Config.options.appearance.transparency.automatic
        && !Config.options.appearance.extraBackgroundTint
        && Math.abs(Config.options.appearance.transparency.backgroundTransparency - 0.40) < 0.001
        && Math.abs(Config.options.appearance.transparency.contentTransparency - 0.80) < 0.001
        && Config.options.appearance.geometry.radius.global === 8
        && Config.options.appearance.geometry.radius.control.value === 4

    m3colors: QtObject {
        property bool darkmode: true
        property bool transparent: false
        property color m3background: "#141313"
        property color m3onBackground: "#e6e1e1"
        property color m3surface: "#141313"
        property color m3surfaceDim: "#141313"
        property color m3surfaceBright: "#3a3939"
        property color m3surfaceContainerLowest: "#0f0e0e"
        property color m3surfaceContainerLow: "#1c1b1c"
        property color m3surfaceContainer: "#201f20"
        property color m3surfaceContainerHigh: "#2b2a2a"
        property color m3surfaceContainerHighest: "#363435"
        property color m3onSurface: "#e6e1e1"
        property color m3surfaceVariant: "#49464a"
        property color m3onSurfaceVariant: "#cbc5ca"
        property color m3inverseSurface: "#e6e1e1"
        property color m3inverseOnSurface: "#313030"
        property color m3outline: "#948f94"
        property color m3outlineVariant: "#49464a"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#cbc4cb"
        property color m3primary: "#cbc4cb"
        property color m3onPrimary: "#322f34"
        property color m3primaryContainer: "#2d2a2f"
        property color m3onPrimaryContainer: "#bcb6bc"
        property color m3inversePrimary: "#615d63"
        property color m3secondary: "#cac5c8"
        property color m3onSecondary: "#323032"
        property color m3secondaryContainer: "#4d4b4d"
        property color m3onSecondaryContainer: "#ece6e9"
        property color m3tertiary: "#d1c3c6"
        property color m3onTertiary: "#372e30"
        property color m3tertiaryContainer: "#31292b"
        property color m3onTertiaryContainer: "#c1b4b7"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3primaryFixed: "#e7e0e7"
        property color m3primaryFixedDim: "#cbc4cb"
        property color m3onPrimaryFixed: "#1d1b1f"
        property color m3onPrimaryFixedVariant: "#49454b"
        property color m3secondaryFixed: "#e6e1e4"
        property color m3secondaryFixedDim: "#cac5c8"
        property color m3onSecondaryFixed: "#1d1b1d"
        property color m3onSecondaryFixedVariant: "#484648"
        property color m3tertiaryFixed: "#eddfe1"
        property color m3tertiaryFixedDim: "#d1c3c6"
        property color m3onTertiaryFixed: "#211a1c"
        property color m3onTertiaryFixedVariant: "#4e4447"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color term0: "#EDE4E4"
        property color term1: "#B52755"
        property color term2: "#A97363"
        property color term3: "#AF535D"
        property color term4: "#A67F7C"
        property color term5: "#B2416B"
        property color term6: "#8D76AD"
        property color term7: "#272022"
        property color term8: "#0E0D0D"
        property color term9: "#B52755"
        property color term10: "#A97363"
        property color term11: "#AF535D"
        property color term12: "#A67F7C"
        property color term13: "#B2416B"
        property color term14: "#8D76AD"
        property color term15: "#221A1A"
    }

    colors: QtObject {
        property color colSubtext: root.fluidMode ? m3colors.m3onSurfaceVariant : m3colors.m3outline
        // mica-material-v2
        // Stronger Mica/Mica-Alt-inspired hierarchy:
        // - foundation carries the wallpaper hue clearly
        // - higher content layers become progressively calmer/neutral
        // - tint changes hue/saturation while preserving each layer's luminance
        //
        // ColorUtils.mix(c1, c2, p): p=1 means all c1. These ratios therefore
        // intentionally expose 28/18/12/8/5% wallpaper hue in dark mode.
        property color micaAccent0: ColorUtils.adaptToAccent(m3colors.m3background, m3colors.m3primary)
        property color micaAccent1: ColorUtils.adaptToAccent(m3colors.m3surfaceContainerLow, m3colors.m3primary)
        property color micaAccent2: ColorUtils.adaptToAccent(m3colors.m3surfaceContainer, m3colors.m3primary)
        property color micaAccent3: ColorUtils.adaptToAccent(m3colors.m3surfaceContainerHigh, m3colors.m3primary)
        property color micaAccent4: ColorUtils.adaptToAccent(m3colors.m3surfaceContainerHighest, m3colors.m3primary)

        property color micaLayer0Base: ColorUtils.mix(
            m3colors.m3background,
            micaAccent0,
            m3colors.darkmode ? 0.72 : 0.84
        )
        property color micaLayer1Base: ColorUtils.mix(
            m3colors.m3surfaceContainerLow,
            micaAccent1,
            m3colors.darkmode ? 0.82 : 0.90
        )
        property color micaLayer2Base: ColorUtils.mix(
            m3colors.m3surfaceContainer,
            micaAccent2,
            m3colors.darkmode ? 0.88 : 0.94
        )
        property color micaLayer3Base: ColorUtils.mix(
            m3colors.m3surfaceContainerHigh,
            micaAccent3,
            m3colors.darkmode ? 0.92 : 0.96
        )
        property color micaLayer4Base: ColorUtils.mix(
            m3colors.m3surfaceContainerHighest,
            micaAccent4,
            m3colors.darkmode ? 0.95 : 0.98
        )

        property color micaBorder: ColorUtils.mix(
            m3colors.m3outlineVariant,
            ColorUtils.adaptToAccent(m3colors.m3outlineVariant, m3colors.m3primary),
            m3colors.darkmode ? 0.60 : 0.74
        )
        property color micaShadow: ColorUtils.transparentize(
            m3colors.m3shadow,
            m3colors.darkmode ? 0.56 : 0.68
        )

        // fluid-interface-v1
        // fluid-refinement-v1.2
        //
        // Keep the proven 60% foundation / lightweight nested transparency,
        // but neutralize wallpaper chroma before compositing. The palette still
        // owns text and accents; it no longer paints the whole material cyan,
        // orange or red.
        property color fluidNeutral0: m3colors.darkmode ? "#0f1214" : "#f5f7f7"
        property color fluidNeutral1: m3colors.darkmode ? "#14181b" : "#eef1f1"
        property color fluidNeutral2: m3colors.darkmode ? "#181e21" : "#e8ecec"
        property color fluidNeutral3: m3colors.darkmode ? "#1d2428" : "#e1e6e6"
        property color fluidNeutral4: m3colors.darkmode ? "#252d31" : "#d8dede"

        property color fluidLayer0Tone: ColorUtils.mix(fluidNeutral0, m3colors.m3background, 0.92)
        property color fluidLayer1Tone: ColorUtils.mix(fluidNeutral1, m3colors.m3surfaceContainerLow, 0.90)
        property color fluidLayer2Tone: ColorUtils.mix(fluidNeutral2, m3colors.m3surfaceContainer, 0.88)
        property color fluidLayer3Tone: ColorUtils.mix(fluidNeutral3, m3colors.m3surfaceContainerHigh, 0.86)
        property color fluidLayer4Tone: ColorUtils.mix(fluidNeutral4, m3colors.m3surfaceContainerHighest, 0.84)

        property color fluidLayer0Base: ColorUtils.transparentize(fluidLayer0Tone, 0.40)
        property color fluidLayer1Base: ColorUtils.transparentize(fluidLayer1Tone, 0.80)
        property color fluidLayer2Base: ColorUtils.transparentize(fluidLayer2Tone, 0.84)
        property color fluidLayer3Base: ColorUtils.transparentize(fluidLayer3Tone, 0.88)
        property color fluidLayer4Base: ColorUtils.transparentize(fluidLayer4Tone, 0.90)

        // Three edge strengths: outer frame > primary group > nested/inactive.
        property color fluidBorderStrong: ColorUtils.transparentize(
            ColorUtils.mix(m3colors.m3outline, m3colors.m3primary, 0.90),
            0.44
        )
        property color fluidBorderMedium: ColorUtils.transparentize(
            ColorUtils.mix(m3colors.m3outline, m3colors.m3primary, 0.92),
            0.64
        )
        property color fluidBorderSubtle: ColorUtils.transparentize(
            ColorUtils.mix(m3colors.m3outlineVariant, m3colors.m3primary, 0.94),
            0.78
        )
        // Compatibility name used by Fluid v1.
        property color fluidBorder: fluidBorderMedium

        // Selected/toggled containers stay recognizably accented without
        // becoming large solid cyan/teal blocks.
        property color fluidPrimaryContainer: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3primary, 0.84),
            0.38
        )
        property color fluidPrimaryContainerHover: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3primary, 0.72),
            0.28
        )
        property color fluidPrimaryContainerActive: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3primary, 0.60),
            0.18
        )

        property color fluidSecondaryContainer: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3secondary, 0.88),
            0.44
        )
        property color fluidSecondaryContainerHover: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3secondary, 0.76),
            0.32
        )
        property color fluidSecondaryContainerActive: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3secondary, 0.64),
            0.22
        )

        property color fluidTertiaryContainer: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3tertiary, 0.88),
            0.44
        )
        property color fluidTertiaryContainerHover: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3tertiary, 0.76),
            0.32
        )
        property color fluidTertiaryContainerActive: ColorUtils.transparentize(
            ColorUtils.mix(fluidNeutral3, m3colors.m3tertiary, 0.64),
            0.22
        )

        property color fluidTooltip: ColorUtils.transparentize(fluidNeutral4, 0.18)
        property color fluidShadow: ColorUtils.transparentize(m3colors.m3shadow, 0.92)

        // Layer 0
        // Base roles are used directly by several legacy II surfaces. Keep
        // their alpha aligned with the active profile, not just derived roles.
        // realistic-glass-v3: adaptive smoked-glass tint
        property color colLayer0BaseNonMica:
            Config.options.appearance.transparency.enable
                ? ColorUtils.transparentize(
                    ColorUtils.mix(
                        m3colors.m3background,
                        m3colors.m3onBackground,
                        0.88
                    ),
                    root.backgroundTransparency
                  )
                : ColorUtils.transparentize(ColorUtils.mix(m3colors.m3background, m3colors.m3primary, Config.options.appearance.extraBackgroundTint ? 0.99 : 1), root.backgroundTransparency)
        property color colLayer0Base: root.micaMode ? micaLayer0Base : (root.fluidMode ? fluidLayer0Base : colLayer0BaseNonMica)
        property color colLayer0: colLayer0Base
        property color colOnLayer0: m3colors.m3onBackground
        property color colLayer0Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.9, root.contentTransparency))
        property color colLayer0Active: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.8, root.contentTransparency))
        // realistic-glass-v3: optical edge highlight
        property color colLayer0BorderNonMica:
            Config.options.appearance.transparency.enable
                ? ColorUtils.transparentize(
                    ColorUtils.mix(
                        root.m3colors.m3onBackground,
                        root.m3colors.m3outlineVariant,
                        0.72
                    ),
                    0.68
                  )
                : ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer0, 0.4)
        property color colLayer0Border: root.micaMode ? micaBorder : (root.fluidMode ? fluidBorder : colLayer0BorderNonMica)
        // Layer 1
        property color colLayer1BaseNonMica: ColorUtils.transparentize(m3colors.m3surfaceContainerLow, root.contentTransparency)
        property color colLayer1Base: root.micaMode ? micaLayer1Base : (root.fluidMode ? fluidLayer1Base : colLayer1BaseNonMica)
        property color colLayer1: ColorUtils.solveOverlayColor(colLayer0Base, colLayer1Base, 1 - root.contentTransparency);
        property color colOnLayer1: m3colors.m3onSurfaceVariant;
        property color colOnLayer1Inactive: ColorUtils.mix(colOnLayer1, colLayer1, 0.45);
        property color colLayer1Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.92), root.contentTransparency)
        property color colLayer1Active: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.85), root.contentTransparency);
        // Layer 2
        property color colLayer2BaseNonMica: ColorUtils.transparentize(m3colors.m3surfaceContainer, root.contentTransparency)
        property color colLayer2Base: root.micaMode ? micaLayer2Base : (root.fluidMode ? fluidLayer2Base : colLayer2BaseNonMica)
        property color colLayer2: ColorUtils.solveOverlayColor(colLayer1Base, colLayer2Base, 1 - root.contentTransparency)
        property color colLayer2Hover: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.90), 1 - root.contentTransparency)
        property color colLayer2Active: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.80), 1 - root.contentTransparency);
        property color colLayer2Disabled: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, m3colors.m3background, 0.8), 1 - root.contentTransparency);
        property color colOnLayer2: m3colors.m3onSurface;
        property color colOnLayer2Disabled: ColorUtils.mix(colOnLayer2, m3colors.m3background, 0.4);
        // Layer 3
        property color colLayer3BaseNonMica: ColorUtils.transparentize(m3colors.m3surfaceContainerHigh, root.contentTransparency)
        property color colLayer3Base: root.micaMode ? micaLayer3Base : (root.fluidMode ? fluidLayer3Base : colLayer3BaseNonMica)
        property color colLayer3: ColorUtils.solveOverlayColor(colLayer2Base, colLayer3Base, 1 - root.contentTransparency)
        property color colLayer3Hover: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.90), 1 - root.contentTransparency)
        property color colLayer3Active: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.80), 1 - root.contentTransparency);
        property color colOnLayer3: m3colors.m3onSurface;
        // Layer 4
        property color colLayer4BaseNonMica: ColorUtils.transparentize(m3colors.m3surfaceContainerHighest, root.contentTransparency)
        property color colLayer4Base: root.micaMode ? micaLayer4Base : (root.fluidMode ? fluidLayer4Base : colLayer4BaseNonMica)
        property color colLayer4: ColorUtils.solveOverlayColor(colLayer3Base, colLayer4Base, 1 - root.contentTransparency)
        property color colLayer4Hover: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.90), 1 - root.contentTransparency)
        property color colLayer4Active: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.80), 1 - root.contentTransparency);
        property color colOnLayer4: m3colors.m3onSurface;
        // Primary
        property color colPrimary: m3colors.m3primary
        property color colOnPrimary: m3colors.m3onPrimary
        property color colPrimaryHover: ColorUtils.mix(colors.colPrimary, colLayer1Hover, 0.87)
        property color colPrimaryActive: ColorUtils.mix(colors.colPrimary, colLayer1Active, 0.7)
        property color colPrimaryContainer: root.fluidMode ? fluidPrimaryContainer : m3colors.m3primaryContainer
        property color colPrimaryContainerHover: root.fluidMode ? fluidPrimaryContainerHover : ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.9)
        property color colPrimaryContainerActive: root.fluidMode ? fluidPrimaryContainerActive : ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.8)
        property color colOnPrimaryContainer: root.fluidMode ? m3colors.m3onSurface : m3colors.m3onPrimaryContainer
        // Secondary
        property color colSecondary: m3colors.m3secondary
        property color colSecondaryHover: ColorUtils.mix(m3colors.m3secondary, colLayer1Hover, 0.85)
        property color colSecondaryActive: ColorUtils.mix(m3colors.m3secondary, colLayer1Active, 0.4)
        property color colOnSecondary: m3colors.m3onSecondary
        property color colSecondaryContainer: root.fluidMode ? fluidSecondaryContainer : m3colors.m3secondaryContainer
        property color colSecondaryContainerHover: root.fluidMode ? fluidSecondaryContainerHover : ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.90)
        property color colSecondaryContainerActive: root.fluidMode ? fluidSecondaryContainerActive : ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.54)
        property color colOnSecondaryContainer: root.fluidMode ? m3colors.m3onSurface : m3colors.m3onSecondaryContainer
        // Tertiary
        property color colTertiary: m3colors.m3tertiary
        property color colTertiaryHover: ColorUtils.mix(m3colors.m3tertiary, colLayer1Hover, 0.85)
        property color colTertiaryActive: ColorUtils.mix(m3colors.m3tertiary, colLayer1Active, 0.4)
        property color colTertiaryContainer: root.fluidMode ? fluidTertiaryContainer : m3colors.m3tertiaryContainer
        property color colTertiaryContainerHover: root.fluidMode ? fluidTertiaryContainerHover : ColorUtils.mix(m3colors.m3tertiaryContainer, m3colors.m3onTertiaryContainer, 0.90)
        property color colTertiaryContainerActive: root.fluidMode ? fluidTertiaryContainerActive : ColorUtils.mix(m3colors.m3tertiaryContainer, colLayer1Active, 0.54)
        property color colOnTertiary: m3colors.m3onTertiary
        property color colOnTertiaryContainer: root.fluidMode ? m3colors.m3onSurface : m3colors.m3onTertiaryContainer
        // Surface
        property color colBackgroundSurfaceContainerNonMica: ColorUtils.transparentize(m3colors.m3surfaceContainer, root.backgroundTransparency)
        property color colBackgroundSurfaceContainer: root.micaMode ? micaLayer1Base : (root.fluidMode ? fluidLayer1Base : colBackgroundSurfaceContainerNonMica)
        property color colSurfaceContainerLowNonMica: ColorUtils.solveOverlayColor(m3colors.m3background, m3colors.m3surfaceContainerLow, 1 - root.contentTransparency)
        property color colSurfaceContainerLow: root.micaMode ? micaLayer1Base : (root.fluidMode ? fluidLayer1Base : colSurfaceContainerLowNonMica)
        property color colSurfaceContainerNonMica: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerLow, m3colors.m3surfaceContainer, 1 - root.contentTransparency)
        property color colSurfaceContainer: root.micaMode ? micaLayer2Base : (root.fluidMode ? fluidLayer2Base : colSurfaceContainerNonMica)
        property color colSurfaceContainerHighNonMica: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainer, m3colors.m3surfaceContainerHigh, 1 - root.contentTransparency)
        property color colSurfaceContainerHigh: root.micaMode ? micaLayer3Base : (root.fluidMode ? fluidLayer3Base : colSurfaceContainerHighNonMica)
        property color colSurfaceContainerHighestNonMica: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerHigh, m3colors.m3surfaceContainerHighest, 1 - root.contentTransparency)
        property color colSurfaceContainerHighest: root.micaMode ? micaLayer4Base : (root.fluidMode ? fluidLayer4Base : colSurfaceContainerHighestNonMica)
        property color colSurfaceContainerHighestHover: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.95)
        property color colSurfaceContainerHighestActive: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.85)
        property color colOnSurface: m3colors.m3onSurface
        property color colOnSurfaceVariant: m3colors.m3onSurfaceVariant
        // Misc
        property color colTooltip: root.fluidMode ? fluidTooltip : m3colors.m3inverseSurface
        property color colOnTooltip: root.fluidMode ? m3colors.m3onSurface : m3colors.m3inverseOnSurface
        property color colScrim: ColorUtils.transparentize(m3colors.m3scrim, 0.5)
        property color colShadowNonMica: ColorUtils.transparentize(m3colors.m3shadow, 0.7)
        property color colShadow: root.micaMode ? micaShadow : (root.fluidMode ? fluidShadow : colShadowNonMica)
        property color colOutline: root.fluidMode ? fluidBorderMedium : m3colors.m3outline
        property color colOutlineVariant: root.fluidMode ? fluidBorderSubtle : m3colors.m3outlineVariant
        property color colError: m3colors.m3error
        property color colErrorHover: ColorUtils.mix(m3colors.m3error, colLayer1Hover, 0.85)
        property color colErrorActive: ColorUtils.mix(m3colors.m3error, colLayer1Active, 0.7)
        property color colOnError: m3colors.m3onError
        property color colErrorContainer: m3colors.m3errorContainer
        property color colErrorContainerHover: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.90)
        property color colErrorContainerActive: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.70)
        property color colOnErrorContainer: m3colors.m3onErrorContainer
    }

    // phase6b-semantic-material-system-v1
    //
    // Visual roles sit above the existing palette/layer implementation.
    // Consumers choose a role by hierarchy instead of choosing colLayerN
    // directly. Values intentionally alias the current rendering in Phase 6B:
    // this is an architecture migration, not a palette redesign.
    material: QtObject {
        // Level 1 — shell chrome / attached shell surfaces.
        readonly property color chromeFill: root.colors.colLayer0
        readonly property color chromeBorder:
            root.fluidMode
                ? root.colors.fluidBorderStrong
                : root.colors.colLayer0Border

        // Level 2 — grouped cards and control clusters.
        readonly property color groupFill: root.colors.colLayer1
        readonly property color groupHover: root.colors.colLayer1Hover
        readonly property color groupActive: root.colors.colLayer1Active
        readonly property color groupBorder:
            root.fluidMode
                ? root.colors.fluidBorderMedium
                : root.colors.colOutlineVariant

        // Level 2.5 — nested content inside a group.
        readonly property color nestedFill: root.colors.colLayer2
        readonly property color nestedHover: root.colors.colLayer2Hover
        readonly property color nestedActive: root.colors.colLayer2Active
        readonly property color nestedBorder:
            root.fluidMode
                ? root.colors.fluidBorderSubtle
                : root.colors.colOutlineVariant

        // Level 3 — raised/focused and modal material.
        readonly property color raisedFill: root.colors.colLayer3
        readonly property color raisedHover: root.colors.colLayer3Hover
        readonly property color raisedActive: root.colors.colLayer3Active
        readonly property color modalFill: root.colors.colLayer0
        readonly property color modalBorder:
            root.fluidMode
                ? root.colors.fluidBorderStrong
                : root.colors.colLayer0Border
        readonly property color shadow: root.colors.colShadow

        // Level 4 — state emphasis. Accent remains semantic rather than
        // decorative and is not used as a general-purpose surface fill.
        readonly property color selectedFill: root.colors.colSecondaryContainer
        readonly property color selectedHover:
            root.colors.colSecondaryContainerHover
        readonly property color selectedActive:
            root.colors.colSecondaryContainerActive
        readonly property color selectedText:
            root.colors.colOnSecondaryContainer
        readonly property color accent: root.colors.colPrimary
        readonly property color error: root.colors.colError

        readonly property color textPrimary: root.colors.colOnLayer0
        readonly property color textSecondary: root.colors.colOnLayer1
        readonly property color textMuted: root.colors.colSubtext

        // Border hierarchy is color-led; widths stay quiet by default.
        readonly property int frameBorderWidth: 1
        readonly property int groupBorderWidth: 1
        readonly property int nestedBorderWidth: 1
    }

    // inlay-v2-foundation
    // Inlay is material nesting rather than spatial elevation. These tokens are
    // intentionally opaque and radius-free; later phases migrate shell surfaces
    // onto this contract without touching the completed Prism/Fluid branches.
    inlay: QtObject {
        // I0..I4: base shell -> main surface -> inset -> control -> emphasis.
        readonly property color baseFill: root.colors.micaLayer0Base
        readonly property color surfaceFill: root.colors.micaLayer1Base
        readonly property color insetFill: root.colors.micaLayer2Base
        readonly property color controlFill: root.colors.micaLayer3Base
        readonly property color emphasisFill: root.colors.micaLayer4Base

        // Crisp structural borders. No glow, blur or translucent outline.
        readonly property color borderSubtle: ColorUtils.mix(
            root.colors.micaBorder, surfaceFill, 0.46)
        readonly property color borderSection: ColorUtils.mix(
            root.colors.micaBorder, insetFill, 0.62)
        readonly property color borderControl: ColorUtils.mix(
            root.m3colors.m3outline, controlFill, 0.66)
        readonly property color borderFocus: ColorUtils.mix(
            root.m3colors.m3primary, root.m3colors.m3outline, 0.74)

        // State is expressed through tone + border rather than glow/elevation.
        readonly property color hoverFill: ColorUtils.mix(
            controlFill, root.m3colors.m3onSurface, 0.96)
        readonly property color pressedFill: ColorUtils.mix(
            insetFill, root.m3colors.m3background, 0.90)
        readonly property color selectedFill: ColorUtils.mix(
            controlFill, root.m3colors.m3primary, 0.91)

        // Shape contract: Inlay is square by definition.
        readonly property int radius: 0
        readonly property int borderWidth: 1
        readonly property int focusBorderWidth: 1

        // Matte contract: no interface shadow is part of the visual language.
        readonly property color shadow: "transparent"
        readonly property int shadowBlur: 0
        readonly property int shadowOffset: 0

        // Motion is direct and mechanical: no bounce, overshoot or deformation.
        readonly property int hoverDuration: 120
        readonly property int enterDuration: 180
        readonly property int exitDuration: 150
        readonly property int enterDistance: 4
        readonly property real enterScale: 1.0
    }

    // prism-v2-foundation
    // Spatial tokens are isolated from the global material system so Prism can
    // evolve without changing Fluid, Mica, or Default rendering. Phase 1 only
    // defines the contract; consumers migrate to these roles in later phases.
    prism: QtObject {
        // Four visible planes above the wallpaper/canvas.
        readonly property int depthPersistent: 1
        readonly property int depthInteractive: 2
        readonly property int depthTransient: 3
        readonly property int depthModal: 4

        // Composition: detached objects use wallpaper as deliberate negative space.
        // prism-v2-phase2a4: persistent shell edges follow the same outer
        // rhythm as Hyprland windows. The bar host already derives its vertical
        // detachment from hyprlandGapsOut, so use that same token horizontally.
        readonly property int screenInset: Math.round(root.sizes.hyprlandGapsOut)
        readonly property int islandGap: 10
        readonly property int panelPadding: 16
        readonly property int sectionGap: 20

        // Solid, neutral surfaces. Accent is reserved for state/focus, not decoration.
        readonly property color persistentFill: ColorUtils.mix(
            root.m3colors.m3surfaceContainerLow, root.m3colors.m3background, 0.88)
        readonly property color interactiveFill: ColorUtils.mix(
            root.m3colors.m3surfaceContainer, root.m3colors.m3background, 0.90)
        readonly property color transientFill: ColorUtils.mix(
            root.m3colors.m3surfaceContainerHigh, root.m3colors.m3surfaceContainer, 0.90)
        readonly property color modalFill: ColorUtils.mix(
            root.m3colors.m3surfaceContainerHighest, root.m3colors.m3surfaceContainerHigh, 0.90)

        readonly property color borderSubtle: ColorUtils.mix(
            root.m3colors.m3outlineVariant, persistentFill, 0.46)
        readonly property color borderStrong: ColorUtils.mix(
            root.m3colors.m3outline, interactiveFill, 0.42)
        readonly property color focusBorder: ColorUtils.mix(
            root.m3colors.m3primary, root.m3colors.m3outline, 0.68)

        // prism-v2-phase2b: persistent state belongs to the owning surface.
        // Hover/open state becomes part of the island itself instead of
        // spawning nested pills or decorative accent marks.
        readonly property color persistentHoverFill: ColorUtils.mix(
            persistentFill, root.m3colors.m3onSurface, 0.95)
        readonly property color persistentActiveFill: ColorUtils.mix(
            persistentFill, root.m3colors.m3primary, 0.90)

        // Elevation recipes. These are intentionally separate from the existing
        // StyledRectangularShadow so Fluid's proven shadow path stays untouched.
        readonly property color shadowPersistent: ColorUtils.transparentize(root.m3colors.m3shadow, 0.78)
        readonly property color shadowInteractive: ColorUtils.transparentize(root.m3colors.m3shadow, 0.70)
        readonly property color shadowTransient: ColorUtils.transparentize(root.m3colors.m3shadow, 0.62)
        readonly property color shadowModal: ColorUtils.transparentize(root.m3colors.m3shadow, 0.54)
        readonly property int shadowBlurPersistent: 12
        readonly property int shadowBlurInteractive: 18
        readonly property int shadowBlurTransient: 22
        readonly property int shadowBlurModal: 28
        readonly property int shadowOffsetPersistent: 3
        readonly property int shadowOffsetInteractive: 5
        readonly property int shadowOffsetTransient: 7
        readonly property int shadowOffsetModal: 10

        // Geometry follows the existing semantic-radius system instead of creating
        // a second radius authority.
        readonly property int radiusPersistent: root.radius.bar
        readonly property int radiusInteractive: root.radius.sidebar
        readonly property int radiusTransient: root.radius.popup
        readonly property int radiusModal: root.radius.modal
        readonly property int radiusCard: root.radius.card
        readonly property int radiusControl: root.radius.control

        // Motion should communicate origin/placement, not rubbery deformation.
        readonly property real enterScale: 0.97
        readonly property real hoverScale: 1.01
        readonly property real pressedScale: 0.98
        readonly property int enterDistance: 10
        readonly property int enterDuration: 220
        readonly property int exitDuration: 170
    }

    // Small canonical spacing scale for shell composition. Existing geometry
    // that is intrinsically sized can keep its explicit value; repeated layout
    // spacing should migrate here gradually.
    spacing: QtObject {
        readonly property int xxs: 2
        readonly property int xs: 4
        readonly property int sm: 6
        readonly property int md: 8
        readonly property int lg: 10
        readonly property int xl: 12
        readonly property int xxl: 16
        readonly property int xxxl: 20
        readonly property int huge: 24
    }

    rounding: QtObject {
        property int unsharpen: 2
        property int unsharpenmore: 6
        property int verysmall: Math.min(8, root.radius.control)
        property int small: root.radius.control
        property int normal: root.radius.card
        property int large: root.radius.modal
        property int verylarge: root.radius.sidebar
        property int full: 9999
        property int screenRounding: root.radius.screen
        property int windowRounding: root.radius.window
    }

    // Semantic corner geometry. Components should choose a role by purpose instead
    // of choosing an arbitrary small/normal/large token.
    radius: QtObject {
        // radiusRevision is read inside semanticRadiusResolvedValue(), so calls
        // through the Settings bridge invalidate every consumer immediately.
        readonly property int global: root.semanticRadiusResolvedValue("global")
        readonly property int window: root.semanticRadiusResolvedValue("window")
        readonly property int bar: root.semanticRadiusResolvedValue("bar")
        readonly property int modal: root.semanticRadiusResolvedValue("modal")
        readonly property int sidebar: root.semanticRadiusResolvedValue("sidebar")
        readonly property int popup: root.semanticRadiusResolvedValue("popup")
        readonly property int card: root.semanticRadiusResolvedValue("card")
        readonly property int control: root.semanticRadiusResolvedValue("control")
        readonly property int screen: root.semanticRadiusResolvedValue("screen")
        readonly property int full: root.rounding.full
    }

    font: QtObject {
        property QtObject family: QtObject {
            property string main: Config.options.appearance.fonts.main
            property string numbers: Config.options.appearance.fonts.numbers
            property string title: Config.options.appearance.fonts.title
            property string iconMaterial: "Material Symbols Rounded"
            property string iconNerd: Config.options.appearance.fonts.iconNerd
            property string monospace: Config.options.appearance.fonts.monospace
            property string reading: Config.options.appearance.fonts.reading
            property string expressive: Config.options.appearance.fonts.expressive
        }
        property QtObject variableAxes: QtObject {
            property var main: ({
                "wght": 450,
                "wdth": 100,
            })
            property var numbers: ({
                "wght": 450,
            })
            property var title: ({ // Slightly bold weight for title
                "wght": 550, // Weight (Lowered to compensate for increased grade)
            })
        }
        property QtObject pixelSize: QtObject {
            property int smallest: 10
            property int smaller: 12
            property int smallie: 13
            property int small: 15
            property int normal: 16
            property int large: 17
            property int larger: 19
            property int huge: 22
            property int hugeass: 23
            property int title: huge
        }
    }

    animationCurves: QtObject {
        readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1] // Default, 350ms
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // Default, 500ms
        readonly property list<real> expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1] // Default, 650ms
        // Caelestia-style effects tiers: visual state changes should resolve
        // faster than geometry/spatial movement.
        readonly property list<real> expressiveFastEffects: [0.31, 0.94, 0.34, 1.00, 1, 1]
        readonly property list<real> expressiveDefaultEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
        readonly property list<real> expressiveSlowEffects: [0.34, 0.88, 0.34, 1.00, 1, 1]
        // Legacy compatibility alias used by existing Impulse components.
        readonly property list<real> expressiveEffects: expressiveDefaultEffects
        readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedFirstHalf: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82]
        readonly property list<real> emphasizedLastHalf: [5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        readonly property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        readonly property real expressiveFastSpatialDuration: 350
        readonly property real expressiveDefaultSpatialDuration: 500
        readonly property real expressiveSlowSpatialDuration: 650
        readonly property real expressiveFastEffectsDuration: 150
        readonly property real expressiveDefaultEffectsDuration: 200
        readonly property real expressiveSlowEffectsDuration: 300
        // Legacy compatibility alias.
        readonly property real expressiveEffectsDuration: expressiveDefaultEffectsDuration
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: animationCurves.expressiveDefaultSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveExit: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveExit.duration
                    easing.type: root.animation.elementMoveExit.type
                    easing.bezierCurve: root.animation.elementMoveExit.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: animationCurves.expressiveEffectsDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property int velocity: 850
            property Component colorAnimation: Component { ColorAnimation {
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
        }

        property QtObject elementResize: QtObject {
            property int duration: 300
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasized
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementResize.duration
                    easing.type: root.animation.elementResize.type
                    easing.bezierCurve: root.animation.elementResize.bezierCurve
                }
            }
        }

        property QtObject clickBounce: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 850
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.clickBounce.duration
                easing.type: root.animation.clickBounce.type
                easing.bezierCurve: root.animation.clickBounce.bezierCurve
            }}
        }
        
        property QtObject scroll: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.standardDecel
        }

        property QtObject menuDecel: QtObject {
            property int duration: 350
            property int type: Easing.OutExpo
        }
    }

    sizes: QtObject {
        property real baseBarHeight: 40
        property real barHeight: Config.options.bar.cornerStyle === 1 ? 
            (baseBarHeight + root.sizes.hyprlandGapsOut * 2) : baseBarHeight
        property real barCenterSideModuleWidth: Config.options?.bar.verbose ? 360 : 140
        property real barCenterSideModuleWidthShortened: 280
        property real barCenterSideModuleWidthHellaShortened: 190
        property real barShortenScreenWidthThreshold: 1200 // Shorten if screen width is at most this value
        property real barHellaShortenScreenWidthThreshold: 1000 // Shorten even more...
        property real elevationMargin: 10
        property real fabShadowRadius: 5
        property real fabHoveredShadowRadius: 7
        property real hyprlandGapsOut: 5
        property real mediaControlsWidth: 440
        property real mediaControlsHeight: 160
        property real notificationPopupWidth: 410
        property real osdWidth: 180
        property real searchWidthCollapsed: 210
        property real searchWidth: 360
        property real sidebarWidth: 460
        property real sidebarWidthExtended: 750
        property real baseVerticalBarWidth: 46
        property real verticalBarWidth: Config.options.bar.cornerStyle === 1 ? 
            (baseVerticalBarWidth + root.sizes.hyprlandGapsOut * 2) : baseVerticalBarWidth
        property real wallpaperSelectorWidth: 1200
        property real wallpaperSelectorHeight: 690
        property real wallpaperSelectorItemMargins: 8
        property real wallpaperSelectorItemPadding: 6
    }

    syntaxHighlightingTheme: root.m3colors.darkmode ? "Monokai" : "ayu Light"
}
