import qs.modules.nyvorel.bar.weather

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Services.UPower

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions


Item {
    id: root

    // ============================================================
    // Root state
    // ============================================================

    property var screen:
        root.QsWindow.window?.screen

    property var brightnessMonitor:
        Brightness.getMonitorForScreen(root.screen)

    property real useShortenedForm:
        Appearance.sizes.barHellaShortenScreenWidthThreshold >= root.screen?.width
            ? 2
            : Appearance.sizes.barShortenScreenWidthThreshold >= root.screen?.width
                ? 1
                : 0

    // True whenever at least one Settings > Bar > Utility action is enabled.
    // This is derived only; Settings remains the source of truth.
    readonly property bool hasUtilityActions:
        Config.options.bar.utilButtons.showScreenSnip
        || Config.options.bar.utilButtons.showScreenRecord
        || Config.options.bar.utilButtons.showColorPicker
        || Config.options.bar.utilButtons.showKeyboardToggle
        || Config.options.bar.utilButtons.showMicToggle
        || Config.options.bar.utilButtons.showDarkModeToggle
        || Config.options.bar.utilButtons.showKeepAwakeToggle
        || Config.options.bar.utilButtons.showNightLightToggle

    // ============================================================
    // Dynamic three-zone layout
    //
    // LEFT   -> current app/context
    // CENTER -> media + physically anchored workspaces
    // RIGHT  -> system state
    //
    // Visibility changes in one zone never move the center anchor.
    // ============================================================

    readonly property real zoneGap: Appearance.prismMode ? Appearance.prism.islandGap : 8
    readonly property real safetyGap: 12

    // prism-v2-phase2a3: all persistent Prism islands use the canonical
    // 40px bar host height. Do not shrink the surface to manufacture equality:
    // BarContent's surrounding shell already owns the outer vertical rhythm.
    readonly property real prismIslandHeight:
        Appearance.sizes.baseBarHeight

    readonly property real mediaDesiredWidth:
        (
            root.useShortenedForm < 2
            && mediaWidget.hasMedia
        )
            ? Math.min(mediaWidget.implicitWidth + 10, 200)
            : 0

    readonly property real leftAvailableWidth:
        Math.max(
            0,
            root.width / 2
                - middleSection.implicitWidth / 2
                - root.safetyGap
                - root.mediaDesiredWidth
                - (root.mediaDesiredWidth > 0 ? root.zoneGap : 0)
        )

    readonly property real rightAvailableWidth:
        Math.max(
            0,
            root.width / 2
                - middleSection.implicitWidth / 2
                - root.safetyGap
        )

    readonly property bool wantsRightClock:
        root.useShortenedForm < 2
        && Config.options.bar.visibility.clock

    readonly property bool wantsRightResources:
        root.useShortenedForm < 2
        && Config.options.bar.visibility.resources

    readonly property bool wantsRightTray:
        root.useShortenedForm === 0

    readonly property bool wantsRightUtilities:
        root.useShortenedForm === 0
        && root.hasUtilityActions

    readonly property bool wantsRightWeather:
        root.useShortenedForm === 0
        && Config.options.bar.weather.enable

    readonly property real rightEssentialWidth:
        rightSidebarButton.implicitWidth
        + (
            batteryIndicator.visible
                ? batteryIndicator.implicitWidth + root.zoneGap
                : 0
        )
        + (
            root.wantsRightClock
                ? clockRightGroup.implicitWidth + root.zoneGap
                : 0
        )

    readonly property bool showRightResources:
        root.wantsRightResources
        && root.rightAvailableWidth
            >= root.rightEssentialWidth
                + resourcesRightGroup.implicitWidth
                + root.zoneGap

    readonly property real rightAfterResourcesWidth:
        root.rightEssentialWidth
        + (
            root.showRightResources
                ? resourcesRightGroup.implicitWidth + root.zoneGap
                : 0
        )

    readonly property bool showRightTray:
        root.wantsRightTray
        && root.rightAvailableWidth
            >= root.rightAfterResourcesWidth
                + sysTray.implicitWidth
                + root.zoneGap

    readonly property real rightAfterTrayWidth:
        root.rightAfterResourcesWidth
        + (
            root.showRightTray
                ? sysTray.implicitWidth + root.zoneGap
                : 0
        )

    readonly property real utilityActionsWidth:
        utilityActionsLoader.item?.implicitWidth ?? 0

    readonly property bool showRightUtilities:
        root.wantsRightUtilities
        && root.rightAvailableWidth
            >= root.rightAfterTrayWidth
                + root.utilityActionsWidth
                + root.zoneGap

    readonly property real rightAfterUtilitiesWidth:
        root.rightAfterTrayWidth
        + (
            root.showRightUtilities
                ? root.utilityActionsWidth + root.zoneGap
                : 0
        )

    readonly property real weatherWidth:
        weatherLoader.item?.implicitWidth ?? 0

    readonly property bool showRightWeather:
        root.wantsRightWeather
        && root.rightAvailableWidth
            >= root.rightAfterUtilitiesWidth
                + root.weatherWidth
                + root.zoneGap


    // ============================================================
    // Bar background shadow
    // ============================================================

    Loader {
        active:
            Config.options.bar.showBackground
            && Config.options.bar.cornerStyle === 1
            && Config.options.bar.floatStyleShadow
            && !Appearance.prismMode
            && !Appearance.inlayMode

        anchors.fill:
            barBackground

        sourceComponent:
            StyledRectangularShadow {
                anchors.fill: undefined
                target: barBackground
            }
    }


    // ============================================================
    // Bar background
    // ============================================================

    Rectangle {
        id: barBackground

        anchors {
            fill: parent

            margins:
                Config.options.bar.cornerStyle === 1
                    ? Appearance.sizes.hyprlandGapsOut
                    : 0
        }

        // inlay-v2-i2: a single opaque material rail owns the navbar.
        // Functional zones are carved into it with crisp inset borders.
        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.inlayMode
                    ? (Config.options.bar.showBackground
                        ? Appearance.inlay.surfaceFill
                        : "transparent")
                    : (Config.options.bar.showBackground
                        ? Appearance.colors.colLayer0
                        : "transparent")

        radius:
            Appearance.inlayMode
                ? 0
                : Config.options.bar.cornerStyle === 1
                    ? Appearance.radius.bar
                    : 0

        border.width:
            Appearance.prismMode
                ? 0
                : Appearance.inlayMode
                    ? (Config.options.bar.showBackground ? Appearance.inlay.borderWidth : 0)
                    : (Config.options.bar.cornerStyle === 1 ? 1 : 0)

        border.color:
            Appearance.inlayMode
                ? Appearance.inlay.borderSubtle
                : Appearance.colors.colLayer0Border
    }


    // ============================================================
    // LEFT SIDE
    //
    // Left sidebar button + active application.
    //
    // Scroll -> brightness
    // Click  -> left sidebar
    //
    // The hit target is intentionally content-sized; visually empty
    // bar space is not a hidden click target.
    // ============================================================

    PrismSurface {
        id: leftContextSurface
        z: 0
        visible: Appearance.prismMode
        depth: Appearance.prism.depthPersistent
        surfaceRadius: Appearance.prism.radiusPersistent
        hovered: barLeftSideMouseArea.hovered && !GlobalStates.sidebarLeftOpen
        active: GlobalStates.sidebarLeftOpen

        anchors {
            left: barLeftSideMouseArea.left
            right: barLeftSideMouseArea.right
            verticalCenter: barLeftSideMouseArea.verticalCenter
        }

        height: root.prismIslandHeight
    }

    Rectangle {
        id: inlayContextSegment
        z: 0
        visible: Appearance.inlayMode
        anchors {
            left: barLeftSideMouseArea.left
            right: barLeftSideMouseArea.right
            leftMargin: -Appearance.spacing.xs
            rightMargin: -Appearance.spacing.xs
            verticalCenter: barLeftSideMouseArea.verticalCenter
        }
        height: Appearance.sizes.baseBarHeight - 10
        radius: 0
        color: GlobalStates.sidebarLeftOpen
            ? Appearance.inlay.selectedFill
            : barLeftSideMouseArea.hovered
                ? Appearance.inlay.hoverFill
                : Appearance.inlay.insetFill
        border.width: Appearance.inlay.borderWidth
        border.color: GlobalStates.sidebarLeftOpen
            ? Appearance.inlay.borderFocus
            : Appearance.inlay.borderSection

        Behavior on color { MotionColorAnim { type: MotionColorAnim.FastEffects } }
    }

    FocusedScrollMouseArea {
        id: barLeftSideMouseArea
        z: 1

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left

            leftMargin:
                Appearance.prismMode
                    ? Appearance.prism.screenInset
                    : Appearance.inlayMode
                        ? Appearance.sizes.hyprlandGapsOut + Appearance.spacing.md
                        : 0
        }

        width:
            Math.min(
                leftSectionRowLayout.implicitWidth,
                root.leftAvailableWidth
            )

        implicitHeight:
            Appearance.sizes.baseBarHeight

        clip:
            true


        onScrollDown: {
            if (
                !Config.options.sidebar.cornerOpen.enable
                || !Config.options.sidebar.cornerOpen.valueScroll
                || Config.options.sidebar.cornerOpen.bottom
                    !== Config.options.bar.bottom
                || !root.brightnessMonitor
            ) {
                return
            }

            root.brightnessMonitor.setBrightness(
                Math.max(
                    0,
                    root.brightnessMonitor.brightness - 0.05
                )
            )
            GlobalStates.osdBrightnessOpen = true
        }

        onScrollUp: {
            if (
                !Config.options.sidebar.cornerOpen.enable
                || !Config.options.sidebar.cornerOpen.valueScroll
                || Config.options.sidebar.cornerOpen.bottom
                    !== Config.options.bar.bottom
                || !root.brightnessMonitor
            ) {
                return
            }

            root.brightnessMonitor.setBrightness(
                Math.min(
                    1,
                    root.brightnessMonitor.brightness + 0.05
                )
            )
            GlobalStates.osdBrightnessOpen = true
        }

        onMovedAway:
            GlobalStates.osdBrightnessOpen = false

        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarLeftOpen =
                    !GlobalStates.sidebarLeftOpen;
            }
        }


        RowLayout {
            id: leftSectionRowLayout

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            height:
                Appearance.prismMode
                    ? Appearance.sizes.baseBarHeight
                    : parent.height

            spacing:
                0


            LeftSidebarButton {
                id: leftSidebarButton

                Layout.alignment:
                    Qt.AlignVCenter

                Layout.leftMargin:
                    Appearance.prismMode
                        ? Appearance.spacing.sm
                        : Appearance.inlayMode
                            ? Appearance.spacing.md
                            : Appearance.rounding.screenRounding

                // Inlay state belongs to the outer framed region; the
                // icon is content, not another nested chip.
                colBackground:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : barLeftSideMouseArea.hovered
                            ? Appearance.colors.colLayer1Hover
                            : ColorUtils.transparentize(
                                Appearance.colors.colLayer1Hover,
                                1
                            )
                colBackgroundHover:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colLayer1Hover
                colBackgroundToggled:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colSecondaryContainerHover
            }


            ActiveWindow {
                Layout.leftMargin:
                    8
                    + (
                        leftSidebarButton.visible
                            ? 0
                            : Appearance.inlayMode
                                ? Appearance.spacing.md
                                : Appearance.rounding.screenRounding
                    )

                Layout.rightMargin:
                    8

                Layout.fillWidth:
                    true

                Layout.fillHeight:
                    true

                visible:
                    root.useShortenedForm === 0
            }
        }
    }


    // ============================================================
    // CENTER
    //
    // Workspaces are the permanent physical anchor. Optional media
    // attaches to their left but never owns the mathematical center.
    // ============================================================

    BarGroup {
        id: middleSection
        z: 4

        anchors {
            horizontalCenter:
                parent.horizontalCenter

            verticalCenter:
                parent.verticalCenter
        }

        width:
            implicitWidth

        height:
            implicitHeight

        padding:
            Appearance.prismMode
                ? Appearance.spacing.sm
                : workspacesWidget.widgetPadding

        prismActive: Appearance.prismMode && GlobalStates.overviewOpen

        Workspaces {
            id: workspacesWidget

            Layout.fillHeight:
                true


            MouseArea {
                anchors.fill:
                    parent

                acceptedButtons:
                    Qt.RightButton

                onPressed: event => {
                    if (event.button === Qt.RightButton) {
                        GlobalStates.overviewOpen =
                            !GlobalStates.overviewOpen;
                    }
                }
            }
        }
    }


    // ============================================================
    // MEDIA
    //
    // Secondary center content. The active-window region yields
    // horizontal room first; Workspaces never move.
    // ============================================================

    BarGroup {
        id: mediaCenterGroup
        z: 4

        // Contextual media belongs to the persistent plane but should never
        // compete with navigation/system anchors for visual weight.
        prismElevated: false
        prismSurfaceOpacity: 0.82

        anchors {
            right:
                middleSection.left

            rightMargin:
                visible
                    ? root.zoneGap
                    : 0

            verticalCenter:
                parent.verticalCenter
        }

        visible:
            Appearance.prismMode
                ? (root.mediaDesiredWidth > 0 || width > 0.5)
                : root.mediaDesiredWidth > 0

        width:
            Appearance.prismMode
                ? root.mediaDesiredWidth
                : (visible ? root.mediaDesiredWidth : 0)

        height:
            implicitHeight

        opacity:
            Appearance.prismMode
                ? (root.mediaDesiredWidth > 0 ? 1 : 0)
                : 1

        scale:
            Appearance.prismMode
                ? (root.mediaDesiredWidth > 0 ? 1 : Appearance.prism.enterScale)
                : 1

        transformOrigin: Item.Right
        clip: true

        Behavior on width {
            enabled: Appearance.prismMode
            MotionAnim {
                type: MotionAnim.DefaultSpatial
                duration: Appearance.prism.enterDuration
            }
        }

        Behavior on opacity {
            enabled: Appearance.prismMode
            MotionAnim {
                type: MotionAnim.FastEffects
                duration: Appearance.prism.exitDuration
            }
        }

        Behavior on scale {
            enabled: Appearance.prismMode
            MotionAnim {
                type: MotionAnim.DefaultSpatial
                duration: Appearance.prism.enterDuration
            }
        }


        Media {
            id: mediaWidget

            Layout.fillWidth:
                true
        }
    }


    // ============================================================
    // RIGHT SIDE
    //
    // Weather + tray + battery + system-status pill.
    //
    // Scroll -> volume
    // Click  -> right sidebar
    // ============================================================

    // prism-v2-phase2a: one coherent system-state island replaces the
    // previous collection of independently framed right-side pills.
    PrismSurface {
        z: 0
        visible: Appearance.prismMode
        depth: Appearance.prism.depthPersistent
        surfaceRadius: Appearance.prism.radiusPersistent
        hovered: barRightSideMouseArea.hovered && !GlobalStates.sidebarRightOpen
        active: GlobalStates.sidebarRightOpen
        anchors {
            left: barRightSideMouseArea.left
            right: barRightSideMouseArea.right
            verticalCenter: barRightSideMouseArea.verticalCenter
        }

        height: root.prismIslandHeight
    }

    Rectangle {
        id: inlaySystemSegment
        z: 0
        visible: Appearance.inlayMode
        anchors {
            left: barRightSideMouseArea.left
            right: barRightSideMouseArea.right
            leftMargin: -Appearance.spacing.xs
            rightMargin: -Appearance.spacing.xs
            verticalCenter: barRightSideMouseArea.verticalCenter
        }
        height: Appearance.sizes.baseBarHeight - 10
        radius: 0
        color: GlobalStates.sidebarRightOpen
            ? Appearance.inlay.selectedFill
            : barRightSideMouseArea.hovered
                ? Appearance.inlay.hoverFill
                : Appearance.inlay.insetFill
        border.width: Appearance.inlay.borderWidth
        border.color: GlobalStates.sidebarRightOpen
            ? Appearance.inlay.borderFocus
            : Appearance.inlay.borderSection

        Behavior on color { MotionColorAnim { type: MotionColorAnim.FastEffects } }
    }

    FocusedScrollMouseArea {
        id: barRightSideMouseArea
        z: 1

        anchors {
            top:
                parent.top

            bottom:
                parent.bottom

            right:
                parent.right

            rightMargin:
                Appearance.prismMode
                    ? Appearance.prism.screenInset
                    : Appearance.inlayMode
                        ? Appearance.sizes.hyprlandGapsOut + Appearance.spacing.md
                        : 0
        }

        width:
            Math.min(
                rightSectionRowLayout.implicitWidth,
                root.rightAvailableWidth
            )

        implicitHeight:
            Appearance.sizes.baseBarHeight

        clip:
            true


        onScrollDown: {
            if (
                !Config.options.sidebar.cornerOpen.enable
                || !Config.options.sidebar.cornerOpen.valueScroll
                || Config.options.sidebar.cornerOpen.bottom
                    !== Config.options.bar.bottom
            ) {
                return
            }

            Audio.decrementVolume()
            GlobalStates.osdVolumeOpen = true
        }

        onScrollUp: {
            if (
                !Config.options.sidebar.cornerOpen.enable
                || !Config.options.sidebar.cornerOpen.valueScroll
                || Config.options.sidebar.cornerOpen.bottom
                    !== Config.options.bar.bottom
            ) {
                return
            }

            Audio.incrementVolume()
            GlobalStates.osdVolumeOpen = true
        }

        onMovedAway:
            GlobalStates.osdVolumeOpen = false

        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen =
                    !GlobalStates.sidebarRightOpen;
            }
        }


        RowLayout {
            id: rightSectionRowLayout

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }

            height:
                Appearance.prismMode
                    ? Appearance.sizes.baseBarHeight
                    : parent.height

            spacing:
                Appearance.prismMode
                    ? Appearance.spacing.xs
                    : Appearance.inlayMode
                        ? Appearance.spacing.sm
                        : 8

            // First child appears at the physical right edge.
            layoutDirection:
                Qt.RightToLeft


            // ====================================================
            // System status
            // ====================================================

            RippleButton {
                id: rightSidebarButton

                Layout.alignment:
                    Qt.AlignRight | Qt.AlignVCenter

                Layout.rightMargin:
                    Appearance.prismMode
                        ? Appearance.spacing.sm
                        : Appearance.inlayMode
                            ? Appearance.spacing.md
                            : Appearance.rounding.screenRounding

                Layout.fillWidth:
                    false

                implicitWidth:
                    indicatorsRowLayout.implicitWidth
                        + (Appearance.prismMode
                            ? 12
                            : Appearance.inlayMode
                                ? 0
                                : 16)

                implicitHeight:
                    indicatorsRowLayout.implicitHeight
                        + (Appearance.prismMode ? 6 : 8)

                buttonRadius:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.prismMode
                            ? Appearance.prism.radiusControl
                            : Appearance.rounding.full


                colBackground:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : GlobalStates.sidebarRightOpen
                            ? Appearance.colors.colSecondaryContainer
                            : barRightSideMouseArea.hovered
                                ? Appearance.colors.colLayer1Hover
                                : ColorUtils.transparentize(
                                    Appearance.colors.colLayer1,
                                    0.30
                                )

                colBackgroundHover:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colLayer1Hover

                colRipple:
                    Appearance.colors.colLayer1Active

                colBackgroundToggled:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colSecondaryContainer

                colBackgroundToggledHover:
                    (Appearance.prismMode || Appearance.inlayMode)
                        ? "transparent"
                        : Appearance.colors.colSecondaryContainerHover

                colRippleToggled:
                    Appearance.colors.colSecondaryContainerActive

                toggled:
                    GlobalStates.sidebarRightOpen


                property color colText:
                    toggled
                        ? Appearance.m3colors.m3onSecondaryContainer
                        : Appearance.colors.colOnLayer0


                Behavior on colText {
                    MotionColorAnim {
                        type: MotionColorAnim.FastEffects
                    }
                }


                onPressed: {
                    GlobalStates.sidebarRightOpen =
                        !GlobalStates.sidebarRightOpen;
                }


                RowLayout {
                    id: indicatorsRowLayout

                    anchors.centerIn:
                        parent

                    property real realSpacing:
                        Appearance.prismMode ? Appearance.spacing.md : 10

                    spacing:
                        0


                    // --------------------------------------------
                    // Output muted
                    // --------------------------------------------

                    Revealer {
                        reveal:
                            Audio.sink?.audio?.muted ?? false

                        Layout.fillHeight:
                            true

                        Layout.rightMargin:
                            reveal
                                ? indicatorsRowLayout.realSpacing
                                : 0


                        Behavior on Layout.rightMargin {
                            MotionAnim {
                                type: MotionAnim.FastSpatial
                                duration: 220
                            }
                        }


                        MaterialSymbol {
                            text:
                                "volume_off"

                            iconSize:
                                Appearance.font.pixelSize.larger

                            color:
                                rightSidebarButton.colText
                        }
                    }


                    // --------------------------------------------
                    // Microphone muted
                    // --------------------------------------------

                    Revealer {
                        reveal:
                            Audio.source?.audio?.muted ?? false

                        Layout.fillHeight:
                            true

                        Layout.rightMargin:
                            reveal
                                ? indicatorsRowLayout.realSpacing
                                : 0


                        Behavior on Layout.rightMargin {
                            MotionAnim {
                                type: MotionAnim.FastSpatial
                                duration: 220
                            }
                        }


                        MaterialSymbol {
                            text:
                                "mic_off"

                            iconSize:
                                Appearance.font.pixelSize.larger

                            color:
                                rightSidebarButton.colText
                        }
                    }


                    // --------------------------------------------
                    // Keyboard layout
                    // --------------------------------------------

                    HyprlandXkbIndicator {
                        Layout.alignment:
                            Qt.AlignVCenter

                        Layout.rightMargin:
                            indicatorsRowLayout.realSpacing

                        color:
                            rightSidebarButton.colText
                    }


                    // --------------------------------------------
                    // Notifications
                    // --------------------------------------------

                    Revealer {
                        reveal:
                            Notifications.silent
                            || Notifications.unread > 0

                        Layout.fillHeight:
                            true

                        Layout.rightMargin:
                            reveal
                                ? indicatorsRowLayout.realSpacing
                                : 0

                        implicitHeight:
                            reveal
                                ? notificationUnreadCount.implicitHeight
                                : 0

                        implicitWidth:
                            reveal
                                ? notificationUnreadCount.implicitWidth
                                : 0


                        Behavior on Layout.rightMargin {
                            MotionAnim {
                                type: MotionAnim.FastSpatial
                                duration: 220
                            }
                        }


                        NotificationUnreadCount {
                            id: notificationUnreadCount
                        }
                    }


                    // --------------------------------------------
                    // Network
                    // --------------------------------------------

                    MaterialSymbol {
                        text:
                            Network.ethernet
                                ? "signal_wifi_4_bar"
                                : Network.materialSymbol

                        iconSize:
                            Appearance.font.pixelSize.larger

                        color:
                            rightSidebarButton.colText
                    }


                    // --------------------------------------------
                    // Bluetooth
                    // --------------------------------------------

                    MaterialSymbol {
                        visible:
                            BluetoothStatus.available
                            && BluetoothStatus.enabled

                        Layout.leftMargin:
                            visible
                                ? indicatorsRowLayout.realSpacing
                                : 0

                        text:
                            BluetoothStatus.connected
                                ? "bluetooth_connected"
                                : "bluetooth"

                        iconSize:
                            Appearance.font.pixelSize.larger

                        color:
                            rightSidebarButton.colText
                    }
                }
            }


            // ====================================================
            // Battery
            // ====================================================

            BatteryIndicator {
                id: batteryIndicator

                visible:
                    root.useShortenedForm < 2
                    && Battery.available

                Layout.alignment:
                    Qt.AlignVCenter
            }


            // ====================================================
            // System tray
            // ====================================================

            SysTray {
                id: sysTray

                visible:
                    root.showRightTray

                showSeparator:
                    false

                Layout.fillWidth:
                    false

                Layout.fillHeight:
                    true

                invertSide:
                    Config?.options.bar.bottom
            }


            // ====================================================
            // Utility actions
            //
            // Secondary actions are intentionally unframed in Fluid;
            // each icon owns its own hover/toggled state.
            // ====================================================

            Loader {
                id: utilityActionsLoader

                active:
                    root.wantsRightUtilities

                visible:
                    root.showRightUtilities

                Layout.alignment:
                    Qt.AlignVCenter

                Layout.fillWidth:
                    false

                Layout.fillHeight:
                    true

                sourceComponent:
                    BarGroup {
                        prismSurface: false

                        quiet:
                            Appearance.fluidMode

                        padding:
                            Appearance.inlayMode
                                ? 0
                                : Appearance.fluidMode
                                    ? 0
                                    : Appearance.prismMode
                                        ? Appearance.spacing.xxs
                                        : 3

                        UtilButtons {}
                    }
            }


            // ====================================================
            // Clock
            // ====================================================

            BarGroup {
                id: clockRightGroup
                prismSurface: false
                padding:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.prismMode
                            ? Appearance.spacing.xs
                            : 5

                visible:
                    root.wantsRightClock

                width:
                    visible
                        ? implicitWidth
                        : 0

                ClockWidget {
                    showDate:
                        false

                    Layout.alignment:
                        Qt.AlignVCenter
                }
            }


            // ====================================================
            // Resources
            //
            // System telemetry belongs to the system-state zone,
            // not to the navigation center.
            // ====================================================

            BarGroup {
                id: resourcesRightGroup
                prismSurface: false

                visible:
                    root.showRightResources

                width:
                    visible
                        ? implicitWidth
                        : 0

                padding:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.fluidMode
                            ? 4
                            : Appearance.prismMode
                                ? Appearance.spacing.xs
                                : 5

                Resources {
                    alwaysShowAllResources:
                        false
                }
            }


            // ====================================================
            // Weather — lowest-priority optional right-side module
            // ====================================================

            Loader {
                id: weatherLoader

                active:
                    root.wantsRightWeather

                visible:
                    root.showRightWeather

                sourceComponent:
                    BarGroup {
                        prismSurface: false
                        padding:
                    Appearance.inlayMode
                        ? 0
                        : Appearance.prismMode
                            ? Appearance.spacing.xs
                            : 5
                        WeatherBar {}
                    }
            }
        }
    }
}
