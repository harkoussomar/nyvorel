pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs.modules.common
import qs.modules.common.functions

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import QtQuick

/**
 * For managing brightness of monitors.
 * Supports both brightnessctl and ddcutil.
 */
Singleton {
    id: root


    // =========================================================
    // Signals
    // =========================================================

    signal brightnessChanged()

    // Fired when the user tries to go beyond 0% or 100%.
    signal brightnessLimitHit()


    // =========================================================
    // Limit feedback
    // =========================================================

    // Avoid several identical limit sounds from one rapid
    // key press / scroll sequence.
    property double lastBrightnessLimitSoundAt: 0

    property int brightnessLimitSoundCooldown: 250


    function hitBrightnessLimit(): void {
        const now = Date.now();


        if (
            now - root.lastBrightnessLimitSoundAt
            >= root.brightnessLimitSoundCooldown
        ) {
            root.lastBrightnessLimitSoundAt = now;


            Audio.playSystemSound(
                "bell"
            );
        }


        root.brightnessLimitHit();
    }


    // =========================================================
    // Monitor state
    // =========================================================

    property var ddcMonitors: []


    readonly property list<BrightnessMonitor> monitors:
        Quickshell.screens.map(
            (screen) =>
                monitorComp.createObject(
                    root,
                    {
                        "screen": screen
                    }
                )
        )


    function getMonitorForScreen(
        screen: ShellScreen
    ): var {
        return root.monitors.find(
            (monitor) =>
                monitor.screen === screen
        );
    }


    // =========================================================
    // Global brightness controls
    // =========================================================

    function increaseBrightness(): void {
        const focusedName =
            Hyprland.focusedMonitor?.name;


        if (!focusedName) {
            return;
        }


        const monitor =
            root.monitors.find(
                (candidate) =>
                    candidate.screen.name
                    === focusedName
            );


        if (!monitor) {
            return;
        }


        monitor.setBrightness(
            monitor.brightness + 0.05
        );
    }


    function decreaseBrightness(): void {
        const focusedName =
            Hyprland.focusedMonitor?.name;


        if (!focusedName) {
            return;
        }


        const monitor =
            root.monitors.find(
                (candidate) =>
                    candidate.screen.name
                    === focusedName
            );


        if (!monitor) {
            return;
        }


        monitor.setBrightness(
            monitor.brightness - 0.05
        );
    }


    reloadableId: "brightness"


    // =========================================================
    // Monitor discovery
    // =========================================================

    onMonitorsChanged: {
        root.ddcMonitors = [];

        ddcProc.running = true;
    }


    function initializeMonitor(
        index: int
    ): void {
        if (
            index >= root.monitors.length
        ) {
            return;
        }


        root.monitors[index]
            .initialize();
    }


    function ddcDetectFinished(): void {
        root.initializeMonitor(0);
    }


    Process {
        id: ddcProc


        command: [
            "ddcutil",
            "detect",
            "--brief"
        ]


        stdout:
            SplitParser {
                splitMarker: "\n\n"


                onRead: (data) => {
                    if (
                        !data.startsWith(
                            "Display "
                        )
                    ) {
                        return;
                    }


                    const lines =
                        data
                            .split("\n")
                            .map(
                                (line) =>
                                    line.trim()
                            );


                    const connectorLine =
                        lines.find(
                            (line) =>
                                line.startsWith(
                                    "DRM connector:"
                                )
                        );


                    const busLine =
                        lines.find(
                            (line) =>
                                line.startsWith(
                                    "I2C bus:"
                                )
                        );


                    if (
                        !connectorLine
                        || !busLine
                    ) {
                        return;
                    }


                    root.ddcMonitors.push({
                        "name":
                            connectorLine
                                .split("-")
                                .slice(1)
                                .join("-"),

                        "busNum":
                            busLine
                                .split(
                                    "/dev/i2c-"
                                )[1]
                    });
                }
            }


        onExited:
            root.ddcDetectFinished()
    }


    Process {
        id: setProc
    }


    // =========================================================
    // Individual brightness monitor
    // =========================================================

    component BrightnessMonitor: QtObject {
        id: monitor


        required property ShellScreen screen


        property bool isDdc

        property string busNum

        property int rawMaxBrightness: 100

        property real brightness

        property real brightnessMultiplier: 1.0


        property real multipliedBrightness:
            Math.max(
                0,
                Math.min(
                    1,

                    monitor.brightness
                    * (
                        Config
                            .options
                            .light
                            .antiFlashbang
                            .enable

                            ? monitor
                                .brightnessMultiplier

                            : 1
                    )
                )
            )


        property bool ready: false


        // DDC displays are intentionally not smoothly animated,
        // because they can be slow with repeated commands.
        property bool animateChanges:
            !monitor.isDdc


        // =====================================================
        // Value changes
        // =====================================================

        onBrightnessChanged: {
            if (!monitor.ready) {
                return;
            }


            root.brightnessChanged();
        }


        Behavior on multipliedBrightness {
            enabled:
                monitor.animateChanges


            NumberAnimation {
                duration: 200

                easing.type:
                    Easing.BezierSpline

                easing.bezierCurve:
                    Appearance
                        .animationCurves
                        .expressiveEffects
            }
        }


        onMultipliedBrightnessChanged: {
            if (!monitor.ready) {
                return;
            }


            if (
                monitor.animateChanges
            ) {
                monitor.syncBrightness();

            } else {
                setTimer.restart();
            }
        }


        // =====================================================
        // Initialization
        // =====================================================

        function initialize(): void {
            monitor.ready = false;


            const monitorIndex =
                root.monitors.indexOf(
                    monitor
                );


            const match =
                root.ddcMonitors.find(
                    (candidate) =>
                        candidate.name
                        === monitor.screen.name

                        && !root.monitors
                            .slice(
                                0,
                                monitorIndex
                            )
                            .some(
                                (previousMonitor) =>
                                    previousMonitor.busNum
                                    === candidate.busNum
                            )
                );


            monitor.isDdc =
                !!match;


            monitor.busNum =
                match?.busNum ?? "";


            initProc.command =
                monitor.isDdc

                    ? [
                        "ddcutil",
                        "-b",
                        monitor.busNum,
                        "getvcp",
                        "10",
                        "--brief"
                    ]

                    : [
                        "sh",
                        "-c",
                        `echo "a b c $(brightnessctl g) $(brightnessctl m)"`
                    ];


            initProc.running = true;
        }


        readonly property Process initProc:
            Process {
                stdout:
                    SplitParser {
                        onRead: (data) => {
                            const parts =
                                data.split(" ");


                            const current =
                                parts[3];


                            const max =
                                parts[4];


                            const parsedCurrent =
                                parseInt(current);


                            const parsedMax =
                                parseInt(max);


                            if (
                                isNaN(parsedCurrent)
                                || isNaN(parsedMax)
                                || parsedMax <= 0
                            ) {
                                return;
                            }


                            monitor.rawMaxBrightness =
                                parsedMax;


                            monitor.brightness =
                                Math.max(
                                    0,
                                    Math.min(
                                        1,
                                        parsedCurrent
                                        / parsedMax
                                    )
                                );


                            monitor.ready = true;
                        }
                    }


                onExited: (
                    exitCode,
                    exitStatus
                ) => {
                    root.initializeMonitor(
                        root.monitors
                            .indexOf(monitor)
                        + 1
                    );
                }
            }


        // =====================================================
        // DDC write delay
        // =====================================================

        property var setTimer:
            Timer {
                id: setTimer


                interval:
                    monitor.isDdc
                        ? 300
                        : 0


                repeat: false


                onTriggered: {
                    monitor.syncBrightness();
                }
            }


        // =====================================================
        // Hardware synchronization
        // =====================================================

        function syncBrightness(): void {
            if (!monitor.ready) {
                return;
            }


            const brightnessValue =
                Math.max(
                    0,
                    Math.min(
                        1,
                        monitor.multipliedBrightness
                    )
                );


            if (monitor.isDdc) {
                const rawValueRounded =
                    Math.max(
                        Math.floor(
                            brightnessValue
                            * monitor.rawMaxBrightness
                        ),
                        1
                    );


                setProc.exec([
                    "ddcutil",
                    "-b",
                    monitor.busNum,
                    "setvcp",
                    "10",
                    rawValueRounded
                ]);


            } else {
                const valuePercentNumber =
                    Math.floor(
                        brightnessValue * 100
                    );


                let valuePercent =
                    `${valuePercentNumber}%`;


                // Preserve the original behavior:
                // logical 0% is allowed for the OSD, but don't
                // make the internal laptop display fully black.
                if (
                    valuePercentNumber === 0
                ) {
                    valuePercent = "1";
                }


                setProc.exec([
                    "brightnessctl",
                    "--class",
                    "backlight",
                    "s",
                    valuePercent,
                    "--quiet"
                ]);
            }
        }


        // =====================================================
        // Public brightness setter
        // =====================================================

        function setBrightness(
            value: real
        ): void {
            if (
                isNaN(value)
                || value === undefined
                || value === null
            ) {
                return;
            }


            const current =
                monitor.brightness;


            const epsilon = 0.001;


            const atMaximum =
                current >= 1 - epsilon;


            const atMinimum =
                current <= epsilon;


            const tryingAboveMaximum =
                value > 1;


            const tryingBelowMinimum =
                value < 0;


            // -------------------------------------------------
            // 100% + increase
            // -------------------------------------------------

            if (
                atMaximum
                && tryingAboveMaximum
            ) {
                // Normalize any tiny floating-point drift.
                monitor.brightness = 1;


                root.hitBrightnessLimit();

                return;
            }


            // -------------------------------------------------
            // 0% + decrease
            // -------------------------------------------------

            if (
                atMinimum
                && tryingBelowMinimum
            ) {
                monitor.brightness = 0;


                root.hitBrightnessLimit();

                return;
            }


            // -------------------------------------------------
            // Normal brightness change
            // -------------------------------------------------

            monitor.brightness =
                Math.max(
                    0,
                    Math.min(
                        1,
                        value
                    )
                );
        }


        function setBrightnessMultiplier(
            value: real
        ): void {
            monitor.brightnessMultiplier =
                value;
        }
    }


    Component {
        id: monitorComp

        BrightnessMonitor {}
    }


    // =========================================================
    // Anti-flashbang
    // =========================================================

    property int workspaceAnimationDelay:
        500


    property int contentSwitchDelay:
        30


    property string screenshotDir:
        "/tmp/quickshell/brightness/antiflashbang"


    function brightnessMultiplierForLightness(
        x: real
    ): real {
        // Original fitted curve:
        //
        // 6.600135
        // + 216.360356 * e^(-0.0811129189x)
        //
        // Divide by 100 to normalize.

        return (
            6.600135

            + 216.360356

            * Math.pow(
                Math.E,
                -0.0811129189 * x
            )
        ) / 100.0;
    }


    Variants {
        model:
            Quickshell.screens


        Scope {
            id: screenScope


            required property var modelData


            property string screenName:
                screenScope.modelData.name


            property string screenshotPath:
                `${root.screenshotDir}/screenshot-${screenScope.screenName}.png`


            Connections {
                enabled:
                    Config
                        .options
                        .light
                        .antiFlashbang
                        .enable

                    && Appearance
                        .m3colors
                        .darkmode


                target:
                    Hyprland


                function onRawEvent(
                    event
                ) {
                    if (
                        [
                            "activewindowv2",
                            "windowtitlev2"
                        ].includes(
                            event.name
                        )
                    ) {
                        screenshotTimer.interval =
                            root.contentSwitchDelay;


                        screenshotTimer.restart();


                    } else if (
                        [
                            "workspacev2"
                        ].includes(
                            event.name
                        )
                    ) {
                        screenshotTimer.interval =
                            root.workspaceAnimationDelay;


                        screenshotTimer.restart();
                    }
                }
            }


            Timer {
                id: screenshotTimer


                interval: 700

                repeat: false


                onTriggered: {
                    screenshotProc.running =
                        false;


                    screenshotProc.running =
                        true;
                }
            }


            Process {
                id: screenshotProc


                command: [
                    "bash",
                    "-c",

                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`
                    + ` && grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]


                stdout:
                    StdioCollector {
                        id: lightnessCollector


                        onStreamFinished: {
                            Quickshell.execDetached([
                                "rm",
                                screenScope.screenshotPath
                            ]);


                            const lightness =
                                lightnessCollector.text;


                            const newMultiplier =
                                root
                                    .brightnessMultiplierForLightness(
                                        parseFloat(
                                            lightness
                                        )
                                    );


                            const monitor =
                                root.getMonitorForScreen(
                                    screenScope.modelData
                                );


                            if (monitor) {
                                monitor
                                    .setBrightnessMultiplier(
                                        newMultiplier
                                    );
                            }
                        }
                    }
            }
        }
    }


    // =========================================================
    // IPC
    // =========================================================

    IpcHandler {
        target: "brightness"


        function increment(): void {
            root.increaseBrightness();
        }


        function decrement(): void {
            root.decreaseBrightness();
        }
    }


    // =========================================================
    // Global shortcuts
    // =========================================================

    GlobalShortcut {
        name:
            "brightnessIncrease"


        description:
            "Increase brightness"


        onPressed: {
            root.increaseBrightness();
        }
    }


    GlobalShortcut {
        name:
            "brightnessDecrease"


        description:
            "Decrease brightness"


        onPressed: {
            root.decreaseBrightness();
        }
    }
}