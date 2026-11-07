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
import qs.modules.nyvorel.sidebarRight
import qs.modules.nyvorel.sidebarLeft


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

    readonly property real zoneGap: Appearance.barLayout.zoneGap
    readonly property real safetyGap: Appearance.barLayout.safetyGap

    // nyvorel-phase3e-media-yield: preserve the left launcher before
    // allocating the remaining left-half width to contextual media.
    readonly property real mediaFitWidth:
        Math.max(0,
            root.width / 2 - middleSection.implicitWidth / 2
            - root.safetyGap - Appearance.barLayout.edgeInset
            - leftSidebarButton.implicitWidth - root.zoneGap)

    readonly property real mediaDesiredWidth:
        root.useShortenedForm < 2
        && mediaWidget.hasMedia
        && root.mediaFitWidth >= Appearance.barLayout.minimumMediaWidth
            ? Math.min(mediaWidget.implicitWidth + 10, 200, root.mediaFitWidth)
            : 0

    readonly property real leftAvailableWidth:
        Math.max(
            0,
            root.width / 2
                - middleSection.implicitWidth / 2
                - root.safetyGap
                - Appearance.barLayout.edgeInset
                - root.mediaDesiredWidth
                - (root.mediaDesiredWidth > 0 ? root.zoneGap : 0)
        )

    readonly property real rightAvailableWidth:
        Math.max(
            0,
            root.width / 2
                - middleSection.implicitWidth / 2
                - root.safetyGap
                - Appearance.barLayout.edgeInset
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

    // Default and Fluid share Axiom structure; only their material differs.
    // Retain the established property name for pre-existing bindings.
    readonly property bool axiomFluidRight: Appearance.barLayout.axiomComponents
    // The content contract is independent of the navbar material.
    readonly property bool sharedNavbarContent: true
    // No second surface: the original Fluid bar owns all outer padding.
    // Match the natural breathing room at the left outer navbar edge.
    readonly property real axiomSideInset: root.axiomFluidRight ? 3 : 0
    readonly property real rightFitWidth:
        Math.max(0, root.rightAvailableWidth - root.axiomSideInset * 2)
    // 6px either side of each 1px section divider = 13px total.
    readonly property real axiomFitGap:
        root.axiomFluidRight ? 13 : Appearance.barLayout.rightSectionGap

    // nyvorel-phase3e-essential-fit: all right-side fit decisions use the
    // actual RowLayout gap and include the status control's right inset.
    // The right sidebar control remains visible at every width.
    readonly property real rightStatusWidth:
        rightSidebarButton.implicitWidth + Appearance.barLayout.rightStatusInset
        + networkButton.implicitWidth + root.axiomFitGap

    readonly property bool showRightBattery:
        root.useShortenedForm < 2
        && Battery.available
        && root.rightFitWidth >= root.rightStatusWidth
            + root.axiomFitGap + batteryIndicator.implicitWidth

    readonly property real rightAfterBatteryWidth:
        root.rightStatusWidth
        + (root.showRightBattery
            ? root.axiomFitGap + batteryIndicator.implicitWidth
            : 0)

    readonly property bool showRightClock:
        root.wantsRightClock
        && root.rightFitWidth >= root.rightAfterBatteryWidth
            + root.axiomFitGap + clockRightGroup.implicitWidth

    readonly property real rightEssentialWidth:
        root.rightAfterBatteryWidth
        + (root.showRightClock
            ? root.axiomFitGap + clockRightGroup.implicitWidth
            : 0)

    readonly property bool showRightResources:
        root.wantsRightResources
        && root.rightFitWidth >= root.rightEssentialWidth
            + root.axiomFitGap + resourcesRightGroup.implicitWidth

    readonly property real rightAfterResourcesWidth:
        root.rightEssentialWidth
        + (root.showRightResources
            ? root.axiomFitGap + resourcesRightGroup.implicitWidth
            : 0)

    readonly property bool showRightTray:
        root.wantsRightTray
        && root.rightFitWidth >= root.rightAfterResourcesWidth
            + root.axiomFitGap + sysTray.implicitWidth

    readonly property real rightAfterTrayWidth:
        root.rightAfterResourcesWidth
        + (root.showRightTray
            ? root.axiomFitGap + sysTray.implicitWidth
            : 0)

    readonly property real utilityActionsWidth:
        utilityActionsLoader.item?.implicitWidth ?? 0

    readonly property bool showRightUtilities:
        root.wantsRightUtilities
        && root.rightFitWidth >= root.rightAfterTrayWidth
            + root.axiomFitGap + root.utilityActionsWidth

    readonly property real rightAfterUtilitiesWidth:
        root.rightAfterTrayWidth
        + (root.showRightUtilities
            ? root.axiomFitGap + root.utilityActionsWidth
            : 0)

    readonly property real weatherWidth:
        weatherLoader.item?.implicitWidth ?? 0

    readonly property bool showRightWeather:
        root.wantsRightWeather
        && root.rightFitWidth >= root.rightAfterUtilitiesWidth
            + root.axiomFitGap + root.weatherWidth


    // ============================================================
    // Bar background shadow
    // ============================================================

    Loader {
        active:
            Config.options.bar.showBackground
            && Config.options.bar.cornerStyle === 1
            && Config.options.bar.floatStyleShadow
            && !false
            && !false

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

        // Functional zones are carved into it with crisp inset borders.
        color:
              (Config.options.bar.showBackground
                 ? Appearance.barVisual.attachedSurfaceFill
                 : "transparent")

        radius:
             Config.options.bar.cornerStyle === 1
                ? Appearance.radius.bar
                : 0

        border.width:
              (Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 ? 1 : 0)

        border.color:
             Appearance.colors.colLayer0Border

        Rectangle {
            visible: Config.options.bar.showBackground && Config.options.bar.cornerStyle !== 1
            color: Appearance.colors.colLayer0Border
            width: parent.width - (Config.options.bar.cornerStyle === 0
                ? Appearance.rounding.screenRounding * 2 : 0)
            x: Config.options.bar.cornerStyle === 0
                ? Appearance.rounding.screenRounding : 0
            height: 1
            anchors.top: Config.options.bar.bottom ? parent.top : undefined
            anchors.bottom: Config.options.bar.bottom ? undefined : parent.bottom
        }
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



    FocusedScrollMouseArea {
        id: barLeftSideMouseArea
        z: 1

        // nyvorel-phase3a-real-hit-plane: interact only with the
        // 40px persistent control plane, not transparent floating insets.
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left

            // nyvorel-phase3e: the hit plane and width budgets share one inset.
            leftMargin:
                Appearance.barLayout.edgeInset
        }

        width:
            Math.min(
                leftSectionRowLayout.implicitWidth,
                root.leftAvailableWidth
            )

        height:
            Appearance.barLayout.persistentHeight

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
                GlobalStates.toggleBarPopup("operations", root.screen?.name);
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
                 parent.height

            spacing:
                0


            LeftSidebarButton {
                id: leftSidebarButton

                Layout.alignment:
                    Qt.AlignVCenter

                Layout.leftMargin:
                      Appearance.rounding.screenRounding

                // icon is content, not another nested chip.
                colBackground:
                    barLeftSideMouseArea.hovered
                        ? Appearance.colors.colLayer1Hover
                        : ColorUtils.transparentize(
                            Appearance.colors.colLayer1Hover,
                            1
                        )
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            }


            ActiveWindow {
                Layout.leftMargin:
                    (Appearance.barLayout.axiomComponents ? Appearance.spacing.sm : 8)
                    + (
                        leftSidebarButton.visible
                            ? 0
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


    // Operations grows from the left navbar control and shares the joined
    // popup geometry used by the right control center.
    StyledPopup {
        id: operationsPopup
        hoverTarget: leftSidebarButton
        showOnHover: false
        forceActive: GlobalStates.isBarPopupOpen("operations", root.screen?.name)
        irisAnimation: true
        dismissOnOutsideClick: true
        popupRadius: Appearance.radius.bar
        contentMargin: 0
        onDismissRequested: GlobalStates.closeBarPopup("operations", root.screen?.name)
        SidebarLeftContent {}
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

        // Axiom / Fluid-native: workspace chrome is owned by the existing bar.
        // The active workspace remains visible, centered and interactive.
        quiet: Appearance.barLayout.axiomComponents

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
             workspacesWidget.widgetPadding


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


    // The control center grows from the right navbar control.
    StyledPopup {
        id: rightHubPopup
        popupRadius: Appearance.radius.bar
        contentMargin: 0
        hoverTarget: rightSidebarButton
        showOnHover: false
        forceActive: GlobalStates.isBarPopupOpen("controls", root.screen?.name)
        irisAnimation: true
        dismissOnOutsideClick: true
        onDismissRequested: GlobalStates.closeBarPopup("controls", root.screen?.name)
        SidebarRightContent {}
    }

    NetworkOperationsPopup {
        barScreenName: root.screen?.name
        hoverTarget: networkButton
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

        // Axiom / Fluid-native: no secondary opaque island around media.
        quiet: Appearance.barLayout.axiomComponents

        // Contextual media belongs to the persistent plane but should never
        // compete with navigation/system anchors for visual weight.

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
             root.mediaDesiredWidth > 0

        width:
             (visible ? root.mediaDesiredWidth : 0)

        height:
            implicitHeight

        opacity:
             1

        scale:
             1

        transformOrigin: Item.Right
        clip: true

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

    // previous collection of independently framed right-side pills.


    FocusedScrollMouseArea {
        id: barRightSideMouseArea
        z: 1

        // nyvorel-phase3a-real-hit-plane: mirror the left control plane.
        anchors {
            verticalCenter:
                parent.verticalCenter

            right:
                parent.right

            rightMargin:
                Appearance.barLayout.edgeInset
        }

        width:
            Math.min(
                rightSectionRowLayout.implicitWidth + root.axiomSideInset * 2,
                root.rightAvailableWidth
            )

        height:
            Appearance.barLayout.persistentHeight

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
                GlobalStates.toggleBarPopup("controls", root.screen?.name);
            }
        }


        // The Fluid shell's barBackground is the *only* navbar surface.
        // This zone contains Axiom controls, not a nested navbar panel.

        RowLayout {
            id: rightSectionRowLayout

            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.axiomSideInset
                rightMargin: root.axiomSideInset
                verticalCenter: parent.verticalCenter
            }

            height:
                 parent.height

            spacing:
                root.axiomFluidRight ? 6 : Appearance.barLayout.rightSectionGap

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
                    Appearance.barLayout.rightStatusInset

                Layout.fillWidth:
                    false

                implicitWidth:
                    indicatorsRowLayout.implicitWidth
                        + (root.axiomFluidRight ? 0 : 16)

                implicitHeight:
                    root.axiomFluidRight ? 24
                        : indicatorsRowLayout.implicitHeight + 8

                buttonRadius:
                    root.axiomFluidRight ? 5 : Appearance.rounding.full


                colBackground:
                    root.axiomFluidRight
                        ? "transparent"
                        : GlobalStates.isBarPopupOpen("controls", root.screen?.name)
                            ? Appearance.colors.colSecondaryContainer
                            : barRightSideMouseArea.hovered
                                ? Appearance.colors.colLayer1Hover
                                : ColorUtils.transparentize(
                                    Appearance.colors.colLayer1,
                                    0.30
                                )

                colBackgroundHover:
                    root.axiomFluidRight
                        ? "transparent"
                        : Appearance.colors.colLayer1Hover

                colRipple:
                    Appearance.colors.colLayer1Active

                colBackgroundToggled: Appearance.colors.colSecondaryContainer

                colBackgroundToggledHover:
                    root.axiomFluidRight
                        ? "transparent"
                        : Appearance.colors.colSecondaryContainerHover

                colRippleToggled:
                    Appearance.colors.colSecondaryContainerActive

                toggled:
                    GlobalStates.isBarPopupOpen("controls", root.screen?.name)


                property color colText:
                    toggled
                        ? Appearance.m3colors.m3onSecondaryContainer
                        : Appearance.colors.colOnLayer0


                Behavior on colText {
                    MotionColorAnim {
                        type: MotionColorAnim.FastEffects
                    }
                }


                // nyvorel-phase1b-ripple-click-contract
                onClicked: {
                    GlobalStates.toggleBarPopup("controls", root.screen?.name);
                }


                RowLayout {
                    id: indicatorsRowLayout

                    anchors.centerIn:
                        parent

                    property real realSpacing:
                        root.sharedNavbarContent ? 10 : Appearance.barLayout.statusIconGap

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
                                duration: Appearance.barMotion.statusDuration
                            }
                        }


                        MaterialSymbol {
                            text:
                                "volume_off"

                            iconSize:
                                root.sharedNavbarContent ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger

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
                                duration: Appearance.barMotion.statusDuration
                            }
                        }


                        MaterialSymbol {
                            text:
                                "mic_off"

                            iconSize:
                                root.sharedNavbarContent ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger

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
                            root.sharedNavbarContent
                            || Notifications.silent
                            || Notifications.unread > 0

                        Layout.fillHeight:
                            true

                        implicitHeight:
                            reveal
                                ? notificationUnreadCount.implicitHeight
                                : 0

                        implicitWidth:
                            reveal
                                ? notificationUnreadCount.implicitWidth
                                : 0

                        NotificationUnreadCount {
                            id: notificationUnreadCount
                        }
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
                            root.sharedNavbarContent ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger

                        color:
                            rightSidebarButton.colText
                    }
                }
            }


            // Wi-Fi is an independent control; the remaining status area opens Controls.
            Rectangle {
                visible: root.axiomFluidRight
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.barVisual.axiomDivider
            }

            RippleButton {
                id: networkButton
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                toggled: GlobalStates.isBarPopupOpen("network", root.screen?.name)
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: GlobalStates.toggleBarPopup("network", root.screen?.name)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: Network.materialSymbol
                    iconSize: root.sharedNavbarContent ? Appearance.barVisual.axiomIconSize : Appearance.font.pixelSize.larger
                    color: networkButton.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
                }
            }

            // Axiom / precision divider, visible only in Fluid.
            Rectangle {
                visible: root.axiomFluidRight && root.showRightBattery
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.barVisual.axiomDivider
            }

            // ====================================================
            // Battery
            // ====================================================

            BatteryIndicator {

                barScreenName: root.screen?.name
                id: batteryIndicator
                axiomMode: root.sharedNavbarContent

                visible:
                    root.showRightBattery

                Layout.alignment:
                    Qt.AlignVCenter
            }


            // Axiom / precision divider, visible only in Fluid.
            Rectangle {
                visible: root.axiomFluidRight && root.showRightTray && sysTray.implicitWidth > 0
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.barVisual.axiomDivider
            }

            // ====================================================
            // System tray
            // ====================================================

            SysTray {

                barScreenName: root.screen?.name
                id: sysTray
                axiomMode: root.sharedNavbarContent

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

                        quiet:
                            Appearance.barLayout.axiomComponents

                        padding:
                             Appearance.fluidMode
                                ? 0
                                : Appearance.barLayout.axiomComponents ? 0 : 3

                        UtilButtons {}
                    }
            }


            // Axiom / precision divider, visible only in Fluid.
            Rectangle {
                visible: root.axiomFluidRight && root.showRightClock
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.barVisual.axiomDivider
            }

            // ====================================================
            // Clock
            // ====================================================

            BarGroup {
                id: clockRightGroup
                quiet: root.axiomFluidRight
                padding:
                    root.axiomFluidRight ? 0 : 5

                visible:
                    root.showRightClock

                width:
                    visible
                        ? implicitWidth
                        : 0

                ClockWidget {

                    barScreenName: root.screen?.name
                    axiomMode: root.sharedNavbarContent
                    showDate:
                        false

                    Layout.alignment:
                        Qt.AlignVCenter
                }
            }


            // Axiom / precision divider, visible only in Fluid.
            Rectangle {
                visible: root.axiomFluidRight && root.showRightResources
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 1
                implicitHeight: 20
                color: Appearance.barVisual.axiomDivider
            }

            // ====================================================
            // Resources
            //
            // System telemetry belongs to the system-state zone,
            // not to the navigation center.
            // ====================================================

            BarGroup {
                id: resourcesRightGroup
                quiet: root.axiomFluidRight

                visible:
                    root.showRightResources

                width:
                    visible
                        ? implicitWidth
                        : 0

                padding:
                    root.axiomFluidRight ? 0
                        : Appearance.barLayout.axiomComponents ? 4 : 5

                Resources {

                    barScreenName: root.screen?.name
                    axiomMode: root.sharedNavbarContent
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
                        padding:
                      5
                    WeatherBar {}
                    }
            }
        }
    }
}
