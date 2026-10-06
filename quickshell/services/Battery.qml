pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ============================================================
    // UPower state
    // ============================================================

    property bool available: UPower.displayDevice.isLaptopBattery
    property var chargeState: UPower.displayDevice.state

    property bool isCharging:
        chargeState === UPowerDeviceState.Charging

    // More reliable than deriving AC state only from Charging.
    // This also stays correct when plugged in at the charge limit.
    property bool isPluggedIn:
        !UPower.onBattery

    property real percentage:
        UPower.displayDevice?.percentage ?? 1

    readonly property bool allowAutomaticSuspend:
        Config.options.battery.automaticSuspend

    readonly property bool soundEnabled:
        Config.options.sounds.battery

    property bool isLow:
        available
        && percentage <= Config.options.battery.low / 100

    property bool isCritical:
        available
        && percentage <= Config.options.battery.critical / 100

    property bool isSuspending:
        available
        && percentage <= Config.options.battery.suspend / 100

    property bool isFull:
        available
        && percentage >= Config.options.battery.full / 100

    property bool isLowAndNotCharging:
        isLow && !isCharging

    property bool isCriticalAndNotCharging:
        isCritical && !isCharging

    property bool isSuspendingAndNotCharging:
        allowAutomaticSuspend
        && isSuspending
        && !isCharging

    property bool isFullAndCharging:
        isFull && isCharging

    property real energyRate:
        UPower.displayDevice.changeRate

    property real timeToEmpty:
        UPower.displayDevice.timeToEmpty

    property real timeToFull:
        UPower.displayDevice.timeToFull


    // ============================================================
    // Battery health
    // ============================================================

    property real health: (function() {
        const devList = UPower.devices.values;

        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];

            if (dev.isLaptopBattery && dev.healthSupported) {
                const health = dev.healthPercentage;

                if (health === 0)
                    return 0.01;

                if (health < 1)
                    return health * 100;

                return health;
            }
        }

        return 0;
    })()


    // ============================================================
    // Power-management UI state
    // ============================================================

    property bool batteryAware: true

    function fileInt(file, fallbackValue) {
        const raw = file.text().trim();
        const value = Number(raw);

        return Number.isFinite(value)
            ? Math.round(value)
            : fallbackValue;
    }

    readonly property int currentChargeLimit:
        fileInt(currentChargeLimitFile, 100)

    readonly property int persistentChargeLimit:
        fileInt(persistentChargeLimitFile, 100)

    readonly property bool chargeProtectionEnabled:
        persistentChargeLimit < 100

    readonly property int cycleCount:
        fileInt(cycleCountFile, 0)

    readonly property string platformProfile: {
        const value = platformProfileFile.text().trim();
        return value.length > 0 ? value : "unknown";
    }

    readonly property string energyPreference: {
        const value = eppFile.text().trim();
        return value.length > 0 ? value : "unknown";
    }


    // ============================================================
    // Sysfs / persistent files
    // ============================================================

    FileView {
        id: currentChargeLimitFile

        path:
            "/sys/class/power_supply/BAT0/"
            + "charge_control_end_threshold"

        printErrors: false
        watchChanges: true

        onFileChanged:
            reload()
    }

    FileView {
        id: persistentChargeLimitFile

        path: "/etc/nyvorel-battery-threshold"

        printErrors: false
        watchChanges: true

        onFileChanged:
            reload()
    }

    FileView {
        id: cycleCountFile

        path:
            "/sys/class/power_supply/BAT0/cycle_count"

        printErrors: false
        watchChanges: true

        onFileChanged:
            reload()
    }

    FileView {
        id: platformProfileFile

        path:
            "/sys/firmware/acpi/platform_profile"

        printErrors: false
        watchChanges: true

        onFileChanged:
            reload()
    }

    FileView {
        id: eppFile

        path:
            "/sys/devices/system/cpu/cpu0/cpufreq/"
            + "energy_performance_preference"

        printErrors: false
        watchChanges: true

        onFileChanged:
            reload()
    }


    // ============================================================
    // Battery-aware state
    // ============================================================

    Process {
        id: batteryAwareQuery

        command: [
            "powerprofilesctl",
            "query-battery-aware"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const value =
                    this.text.trim().toLowerCase();

                root.batteryAware =
                    value.indexOf("true") !== -1;
            }
        }
    }

    Timer {
        id: batteryAwareRefreshTimer

        interval: 500
        repeat: false

        onTriggered:
            root.refreshBatteryAware()
    }

    Timer {
        id: thresholdRefreshTimer

        interval: 700
        repeat: false

        onTriggered:
            root.refreshLocalPowerState()
    }


    // ============================================================
    // Public power functions used by the UI
    // ============================================================

    function refreshBatteryAware() {
        if (!batteryAwareQuery.running)
            batteryAwareQuery.running = true;
    }

    function refreshLocalPowerState() {
        currentChargeLimitFile.reload();
        persistentChargeLimitFile.reload();
        cycleCountFile.reload();
        platformProfileFile.reload();
        eppFile.reload();
    }

    function refreshPowerSettings() {
        refreshBatteryAware();
        refreshLocalPowerState();
    }

    function setBatteryAware(enabled) {
        root.batteryAware = enabled;

        Quickshell.execDetached([
            "powerprofilesctl",
            "configure-battery-aware",
            enabled ? "--enable" : "--disable"
        ]);

        batteryAwareRefreshTimer.restart();
    }

    function setChargeLimit(limit) {
        const allowed = [60, 70, 80, 90, 100];

        if (allowed.indexOf(limit) === -1)
            return;

        Quickshell.execDetached([
            "sudo",
            "-n",
            "/usr/local/bin/nyvorel-battery-threshold",
            "set",
            String(limit)
        ]);

        thresholdRefreshTimer.restart();
    }

    function chargeToFullOnce() {
        Quickshell.execDetached([
            "sudo",
            "-n",
            "/usr/local/bin/nyvorel-battery-threshold",
            "once"
        ]);

        thresholdRefreshTimer.restart();
    }


    // ============================================================
    // Existing battery notifications
    // ============================================================

    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging)
            return;

        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Low battery"),
            Translation.tr(
                "Consider plugging in your device"
            ),
            "-u",
            "critical",
            "-a",
            "Shell",
            "--hint=int:transient:1"
        ]);

        if (root.soundEnabled)
            Audio.playSystemSound("dialog-warning");
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging)
            return;

        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Critically low battery"),
            Translation.tr(
                "Please charge!\n"
                + "Automatic suspend triggers at %1%"
            ).arg(Config.options.battery.suspend),
            "-u",
            "critical",
            "-a",
            "Shell",
            "--hint=int:transient:1"
        ]);

        if (root.soundEnabled)
            Audio.playSystemSound("suspend-error");
    }

    onIsSuspendingAndNotChargingChanged: {
        if (
            root.available
            && isSuspendingAndNotCharging
        ) {
            Quickshell.execDetached([
                "bash",
                "-c",
                "systemctl suspend || loginctl suspend"
            ]);
        }
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging)
            return;

        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Battery full"),
            Translation.tr(
                "Please unplug the charger"
            ),
            "-a",
            "Shell",
            "--hint=int:transient:1"
        ]);

        if (root.soundEnabled)
            Audio.playSystemSound("complete");
    }

    onIsPluggedInChanged: {
        if (!root.available || !root.soundEnabled)
            return;

        if (isPluggedIn)
            Audio.playSystemSound("power-plug");
        else
            Audio.playSystemSound("power-unplug");

        // Refresh EPP/platform values after PPD reacts
        // to the AC state change.
        thresholdRefreshTimer.restart();
    }


    // ============================================================
    // Initial state
    // ============================================================

    Component.onCompleted:
        refreshPowerSettings()
}