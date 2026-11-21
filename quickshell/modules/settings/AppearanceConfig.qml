import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Quickshell
import Quickshell.Io
import "." as SettingsComponents

Item {
    id: root

    readonly property string managerPath: FileUtils.trimFileProtocol(
        Quickshell.shellPath("scripts/system/nyvorel-appearance-studio"))
    property var statusData: ({})
    property var variantsData: []
    property string variantsError: ""
    property int currentPage: 0
    readonly property bool currentTabReady:
        initialized && [themeTab, surfacesTab, cornersTab, appThemingTab, savedLooksTab][currentPage]?.status === Loader.Ready
    readonly property bool usesWallpaperPalette: selectedSource === "wallpaper" || selectedSource === "hybrid"
    readonly property bool wallpaperVariantsVisible:
        visible && currentPage === 0 && currentTabReady && usesWallpaperPalette
    property bool terminalTuningRequested: false
    readonly property int cornerCardPadding: 14
    signal wallpaperRequested()

    function expandTerminalTuning(): void {
        if (!appThemingTab.item) {
            root.terminalTuningRequested = true
            return
        }
        root.terminalTuningRequested = false
        appThemingTab.item.expandTerminalTuning()
    }
    readonly property bool canClose: !root.pending && root.previewToken.length === 0
    readonly property string feedback: root.toastText.length ? root.toastText
        : !root.initialized ? "Loading appearance…" : ""
    readonly property bool pending: actionProc.running || targetProc.running || root.autoApplyPending

    function prepareToClose(): void {
        if (root.previewToken.length > 0 && !actionProc.running)
            root.revertPreview()
        else if (root.autoApplyPending && !actionProc.running) {
            root.flushAutoApply()
            // Incomplete custom colors are never written by the backend.
            if (!actionProc.running)
                root.autoApplyPending = false
        }
    }
    readonly property bool editing: actionProc.running || root.autoApplyPending || root.previewToken.length > 0
    readonly property var pageModel: [
        { id: "theme", label: "Theme", icon: "palette" },
        { id: "surfaces-motion", label: "Surfaces & motion", icon: "tune" },
        { id: "corners", label: "Corners", icon: "rounded_corner" },
        { id: "app-theming", label: "App theming", icon: "devices" },
        { id: "saved-looks", label: "Saved looks", icon: "bookmark" }
    ]

    Component.onCompleted: Qt.callLater(root.refreshStatus)

    Connections {
        target: Config.options.background
        function onWallpaperPathChanged() { wallpaperSync.restart() }
    }

    Timer {
        id: wallpaperSync
        interval: 300
        onTriggered: {
            if (root.editing) {
                restart()
                return
            }
            root.syncDraftOnNextStatus = true
            root.refreshStatus()
        }
    }

    function revertPreview(): void {
        root.previewRefreshPending = false
        previewRefreshTimer.stop()
        root.runAction([root.managerPath, "revert-preview"], "revert-preview")
    }

    function previewSaved(entry): void {
        const active = entry.active ?? ({})
        const palette = active.customPalette
        const seed = palette?.primary && palette?.secondary && palette?.tertiary && palette?.neutral
            ? "ii4:" + [palette.primary, palette.secondary, palette.tertiary, palette.neutral].join("|")
            : (active.seed ?? "")
        actionProc.savedRequest = Object.assign({}, active, {ui: entry.ui ?? ({})})
        root.runAction([root.managerPath, "apply", "--preview",
            "--source", active.source ?? "wallpaper", "--mode", active.mode ?? "dark",
            "--scheme", active.scheme ?? "auto", "--preset", active.preset ?? "",
            "--seed", seed, "--wallpaper", active.wallpaper ?? "",
            "--ui-json", JSON.stringify(entry.ui ?? ({}))], "saved-preview")
    }

    property string selectedSource: "wallpaper"
    property string selectedMode: "dark"
    property string selectedScheme: "auto"
    property string selectedPreset: "midnight"
    property string selectedWallpaper: ""
    property string customSeed: "#7AA2F7"

    // BEGIN custom-palette-studio-v2
    property bool customAdvanced: false
    property bool customShowMoreDirections: false
    property string customSecondary: "#65758A"
    property string customTertiary: "#7A6488"
    property string customNeutral: "#74777D"

    function validCustomHex(value) {
        return /^#[0-9A-Fa-f]{6}$/.test(value ?? "")
    }

    function normalizeCustomHex(value) {
        let next = (value ?? "").trim()
        if (/^[0-9A-Fa-f]{6}$/.test(next))
            next = "#" + next
        return root.validCustomHex(next) ? next.toUpperCase() : value
    }

    function customSeedPayload() {
        if (!root.customAdvanced)
            return root.customSeed
        return "ii4:" + root.customSeed
            + "|" + root.customSecondary
            + "|" + root.customTertiary
            + "|" + root.customNeutral
    }

    function restoreCustomPalette(seed, palette) {
        const p = palette ?? null
        if (p
                && root.validCustomHex(p.primary)
                && root.validCustomHex(p.secondary)
                && root.validCustomHex(p.tertiary)
                && root.validCustomHex(p.neutral)) {
            root.customAdvanced = true
            root.customSeed = p.primary.toUpperCase()
            root.customSecondary = p.secondary.toUpperCase()
            root.customTertiary = p.tertiary.toUpperCase()
            root.customNeutral = p.neutral.toUpperCase()
            return
        }

        if (root.validCustomHex(seed)) {
            root.customAdvanced = false
            root.customSeed = seed.toUpperCase()
        }
    }

    function customPaletteChanged() {
        root.markDraftChanged(false)
    }
    // END custom-palette-studio-v2

    property string favoriteName: ""
    property bool clearHistoryArmed: false
    property bool initialized: false
    property bool suppressDraftSignals: false
    property bool syncDraftOnNextStatus: false
    property bool previewRefreshPending: false
    property bool autoApplyPending: false
    property bool autoApplyInFlight: false
    property bool keepAfterPreviewUpdate: false
    property bool variantReloadPending: false
    property string previewToken: ""
    property int previewRevision: 0
    property double previewExpiresAt: 0
    property int previewSeconds: 0
    property string toastText: ""
    property bool actionFailed: false

    // Interface settings are staged locally just like theme/wallpaper choices.
    // Preview and Apply send this complete draft to the controller atomically.
    property string selectedUiProfile: "custom"
    property string interfaceBaseProfile: ""
    property string interfaceFineTuneSection: "surfaces"
    // Style identity survives fine-tuning independently of the profile label.
    property string draftInterfaceStyle: ""
    property bool draftTransparencyEnable: false
    property bool draftTransparencyAutomatic: true
    property real draftBackgroundTransparency: 0.0
    property real draftContentTransparency: 0.0
    property bool draftExtraBackgroundTint: true
    property int draftFakeScreenRounding: 0
    property int draftBarCornerStyle: 0
    property bool draftBarFloatStyleShadow: true
    property bool draftBarBorderless: false
    property bool draftBarShowBackground: true
    property bool draftBarVerbose: true
    property bool draftBarBottom: false
    property bool draftBarVertical: false
    property bool draftParallaxWorkspace: false
    property bool draftParallaxSidebar: false

    // Phase 3D motion accessibility/preferences. These remain independent
    // from the selected interface profile and use the same auto-apply/
    // preview transaction as the theme controls.
    property bool draftReducedMotion: false
    property real draftMotionScale: 1.0
    property bool draftExpressiveMotion: true

    // Semantic corner geometry. Values are staged and participate in the same
    // Preview / Keep / Revert transaction as the rest of the interface.
    property int draftRadiusGlobal: 17
    property bool draftRadiusWindowFollowGlobal: false
    property int draftRadiusWindowValue: 8
    property bool draftRadiusBarFollowGlobal: false
    property int draftRadiusBarValue: 8
    property bool draftRadiusModalFollowGlobal: false
    property int draftRadiusModalValue: 23
    property bool draftRadiusSidebarFollowGlobal: false
    property int draftRadiusSidebarValue: 23
    property bool draftRadiusPopupFollowGlobal: true
    property int draftRadiusPopupValue: 17
    property bool draftRadiusCardFollowGlobal: true
    property int draftRadiusCardValue: 17
    property bool draftRadiusControlFollowGlobal: false
    property int draftRadiusControlValue: 12
    property bool draftRadiusScreenFollowGlobal: false
    property int draftRadiusScreenValue: 8

    function refreshStatus() {
        if (!statusProc.running)
            statusProc.running = true
    }

    function uiDraftObject() {
        return {
            "appearance.interfaceStyle": root.draftInterfaceStyle,
            "appearance.extraBackgroundTint": root.draftExtraBackgroundTint,
            "appearance.fakeScreenRounding": root.draftFakeScreenRounding,
            "appearance.transparency.enable": root.draftTransparencyEnable,
            "appearance.transparency.automatic": root.draftTransparencyAutomatic,
            "appearance.transparency.backgroundTransparency": root.draftBackgroundTransparency,
            "appearance.transparency.contentTransparency": root.draftContentTransparency,
            "bar.cornerStyle": root.draftBarCornerStyle,
            "bar.floatStyleShadow": root.draftBarFloatStyleShadow,
            "bar.borderless": root.draftBarBorderless,
            "bar.showBackground": root.draftBarShowBackground,
            "bar.verbose": root.draftBarVerbose,
            "bar.bottom": root.draftBarBottom,
            "bar.vertical": root.draftBarVertical,
            "background.parallax.enableWorkspace": root.draftParallaxWorkspace,
            "background.parallax.enableSidebar": root.draftParallaxSidebar,
            "appearance.motion.reduced": root.draftReducedMotion,
            "appearance.motion.scale": root.draftMotionScale,
            "appearance.motion.expressive": root.draftExpressiveMotion,
            "appearance.geometry.radius.global": root.draftRadiusGlobal,
            "appearance.geometry.radius.window.followGlobal": root.draftRadiusWindowFollowGlobal,
            "appearance.geometry.radius.window.value": root.draftRadiusWindowValue,
            "appearance.geometry.radius.bar.followGlobal": root.draftRadiusBarFollowGlobal,
            "appearance.geometry.radius.bar.value": root.draftRadiusBarValue,
            "appearance.geometry.radius.modal.followGlobal": root.draftRadiusModalFollowGlobal,
            "appearance.geometry.radius.modal.value": root.draftRadiusModalValue,
            "appearance.geometry.radius.sidebar.followGlobal": root.draftRadiusSidebarFollowGlobal,
            "appearance.geometry.radius.sidebar.value": root.draftRadiusSidebarValue,
            "appearance.geometry.radius.popup.followGlobal": root.draftRadiusPopupFollowGlobal,
            "appearance.geometry.radius.popup.value": root.draftRadiusPopupValue,
            "appearance.geometry.radius.card.followGlobal": root.draftRadiusCardFollowGlobal,
            "appearance.geometry.radius.card.value": root.draftRadiusCardValue,
            "appearance.geometry.radius.control.followGlobal": root.draftRadiusControlFollowGlobal,
            "appearance.geometry.radius.control.value": root.draftRadiusControlValue,
            "appearance.geometry.radius.screen.followGlobal": root.draftRadiusScreenFollowGlobal,
            "appearance.geometry.radius.screen.value": root.draftRadiusScreenValue
        }
    }

    function syncUiDraft(ui, profileId) {
        const d = ui ?? ({})
        root.suppressDraftSignals = true
        root.draftInterfaceStyle = d["appearance.interfaceStyle"] ?? ""
        root.draftExtraBackgroundTint = d["appearance.extraBackgroundTint"] ?? true
        root.draftFakeScreenRounding = d["appearance.fakeScreenRounding"] ?? 0
        root.draftTransparencyEnable = d["appearance.transparency.enable"] ?? false
        root.draftTransparencyAutomatic = d["appearance.transparency.automatic"] ?? true
        root.draftBackgroundTransparency = d["appearance.transparency.backgroundTransparency"] ?? 0
        root.draftContentTransparency = d["appearance.transparency.contentTransparency"] ?? 0
        root.draftBarCornerStyle = d["bar.cornerStyle"] ?? 0
        root.draftBarFloatStyleShadow = d["bar.floatStyleShadow"] ?? true
        root.draftBarBorderless = d["bar.borderless"] ?? false
        root.draftBarShowBackground = d["bar.showBackground"] ?? true
        root.draftBarVerbose = d["bar.verbose"] ?? true
        root.draftBarBottom = d["bar.bottom"] ?? false
        root.draftBarVertical = d["bar.vertical"] ?? false
        root.draftParallaxWorkspace = d["background.parallax.enableWorkspace"] ?? false
        root.draftParallaxSidebar = d["background.parallax.enableSidebar"] ?? false
        root.draftReducedMotion = d["appearance.motion.reduced"] ?? false
        root.draftMotionScale = Math.max(0.5, Math.min(1.5, d["appearance.motion.scale"] ?? 1.0))
        root.draftExpressiveMotion = d["appearance.motion.expressive"] ?? true
        root.draftRadiusGlobal = d["appearance.geometry.radius.global"] ?? 17
        root.draftRadiusWindowFollowGlobal = d["appearance.geometry.radius.window.followGlobal"] ?? false
        root.draftRadiusWindowValue = d["appearance.geometry.radius.window.value"] ?? 8
        root.draftRadiusBarFollowGlobal = d["appearance.geometry.radius.bar.followGlobal"] ?? false
        root.draftRadiusBarValue = d["appearance.geometry.radius.bar.value"] ?? 8
        root.draftRadiusModalFollowGlobal = d["appearance.geometry.radius.modal.followGlobal"] ?? false
        root.draftRadiusModalValue = d["appearance.geometry.radius.modal.value"] ?? 23
        root.draftRadiusSidebarFollowGlobal = d["appearance.geometry.radius.sidebar.followGlobal"] ?? false
        root.draftRadiusSidebarValue = d["appearance.geometry.radius.sidebar.value"] ?? 23
        root.draftRadiusPopupFollowGlobal = d["appearance.geometry.radius.popup.followGlobal"] ?? true
        root.draftRadiusPopupValue = d["appearance.geometry.radius.popup.value"] ?? 17
        root.draftRadiusCardFollowGlobal = d["appearance.geometry.radius.card.followGlobal"] ?? true
        root.draftRadiusCardValue = d["appearance.geometry.radius.card.value"] ?? 17
        root.draftRadiusControlFollowGlobal = d["appearance.geometry.radius.control.followGlobal"] ?? false
        root.draftRadiusControlValue = d["appearance.geometry.radius.control.value"] ?? 12
        root.draftRadiusScreenFollowGlobal = d["appearance.geometry.radius.screen.followGlobal"] ?? false
        root.draftRadiusScreenValue = d["appearance.geometry.radius.screen.value"] ?? 8
        const incomingProfile = profileId ?? "custom"
        const visibleProfile =
            incomingProfile === "default" || incomingProfile === "fluid"
                ? incomingProfile
                : "custom"
        const identityStyle = root.draftInterfaceStyle
        const identityProfile =
            identityStyle === "default" || identityStyle === "fluid"
                ? identityStyle
                : ""
        root.interfaceBaseProfile = visibleProfile === "custom" ? identityProfile : visibleProfile
        root.selectedUiProfile = visibleProfile
        root.suppressDraftSignals = false
    }

    function syncDraftFromStatus(data) {
        const active = data.active ?? ({})
        root.suppressDraftSignals = true
        root.selectedSource = active.source ?? "wallpaper"
        root.selectedMode = root.normalizeAppearanceMode(active.mode ?? (Appearance.m3colors.darkmode ? "dark" : "light"))
        root.selectedScheme = active.scheme ?? data.palette?.type ?? "auto"
        root.selectedPreset = active.preset?.length > 0 ? active.preset : "midnight"
        root.selectedWallpaper = active.wallpaper?.length > 0
            ? active.wallpaper
            : (data.wallpaper ?? Config.options.background.wallpaperPath)
        if (active.seed?.length > 0 || active.customPalette)
            root.restoreCustomPalette(active.seed ?? "", active.customPalette ?? null)
        root.suppressDraftSignals = false
        root.syncUiDraft(data.ui ?? ({}), active.uiProfile ?? "custom")
    }

    function syncDraftFromPreview(preview, data) {
        const request = preview?.request ?? ({})
        const candidate = preview?.candidate ?? ({})
        root.suppressDraftSignals = true
        root.selectedSource = request.source ?? candidate.source ?? "wallpaper"
        root.selectedMode = root.normalizeAppearanceMode(request.mode ?? candidate.mode ?? "dark")
        root.selectedScheme = request.scheme ?? candidate.scheme ?? "auto"
        root.selectedPreset = request.preset?.length > 0 ? request.preset : "midnight"
        root.selectedWallpaper = request.wallpaper?.length > 0
            ? request.wallpaper
            : (candidate.wallpaper ?? data.wallpaper ?? Config.options.background.wallpaperPath)
        if (request.seed?.length > 0 || request.customPalette)
            root.restoreCustomPalette(request.seed ?? "", request.customPalette ?? null)
        root.suppressDraftSignals = false
        root.syncUiDraft(request.ui ?? data.ui ?? ({}), candidate.uiProfile ?? "custom")
    }

    function profileFor(profileId) {
        const profiles = root.statusData.uiProfiles ?? []
        for (let i = 0; i < profiles.length; ++i) {
            if (profiles[i].id === profileId)
                return profiles[i]
        }
        return null
    }

    function applyUiPatch(patch) {
        const p = patch ?? ({})
        root.suppressDraftSignals = true
        if (p["appearance.interfaceStyle"] !== undefined) root.draftInterfaceStyle = p["appearance.interfaceStyle"]
        if (p["appearance.extraBackgroundTint"] !== undefined) root.draftExtraBackgroundTint = p["appearance.extraBackgroundTint"]
        if (p["appearance.fakeScreenRounding"] !== undefined) root.draftFakeScreenRounding = p["appearance.fakeScreenRounding"]
        if (p["appearance.transparency.enable"] !== undefined) root.draftTransparencyEnable = p["appearance.transparency.enable"]
        if (p["appearance.transparency.automatic"] !== undefined) root.draftTransparencyAutomatic = p["appearance.transparency.automatic"]
        if (p["appearance.transparency.backgroundTransparency"] !== undefined) root.draftBackgroundTransparency = p["appearance.transparency.backgroundTransparency"]
        if (p["appearance.transparency.contentTransparency"] !== undefined) root.draftContentTransparency = p["appearance.transparency.contentTransparency"]
        if (p["bar.cornerStyle"] !== undefined) root.draftBarCornerStyle = p["bar.cornerStyle"]
        if (p["bar.floatStyleShadow"] !== undefined) root.draftBarFloatStyleShadow = p["bar.floatStyleShadow"]
        if (p["bar.borderless"] !== undefined) root.draftBarBorderless = p["bar.borderless"]
        if (p["bar.showBackground"] !== undefined) root.draftBarShowBackground = p["bar.showBackground"]
        if (p["bar.verbose"] !== undefined) root.draftBarVerbose = p["bar.verbose"]
        if (p["bar.bottom"] !== undefined) root.draftBarBottom = p["bar.bottom"]
        if (p["bar.vertical"] !== undefined) root.draftBarVertical = p["bar.vertical"]
        if (p["background.parallax.enableWorkspace"] !== undefined) root.draftParallaxWorkspace = p["background.parallax.enableWorkspace"]
        if (p["background.parallax.enableSidebar"] !== undefined) root.draftParallaxSidebar = p["background.parallax.enableSidebar"]
        if (p["appearance.geometry.radius.global"] !== undefined) root.draftRadiusGlobal = p["appearance.geometry.radius.global"]
        if (p["appearance.geometry.radius.window.followGlobal"] !== undefined) root.draftRadiusWindowFollowGlobal = p["appearance.geometry.radius.window.followGlobal"]
        if (p["appearance.geometry.radius.window.value"] !== undefined) root.draftRadiusWindowValue = p["appearance.geometry.radius.window.value"]
        if (p["appearance.geometry.radius.bar.followGlobal"] !== undefined) root.draftRadiusBarFollowGlobal = p["appearance.geometry.radius.bar.followGlobal"]
        if (p["appearance.geometry.radius.bar.value"] !== undefined) root.draftRadiusBarValue = p["appearance.geometry.radius.bar.value"]
        if (p["appearance.geometry.radius.modal.followGlobal"] !== undefined) root.draftRadiusModalFollowGlobal = p["appearance.geometry.radius.modal.followGlobal"]
        if (p["appearance.geometry.radius.modal.value"] !== undefined) root.draftRadiusModalValue = p["appearance.geometry.radius.modal.value"]
        if (p["appearance.geometry.radius.sidebar.followGlobal"] !== undefined) root.draftRadiusSidebarFollowGlobal = p["appearance.geometry.radius.sidebar.followGlobal"]
        if (p["appearance.geometry.radius.sidebar.value"] !== undefined) root.draftRadiusSidebarValue = p["appearance.geometry.radius.sidebar.value"]
        if (p["appearance.geometry.radius.popup.followGlobal"] !== undefined) root.draftRadiusPopupFollowGlobal = p["appearance.geometry.radius.popup.followGlobal"]
        if (p["appearance.geometry.radius.popup.value"] !== undefined) root.draftRadiusPopupValue = p["appearance.geometry.radius.popup.value"]
        if (p["appearance.geometry.radius.card.followGlobal"] !== undefined) root.draftRadiusCardFollowGlobal = p["appearance.geometry.radius.card.followGlobal"]
        if (p["appearance.geometry.radius.card.value"] !== undefined) root.draftRadiusCardValue = p["appearance.geometry.radius.card.value"]
        if (p["appearance.geometry.radius.control.followGlobal"] !== undefined) root.draftRadiusControlFollowGlobal = p["appearance.geometry.radius.control.followGlobal"]
        if (p["appearance.geometry.radius.control.value"] !== undefined) root.draftRadiusControlValue = p["appearance.geometry.radius.control.value"]
        if (p["appearance.geometry.radius.screen.followGlobal"] !== undefined) root.draftRadiusScreenFollowGlobal = p["appearance.geometry.radius.screen.followGlobal"]
        if (p["appearance.geometry.radius.screen.value"] !== undefined) root.draftRadiusScreenValue = p["appearance.geometry.radius.screen.value"]
        root.suppressDraftSignals = false
    }

    function interfaceBaseProfileObject() {
        if (root.interfaceBaseProfile.length === 0)
            return null
        return root.profileFor(root.interfaceBaseProfile)
    }

    function interfaceProfileStateLabel() {
        if (root.selectedUiProfile !== "custom") {
            const active = root.profileFor(root.selectedUiProfile)
            return active?.name ?? root.humanizeName(root.selectedUiProfile)
        }

        const base = root.interfaceBaseProfileObject()
        if (base)
            return `${base.name} · Modified`

        return "Customized"
    }

    function resetInterfaceProfile() {
        const base = root.interfaceBaseProfileObject()
        if (base)
            root.chooseUiProfile(base.id)
    }

    function chooseUiProfile(profileId) {
        const profile = root.profileFor(profileId)
        if (!profile || root.editing)
            return

        root.interfaceBaseProfile = profileId
        root.applyUiPatch(profile.patch ?? ({}))
        root.selectedUiProfile = profileId
        root.applyTheme(true, false)
    }

    function applyBarPosition(value) {
        root.suppressDraftSignals = true
        root.draftBarBottom = value === "bottom" || value === "right"
        root.draftBarVertical = value === "left" || value === "right"
        root.suppressDraftSignals = false
        root.markDraftChanged(true)
    }

    function currentBarPosition() {
        if (root.draftBarVertical)
            return root.draftBarBottom ? "right" : "left"
        return root.draftBarBottom ? "bottom" : "top"
    }

    function radiusFollowGlobal(role) {
        if (role === "window") return root.draftRadiusWindowFollowGlobal
        if (role === "bar") return root.draftRadiusBarFollowGlobal
        if (role === "modal") return root.draftRadiusModalFollowGlobal
        if (role === "sidebar") return root.draftRadiusSidebarFollowGlobal
        if (role === "popup") return root.draftRadiusPopupFollowGlobal
        if (role === "card") return root.draftRadiusCardFollowGlobal
        if (role === "control") return root.draftRadiusControlFollowGlobal
        if (role === "screen") return root.draftRadiusScreenFollowGlobal
        return false
    }

    function radiusValue(role) {
        if (role === "window") return root.draftRadiusWindowValue
        if (role === "bar") return root.draftRadiusBarValue
        if (role === "modal") return root.draftRadiusModalValue
        if (role === "sidebar") return root.draftRadiusSidebarValue
        if (role === "popup") return root.draftRadiusPopupValue
        if (role === "card") return root.draftRadiusCardValue
        if (role === "control") return root.draftRadiusControlValue
        if (role === "screen") return root.draftRadiusScreenValue
        return root.draftRadiusGlobal
    }

    function resolvedDraftRadius(role) {
        return root.radiusFollowGlobal(role) ? root.draftRadiusGlobal : root.radiusValue(role)
    }

    function setRadiusFollowGlobal(role, enabled) {
        root.suppressDraftSignals = true
        if (role === "window") root.draftRadiusWindowFollowGlobal = enabled
        else if (role === "bar") root.draftRadiusBarFollowGlobal = enabled
        else if (role === "modal") root.draftRadiusModalFollowGlobal = enabled
        else if (role === "sidebar") root.draftRadiusSidebarFollowGlobal = enabled
        else if (role === "popup") root.draftRadiusPopupFollowGlobal = enabled
        else if (role === "card") root.draftRadiusCardFollowGlobal = enabled
        else if (role === "control") root.draftRadiusControlFollowGlobal = enabled
        else if (role === "screen") root.draftRadiusScreenFollowGlobal = enabled
        root.suppressDraftSignals = false
        root.selectedUiProfile = "custom"
        root.markDraftChanged(false)
    }

    function setRadiusValue(role, value) {
        const v = Math.max(0, Math.min(48, Math.round(value)))
        root.suppressDraftSignals = true
        if (role === "window") root.draftRadiusWindowValue = v
        else if (role === "bar") root.draftRadiusBarValue = v
        else if (role === "modal") root.draftRadiusModalValue = v
        else if (role === "sidebar") root.draftRadiusSidebarValue = v
        else if (role === "popup") root.draftRadiusPopupValue = v
        else if (role === "card") root.draftRadiusCardValue = v
        else if (role === "control") root.draftRadiusControlValue = v
        else if (role === "screen") root.draftRadiusScreenValue = v
        root.suppressDraftSignals = false
        root.selectedUiProfile = "custom"
        root.markDraftChanged(false)
    }

    function makeAllRadiiFollowGlobal() {
        root.suppressDraftSignals = true
        root.draftRadiusModalFollowGlobal = true
        root.draftRadiusCardFollowGlobal = true
        root.draftRadiusControlFollowGlobal = true
        root.draftRadiusBarFollowGlobal = true
        root.draftRadiusWindowFollowGlobal = true
        root.draftRadiusSidebarFollowGlobal = true
        root.draftRadiusPopupFollowGlobal = true
        root.draftRadiusScreenFollowGlobal = true
        root.suppressDraftSignals = false
        root.selectedUiProfile = "custom"
        root.markDraftChanged(false)
    }

    function resetRadiusDefaults() {
        root.suppressDraftSignals = true
        root.draftRadiusGlobal = 17
        root.draftRadiusWindowFollowGlobal = false
        root.draftRadiusWindowValue = 8
        root.draftRadiusBarFollowGlobal = false
        root.draftRadiusBarValue = 8
        root.draftRadiusModalFollowGlobal = false
        root.draftRadiusModalValue = 23
        root.draftRadiusSidebarFollowGlobal = false
        root.draftRadiusSidebarValue = 23
        root.draftRadiusPopupFollowGlobal = true
        root.draftRadiusPopupValue = 17
        root.draftRadiusCardFollowGlobal = true
        root.draftRadiusCardValue = 17
        root.draftRadiusControlFollowGlobal = false
        root.draftRadiusControlValue = 12
        root.draftRadiusScreenFollowGlobal = false
        root.draftRadiusScreenValue = 8
        root.suppressDraftSignals = false
        root.selectedUiProfile = "custom"
        root.markDraftChanged(false)
    }

    function markDraftChanged(markCustomUi) {
        if (!root.initialized || root.suppressDraftSignals)
            return

        if (markCustomUi) {
            if (root.selectedUiProfile !== "custom")
                root.interfaceBaseProfile = root.selectedUiProfile
            root.selectedUiProfile = "custom"
        }

        if (root.previewToken.length > 0
                || (actionProc.running && ["preview", "preview-update", "saved-preview"].includes(actionProc.actionKind))) {
            root.previewRefreshPending = true
            previewRefreshTimer.restart()
        } else {
            root.autoApplyPending = true
            autoApplyTimer.restart()
        }
    }

    function flushAutoApply() {
        if (!root.initialized || root.suppressDraftSignals)
            return
        if (!root.autoApplyPending)
            return
        if (actionProc.running)
            return

        // Do not send a half-written custom seed while the user is typing.
        if (root.selectedSource === "custom") {
            if (!root.validCustomHex(root.customSeed))
                return
            if (root.customAdvanced
                    && (!root.validCustomHex(root.customSecondary)
                        || !root.validCustomHex(root.customTertiary)
                        || !root.validCustomHex(root.customNeutral)))
                return
        }

        root.autoApplyPending = false
        root.autoApplyInFlight = true
        root.actionFailed = false
        root.toastText = "Applying…"
        actionProc.actionKind = "auto-apply"
        actionProc.resultText = ""
        actionProc.exec(root.buildApplyCommand(false))
    }

    function loadVariants() {
        if (!root.wallpaperVariantsVisible)
            return

        const wallpaper = root.selectedWallpaper.length > 0
            ? root.selectedWallpaper
            : (root.statusData.wallpaper ?? Config.options.background.wallpaperPath)
        if (variantProc.running) {
            root.variantReloadPending = true
            return
        }
        root.variantReloadPending = false
        variantProc.requestWallpaper = wallpaper ?? ""
        variantProc.requestMode = root.selectedMode
        variantProc.resultText = ""
        variantProc.errorText = ""
        variantProc.exec([
            root.managerPath,
            "variants",
            "--wallpaper", variantProc.requestWallpaper,
            "--mode", variantProc.requestMode
        ])
    }

    function variantFor(schemeId) {
        for (let i = 0; i < root.variantsData.length; ++i) {
            if (root.variantsData[i].id === schemeId)
                return root.variantsData[i]
        }
        return null
    }

    function presetFor(presetId) {
        const presets = root.statusData.presets ?? []
        for (let i = 0; i < presets.length; ++i) {
            if (presets[i].id === presetId)
                return presets[i]
        }
        return null
    }

    function buildApplyCommand(preview) {
        let command = [
            root.managerPath,
            "apply",
            "--source", root.selectedSource,
            "--mode", root.selectedMode,
            "--scheme", root.selectedScheme,
            "--ui-json", JSON.stringify(root.uiDraftObject())
        ]

        if (root.selectedSource === "preset") {
            command.push("--preset", root.selectedPreset)
        } else if (root.selectedSource === "hybrid") {
            command.push("--preset", root.selectedPreset)
            if (root.selectedWallpaper.length > 0)
                command.push("--wallpaper", root.selectedWallpaper)
        } else if (root.selectedSource === "custom") {
            command.push("--seed", root.customSeedPayload())
        } else if (root.selectedWallpaper.length > 0) {
            command.push("--wallpaper", root.selectedWallpaper)
        }

        if (preview)
            command.push("--preview")

        return command
    }

    function applyTheme(preview, update) {
        if (actionProc.running) {
            if (preview)
                root.previewRefreshPending = true
            return
        }
        root.toastText = preview ? (update ? "Updating preview…" : "Building preview…") : "Applying appearance…"
        root.actionFailed = false
        actionProc.actionKind = preview ? (update ? "preview-update" : "preview") : "apply"
        actionProc.resultText = ""
        actionProc.exec(root.buildApplyCommand(preview))
    }

    function runAction(command, kind) {
        if (actionProc.running) return
        root.actionFailed = false
        actionProc.actionKind = kind
        actionProc.resultText = ""
        actionProc.exec(command)
    }

    function keepPreview() {
        if (actionProc.running || root.previewToken.length === 0)
            return

        // A user can change a control and immediately press Keep before the
        // 260 ms live-preview debounce fires. Never commit the stale revision:
        // flush the newest draft first, then Keep that exact revision.
        if (root.previewRefreshPending) {
            root.keepAfterPreviewUpdate = true
            root.previewRefreshPending = false
            previewRefreshTimer.stop()
            root.applyTheme(true, true)
            return
        }
        root.runAction([root.managerPath, "keep-preview"], "keep-preview")
    }

    function setTarget(name, enabled) {
        if (targetProc.running)
            return

        root.actionFailed = false
        targetProc.resultText = ""
        targetProc.exec([
            root.managerPath,
            "target",
            name,
            enabled ? "true" : "false"
        ])
    }

    function targetEnabled(name) {
        const targets = root.statusData.targets ?? ({})
        return targets[name] ?? true
    }

    function formatAge(timestamp) {
        if (!timestamp) return ""
        const seconds = Math.max(0, Math.floor(Date.now() / 1000) - timestamp)
        if (seconds < 60) return "just now"
        if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`
        if (seconds < 86400) return `${Math.floor(seconds / 3600)} h ago`
        return `${Math.floor(seconds / 86400)} d ago`
    }

    function humanizeName(value) {
        if (!value) return "Appearance"
        return value.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
    }

    function wallpaperTitle(path) {
        if (!path) return "Wallpaper theme"
        const name = root.shortPath(path).replace(/\.[^.]+$/, "")
        return root.humanizeName(name)
    }

    function activeTitle(active) {
        if (!active) return "Current appearance"
        const source = active.source ?? "wallpaper"
        if (source === "preset") {
            return root.presetFor(active.preset)?.name ?? "Preset theme"
        }
        if (source === "hybrid") {
            const wallpaper = root.wallpaperTitle(active.wallpaper)
            const preset = root.presetFor(active.preset)?.name ?? "Preset"
            return `${wallpaper} + ${preset}`
        }
        if (source === "custom")
            return "Custom color"
        return root.wallpaperTitle(active.wallpaper)
    }

    function entryTitle(entry, favorite) {
        if (!entry) return "Saved appearance"
        if (favorite && entry.customLabel && entry.label?.length > 0)
            return entry.label
        const active = entry.active ?? ({})
        if ((active.source ?? "") === "custom" && entry.label?.length > 0) {
            const firstPart = entry.label.split(" · ")[0]
            if (firstPart.length > 0 && !firstPart.startsWith("#"))
                return root.humanizeName(firstPart)
        }
        return root.activeTitle(active)
    }

    function entryMeta(entry) {
        const active = entry?.active ?? ({})
        const source = root.prettySource(active.source ?? "wallpaper")
        const scheme = root.prettyScheme(active.scheme ?? "auto")
        const mode = root.prettyMode(active.mode ?? "dark")
        const profile = active.uiProfile ? root.humanizeName(active.uiProfile) : "Custom UI"
        return `${source} · ${scheme} · ${mode} · ${profile}`
    }

    function entryMatchesActive(entry) {
        if (entry?.fingerprint?.length > 0 && root.statusData.currentFingerprint?.length > 0)
            return entry.fingerprint === root.statusData.currentFingerprint

        // Backward compatibility for entries created before fingerprints
        // included the complete staged interface state.
        const a = entry?.active ?? ({})
        const b = root.statusData.active ?? ({})
        return (a.source ?? "") === (b.source ?? "")
            && (a.mode ?? "") === (b.mode ?? "")
            && (a.scheme ?? "") === (b.scheme ?? "")
            && (a.preset ?? "") === (b.preset ?? "")
            && (a.seed ?? "") === (b.seed ?? "")
            && (a.wallpaper ?? "") === (b.wallpaper ?? "")
            && (a.uiProfile ?? "") === (b.uiProfile ?? "")
    }

    function historyGroup(group) {
        const items = root.statusData.history ?? []
        const now = new Date()
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000
        const yesterdayStart = todayStart - 86400
        if (group === "today")
            return items.filter(item => (item.timestamp ?? 0) >= todayStart)
        if (group === "yesterday")
            return items.filter(item => (item.timestamp ?? 0) >= yesterdayStart && (item.timestamp ?? 0) < todayStart)
        return items.filter(item => (item.timestamp ?? 0) < yesterdayStart)
    }

    function saveCurrentFavorite() {
        const command = [root.managerPath, "favorite-add"]
        const label = root.favoriteName.trim()
        if (label.length > 0)
            command.push("--label", label)
        root.runAction(command, "favorite")
    }

    function shortPath(path) {
        if (!path) return "No wallpaper"
        const parts = path.split("/")
        return parts[parts.length - 1]
    }

    function appliedWallpaperPath() {
        return root.statusData.active?.wallpaper ?? root.statusData.wallpaper ?? Config.options.background.wallpaperPath ?? ""
    }


    function prettyScheme(id) {
        const names = {
            "auto": "Auto",
            "scheme-tonal-spot": "Balanced",
            "scheme-fidelity": "Faithful",
            "scheme-content": "Natural",
            "scheme-expressive": "Vibrant",
            "scheme-neutral": "Minimal",
            "scheme-monochrome": "Monochrome",
            "scheme-rainbow": "Varied",
            "scheme-fruit-salad": "Playful"
        }
        return names[id] ?? id
    }

    function prettySource(id) {
        const names = {
            "wallpaper": "Wallpaper",
            "preset": "Preset",
            "hybrid": "Hybrid",
            "custom": "Custom"
        }
        return names[id] ?? id
    }


    function normalizeAppearanceMode(id) {
        // Legacy System/Adaptive ids remain readable, but the simplified
        // Appearance UI intentionally resolves them to standard Dark.
        if (id === "auto" || id === "adaptive")
            return "dark"
        if (["light", "dark", "dim", "oled", "high-contrast"].includes(id))
            return id
        return "dark"
    }


    function prettyMode(id) {
        const normalized = root.normalizeAppearanceMode(id)
        const names = {
            "light": "Light",
            "dark": "Dark",
            "dim": "Dim",
            "oled": "OLED",
            "high-contrast": "High Contrast"
        }
        return names[normalized] ?? "Dark"
    }

    function activeWallpaperPath() {
        return root.selectedWallpaper.length > 0
            ? root.selectedWallpaper
            : (root.statusData.wallpaper ?? Config.options.background.wallpaperPath ?? "")
    }

    function schemeTag(id) {
        const tags = {
            "auto": "Recommended",
            "scheme-tonal-spot": "Balanced",
            "scheme-fidelity": "Wallpaper true",
            "scheme-content": "Natural",
            "scheme-expressive": "Vibrant",
            "scheme-neutral": "Minimal",
            "scheme-monochrome": "Monochrome",
            "scheme-rainbow": "Varied",
            "scheme-fruit-salad": "Playful"
        }
        return tags[id] ?? ""
    }


    function schemeDescription(id) {
        const descriptions = {
            "auto": "Scores the actual generated palettes and selects the strongest result for this wallpaper.",
            "scheme-tonal-spot": "Balanced hierarchy and restrained color for everyday desktop use.",
            "scheme-fidelity": "Stays closest to the wallpaper's visual identity.",
            "scheme-content": "Builds a natural relationship from the wallpaper's own colors.",
            "scheme-expressive": "Uses bolder complementary relationships and stronger accent energy.",
            "scheme-neutral": "Keeps surfaces and accents quiet, low-chroma and distraction-free.",
            "scheme-monochrome": "Uses a restrained near-monochrome interpretation.",
            "scheme-rainbow": "Expands hue variety while preserving Material role structure.",
            "scheme-fruit-salad": "Uses a playful complementary relationship with stronger color movement."
        }
        return descriptions[id] ?? ""
    }

    function activeUiProfile() {
        const activeId = root.selectedUiProfile
        const profiles = root.statusData.uiProfiles ?? []
        for (let i = 0; i < profiles.length; i++) {
            if (profiles[i].id === activeId)
                return profiles[i]
        }
        if (activeId === "custom") {
            return {
                "id": "custom",
                "name": "Customized",
                "description": "Manually adjusted interface settings"
            }
        }
        return profiles.length > 0 ? profiles[0] : null
    }

    onSelectedSourceChanged: root.markDraftChanged(false)

    onWallpaperVariantsVisibleChanged: {
        if (root.wallpaperVariantsVisible)
            variantReloadTimer.restart()
    }

    onSelectedModeChanged: {
        if (root.initialized)
            variantReloadTimer.restart()
        root.markDraftChanged(false)
    }

    onSelectedSchemeChanged: root.markDraftChanged(false)
    onSelectedPresetChanged: root.markDraftChanged(false)
    onCustomSeedChanged: root.customPaletteChanged()
    onCustomSecondaryChanged: root.customPaletteChanged()
    onCustomTertiaryChanged: root.customPaletteChanged()
    onCustomNeutralChanged: root.customPaletteChanged()
    onCustomAdvancedChanged: root.customPaletteChanged()

    onSelectedWallpaperChanged: {
        if (root.initialized)
            variantReloadTimer.restart()
        root.markDraftChanged(false)
    }

    onDraftTransparencyEnableChanged: root.markDraftChanged(true)
    onDraftTransparencyAutomaticChanged: root.markDraftChanged(true)
    onDraftBackgroundTransparencyChanged: root.markDraftChanged(true)
    onDraftContentTransparencyChanged: root.markDraftChanged(true)
    onDraftExtraBackgroundTintChanged: root.markDraftChanged(true)
    onDraftFakeScreenRoundingChanged: root.markDraftChanged(true)
    onDraftBarCornerStyleChanged: root.markDraftChanged(true)
    onDraftBarFloatStyleShadowChanged: root.markDraftChanged(true)
    onDraftBarBorderlessChanged: root.markDraftChanged(true)
    onDraftBarShowBackgroundChanged: root.markDraftChanged(true)
    onDraftBarVerboseChanged: root.markDraftChanged(true)
    onDraftBarBottomChanged: root.markDraftChanged(true)
    onDraftBarVerticalChanged: root.markDraftChanged(true)
    onDraftParallaxWorkspaceChanged: root.markDraftChanged(true)
    onDraftParallaxSidebarChanged: root.markDraftChanged(true)

    // Motion preferences are global accessibility/timing choices, not profile
    // styling; changing them must not turn Fluid into "Custom".
    onDraftReducedMotionChanged: root.markDraftChanged(false)
    onDraftMotionScaleChanged: root.markDraftChanged(false)
    onDraftExpressiveMotionChanged: root.markDraftChanged(false)

    onDraftRadiusGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusWindowFollowGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusWindowValueChanged: root.markDraftChanged(true)
    onDraftRadiusModalFollowGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusModalValueChanged: root.markDraftChanged(true)
    onDraftRadiusSidebarFollowGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusSidebarValueChanged: root.markDraftChanged(true)
    onDraftRadiusPopupFollowGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusPopupValueChanged: root.markDraftChanged(true)
    onDraftRadiusCardFollowGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusCardValueChanged: root.markDraftChanged(true)
    onDraftRadiusControlFollowGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusControlValueChanged: root.markDraftChanged(true)
    onDraftRadiusScreenFollowGlobalChanged: root.markDraftChanged(true)
    onDraftRadiusScreenValueChanged: root.markDraftChanged(true)

    Timer {
        id: variantReloadTimer
        interval: 180
        repeat: false
        onTriggered: root.loadVariants()
    }

        Timer {
        id: autoApplyTimer
        interval: 320
        repeat: false
        onTriggered: root.flushAutoApply()
    }

Timer {
        id: previewRefreshTimer
        interval: 260
        repeat: false
        onTriggered: {
            if (root.previewToken.length === 0 || !root.previewRefreshPending)
                return
            if (actionProc.running) {
                restart()
                return
            }
            root.previewRefreshPending = false
            root.applyTheme(true, true)
        }
    }

    Timer {
        id: keepAfterPreviewTimer
        interval: 1
        repeat: false
        onTriggered: {
            if (root.previewToken.length > 0 && !actionProc.running)
                root.runAction([root.managerPath, "keep-preview"], "keep-preview")
        }
    }

    Timer {
        id: previewTimer
        interval: 1000
        repeat: true
        running: root.previewToken.length > 0
        onTriggered: {
            const now = Date.now() / 1000
            root.previewSeconds = Math.max(0, Math.ceil(root.previewExpiresAt - now))
            if (root.previewSeconds <= 0)
                previewExpiryRefreshTimer.restart()
        }
    }

    Timer {
        id: previewExpiryRefreshTimer
        interval: 1200
        repeat: false
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: toastTimer
        interval: 2800
        repeat: false
        onTriggered: root.toastText = ""
    }

    Timer {
        id: clearHistoryConfirmTimer
        interval: 3500
        repeat: false
        onTriggered: root.clearHistoryArmed = false
    }

    Process {
        id: statusProc
        command: [root.managerPath, "status"]
        onExited: exitCode => {
            if (exitCode !== 0 && !root.initialized && !root.actionFailed) {
                root.actionFailed = true
                root.toastText = "Could not start the appearance backend."
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    if (!data.ok) {
                        root.actionFailed = true
                        root.toastText = data.error ?? "Could not read appearance settings."
                        return
                    }

                    const hadPreview = root.previewToken.length > 0
                    root.statusData = data

                    if (data.preview) {
                        root.previewToken = data.preview.token ?? ""
                        root.previewRevision = data.preview.revision ?? 0
                        root.previewExpiresAt = data.preview.expiresAt ?? 0
                        root.previewSeconds = Math.max(0, Math.ceil(root.previewExpiresAt - Date.now() / 1000))
                    } else {
                        root.previewToken = ""
                        root.previewRevision = 0
                        root.previewExpiresAt = 0
                        root.previewSeconds = 0
                    }

                    if (!root.initialized) {
                        if (data.preview?.request)
                            root.syncDraftFromPreview(data.preview, data)
                        else
                            root.syncDraftFromStatus(data)
                        root.initialized = true
                    } else if (!data.preview && (root.syncDraftOnNextStatus || hadPreview)) {
                        root.syncDraftFromStatus(data)
                        root.syncDraftOnNextStatus = false
                        root.loadVariants()
                        if (hadPreview && root.toastText.length === 0) {
                            root.toastText = "Preview reverted"
                            toastTimer.restart()
                        }
                    }


                } catch (e) {
                    root.actionFailed = true
                    root.toastText = "Could not read appearance settings."
                    console.warn("[Appearance] status parse failed", e)
                }
            }
        }
    }

        Process {
        id: variantProc

        property string requestWallpaper: ""
        property string requestMode: ""
        property string resultText: ""
        property string errorText: ""

        stdout: StdioCollector {
            onStreamFinished: variantProc.resultText = text
        }

        stderr: StdioCollector {
            onStreamFinished: variantProc.errorText = text
        }

        onExited: (exitCode, exitStatus) => {
            const currentWallpaper = root.selectedWallpaper.length > 0
                ? root.selectedWallpaper
                : (root.statusData.wallpaper ?? Config.options.background.wallpaperPath ?? "")

            const stale = variantProc.requestWallpaper !== currentWallpaper
                || variantProc.requestMode !== root.selectedMode

            if (exitCode !== 0) {
                root.variantsError = variantProc.errorText.length > 0
                    ? variantProc.errorText.trim()
                    : `Variant generator exited with code ${exitCode}`
                console.warn("[AppearanceSettings] variant generator failed:", root.variantsError)
            } else if (!stale) {
                try {
                    const data = JSON.parse(variantProc.resultText)
                    const variants = data.variants ?? []

                    if (data.ok === false) {
                        root.variantsError = data.error ?? "Variant generation failed"
                    } else if (variants.length > 0) {
                        root.variantsData = variants
                        root.variantsError = data.error ?? ""
                    } else {
                        // Keep last known-good data instead of disabling the gallery.
                        root.variantsError = data.error ?? "No variant previews returned"
                    }
                } catch (e) {
                    root.variantsError = "Could not parse variant palette data"
                    console.warn("[AppearanceSettings] variant JSON parse failed", e)
                }
            } else {
                root.variantReloadPending = true
            }

            variantProc.resultText = ""
            variantProc.errorText = ""

            if (root.variantReloadPending) {
                root.variantReloadPending = false
                variantReloadTimer.restart()
            }
        }
    }

    Process {
        id: targetProc

        property string resultText: ""

        stdout: StdioCollector {
            onStreamFinished: targetProc.resultText = text
        }

        onExited: (exitCode, exitStatus) => {
            let result = ({})
            try {
                result = JSON.parse(targetProc.resultText)
            } catch (e) {}

            if (exitCode !== 0 || result.ok !== true) {
                root.actionFailed = true
                root.toastText = result.error ?? "Could not update theme target"
                toastTimer.restart()
                root.refreshStatus()
                return
            }

            root.actionFailed = false

            const warnings = result.warnings ?? []
            if (warnings.length > 0) {
                root.toastText =
                    `Target updated · ${warnings.length} integration warning${warnings.length === 1 ? "" : "s"}`
            } else {
                root.toastText = result.enabled
                    ? "Target enabled · current appearance synchronized"
                    : "Target disabled"
            }
            toastTimer.restart()

            root.refreshStatus()

            if (root.previewToken.length > 0) {
                root.previewRefreshPending = true
                previewRefreshTimer.restart()
            }
        }
    }

    Process {
        id: actionProc
        property var savedRequest: ({})
        property string actionKind: ""
        property string resultText: ""

        stdout: StdioCollector {
            onStreamFinished: actionProc.resultText = text
        }

        onExited: (exitCode, exitStatus) => {
            let result = ({})
            try { result = JSON.parse(actionProc.resultText) } catch (e) {}

            if (exitCode !== 0 || result.ok !== true) {
                root.actionFailed = true
                root.toastText = result.error ?? "Appearance action failed"
                toastTimer.restart()
                if (actionProc.actionKind === "preview-update")
                    root.keepAfterPreviewUpdate = false
                if (!root.autoApplyPending || actionProc.actionKind === "keep-preview") {
                    root.syncDraftOnNextStatus = true
                    root.refreshStatus()
                }
                root.autoApplyInFlight = false
                if (root.previewRefreshPending && root.previewToken.length > 0)
                    previewRefreshTimer.restart()
                if (root.autoApplyPending)
                    autoApplyTimer.restart()
                return
            }

            // The controller writes config.json outside this QML process.
            // Reload the live adapter before refreshing derived appearance
            // values so profile and fine-tune changes affect the shell now.
            Config.reload()
            Appearance.touchSemanticRadius()
            MaterialThemeLoader.reapplyTheme()

            if (["preview", "preview-update", "saved-preview"].includes(actionProc.actionKind)) {
                if (actionProc.actionKind === "saved-preview")
                    root.syncDraftFromPreview(result.previewState ?? {request: actionProc.savedRequest, candidate: result.active}, root.statusData)
                const previewState = result.previewState ?? ({})
                root.previewToken = previewState.token ?? root.previewToken
                root.previewRevision = previewState.revision ?? root.previewRevision
                root.previewExpiresAt = previewState.expiresAt ?? (Date.now() / 1000 + (result.previewTimeout ?? 15))
                root.previewSeconds = Math.max(0, Math.ceil(root.previewExpiresAt - Date.now() / 1000))
                root.toastText = actionProc.actionKind === "preview"
                    ? "Preview active · changes now update live"
                    : "Preview updated"

                if (actionProc.actionKind === "preview-update" && root.keepAfterPreviewUpdate) {
                    if (root.previewRefreshPending) {
                        // Another control changed while this revision was being
                        // generated. Flush that newest draft too before Keep.
                        previewRefreshTimer.restart()
                    } else {
                        root.keepAfterPreviewUpdate = false
                        keepAfterPreviewTimer.restart()
                    }
                }
            } else if (actionProc.actionKind === "keep-preview") {
                root.keepAfterPreviewUpdate = false
                root.previewToken = ""
                root.previewRevision = 0
                root.previewExpiresAt = 0
                root.previewSeconds = 0
                root.syncDraftOnNextStatus = true
                const warnings = result.warnings ?? []
                root.toastText = warnings.length > 0
                    ? `Preview kept · ${warnings.length} integration warning${warnings.length === 1 ? "" : "s"}`
                    : "Preview kept"
            } else if (actionProc.actionKind === "revert-preview") {
                root.keepAfterPreviewUpdate = false
                root.previewToken = ""
                root.previewRevision = 0
                root.previewExpiresAt = 0
                root.previewSeconds = 0
                root.syncDraftOnNextStatus = true
                root.toastText = "Preview reverted"
            } else if (actionProc.actionKind === "auto-apply") {
                root.autoApplyInFlight = false
                root.previewToken = ""
                root.previewRevision = 0
                root.previewExpiresAt = 0
                root.previewSeconds = 0
                root.syncDraftOnNextStatus = true
                const warnings = result.warnings ?? []
                root.toastText = warnings.length > 0
                    ? `Applied · ${warnings.length} integration warning${warnings.length === 1 ? "" : "s"}`
                    : "Changes applied"
            } else if (actionProc.actionKind === "apply" || actionProc.actionKind === "saved-apply") {
                root.syncDraftOnNextStatus = true
                const warnings = result.warnings ?? []
                root.toastText = warnings.length > 0
                    ? `Applied · ${warnings.length} integration warning${warnings.length === 1 ? "" : "s"}`
                    : "Appearance applied"
            } else if (actionProc.actionKind === "favorite") {
                root.favoriteName = ""
                root.toastText = "Saved to favorites"
            } else if (actionProc.actionKind === "favorite-remove") {
                root.toastText = "Favorite removed"
            } else if (actionProc.actionKind === "clear-history") {
                root.clearHistoryArmed = false
                root.toastText = "History cleared"
            } else {
                root.toastText = "Appearance updated"
            }

            toastTimer.restart()
            root.refreshStatus()
            root.loadVariants()

            if (root.previewRefreshPending && root.previewToken.length > 0)
                previewRefreshTimer.restart()

            if (root.autoApplyPending)
                autoApplyTimer.restart()
        }
    }

    component AppearanceTab: Loader {
        required property int pageIndex
        property bool visited: false

        active: visited || (root.visible && root.currentPage === pageIndex)
        asynchronous: true
        onStatusChanged: {
            if (status === Loader.Ready)
                visited = true
        }
    }

    component PillButton: RippleButton {
        id: pill
        property string label: ""
        property string iconName: ""
        implicitHeight: 38
        implicitWidth: Math.max(96, pillContent.implicitWidth + 28)
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer1Base
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colRippleToggled: Appearance.colors.colPrimaryActive

        contentItem: RowLayout {
            id: pillContent
            anchors.centerIn: parent
            spacing: 7
            MaterialSymbol {
                visible: pill.iconName.length > 0
                text: pill.iconName
                iconSize: 17
                fill: pill.toggled ? 1 : 0
                color: pill.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            StyledText {
                text: pill.label
                color: pill.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: pill.toggled ? Font.DemiBold : Font.Normal
            }
        }
    }
   component SourceSegmentButton: RippleButton {
        id: sourceButton
        property string label: ""
        property string iconName: ""
        property bool active: false
        toggled: active
        implicitHeight: 44
        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive
        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: active
        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 8
            MaterialSymbol {
                text: sourceButton.iconName
                iconSize: 18
                fill: sourceButton.active ? 1 : 0
                color: sourceButton.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: sourceButton.label
                color: sourceButton.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: sourceButton.active ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            MaterialSymbol {
                visible: sourceButton.active
                text: "check"
                iconSize: 17
                fill: 1
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }

component SectionTitle: ColumnLayout {
        property string title: ""
        property string subtitle: ""
        spacing: 2
        StyledText {
            text: parent.title
            color: Appearance.colors.colOnLayer1
            font {
                family: Appearance.font.family.title
                pixelSize: Appearance.font.pixelSize.large
                variableAxes: Appearance.font.variableAxes.title
            }
        }
        StyledText {
            visible: parent.subtitle.length > 0
            text: parent.subtitle
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

        component ColorDot: Rectangle {
        property color dotColor: Appearance.colors.colPrimary
        implicitWidth: 20
        implicitHeight: 20
        radius: Appearance.radius.full
        color: dotColor
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }


    component CustomColorField: Rectangle {
        id: field

        property string title: ""
        property string subtitle: ""
        property string value: "#5368B7"
        signal colorEdited(string value)

        Layout.fillWidth: true
        implicitHeight: 76
        radius: Appearance.radius.control
        color: Appearance.colors.colLayer2Base
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus
            ? Appearance.colors.colPrimary
            : Appearance.colors.colLayer0Border

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Rectangle {
                implicitWidth: 42
                implicitHeight: 42
                radius: Appearance.radius.control
                color: root.validCustomHex(field.value)
                    ? field.value
                    : Appearance.colors.colLayer3
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2

                StyledText {
                    text: field.title
                    color: Appearance.colors.colOnLayer2
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: field.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                implicitWidth: 112
                implicitHeight: 38
                radius: Appearance.radius.control
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: input.activeFocus
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer0Border

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    text: field.value
                    color: Appearance.colors.colOnLayer1
                    selectionColor: Appearance.colors.colPrimaryContainer
                    selectedTextColor: Appearance.colors.colOnPrimaryContainer
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    selectByMouse: true

                    onEditingFinished: {
                        const normalized = root.normalizeCustomHex(text)
                        text = normalized
                        if (root.validCustomHex(normalized))
                            field.colorEdited(normalized)
                    }
                }
            }
        }
    }

    component VariantCard: RippleButton {
        id: card
        required property string schemeId

        property var variant: root.variantFor(schemeId)
        property bool previewAvailable: variant !== null
        property string title: root.prettyScheme(schemeId)
        property var palette: variant?.colors ?? root.statusData.colors ?? ({})
        property bool selected: root.selectedScheme === schemeId
        property color primaryColor: palette.primary ?? Appearance.colors.colPrimary
        property color secondaryColor: palette.secondary ?? Appearance.m3colors.m3secondary
        property color tertiaryColor: palette.tertiary ?? Appearance.m3colors.m3tertiary
        property color surfaceColor: palette.surface ?? Appearance.m3colors.m3surfaceContainer

        toggled: selected
        enabled: true
        opacity: 1
        implicitHeight: 218
        buttonRadius: Appearance.radius.card
        buttonRadiusPressed: Appearance.radius.card
        colBackground: Appearance.colors.colLayer1Base
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colLayer2Base
        colBackgroundToggledHover: Appearance.colors.colLayer2Hover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: title
        Accessible.description: root.schemeDescription(schemeId)
        Accessible.checked: selected

        onClicked: root.selectedScheme = schemeId

        contentItem: Rectangle {
            anchors.fill: parent
            radius: Appearance.radius.card
            color: "transparent"
            border.width: card.selected ? 2 : 1
            border.color: card.selected
                ? Appearance.colors.colPrimary
                : Appearance.colors.colLayer0Border

            Behavior on border.color {
                MotionColorAnim {
                    type: MotionColorAnim.FastEffects
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 13
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: card.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: card.schemeId === "auto"
                        implicitHeight: 22
                        implicitWidth: recommendedText.implicitWidth + 16
                        radius: Appearance.radius.full
                        color: Appearance.colors.colSecondaryContainer

                        StyledText {
                            id: recommendedText
                            anchors.centerIn: parent
                            text: "Recommended"
                            color: Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }
                    }

                    MaterialSymbol {
                        visible: card.selected
                        text: "check_circle"
                        iconSize: 20
                        fill: 1
                        color: Appearance.colors.colPrimary
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 82
                    radius: Appearance.radius.control
                    color: card.surfaceColor
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 58
                            Layout.fillHeight: true
                            radius: Appearance.radius.control
                            color: card.primaryColor

                            Rectangle {
                                width: parent.width * 0.56
                                height: parent.height * 0.18
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 8
                                radius: Appearance.radius.full
                                color: card.surfaceColor
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 11
                                radius: Appearance.radius.full
                                color: card.secondaryColor
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    Layout.preferredWidth: 24
                                    implicitHeight: 11
                                    radius: Appearance.radius.full
                                    color: card.tertiaryColor
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 11
                                    radius: Appearance.radius.full
                                    color: card.primaryColor
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    Layout.preferredWidth: 34
                                    implicitHeight: 10
                                    radius: Appearance.radius.full
                                    color: card.secondaryColor
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 10
                                    radius: Appearance.radius.full
                                    color: card.tertiaryColor
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    spacing: 7
                    ColorDot { dotColor: card.primaryColor }
                    ColorDot { dotColor: card.secondaryColor }
                    ColorDot { dotColor: card.tertiaryColor }
                    ColorDot { dotColor: card.surfaceColor }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: root.schemeTag(card.schemeId)
                        color: card.selected
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.schemeDescription(card.schemeId)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    component PresetCard: RippleButton {
        id: card
        required property var preset
        property bool selected: root.selectedPreset === preset.id && (root.selectedSource === "preset" || root.selectedSource === "hybrid")
        toggled: selected
        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: preset.name ?? preset.id
        Accessible.checked: selected
        implicitHeight: 118
        buttonRadius: Appearance.radius.card
        buttonRadiusPressed: Appearance.radius.card
        colBackground: Appearance.colors.colLayer1Base
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        onClicked: {
            if (root.selectedSource !== "hybrid")
                root.selectedSource = "preset"
            root.selectedPreset = preset.id
            if (root.selectedSource === "preset")
                root.selectedScheme = preset.scheme
        }

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            Rectangle {
                implicitWidth: 50
                implicitHeight: 50
                radius: Appearance.radius.control
                color: card.preset.seed
                border.width: card.selected ? 2 : 1
                border.color: card.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colLayer0Border
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                StyledText {
                    text: card.preset.name
                    color: card.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                }
                StyledText {
                    text: card.preset.description
                    color: card.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                StyledText {
                    text: card.preset.seed
                    color: card.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }

            MaterialSymbol {
                visible: card.selected
                text: "check_circle"
                iconSize: 20
                fill: 1
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
    }




    component InterfaceChoiceButton: RippleButton {
        id: choiceButton

        property string label: ""
        property bool active: false

        toggled: active
        implicitHeight: 38
        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control
        colBackground: Appearance.colors.colLayer2Base
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: label
        Accessible.checked: active

        contentItem: Item {
            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    visible: choiceButton.active
                    text: "check"
                    iconSize: 15
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    text: choiceButton.label
                    color: choiceButton.active
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                }
            }
        }
    }

    component InterfaceSliderRow: Item {
        id: sliderRow

        property string title: ""
        property string subtitle: ""
        property real fromValue: 0
        property real toValue: 1
        property real value: 0
        property real stepSize: 0.01
        signal valueEdited(real value)

        implicitHeight: sliderColumn.implicitHeight

        ColumnLayout {
            id: sliderColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: sliderRow.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        visible: sliderRow.subtitle.length > 0
                        Layout.fillWidth: true
                        text: sliderRow.subtitle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    implicitWidth: valueText.implicitWidth + 16
                    implicitHeight: 24
                    radius: Appearance.radius.full
                    color: Appearance.colors.colPrimaryContainer

                    StyledText {
                        id: valueText
                        anchors.centerIn: parent
                        text: `${Math.round(sliderRow.value * 100)}%`
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                    }
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.XS
                from: sliderRow.fromValue
                to: sliderRow.toValue
                value: sliderRow.value
                stepSize: sliderRow.stepSize
                tooltipContent: `${Math.round(value * 100)}%`
                activeFocusOnTab: true
                Accessible.name: sliderRow.title
                Accessible.description: sliderRow.subtitle
                onMoved: sliderRow.valueEdited(value)
            }
        }
    }

                    component UiProfileCard: RippleButton {
        id: profileCard

        required property var profile

        property bool selected: root.selectedUiProfile === profile.id
        property bool modified:
            root.selectedUiProfile === "custom"
            && root.interfaceBaseProfile === profile.id

        readonly property var traitMap: ({
            "default": ["Balanced", "Layered", "Familiar"],
            "fluid": ["Translucent", "Wireframe", "Fluid"],
            "floating": ["Elevated", "Spacious", "Detached bar"],
            "solid": ["Opaque", "Stable", "Readable"],
            "minimal": ["Quiet", "Reduced chrome", "Low noise"]
        })

        readonly property var iconMap: ({
            "default": "dashboard",
            "fluid": "opacity",
            "floating": "layers",
            "solid": "crop_square",
            "minimal": "minimize"
        })

        readonly property var traits:
            traitMap[profile.id] ?? ["Adaptive", "Clean", "Studio"]

        readonly property string profileIcon:
            iconMap[profile.id] ?? "palette"

        toggled: selected || modified
        implicitHeight: 114
        buttonRadius: Appearance.radius.card
        buttonRadiusPressed: Appearance.radius.card
        colBackground: Appearance.colors.colLayer1Base
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        colBackgroundToggled: ColorUtils.transparentize(
            Appearance.colors.colPrimaryContainer, 0.74
        )
        colBackgroundToggledHover: ColorUtils.transparentize(
            Appearance.colors.colPrimaryContainerHover, 0.70
        )
        colRippleToggled: Appearance.colors.colPrimaryContainerActive

        activeFocusOnTab: true
        Accessible.role: Accessible.RadioButton
        Accessible.name: profile.name
        Accessible.description: profile.description
        Accessible.checked: selected || modified

        onClicked: root.chooseUiProfile(profile.id)

        contentItem: Rectangle {
            anchors.fill: parent
            radius: Appearance.radius.card
            color: "transparent"
            border.width: profileCard.selected || profileCard.modified ? 2 : 1
            border.color:
                profileCard.selected || profileCard.modified
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer0Border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        implicitWidth: 30
                        implicitHeight: 30
                        radius: Appearance.radius.full
                        color: profileCard.selected || profileCard.modified
                            ? Appearance.colors.colPrimaryContainer
                            : Appearance.colors.colLayer2Base
                        border.width: 1
                        border.color: profileCard.selected || profileCard.modified
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer0Border

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: profileCard.profileIcon
                            iconSize: 16
                            fill: 1
                            color: profileCard.selected || profileCard.modified
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer2
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: profileCard.profile.name
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.large
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: profileCard.profile.description
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        visible: profileCard.selected || profileCard.modified
                        implicitWidth: stateText.implicitWidth + 18
                        implicitHeight: 26
                        radius: Appearance.radius.full
                        color: profileCard.modified
                            ? Appearance.colors.colLayer2Base
                            : Appearance.colors.colPrimaryContainer
                        border.width: profileCard.modified ? 1 : 0
                        border.color: Appearance.colors.colPrimary

                        StyledText {
                            id: stateText
                            anchors.centerIn: parent
                            text: profileCard.modified ? "Modified" : "Current"
                            color: profileCard.modified
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnPrimaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: profileCard.traits

                        Rectangle {
                            required property var modelData
                            implicitHeight: 24
                            implicitWidth: traitText.implicitWidth + 14
                            radius: Appearance.radius.full
                            color: Appearance.colors.colLayer2Base
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border

                            StyledText {
                                id: traitText
                                anchors.centerIn: parent
                                text: modelData
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                }
            }
        }
    }

        component InterfaceSwitchRow: Item {
        id: settingRow

        property string title: ""
        property string subtitle: ""
        property alias checked: toggle.checked
        property bool switchEnabled: true
        signal userToggled(bool checked)

        implicitHeight: Math.max(48, rowContent.implicitHeight)
        opacity: switchEnabled ? 1 : 0.48

        RowLayout {
            id: rowContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: settingRow.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }

                StyledText {
                    visible: settingRow.subtitle.length > 0
                    Layout.fillWidth: true
                    text: settingRow.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.Wrap
                }
            }

            StyledSwitch {
                id: toggle
                enabled: settingRow.switchEnabled
                activeFocusOnTab: true
                Accessible.name: settingRow.title
                Accessible.description: settingRow.subtitle
                onToggled: settingRow.userToggled(checked)
            }
        }
    }


    component RadiusSettingRow: Rectangle {
        id: radiusRow
        required property string role
        required property string title
        required property string subtitle
        required property bool followGlobal
        required property int radiusValue

        readonly property int resolvedValue: followGlobal ? root.draftRadiusGlobal : radiusValue

        implicitHeight: radiusContent.implicitHeight + 2 * root.cornerCardPadding
        radius: Appearance.radius.card
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: radiusContent
            anchors.fill: parent
            anchors.margins: root.cornerCardPadding
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: radiusRow.title
                        color: Appearance.colors.colOnLayer2
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: radiusRow.subtitle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignTop
                    text: `${radiusRow.resolvedValue} px`
                    color: Appearance.colors.colPrimary
                    font.weight: Font.DemiBold
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                StyledSwitch {
                    checked: radiusRow.followGlobal
                    Accessible.name: `Use global radius for ${radiusRow.title}`
                    onToggled: root.setRadiusFollowGlobal(radiusRow.role, checked)
                }

                StyledText {
                    text: "Use global radius"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }

                StyledSlider {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    enabled: !radiusRow.followGlobal
                    opacity: enabled ? 1 : 0.44
                    configuration: StyledSlider.Configuration.XS
                    from: 0
                    to: 40
                    stepSize: 1
                    usePercentTooltip: false
                    value: radiusRow.resolvedValue
                    Accessible.name: `${radiusRow.title} radius, in pixels`
                    onMoved: root.setRadiusValue(radiusRow.role, value)
                }
            }
        }
    }

    component SavedPalette: RowLayout {
        id: savedPalette
        property var entry: ({})
        property var colors: entry?.colors ?? ({})
        property color fallbackPrimary: entry?.active?.seed?.length > 0 ? entry.active.seed : Appearance.colors.colPrimary
        spacing: 5

        Rectangle {
            implicitWidth: 17
            implicitHeight: 17
            radius: Appearance.rounding.full
            color: savedPalette.colors.primary ?? savedPalette.fallbackPrimary
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
        Rectangle {
            implicitWidth: 17
            implicitHeight: 17
            radius: Appearance.rounding.full
            color: savedPalette.colors.secondary ?? Appearance.m3colors.m3secondary
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
        Rectangle {
            implicitWidth: 17
            implicitHeight: 17
            radius: Appearance.rounding.full
            color: savedPalette.colors.tertiary ?? Appearance.m3colors.m3tertiary
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
        Rectangle {
            implicitWidth: 17
            implicitHeight: 17
            radius: Appearance.rounding.full
            color: savedPalette.colors.surface ?? Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }



    component TargetIntegrationRow: Rectangle {
        id: targetRow

        required property var targetData

        Layout.fillWidth: true
        implicitHeight: 76

        radius: Appearance.radius.card
        color: Appearance.colors.colLayer1Base
        border.width: 1
        border.color: root.targetEnabled(targetData.id)
            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
            : Appearance.colors.colLayer0Border

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Rectangle {
                implicitWidth: 42
                implicitHeight: 42
                radius: Appearance.radius.control
                color: root.targetEnabled(targetRow.targetData.id)
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer2Base

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: targetRow.targetData.icon
                    iconSize: 20
                    fill: root.targetEnabled(targetRow.targetData.id) ? 1 : 0
                    color: root.targetEnabled(targetRow.targetData.id)
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer2
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    StyledText {
                        Layout.fillWidth: true
                        text: targetRow.targetData.name
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: targetRow.targetData.compatibility ?? false
                        implicitWidth: compatibilityText.implicitWidth + 14
                        implicitHeight: 22
                        radius: Appearance.radius.full
                        color: Appearance.colors.colTertiaryContainer

                        StyledText {
                            id: compatibilityText
                            anchors.centerIn: parent
                            text: "Hyprland opt-in"
                            color: Appearance.colors.colOnTertiaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: targetRow.targetData.desc
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }

            StyledText {
                text: root.targetEnabled(targetRow.targetData.id) ? "On" : "Off"
                color: root.targetEnabled(targetRow.targetData.id)
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
            }

            StyledSwitch {
                checked: root.targetEnabled(targetRow.targetData.id)
                enabled: !actionProc.running && !targetProc.running
                activeFocusOnTab: true
                Accessible.name: `${targetRow.targetData.name} target`
                Accessible.description: targetRow.targetData.desc
                onClicked: root.setTarget(targetRow.targetData.id, checked)
            }
        }
    }


    component TargetIntegrationSection: ColumnLayout {
        id: targetSection

        required property string title
        required property string subtitle
        required property var targetItems

        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                text: targetSection.title
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.fillWidth: true
                text: targetSection.subtitle
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                wrapMode: Text.WordWrap
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width >= 700 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10

            Repeater {
                model: targetSection.targetItems

                TargetIntegrationRow {
                    required property var modelData
                    targetData: modelData
                }
            }
        }
    }

    component FavoriteCard: Rectangle {
        id: favoriteCard

        required property var entry

        property bool current: root.entryMatchesActive(entry)
        property bool removeArmed: false

        Layout.fillWidth: true
        implicitHeight: 128

        radius: Appearance.radius.card
        color: current
            ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.82)
            : Appearance.colors.colLayer1Base
        border.width: 1
        border.color: current
            ? Appearance.colors.colPrimary
            : Appearance.colors.colLayer0Border

        Timer {
            id: removeFavoriteConfirmTimer
            interval: 3500
            repeat: false
            onTriggered: favoriteCard.removeArmed = false
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                SavedPalette {
                    entry: favoriteCard.entry
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        StyledText {
                            Layout.fillWidth: true
                            text: root.entryTitle(favoriteCard.entry, true)
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: favoriteCard.current
                            implicitWidth: favoriteCurrentText.implicitWidth + 14
                            implicitHeight: 22
                            radius: Appearance.radius.full
                            color: Appearance.colors.colPrimaryContainer

                            StyledText {
                                id: favoriteCurrentText
                                anchors.centerIn: parent
                                text: "Current"
                                color: Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.entryMeta(favoriteCard.entry)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: root.formatAge(favoriteCard.entry.timestamp)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }

                RippleButton {
                    implicitHeight: 34
                    implicitWidth: favoriteUseText.implicitWidth + 34
                    buttonRadius: Appearance.radius.control
                    buttonRadiusPressed: Appearance.radius.control
                    colBackground: favoriteCard.current
                        ? Appearance.colors.colLayer2Base
                        : Appearance.colors.colPrimaryContainer
                    colBackgroundHover: favoriteCard.current
                        ? Appearance.colors.colLayer2Hover
                        : Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colLayer2Active
                    enabled: !favoriteCard.current
                        && root.previewToken.length === 0
                        && !root.editing
                    activeFocusOnTab: true
                    Accessible.name: favoriteCard.current
                        ? "Current favorite"
                        : `Use ${root.entryTitle(favoriteCard.entry, true)}`
                    onClicked: root.previewSaved(favoriteCard.entry)

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: favoriteCard.current ? "check_circle" : "palette"
                            iconSize: 17
                            fill: favoriteCard.current ? 1 : 0
                            color: favoriteCard.current
                                ? Appearance.colors.colSubtext
                                : Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            id: favoriteUseText
                            text: favoriteCard.current ? "Current" : "Use"
                            color: favoriteCard.current
                                ? Appearance.colors.colSubtext
                                : Appearance.colors.colOnPrimaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }
                    }
                }

                RippleButton {
                    implicitWidth: favoriteCard.removeArmed
                        ? removeFavoriteText.implicitWidth + 28
                        : 34
                    implicitHeight: 34
                    buttonRadius: Appearance.radius.control
                    buttonRadiusPressed: Appearance.radius.control
                    colBackground: favoriteCard.removeArmed
                        ? Appearance.colors.colErrorContainer
                        : "transparent"
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.colors.colErrorContainerActive
                    activeFocusOnTab: true
                    Accessible.name: favoriteCard.removeArmed
                        ? "Confirm remove favorite"
                        : "Remove favorite"
                    onClicked: {
                        if (favoriteCard.removeArmed) {
                            favoriteCard.removeArmed = false
                            removeFavoriteConfirmTimer.stop()
                            root.runAction(
                                [root.managerPath, "favorite-remove", favoriteCard.entry.id],
                                "favorite-remove"
                            )
                        } else {
                            favoriteCard.removeArmed = true
                            removeFavoriteConfirmTimer.restart()
                        }
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            text: favoriteCard.removeArmed ? "delete_forever" : "delete"
                            iconSize: 17
                            color: favoriteCard.removeArmed
                                ? Appearance.colors.colOnErrorContainer
                                : Appearance.colors.colSubtext
                        }

                        StyledText {
                            id: removeFavoriteText
                            visible: favoriteCard.removeArmed
                            text: "Remove?"
                            color: Appearance.colors.colOnErrorContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }




    component HistoryRow: Rectangle {
        id: historyRow

        required property var entry

        property bool current: root.entryMatchesActive(entry)

        Layout.fillWidth: true
        implicitHeight: 66

        radius: Appearance.radius.control
        color: current
            ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.86)
            : Appearance.colors.colLayer1Base
        border.width: 1
        border.color: current
            ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.36)
            : Appearance.colors.colLayer0Border

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 11

            SavedPalette {
                entry: historyRow.entry
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    StyledText {
                        Layout.fillWidth: true
                        text: root.entryTitle(historyRow.entry, false)
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: historyRow.current
                        implicitWidth: historyCurrentText.implicitWidth + 14
                        implicitHeight: 20
                        radius: Appearance.radius.full
                        color: Appearance.colors.colPrimaryContainer

                        StyledText {
                            id: historyCurrentText
                            anchors.centerIn: parent
                            text: "Current"
                            color: Appearance.colors.colOnPrimaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: root.entryMeta(historyRow.entry)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: root.formatAge(historyRow.entry.timestamp)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }
            }

            RippleButton {
                implicitHeight: 34
                implicitWidth: historyRestoreText.implicitWidth + 32
                buttonRadius: Appearance.radius.control
                buttonRadiusPressed: Appearance.radius.control
                colBackground: Appearance.colors.colLayer2Base
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                enabled: !historyRow.current
                    && root.previewToken.length === 0
                    && !actionProc.running
                activeFocusOnTab: true
                Accessible.name: historyRow.current
                    ? "Current appearance"
                    : `Restore ${root.entryTitle(historyRow.entry, false)}`
                onClicked: root.previewSaved(historyRow.entry)

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    StyledText {
                        id: historyRestoreText
                        text: historyRow.current ? "Current" : "Restore"
                        color: historyRow.current
                            ? Appearance.colors.colSubtext
                            : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                    }

                    MaterialSymbol {
                        text: historyRow.current ? "check_circle" : "restore"
                        iconSize: 17
                        fill: historyRow.current ? 1 : 0
                        color: historyRow.current
                            ? Appearance.colors.colSubtext
                            : Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }



    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SettingsComponents.SettingsSectionTabs {
            Layout.leftMargin: root.width < 760 ? 12 : 16
            Layout.rightMargin: Layout.leftMargin
            Layout.topMargin: Layout.leftMargin

            sections: root.pageModel
            section: root.pageModel[root.currentPage].id
            onSectionRequested: sectionId => {
                root.currentPage = root.pageModel.findIndex(page => page.id === sectionId)
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            enabled: root.initialized
            currentIndex: root.currentPage
            AppearanceTab { id: themeTab; pageIndex: 0; sourceComponent: themePage }
            AppearanceTab { id: surfacesTab; pageIndex: 1; sourceComponent: surfacesPage }
            AppearanceTab { id: cornersTab; pageIndex: 2; sourceComponent: cornersPage }
            AppearanceTab {
                id: appThemingTab
                pageIndex: 3
                sourceComponent: appThemingPage
                onLoaded: {
                    if (root.terminalTuningRequested)
                        root.expandTerminalTuning()
                }
            }
            AppearanceTab { id: savedLooksTab; pageIndex: 4; sourceComponent: savedLooksPage }
        }

        Component {
            id: themePage

            ScrollView {
                clip: true
                leftPadding: 20
                rightPadding: 20
                topPadding: 20
                bottomPadding: 20
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 16

                    SectionTitle {
                        title: "Theme"
                        subtitle: "Choose the color source and appearance mode first, then shape the visual character below."
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sourcePicker.implicitHeight + 24
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            id: sourcePicker
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            StyledText { text: "Theme source"; color: Appearance.colors.colOnLayer1; font.weight: Font.DemiBold }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Choose where the palette comes from. This does not change the light or dark treatment."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.Wrap
                            }
                            RowLayout {
                                id: themeSourceRow
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    id: sourceWallpaper
                                    readonly property bool active: root.selectedSource === "wallpaper"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : sourceWallpaperMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : sourceWallpaperMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: sourceWallpaperMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "wallpaper"
                                            iconSize: 18
                                            color: sourceWallpaper.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "Wallpaper"
                                            color: sourceWallpaper.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: sourceWallpaper.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: sourceWallpaper.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: sourceWallpaperMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedSource = "wallpaper"
                                    }
                                }

                                Rectangle {
                                    id: sourcePreset
                                    readonly property bool active: root.selectedSource === "preset"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : sourcePresetMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : sourcePresetMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: sourcePresetMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "auto_awesome"
                                            iconSize: 18
                                            color: sourcePreset.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "Preset"
                                            color: sourcePreset.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: sourcePreset.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: sourcePreset.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: sourcePresetMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedSource = "preset"
                                    }
                                }

                                Rectangle {
                                    id: sourceHybrid
                                    readonly property bool active: root.selectedSource === "hybrid"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : sourceHybridMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : sourceHybridMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: sourceHybridMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "join_inner"
                                            iconSize: 18
                                            color: sourceHybrid.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "Hybrid"
                                            color: sourceHybrid.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: sourceHybrid.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: sourceHybrid.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: sourceHybridMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedSource = "hybrid"
                                    }
                                }

                                Rectangle {
                                    id: sourceCustom
                                    readonly property bool active: root.selectedSource === "custom"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : sourceCustomMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : sourceCustomMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: sourceCustomMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "colorize"
                                            iconSize: 18
                                            color: sourceCustom.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "Custom"
                                            color: sourceCustom.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: sourceCustom.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: sourceCustom.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: sourceCustomMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedSource = "custom"
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.selectedSource === "wallpaper"
                                    ? "Build the Material palette from the selected wallpaper."
                                    : root.selectedSource === "preset"
                                        ? "Use a curated seed that stays independent from the wallpaper."
                                        : root.selectedSource === "hybrid"
                                            ? "Use wallpaper accents with preset-driven surfaces and neutrals."
                                            : "Build from one seed in Quick, or control four semantic anchors in Advanced."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    // BEGIN appearance-mode-direction-v5
                    // BEGIN appearance-modes-minimal-v7
                   // BEGIN appearance-mode-row-v10
                   // BEGIN appearance-mode-buttons-v11
                   // BEGIN appearance-source-buttons-v15
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: appearanceModeColumn.implicitHeight + 24
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        ColumnLayout {
                            id: appearanceModeColumn
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 11

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "Appearance"
                                        color: Appearance.colors.colOnLayer1
                                        font.weight: Font.DemiBold
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Choose one surface style for the desktop."
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            RowLayout {
                                id: appearanceModeRow
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    id: modeLight
                                    readonly property bool active: root.selectedMode === "light"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : modeLightMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : modeLightMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: modeLightMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "light_mode"
                                            iconSize: 18
                                            color: modeLight.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "Light"
                                            color: modeLight.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: modeLight.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: modeLight.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: modeLightMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedMode = "light"
                                    }
                                }

                                Rectangle {
                                    id: modeDark
                                    readonly property bool active: root.selectedMode === "dark"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : modeDarkMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : modeDarkMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: modeDarkMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "dark_mode"
                                            iconSize: 18
                                            color: modeDark.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "Dark"
                                            color: modeDark.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: modeDark.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: modeDark.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: modeDarkMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedMode = "dark"
                                    }
                                }

                                Rectangle {
                                    id: modeDim
                                    readonly property bool active: root.selectedMode === "dim"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : modeDimMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : modeDimMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: modeDimMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "brightness_4"
                                            iconSize: 18
                                            color: modeDim.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "Dim"
                                            color: modeDim.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: modeDim.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: modeDim.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: modeDimMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedMode = "dim"
                                    }
                                }

                                Rectangle {
                                    id: modeOled
                                    readonly property bool active: root.selectedMode === "oled"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : modeOledMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : modeOledMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: modeOledMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "contrast"
                                            iconSize: 18
                                            color: modeOled.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "OLED"
                                            color: modeOled.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: modeOled.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: modeOled.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: modeOledMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedMode = "oled"
                                    }
                                }

                                Rectangle {
                                    id: modeHighContrast
                                    readonly property bool active: root.selectedMode === "high-contrast"

                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: 46

                                    radius: Appearance.radius.control
                                    color: active
                                        ? Appearance.colors.colPrimaryContainer
                                        : modeHighContrastMouse.containsMouse
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer2Base

                                    border.width: active ? 2 : 1
                                    border.color: active
                                        ? Appearance.colors.colPrimary
                                        : modeHighContrastMouse.containsMouse
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer0Border

                                    scale: modeHighContrastMouse.pressed ? 0.985 : 1.0

                                    Behavior on scale {
                                        NumberAnimation { duration: 90 }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 7

                                        MaterialSymbol {
                                            text: "visibility"
                                            iconSize: 18
                                            color: modeHighContrast.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                        }

                                        StyledText {
                                            text: "High Contrast"
                                            color: modeHighContrast.active
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: modeHighContrast.active ? Font.DemiBold : Font.Medium
                                        }
                                    }

                                    Rectangle {
                                        visible: modeHighContrast.active
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 5
                                        width: 20
                                        height: 3
                                        radius: 2
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: modeHighContrastMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedMode = "high-contrast"
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.selectedMode === "light"
                                    ? "Bright surfaces with the generated palette's light roles."
                                    : root.selectedMode === "dark"
                                        ? "Standard dark surfaces with the full Material hierarchy."
                                        : root.selectedMode === "dim"
                                            ? "Lower perceptual surface lightness for a softer dark appearance."
                                            : root.selectedMode === "oled"
                                                ? "True-black foundations with near-black elevated surfaces."
                                                : "Maximum semantic contrast for text and controls."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: root.initialized && root.usesWallpaperPalette
                        visible: active
                        sourceComponent: Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: contextRow.implicitHeight + 24
                            radius: Appearance.radius.card
                            color: Appearance.colors.colLayer1Base
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                            RowLayout {
                                id: contextRow
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12
                                Rectangle {
                                    implicitWidth: 112
                                    implicitHeight: 72
                                    radius: Appearance.radius.control
                                    color: Appearance.colors.colLayer0Base
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0Border
                                    clip: true
                                    StyledImage { anchors.fill: parent; visible: root.activeWallpaperPath().length > 0; source: FileUtils.localFileUrl(root.activeWallpaperPath()); asynchronous: true; cache: true; mipmap: true; sourceSize.width: 224; sourceSize.height: 144; fillMode: Image.PreserveAspectCrop }
                                    MaterialSymbol { anchors.centerIn: parent; visible: root.activeWallpaperPath().length === 0; text: "wallpaper"; iconSize: 28; color: Appearance.colors.colPrimary }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 3
                                    StyledText { text: root.selectedSource === "hybrid" ? "Accent wallpaper" : "Current wallpaper"; color: Appearance.colors.colOnLayer1; font.weight: Font.DemiBold }
                                    StyledText { Layout.fillWidth: true; text: root.shortPath(root.activeWallpaperPath()); color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; elide: Text.ElideMiddle }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.selectedSource === "hybrid"
                                            ? "The wallpaper drives the accent family; the preset below controls the neutral surfaces."
                                            : "The gallery below compares Material interpretations generated from this image."
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                                PillButton { label: "Change wallpaper"; iconName: "wallpaper"; implicitHeight: 38; buttonRadius: Appearance.radius.control; onClicked: root.wallpaperRequested() }
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: root.initialized && root.usesWallpaperPalette
                        asynchronous: true
                        visible: active
                        sourceComponent: ColumnLayout {
                            spacing: 11
                            SectionTitle {
                                title: root.selectedSource === "hybrid" ? "Accent character" : "Color character"
                                subtitle: root.selectedSource === "hybrid" ? "Choose how the wallpaper shapes the accent family." : "Auto scores the real palettes; choose a character manually when you want a specific look."
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Flow {
                                    id: variantFlow
                                    Layout.fillWidth: true
                                    spacing: 12
                                    property int columnCount: width >= 760 ? 3 : width >= 500 ? 2 : 1

                                    Repeater {
                                        model: [
                                            "auto",
                                            "scheme-tonal-spot",
                                            "scheme-fidelity",
                                            "scheme-content",
                                            "scheme-expressive",
                                            "scheme-neutral",
                                            "scheme-monochrome"
                                        ]

                                        VariantCard {
                                            required property string modelData
                                            width: Math.max(0, (variantFlow.width - variantFlow.spacing * (variantFlow.columnCount - 1)) / variantFlow.columnCount)
                                            schemeId: modelData
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledText {
                                        text: "More directions"
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                    }

                                    PillButton {
                                        label: "Varied"
                                        toggled: root.selectedScheme === "scheme-rainbow"
                                        onClicked: root.selectedScheme = "scheme-rainbow"
                                    }

                                    PillButton {
                                        label: "Playful"
                                        toggled: root.selectedScheme === "scheme-fruit-salad"
                                        onClicked: root.selectedScheme = "scheme-fruit-salad"
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                            StyledText { visible: root.variantsError.length > 0; Layout.fillWidth: true; text: root.variantsError; color: Appearance.m3colors.m3error; font.pixelSize: Appearance.font.pixelSize.smallest; wrapMode: Text.Wrap }
                        }
                    }

                    Rectangle {
                        visible: root.selectedSource === "hybrid"
                        Layout.fillWidth: true
                        implicitHeight: hybridInfo.implicitHeight + 22
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer2Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        RowLayout {
                            id: hybridInfo
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 10
                            MaterialSymbol { text: "join_inner"; iconSize: 21; color: Appearance.colors.colPrimary }
                            StyledText { Layout.fillWidth: true; text: "Hybrid keeps the wallpaper accent family while the selected preset supplies backgrounds, surfaces, outlines and neutral text roles."; color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.smallest; wrapMode: Text.Wrap }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: root.selectedSource === "preset" || root.selectedSource === "hybrid"
                        visible: active
                        sourceComponent: ColumnLayout {
                            spacing: 10
                            SectionTitle {
                                title: root.selectedSource === "hybrid" ? "Surface base" : "Preset themes"
                                subtitle: root.selectedSource === "hybrid" ? "Choose the preset that supplies surfaces and neutral roles." : "Curated starting palettes that do not depend on the current wallpaper."
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: width >= 650 ? 2 : 1
                                columnSpacing: 10
                                rowSpacing: 10
                                Repeater {
                                    model: root.statusData.presets ?? []
                                    PresetCard { required property var modelData; Layout.fillWidth: true; preset: modelData }
                                }
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: root.selectedSource === "custom"
                        visible: active

                        sourceComponent: ColumnLayout {
                            spacing: 12

                            SectionTitle {
                                title: "Custom palette"
                                subtitle: "Start from one seed, or control the four color families that shape your desktop."
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: customBuilder.implicitHeight + 22
                                radius: Appearance.radius.card
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                ColumnLayout {
                                    id: customBuilder
                                    anchors.fill: parent
                                    anchors.margins: 11
                                    spacing: 11

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            StyledText {
                                                text: root.customAdvanced ? "Advanced palette" : "Quick custom"
                                                color: Appearance.colors.colOnLayer1
                                                font.weight: Font.DemiBold
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: root.customAdvanced
                                                    ? "Control accents and surface temperature independently."
                                                    : "Choose one color and let Material generate the rest."
                                                color: Appearance.colors.colSubtext
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                wrapMode: Text.Wrap
                                            }
                                        }

                                        PillButton {
                                            label: "Quick"
                                            iconName: "bolt"
                                            toggled: !root.customAdvanced
                                            onClicked: root.customAdvanced = false
                                        }

                                        PillButton {
                                            label: "Advanced"
                                            iconName: "tune"
                                            toggled: root.customAdvanced
                                            onClicked: root.customAdvanced = true
                                        }
                                    }

                                    CustomColorField {
                                        visible: !root.customAdvanced
                                        title: "Seed color"
                                        subtitle: "One hue drives the generated palette"
                                        value: root.customSeed
                                        onColorEdited: value => root.customSeed = value
                                    }

                                    GridLayout {
                                        visible: root.customAdvanced
                                        Layout.fillWidth: true
                                        columns: width >= 650 ? 2 : 1
                                        columnSpacing: 10
                                        rowSpacing: 10

                                        CustomColorField {
                                            title: "Primary"
                                            subtitle: "Main accent and selected states"
                                            value: root.customSeed
                                            onColorEdited: value => root.customSeed = value
                                        }

                                        CustomColorField {
                                            title: "Secondary"
                                            subtitle: "Supporting controls and emphasis"
                                            value: root.customSecondary
                                            onColorEdited: value => root.customSecondary = value
                                        }

                                        CustomColorField {
                                            title: "Tertiary"
                                            subtitle: "Contrast family and highlights"
                                            value: root.customTertiary
                                            onColorEdited: value => root.customTertiary = value
                                        }

                                        CustomColorField {
                                            title: "Neutral"
                                            subtitle: "Backgrounds, surfaces and outlines"
                                            value: root.customNeutral
                                            onColorEdited: value => root.customNeutral = value
                                        }
                                    }

                                    RowLayout {
                                        visible: root.customAdvanced
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: "Containers and readable on-colors stay automatic."
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                        }

                                        PillButton {
                                            label: "Reset companions"
                                            iconName: "restart_alt"
                                            onClicked: {
                                                root.customSecondary = "#65758A"
                                                root.customTertiary = "#7A6488"
                                                root.customNeutral = "#74777D"
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: paletteAnchorRow.implicitHeight + 22
                                radius: Appearance.radius.card
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                RowLayout {
                                    id: paletteAnchorRow
                                    anchors.fill: parent
                                    anchors.margins: 11
                                    spacing: 9

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        StyledText {
                                            text: "Palette anchors"
                                            color: Appearance.colors.colOnLayer1
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            text: root.customAdvanced
                                                ? "Primary · Secondary · Tertiary · Neutral"
                                                : "Seed-generated palette"
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                        }
                                    }

                                    Rectangle { implicitWidth: 28; implicitHeight: 28; radius: Appearance.radius.full; color: root.customSeed; border.width: 1; border.color: Appearance.colors.colLayer0Border }
                                    Rectangle { visible: root.customAdvanced; implicitWidth: 28; implicitHeight: 28; radius: Appearance.radius.full; color: root.customSecondary; border.width: 1; border.color: Appearance.colors.colLayer0Border }
                                    Rectangle { visible: root.customAdvanced; implicitWidth: 28; implicitHeight: 28; radius: Appearance.radius.full; color: root.customTertiary; border.width: 1; border.color: Appearance.colors.colLayer0Border }
                                    Rectangle { visible: root.customAdvanced; implicitWidth: 28; implicitHeight: 28; radius: Appearance.radius.full; color: root.customNeutral; border.width: 1; border.color: Appearance.colors.colLayer0Border }
                                }
                            }

                            SectionTitle {
                                title: "Color character"
                                subtitle: "Choose how Material interprets your custom palette."
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 7

                                Repeater {
                                    model: [
                                        { "id": "auto", "name": "Auto" },
                                        { "id": "scheme-tonal-spot", "name": "Balanced" },
                                        { "id": "scheme-fidelity", "name": "Faithful" },
                                        { "id": "scheme-content", "name": "Natural" },
                                        { "id": "scheme-expressive", "name": "Vibrant" },
                                        { "id": "scheme-neutral", "name": "Minimal" },
                                        { "id": "scheme-monochrome", "name": "Monochrome" }
                                    ]

                                    PillButton {
                                        required property var modelData
                                        label: modelData.name
                                        toggled: root.selectedScheme === modelData.id
                                        onClicked: root.selectedScheme = modelData.id
                                    }
                                }

                                PillButton {
                                    label: root.customShowMoreDirections ? "Less" : "More"
                                    iconName: root.customShowMoreDirections ? "expand_less" : "expand_more"
                                    toggled: root.customShowMoreDirections
                                    onClicked: root.customShowMoreDirections = !root.customShowMoreDirections
                                }
                            }

                            Flow {
                                visible: root.customShowMoreDirections
                                Layout.fillWidth: true
                                spacing: 7

                                PillButton {
                                    label: "Varied"
                                    toggled: root.selectedScheme === "scheme-rainbow"
                                    onClicked: root.selectedScheme = "scheme-rainbow"
                                }

                                PillButton {
                                    label: "Playful"
                                    toggled: root.selectedScheme === "scheme-fruit-salad"
                                    onClicked: root.selectedScheme = "scheme-fruit-salad"
                                }
                            }
                        }
                    }

                    Item { implicitHeight: 12 }
                }
            }
        }

        Component {
            id: surfacesPage

            ScrollView {
                clip: true
                leftPadding: 20
                rightPadding: 20
                topPadding: 20
                bottomPadding: 20
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: "Interface style"
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Preview an interface profile, or fine-tune individual settings."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            implicitWidth: profileStateLabel.implicitWidth + 18
                            implicitHeight: 28
                            radius: Appearance.radius.full
                            color: root.selectedUiProfile === "custom"
                                ? Appearance.colors.colLayer2Base
                                : Appearance.colors.colPrimaryContainer
                            border.width: root.selectedUiProfile === "custom" ? 1 : 0
                            border.color: Appearance.colors.colPrimary

                            StyledText {
                                id: profileStateLabel
                                anchors.centerIn: parent
                                text: root.interfaceProfileStateLabel()
                                color: root.selectedUiProfile === "custom"
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOnPrimaryContainer
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                            }
                        }

                        RippleButton {
                            visible:
                                root.selectedUiProfile === "custom"
                                && root.interfaceBaseProfile.length > 0
                            implicitWidth: resetProfileRow.implicitWidth + 20
                            implicitHeight: 36
                            buttonRadius: Appearance.radius.control
                            buttonRadiusPressed: Appearance.radius.control
                            colBackground: Appearance.colors.colLayer1Base
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: "Reset interface profile"
                            onClicked: root.resetInterfaceProfile()

                            contentItem: RowLayout {
                                id: resetProfileRow
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialSymbol {
                                    text: "restart_alt"
                                    iconSize: 16
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    text: "Reset"
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: root.actionFailed
                        Layout.fillWidth: true
                        text: "The latest interface change could not be applied."
                        color: Appearance.m3colors.m3error
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.Wrap
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 920 ? 3 : width >= 640 ? 2 : 1
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: (root.statusData.uiProfiles ?? []).filter(
                                profile => profile.id === "default" || profile.id === "fluid"
                            )

                            UiProfileCard {
                                required property var modelData
                                Layout.fillWidth: true
                                profile: modelData
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: interfaceControls.implicitHeight + 2
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        ColumnLayout {
                            id: interfaceControls
                            anchors.fill: parent
                            anchors.margins: 1
                            spacing: 0

                            SettingsComponents.SettingsSectionTabs {
                                sections: [
                                    { id: "surfaces", label: "Surfaces", icon: "blur_on" },
                                    { id: "motion", label: "Motion", icon: "motion_mode" },
                                    { id: "screen", label: "Screen edges", icon: "crop_free" }
                                ]
                                section: root.interfaceFineTuneSection
                                onSectionRequested: sectionId => root.interfaceFineTuneSection = sectionId
                            }

                            Loader {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.margins: 16
                                sourceComponent: root.interfaceFineTuneSection === "motion"
                                    ? motionSectionComponent
                                    : root.interfaceFineTuneSection === "screen"
                                        ? screenSectionComponent
                                        : surfacesSectionComponent
                            }
                        }
                    }

                    Component {
                        id: surfacesSectionComponent

                        ColumnLayout {
                            spacing: 10

                            InterfaceSwitchRow {
                                Layout.fillWidth: true
                                title: "Transparency"
                                subtitle: "Let the wallpaper show through shell surfaces."
                                checked: root.draftTransparencyEnable
                                onUserToggled: checked => root.draftTransparencyEnable = checked
                            }

                            InterfaceSwitchRow {
                                Layout.fillWidth: true
                                title: "Automatic transparency"
                                subtitle: "Adapts transparency to your wallpaper. Turn this off to set your own values."
                                switchEnabled: root.draftTransparencyEnable
                                checked: root.draftTransparencyAutomatic
                                onUserToggled: checked => root.draftTransparencyAutomatic = checked
                            }

                            ColumnLayout {
                                visible: root.draftTransparencyEnable && !root.draftTransparencyAutomatic
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: 14

                                InterfaceSliderRow {
                                    Layout.fillWidth: true
                                    title: "Shell background transparency"
                                    subtitle: "Adjust the shell background from 0% to 40%."
                                    fromValue: 0
                                    toValue: 0.4
                                    value: root.draftBackgroundTransparency
                                    onValueEdited: value => root.draftBackgroundTransparency = value
                                }

                                InterfaceSliderRow {
                                    Layout.fillWidth: true
                                    title: "Content surface transparency"
                                    subtitle: "Adjust the transparency of cards and controls."
                                    fromValue: 0
                                    toValue: 0.95
                                    value: root.draftContentTransparency
                                    onValueEdited: value => root.draftContentTransparency = value
                                }
                            }

                            InterfaceSwitchRow {
                                Layout.fillWidth: true
                                title: "Background tint"
                                subtitle: "Blend a subtle accent color into the shell background."
                                checked: root.draftExtraBackgroundTint
                                onUserToggled: checked => root.draftExtraBackgroundTint = checked
                            }
                        }
                    }

                    Component {
                        id: motionSectionComponent

                        ColumnLayout {
                            spacing: 10

                            InterfaceSwitchRow {
                                Layout.fillWidth: true
                                title: "Reduced motion"
                                subtitle: "Limit movement in shell transitions."
                                checked: root.draftReducedMotion
                                onUserToggled: checked => root.draftReducedMotion = checked
                            }

                            InterfaceSliderRow {
                                Layout.fillWidth: true
                                enabled: !root.draftReducedMotion
                                opacity: enabled ? 1 : 0.46
                                title: "Motion duration"
                                subtitle: "50% is faster, 100% is standard, and 150% is slower."
                                fromValue: 0.5
                                toValue: 1.5
                                stepSize: 0.05
                                value: root.draftMotionScale
                                onValueEdited: value => root.draftMotionScale = value
                            }

                            InterfaceSwitchRow {
                                Layout.fillWidth: true
                                title: "Expressive motion"
                                subtitle: "Allow supported animations to overshoot briefly."
                                checked: root.draftExpressiveMotion
                                switchEnabled: !root.draftReducedMotion
                                onUserToggled: checked => root.draftExpressiveMotion = checked
                            }
                        }
                    }

                    Component {
                        id: screenSectionComponent

                        ColumnLayout {
                            spacing: 12

                            StyledText {
                                Layout.fillWidth: true
                                text: "Choose when to show simulated display corners."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.Wrap
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: width >= 390 ? 3 : 1
                                uniformCellWidths: true
                                columnSpacing: 8
                                rowSpacing: 6

                                InterfaceChoiceButton {
                                    Layout.fillWidth: true
                                    label: "Off"
                                    active: root.draftFakeScreenRounding === 0
                                    onClicked: root.draftFakeScreenRounding = 0
                                }

                                InterfaceChoiceButton {
                                    Layout.fillWidth: true
                                    label: "Always"
                                    active: root.draftFakeScreenRounding === 1
                                    onClicked: root.draftFakeScreenRounding = 1
                                }

                                InterfaceChoiceButton {
                                    Layout.fillWidth: true
                                    label: "Except fullscreen"
                                    active: root.draftFakeScreenRounding === 2
                                    onClicked: root.draftFakeScreenRounding = 2
                                }
                            }
                        }
                    }

                    Item { implicitHeight: 10 }
                }
            }
        }

        Component {
            id: cornersPage

            ScrollView {
                clip: true
                leftPadding: 20
                rightPadding: 20
                topPadding: 20
                bottomPadding: 20
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 14

                    SectionTitle {
                        title: "Corner geometry"
                        subtitle: "Set a shared radius or override it for individual surfaces."
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: globalRadiusColumn.implicitHeight + 2 * root.cornerCardPadding
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        ColumnLayout {
                            id: globalRadiusColumn
                            anchors.fill: parent
                            anchors.margins: root.cornerCardPadding
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        text: "Global radius"
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Surfaces with “Use global radius” enabled follow this value."
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        wrapMode: Text.Wrap
                                    }
                                }

                                StyledText {
                                    text: `${root.draftRadiusGlobal} px`
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.DemiBold
                                }
                            }

                            StyledSlider {
                                Layout.fillWidth: true
                                configuration: StyledSlider.Configuration.XS
                                from: 0
                                to: 40
                                stepSize: 1
                                usePercentTooltip: false
                                value: root.draftRadiusGlobal
                                Accessible.name: "Global radius, in pixels"
                                onMoved: root.draftRadiusGlobal = Math.round(value)
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 8

                                PillButton {
                                    label: "All follow global"
                                    toggled: root.draftRadiusModalFollowGlobal
                                        && root.draftRadiusCardFollowGlobal
                                        && root.draftRadiusControlFollowGlobal
                                        && root.draftRadiusWindowFollowGlobal
                                        && root.draftRadiusBarFollowGlobal
                                        && root.draftRadiusSidebarFollowGlobal
                                        && root.draftRadiusPopupFollowGlobal
                                        && root.draftRadiusScreenFollowGlobal
                                    onClicked: root.makeAllRadiiFollowGlobal()
                                }
                                PillButton {
                                    label: "Reset defaults"
                                    onClicked: root.resetRadiusDefaults()
                                }
                            }
                        }
                    }

                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "modal"
                        title: "Modals"
                        subtitle: "Settings, selectors and large dialogs"
                        followGlobal: root.draftRadiusModalFollowGlobal
                        radiusValue: root.draftRadiusModalValue
                    }
                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "card"
                        title: "Cards"
                        subtitle: "Reusable content sections inside panels and pages"
                        followGlobal: root.draftRadiusCardFollowGlobal
                        radiusValue: root.draftRadiusCardValue
                    }
                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "control"
                        title: "Controls"
                        subtitle: "Rectangular buttons, fields and interactive controls"
                        followGlobal: root.draftRadiusControlFollowGlobal
                        radiusValue: root.draftRadiusControlValue
                    }

                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "window"
                        title: "Windows"
                        subtitle: "Compositor-managed application windows"
                        followGlobal: root.radiusFollowGlobal(role)
                        radiusValue: root.radiusValue(role)
                    }
                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "bar"
                        title: "Bar"
                        subtitle: "Horizontal and vertical bars"
                        followGlobal: root.radiusFollowGlobal(role)
                        radiusValue: root.radiusValue(role)
                    }
                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "sidebar"
                        title: "Sidebars"
                        subtitle: "Shell side panels"
                        followGlobal: root.radiusFollowGlobal(role)
                        radiusValue: root.radiusValue(role)
                    }
                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "popup"
                        title: "Popups"
                        subtitle: "Popup menus and controls"
                        followGlobal: root.radiusFollowGlobal(role)
                        radiusValue: root.radiusValue(role)
                    }
                    RadiusSettingRow {
                        Layout.fillWidth: true
                        role: "screen"
                        title: "Screen"
                        subtitle: "Simulated display corners"
                        followGlobal: root.radiusFollowGlobal(role)
                        radiusValue: root.radiusValue(role)
                    }
                }
            }
        }

        Component {
            id: appThemingPage

            ScrollView {
                function expandTerminalTuning(): void {
                    terminalEditor.terminalTuningExpanded = true
                }
                clip: true
                leftPadding: 20
                rightPadding: 20
                topPadding: 20
                bottomPadding: 20
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 18

                    SectionTitle {
                        title: "App theming"
                        subtitle: "Choose where the current appearance is synchronized. Enabling a target applies the current look to it immediately."
                    }

                    TargetIntegrationSection {
                        title: "Desktop"
                        subtitle: "Core shell and compositor surfaces."
                        targetItems: [
                            { "id": "shell", "name": "Nyvorel", "icon": "dashboard", "desc": "Panels, dialogs and widgets" },
                            { "id": "hyprland", "name": "Hyprland", "icon": "select_window", "desc": "Compositor colors and borders" }
                        ]
                    }

                    TargetIntegrationSection {
                        title: "Apps"
                        subtitle: "Generated toolkit themes and app-specific accents."
                        targetItems: [
                            { "id": "gtk", "name": "GTK", "icon": "widgets", "desc": "GTK 3 and GTK 4 generated CSS" },
                            { "id": "fuzzel", "name": "Fuzzel", "icon": "search", "desc": "Launcher color theme" },
                            { "id": "terminal", "name": "Terminal", "icon": "terminal", "desc": "Live terminal color sequences" },
                            { "id": "editors", "name": "Code editors", "icon": "code", "desc": "VS Code, VSCodium, Cursor and related editor accents" }
                        ]
                    }

                    TargetIntegrationSection {
                        title: "Compatibility"
                        subtitle: "Optional bridges that may depend on your desktop session."
                        targetItems: [
                            { "id": "qt", "name": "Qt / KDE bridge", "icon": "desktop_windows", "desc": "Optional KDE color bridge; kept opt-in on Hyprland", "compatibility": true }
                        ]
                    }

                    SettingsComponents.TerminalColorSettings {
                        id: terminalEditor
                        Layout.fillWidth: true
                        targetEnabled: root.targetEnabled("terminal")
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 4
                    }
                }
            }
        }

        Component {
            id: savedLooksPage

            ScrollView {
                clip: true
                leftPadding: 20
                rightPadding: 20
                topPadding: 20
                bottomPadding: 20
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 18

                    SectionTitle {
                        title: "Saved looks"
                        subtitle: "Keep favorite looks for reuse and recover recently applied appearances."
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: currentAppearanceColumn.implicitHeight + 24

                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        ColumnLayout {
                            id: currentAppearanceColumn
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        text: "Current appearance"
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.activeTitle(root.statusData.active ?? ({}))
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.entryMeta({ "active": root.statusData.active ?? ({}) })
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        elide: Text.ElideRight
                                    }
                                }

                                RowLayout {
                                    spacing: 5
                                    ColorDot { dotColor: Appearance.colors.colPrimary }
                                    ColorDot { dotColor: Appearance.m3colors.m3secondary }
                                    ColorDot { dotColor: Appearance.m3colors.m3tertiary }
                                    ColorDot { dotColor: Appearance.m3colors.m3surfaceContainer }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialTextField {
                                    Layout.fillWidth: true
                                    placeholderText: "Optional name"
                                    text: root.favoriteName
                                    onTextChanged: root.favoriteName = text
                                }

                                RippleButton {
                                    implicitHeight: 40
                                    implicitWidth: saveFavoriteText.implicitWidth + 42
                                    buttonRadius: Appearance.radius.control
                                    buttonRadiusPressed: Appearance.radius.control
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    colRipple: Appearance.colors.colPrimaryActive
                                    enabled: root.previewToken.length === 0 && !actionProc.running
                                    activeFocusOnTab: true
                                    Accessible.name: "Save current appearance to favorites"
                                    onClicked: root.saveCurrentFavorite()

                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol {
                                            text: "bookmark_add"
                                            iconSize: 17
                                            color: Appearance.colors.colOnPrimary
                                        }
                                        StyledText {
                                            id: saveFavoriteText
                                            text: "Save favorite"
                                            color: Appearance.colors.colOnPrimary
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        SectionTitle {
                            Layout.fillWidth: true
                            title: "Favorites"
                            subtitle: "Looks you intentionally keep and reuse"
                        }

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: favoriteCountText.implicitWidth + 16
                            radius: Appearance.radius.full
                            color: Appearance.colors.colLayer2Base

                            StyledText {
                                id: favoriteCountText
                                anchors.centerIn: parent
                                text: `${(root.statusData.favorites ?? []).length}`
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        visible: (root.statusData.favorites ?? []).length === 0
                        Layout.fillWidth: true
                        implicitHeight: 86
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 11

                            Rectangle {
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: Appearance.radius.control
                                color: Appearance.colors.colLayer2Base

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "bookmark"
                                    iconSize: 21
                                    color: Appearance.colors.colPrimary
                                }
                            }

                            ColumnLayout {
                                spacing: 1
                                StyledText {
                                    text: "No favorites yet"
                                    color: Appearance.colors.colOnLayer1
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    text: "Save the current appearance above to keep it here."
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }
                        }
                    }

                    GridLayout {
                        visible: (root.statusData.favorites ?? []).length > 0
                        Layout.fillWidth: true
                        columns: width >= 720 ? 2 : 1
                        columnSpacing: 12
                        rowSpacing: 12

                        Repeater {
                            model: root.statusData.favorites ?? []
                            FavoriteCard {
                                required property var modelData
                                entry: modelData
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 8

                        SectionTitle {
                            Layout.fillWidth: true
                            title: "History"
                            subtitle: "Recent committed appearances you can restore"
                        }

                        RippleButton {
                            visible: (root.statusData.history ?? []).length > 0
                            implicitHeight: 34
                            implicitWidth: clearHistoryText.implicitWidth + 34
                            buttonRadius: Appearance.radius.control
                            buttonRadiusPressed: Appearance.radius.control
                            colBackground: root.clearHistoryArmed
                                ? Appearance.colors.colErrorContainer
                                : Appearance.colors.colLayer1Base
                            colBackgroundHover: Appearance.colors.colErrorContainerHover
                            colRipple: Appearance.colors.colErrorContainerActive
                            activeFocusOnTab: true
                            Accessible.name: root.clearHistoryArmed
                                ? "Confirm clear history"
                                : "Clear history"
                            onClicked: {
                                if (root.clearHistoryArmed) {
                                    root.runAction(
                                        [root.managerPath, "clear-history"],
                                        "clear-history"
                                    )
                                } else {
                                    root.clearHistoryArmed = true
                                    clearHistoryConfirmTimer.restart()
                                }
                            }

                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                MaterialSymbol {
                                    text: root.clearHistoryArmed ? "delete_forever" : "delete_sweep"
                                    iconSize: 16
                                    color: root.clearHistoryArmed
                                        ? Appearance.colors.colOnErrorContainer
                                        : Appearance.colors.colSubtext
                                }

                                StyledText {
                                    id: clearHistoryText
                                    text: root.clearHistoryArmed ? "Confirm clear" : "Clear history"
                                    color: root.clearHistoryArmed
                                        ? Appearance.colors.colOnErrorContainer
                                        : Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: (root.statusData.history ?? []).length === 0
                        Layout.fillWidth: true
                        implicitHeight: 76
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 10

                            MaterialSymbol {
                                text: "history"
                                iconSize: 21
                                color: Appearance.colors.colSubtext
                            }

                            ColumnLayout {
                                spacing: 1
                                StyledText {
                                    text: "No history yet"
                                    color: Appearance.colors.colOnLayer1
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    text: "Applied appearances will appear here automatically."
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.historyGroup("today").length > 0
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: "Today"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.historyGroup("today")
                            HistoryRow {
                                required property var modelData
                                entry: modelData
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.historyGroup("yesterday").length > 0
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: "Yesterday"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.historyGroup("yesterday")
                            HistoryRow {
                                required property var modelData
                                entry: modelData
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.historyGroup("earlier").length > 0
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: "Earlier"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.historyGroup("earlier")
                            HistoryRow {
                                required property var modelData
                                entry: modelData
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 12
                    }
                }
            }
        }
    }
}
