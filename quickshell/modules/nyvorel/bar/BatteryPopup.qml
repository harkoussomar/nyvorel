import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

StyledPopup {
    id: root

    popupColor:
        Appearance.colors.colLayer0

    popupRadius:
        Appearance.radius.popup

    dismissOnOutsideClick:
        true

    onDismissRequested:
        root.closeRequested()


    signal closeRequested()

    // Responsive bounds for small monitors, fractional scaling and
    // larger accessibility fonts. Content scrolls only when necessary.
    readonly property real screenWidth:
        root.QsWindow
        && root.QsWindow.window
        && root.QsWindow.window.screen
            ? root.QsWindow.window.screen.width
            : 480

    readonly property real screenHeight:
        root.QsWindow
        && root.QsWindow.window
        && root.QsWindow.window.screen
            ? root.QsWindow.window.screen.height
            : 900

    readonly property real preferredContentWidth:
        Math.max(300, Math.min(420, root.screenWidth - 56))

    readonly property real maximumContentHeight:
        Math.max(340, root.screenHeight - Appearance.sizes.barHeight - 64)

    readonly property real sectionGap: 10
    readonly property real compactGap: 6
    readonly property real cardPadding: 12

    // ============================================================
    // Helpers
    // ============================================================

    function formatTime(seconds) {
        if (seconds <= 0)
            return "";

        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        if (hours > 0)
            return `${hours}h ${minutes}m`;

        return `${minutes}m`;
    }

    function statusText() {
        if (Battery.isCharging)
            return Translation.tr("Charging");

        if (Battery.isPluggedIn)
            return Translation.tr("Plugged in");

        return Translation.tr("On battery");
    }

    function remainingText() {
        const seconds =
            Battery.isCharging
                ? Battery.timeToFull
                : Battery.timeToEmpty;

        if (seconds <= 0)
            return "";

        if (Battery.isCharging)
            return Translation.tr("%1 until full")
                .arg(formatTime(seconds));

        return Translation.tr("%1 remaining")
            .arg(formatTime(seconds));
    }


    function finiteNumber(value) {
        const numeric = Number(value);
        return isFinite(numeric) ? numeric : NaN;
    }

    function healthText() {
        const value = finiteNumber(Battery.health);
        return isFinite(value) && value >= 0
            ? `${value.toFixed(0)}%`
            : "—";
    }

    function cycleText() {
        const value = finiteNumber(Battery.cycleCount);
        return isFinite(value) && value >= 0
            ? `${Math.round(value)}`
            : "—";
    }

    function powerText() {
        const value = finiteNumber(Battery.energyRate);
        return isFinite(value) && value >= 0
            ? `${value.toFixed(1)} W`
            : "—";
    }


    // ============================================================
    // Reusable pieces
    // ============================================================

    component SectionLabel: StyledText {
        font {
            pixelSize: Appearance.font.pixelSize.smaller
            weight: Font.DemiBold
        }

        color: Appearance.colors.colOnSurfaceVariant
        opacity: 0.58
    }


    component Card: Rectangle {
        Layout.fillWidth: true

        radius: Appearance.radius.card

        color: Appearance.colors.colLayer1

        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }


    component ToggleSwitch: Rectangle {
        id: toggle

        property bool checked: false
        property string accessibleName: ""

        opacity: enabled ? 1 : 0.42

        signal toggled(bool checked)

        activeFocusOnTab: enabled
        Accessible.role: Accessible.Switch
        Accessible.name: toggle.accessibleName
        Accessible.checkable: true
        Accessible.checked: toggle.checked
        Accessible.focusable: true
        Accessible.focused: toggle.activeFocus
        Accessible.onPressAction:
            toggle.toggled(!toggle.checked)

        Keys.onPressed: event => {
            if (
                event.key === Qt.Key_Space
                || event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter
            ) {
                toggle.toggled(!toggle.checked)
                event.accepted = true
            }
        }

        implicitWidth: 44
        implicitHeight: 25

        Layout.minimumWidth: 44
        Layout.maximumWidth: 44

        radius: height / 2

        color:
            checked
                ? Appearance.colors.colPrimary
                : Qt.rgba(
                    Appearance.colors.colOnSurfaceVariant.r,
                    Appearance.colors.colOnSurfaceVariant.g,
                    Appearance.colors.colOnSurfaceVariant.b,
                    0.08
                )

        border.width: 1

        border.color:
            checked
                ? Appearance.colors.colPrimary
                : Appearance.colors.colLayer0Border

        Rectangle {
            width: 17
            height: 17

            radius: width / 2

            anchors.verticalCenter: parent.verticalCenter

            x:
                toggle.checked
                    ? parent.width - width - 4
                    : 4

            color:
                toggle.checked
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnSurfaceVariant

            Behavior on x {
                MotionAnim {
                    type: MotionAnim.DefaultEffects
                }
            }
        }

        MouseArea {
            anchors.fill: parent

            cursorShape: Qt.PointingHandCursor

            onClicked:
                toggle.toggled(!toggle.checked)
        }
    }


    component ModeButton: Rectangle {
        id: button

        required property string icon
        required property string label

        property bool selected: false
        property bool buttonEnabled: true

        signal clicked()

        activeFocusOnTab: button.buttonEnabled
        Accessible.role: Accessible.Button
        Accessible.name: button.label
        Accessible.focusable: button.buttonEnabled
        Accessible.focused: button.activeFocus
        Accessible.onPressAction: {
            if (button.buttonEnabled)
                button.clicked()
        }

        Keys.onPressed: event => {
            if (
                button.buttonEnabled
                && (
                    event.key === Qt.Key_Space
                    || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter
                )
            ) {
                button.clicked()
                event.accepted = true
            }
        }

        Layout.fillWidth: true
        Layout.minimumWidth: 0

        implicitHeight: 50

        radius: Appearance.radius.control

        color:
            selected
                ? Appearance.colors.colPrimary
                : "transparent"

        border.width: 1

        border.color:
            selected || button.activeFocus
                ? Appearance.colors.colPrimary
                : Appearance.colors.colLayer0Border

        opacity:
            buttonEnabled ? 1 : 0.4

        ColumnLayout {
            anchors.centerIn: parent

            spacing: 0

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter

                text: button.icon

                fill:
                    button.selected ? 1 : 0

                iconSize:
                    Appearance.font.pixelSize.normal

                color:
                    button.selected
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Math.max(0, button.width - 10)

                text: button.label
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight

                font {
                    pixelSize: Appearance.font.pixelSize.small

                    weight:
                        button.selected
                            ? Font.DemiBold
                            : Font.Normal
                }

                color:
                    button.selected
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent

            enabled: button.buttonEnabled

            cursorShape: Qt.PointingHandCursor

            onClicked:
                button.clicked()
        }
    }


    component LimitButton: Rectangle {
        id: button

        required property int limit

        property bool selected:
            Battery.persistentChargeLimit === limit

        property bool buttonEnabled: true

        signal clicked()

        enabled: button.buttonEnabled
        opacity: button.buttonEnabled ? 1 : 0.42
        activeFocusOnTab: button.buttonEnabled

        Accessible.role: Accessible.Button
        Accessible.name: Translation.tr("%1% charge limit").arg(button.limit)
        Accessible.focusable: button.buttonEnabled
        Accessible.focused: button.activeFocus
        Accessible.onPressAction: {
            if (button.buttonEnabled)
                button.clicked()
        }

        Keys.onPressed: event => {
            if (
                button.buttonEnabled
                && (
                    event.key === Qt.Key_Space
                    || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter
                )
            ) {
                button.clicked()
                event.accepted = true
            }
        }

        Layout.fillWidth: true
        Layout.minimumWidth: 0

        implicitHeight: 36

        radius: Appearance.radius.control

        color:
            selected
                ? Appearance.colors.colPrimary
                : "transparent"

        border.width: 1

        border.color:
            selected || button.activeFocus
                ? Appearance.colors.colPrimary
                : Appearance.colors.colLayer0Border

        StyledText {
            anchors.centerIn: parent

            text: `${button.limit}%`

            font {
                pixelSize: Appearance.font.pixelSize.small

                weight:
                    button.selected
                        ? Font.DemiBold
                        : Font.Normal
            }

            color:
                button.selected
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnSurfaceVariant
        }

        MouseArea {
            anchors.fill: parent

            cursorShape: Qt.PointingHandCursor

            onClicked:
                button.clicked()
        }
    }


    component StatTile: Rectangle {
        id: stat

        required property string value
        required property string label
        required property string icon

        Layout.fillWidth: true
        Layout.minimumWidth: 0

        implicitHeight: 62

        radius: Appearance.radius.card

        color: Appearance.colors.colLayer1

        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors.centerIn: parent

            spacing: 2

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 3

                MaterialSymbol {
                    text: stat.icon

                    iconSize:
                        Appearance.font.pixelSize.small

                    color:
                        Appearance.colors.colOnSurfaceVariant

                    opacity: 0.72
                }

                StyledText {
                    text: stat.value

                    font {
                        pixelSize: Appearance.font.pixelSize.normal
                        weight: Font.DemiBold
                    }

                    color:
                        Appearance.colors.colOnSurfaceVariant
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter

                text: stat.label

                font.pixelSize:
                    Appearance.font.pixelSize.smaller

                color:
                    Appearance.colors.colOnSurfaceVariant

                opacity: 0.56
            }
        }
    }


    // ============================================================
    // Main popup
    // ============================================================

    Controls.ScrollView {
        id: scrollView

        // StyledPopup adds an equal margin around content. Keep the
        // scroll view centered so that padding is symmetric on all edges.
        anchors.centerIn: parent

        implicitWidth: root.preferredContentWidth
        implicitHeight:
            Math.min(
                mainLayout.implicitHeight,
                root.maximumContentHeight
            )

        clip:
            mainLayout.implicitHeight
            > root.maximumContentHeight

        padding: 0
        contentWidth: availableWidth

        Controls.ScrollBar.horizontal.policy:
            Controls.ScrollBar.AlwaysOff

        Controls.ScrollBar.vertical.policy:
            mainLayout.implicitHeight
            > root.maximumContentHeight
                ? Controls.ScrollBar.AsNeeded
                : Controls.ScrollBar.AlwaysOff

        ColumnLayout {
            id: mainLayout

            width: scrollView.availableWidth
            implicitWidth: root.preferredContentWidth

            spacing: root.sectionGap


        // ========================================================
        // Header
        // ========================================================

        Item {
            Layout.fillWidth: true
            implicitHeight: 54

            RowLayout {
                anchors {
                    left: parent.left
                    right: closeButton.left
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }

                spacing: 10

                Rectangle {
                    implicitWidth: 46
                    implicitHeight: 46

                    radius: Appearance.radius.control

                    color: Qt.rgba(
                        Appearance.colors.colPrimary.r,
                        Appearance.colors.colPrimary.g,
                        Appearance.colors.colPrimary.b,
                        0.12
                    )

                    MaterialSymbol {
                        anchors.centerIn: parent

                        text:
                            Battery.isCharging
                                ? "battery_charging_full"
                                : "battery_android_full"

                        fill: 1

                        iconSize:
                            Appearance.font.pixelSize.larger

                        color:
                            Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    spacing: 1

                    StyledText {
                        text:
                            `${Math.round(
                                Battery.percentage * 100
                            )}%`

                        font {
                            pixelSize: Appearance.font.pixelSize.large
                            weight: Font.Bold
                        }

                        color:
                            Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        text: {
                            let text = root.statusText();

                            const remaining =
                                root.remainingText();

                            if (remaining !== "")
                                text += ` · ${remaining}`;

                            return text;
                        }

                        elide: Text.ElideRight
                        maximumLineCount: 1

                        font.pixelSize:
                            Appearance.font.pixelSize.small

                        color:
                            Appearance.colors.colOnSurfaceVariant

                        opacity: 0.66
                    }
                }
            }

            Rectangle {
                id: closeButton

                anchors {
                    right: parent.right
                    top: parent.top
                    topMargin: 2
                }

                implicitWidth: 34
                implicitHeight: 34

                radius: height / 2

                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Close battery settings")
                Accessible.focusable: true
                Accessible.focused: closeButton.activeFocus
                Accessible.onPressAction: root.closeRequested()

                Keys.onPressed: event => {
                    if (
                        event.key === Qt.Key_Space
                        || event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter
                    ) {
                        root.closeRequested()
                        event.accepted = true
                    }
                }

                color:
                    closeArea.containsMouse || closeButton.activeFocus
                        ? Appearance.colors.colPrimary
                        : Qt.rgba(
                            Appearance.colors.colOnSurfaceVariant.r,
                            Appearance.colors.colOnSurfaceVariant.g,
                            Appearance.colors.colOnSurfaceVariant.b,
                            0.07
                        )

                border.width: 1

                border.color:
                    closeArea.containsMouse
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border

                MaterialSymbol {
                    anchors.centerIn: parent

                    text: "close"

                    iconSize:
                        Appearance.font.pixelSize.normal

                    color:
                        closeArea.containsMouse
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSurfaceVariant
                }

                MouseArea {
                    id: closeArea

                    anchors.fill: parent

                    hoverEnabled: true

                    cursorShape: Qt.PointingHandCursor

                    onClicked:
                        root.closeRequested()
                }
            }
        }


        // ========================================================
        // Battery progress
        // ========================================================

        Rectangle {
            Layout.fillWidth: true

            implicitHeight: 8

            radius: height / 2

            color: Qt.rgba(
                Appearance.colors.colOnSurfaceVariant.r,
                Appearance.colors.colOnSurfaceVariant.g,
                Appearance.colors.colOnSurfaceVariant.b,
                0.08
            )

            Rectangle {
                width:
                    parent.width
                    * Math.max(
                        0,
                        Math.min(
                            1,
                            Battery.percentage
                        )
                    )

                height: parent.height

                radius: parent.radius

                color:
                    Battery.isLowAndNotCharging
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colPrimary

                Behavior on width {
                    MotionAnim {
                        type: MotionAnim.DefaultEffects
                    }
                }
            }
        }


        // ========================================================
        // Power mode
        // ========================================================

        StyledText {
            Layout.fillWidth: true
            visible: Battery.actionError.length > 0
            text: Battery.actionError
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.small
        }

        SectionLabel {
            text:
                Translation.tr("POWER MODE")
        }

        GridLayout {
            id: powerModeGrid

            Layout.fillWidth: true
            columns: mainLayout.width < 390 ? 2 : 3
            columnSpacing: root.compactGap
            rowSpacing: root.compactGap

            ModeButton {
                icon: "energy_savings_leaf"
                label: Translation.tr("Saver")

                selected:
                    PowerProfiles.profile
                    === PowerProfile.PowerSaver

                buttonEnabled: !Battery.actionRunning
                onClicked: Battery.setPowerProfile("power-saver")
            }

            ModeButton {
                icon: "airwave"
                label: Translation.tr("Balanced")

                selected:
                    PowerProfiles.profile
                    === PowerProfile.Balanced

                buttonEnabled: !Battery.actionRunning
                onClicked: Battery.setPowerProfile("balanced")
            }

            ModeButton {
                Layout.columnSpan:
                    powerModeGrid.columns === 2 ? 2 : 1

                icon: "local_fire_department"

                label:
                    Translation.tr("Performance")

                buttonEnabled:
                    PowerProfiles.hasPerformanceProfile && !Battery.actionRunning

                selected:
                    PowerProfiles.profile
                    === PowerProfile.Performance

                onClicked: Battery.setPowerProfile("performance")
            }
        }


        // ========================================================
        // Automatic tuning
        // ========================================================

        Card {
            implicitHeight:
                automaticContent.implicitHeight + 22

            RowLayout {
                id: automaticContent

                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter

                    leftMargin: root.cardPadding
                    rightMargin: root.cardPadding
                }

                spacing: 10

                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 36

                    Layout.minimumWidth: 36
                    Layout.maximumWidth: 36

                    radius: Appearance.radius.control

                    color: Qt.rgba(
                        Appearance.colors.colPrimary.r,
                        Appearance.colors.colPrimary.g,
                        Appearance.colors.colPrimary.b,
                        0.10
                    )

                    MaterialSymbol {
                        anchors.centerIn: parent

                        text: "auto_mode"

                        iconSize:
                            Appearance.font.pixelSize.normal

                        color:
                            Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        text:
                            Translation.tr(
                                "Automatic power tuning"
                            )

                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight

                        font.weight:
                            Font.DemiBold

                        color:
                            Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        text: {
                            if (!Battery.batteryAwareAvailable)
                                return Translation.tr("Automatic tuning unavailable");
                            if (!Battery.batteryAware)
                                return Translation.tr(
                                    "Dynamic tuning disabled"
                                );

                            if (Battery.isPluggedIn)
                                return Translation.tr(
                                    "AC · %1"
                                ).arg(
                                    Battery.energyPreference
                                );

                            return Translation.tr(
                                "Battery · %1"
                            ).arg(
                                Battery.energyPreference
                            );
                        }

                        elide: Text.ElideRight
                        maximumLineCount: 1

                        font.pixelSize:
                            Appearance.font.pixelSize.smaller

                        color:
                            Appearance.colors.colOnSurfaceVariant

                        opacity: 0.58
                    }
                }

                ToggleSwitch {
                    Layout.alignment:
                        Qt.AlignRight | Qt.AlignVCenter

                    accessibleName:
                        Translation.tr("Automatic power tuning")

                    enabled: Battery.batteryAwareAvailable && !Battery.actionRunning
                    checked:
                        Battery.batteryAware

                    onToggled:
                        checked =>
                            Battery.setBatteryAware(
                                checked
                            )
                }
            }
        }


        // ========================================================
        // Battery protection
        // ========================================================

        SectionLabel {
            Layout.topMargin: 2

            text:
                Translation.tr(
                    "BATTERY PROTECTION"
                )
        }

        Card {
            implicitHeight:
                protectionContent.implicitHeight + 22

            ColumnLayout {
                id: protectionContent

                anchors {
                    fill: parent
                    margins: root.cardPadding
                }

                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    spacing: 10

                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36

                        Layout.minimumWidth: 36
                        Layout.maximumWidth: 36

                        radius: Appearance.radius.control

                        color: Qt.rgba(
                            Appearance.colors.colPrimary.r,
                            Appearance.colors.colPrimary.g,
                            Appearance.colors.colPrimary.b,
                            0.10
                        )

                        MaterialSymbol {
                            anchors.centerIn: parent

                            text: "battery_saver"

                            iconSize:
                                Appearance.font.pixelSize.normal

                            color:
                                Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0

                            text:
                                Translation.tr(
                                    "Charge limit"
                                )

                            elide: Text.ElideRight

                            font.weight:
                                Font.DemiBold

                            color:
                                Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0

                            text: {
                                if (!Battery.chargeLimitAvailable)
                                    return Battery.chargeLimitMessage;
                                if (
                                    !Battery.chargeProtectionEnabled
                                ) {
                                    return Translation.tr(
                                        "Protection disabled"
                                    );
                                }

                                if (
                                    Battery.currentChargeLimit
                                    === 100
                                ) {
                                    return Translation.tr(
                                        "Until restart · then %1%"
                                    ).arg(
                                        Battery.persistentChargeLimit
                                    );
                                }

                                return Translation.tr(
                                    "Stops charging at %1%"
                                ).arg(
                                    Battery.persistentChargeLimit
                                );
                            }

                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 2

                            font.pixelSize:
                                Appearance.font.pixelSize.smaller

                            color:
                                Appearance.colors.colOnSurfaceVariant

                            opacity: 0.58
                        }
                    }

                    ToggleSwitch {
                        Layout.alignment:
                            Qt.AlignRight | Qt.AlignVCenter

                        accessibleName:
                            Translation.tr("Battery charge protection")

                        enabled: Battery.chargeLimitAvailable && !Battery.actionRunning
                        checked:
                            Battery.chargeProtectionEnabled

                        onToggled: checked => {
                            if (checked)
                                Battery.setChargeLimit(80);
                            else
                                Battery.setChargeLimit(100);
                        }
                    }
                }


                RowLayout {
                    Layout.fillWidth: true

                    spacing: root.compactGap

                    LimitButton {
                        limit: 60
                        buttonEnabled: Battery.chargeLimitAvailable && !Battery.actionRunning

                        onClicked:
                            Battery.setChargeLimit(60)
                    }

                    LimitButton {
                        limit: 70
                        buttonEnabled: Battery.chargeLimitAvailable && !Battery.actionRunning

                        onClicked:
                            Battery.setChargeLimit(70)
                    }

                    LimitButton {
                        limit: 80
                        buttonEnabled: Battery.chargeLimitAvailable && !Battery.actionRunning

                        onClicked:
                            Battery.setChargeLimit(80)
                    }

                    LimitButton {
                        limit: 90
                        buttonEnabled: Battery.chargeLimitAvailable && !Battery.actionRunning

                        onClicked:
                            Battery.setChargeLimit(90)
                    }
                }


                Rectangle {
                    Layout.fillWidth: true

                    implicitHeight: 38

                    radius:
                        Appearance.radius.control

                    enabled:
                        Battery.chargeProtectionEnabled && !Battery.actionRunning

                    opacity: enabled ? 1 : 0.42
                    activeFocusOnTab: enabled

                    Accessible.role: Accessible.Button
                    Accessible.name:
                        Battery.currentChargeLimit === 100
                        && Battery.chargeProtectionEnabled
                            ? Translation.tr("Full charge until restart")
                            : Translation.tr("Allow full charge until restart")
                    Accessible.focusable: enabled
                    Accessible.focused: activeFocus
                    Accessible.onPressAction: {
                        if (enabled)
                            Battery.chargeToFullOnce()
                    }

                    Keys.onPressed: event => {
                        if (
                            enabled
                            && (
                                event.key === Qt.Key_Space
                                || event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter
                            )
                        ) {
                            Battery.chargeToFullOnce()
                            event.accepted = true
                        }
                    }

                    color:
                        fullChargeArea.containsMouse || activeFocus
                            ? Qt.rgba(
                                Appearance.colors.colPrimary.r,
                                Appearance.colors.colPrimary.g,
                                Appearance.colors.colPrimary.b,
                                0.10
                            )
                            : "transparent"

                    border.width: 1
                    border.color:
                        Appearance.colors.colLayer0Border

                    RowLayout {
                        anchors.centerIn: parent

                        spacing: 6

                        MaterialSymbol {
                            text:
                                "battery_full"

                            iconSize:
                                Appearance.font.pixelSize.normal

                            color:
                                Appearance.colors.colPrimary
                        }

                        StyledText {
                            text:
                                Battery.currentChargeLimit === 100
                                && Battery.chargeProtectionEnabled
                                    ? Translation.tr(
                                        "Full charge until restart"
                                    )
                                    : Translation.tr(
                                        "Allow full charge until restart"
                                    )

                            font.weight:
                                Font.Medium

                            color:
                                Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    MouseArea {
                        id: fullChargeArea

                        anchors.fill: parent

                        hoverEnabled: true

                        cursorShape:
                            Qt.PointingHandCursor

                        onClicked:
                            Battery.chargeToFullOnce()
                    }
                }
            }
        }


        // ========================================================
        // Battery health
        // ========================================================

        SectionLabel {
            Layout.topMargin: 2

            text:
                Translation.tr(
                    "BATTERY HEALTH"
                )
        }

        RowLayout {
            Layout.fillWidth: true

            spacing: root.compactGap

            StatTile {
                icon: "favorite"

                value:
                    root.healthText()

                label:
                    Translation.tr("Health")
            }

            StatTile {
                icon: "cycle"

                value:
                    root.cycleText()

                label:
                    Translation.tr("Cycles")
            }

            StatTile {
                icon: "bolt"

                value:
                    root.powerText()

                label:
                    Translation.tr("Power")
            }
        }


        // ========================================================
        // Technical footer
        // ========================================================

        RowLayout {
            Layout.fillWidth: true

            spacing: root.compactGap

            MaterialSymbol {
                text: "tune"

                iconSize:
                    Appearance.font.pixelSize.small

                color:
                    Appearance.colors.colOnSurfaceVariant

                opacity: 0.48
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0

                text:
                    `ASUS ${Battery.platformProfile}`
                    + `  ·  Intel ${Battery.energyPreference}`

                elide: Text.ElideRight
                maximumLineCount: 1

                font.pixelSize:
                    Appearance.font.pixelSize.smaller

                color:
                    Appearance.colors.colOnSurfaceVariant

                opacity: 0.48
            }

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28

                Layout.minimumWidth: 28
                Layout.maximumWidth: 28

                radius: height / 2

                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Refresh power settings")
                Accessible.focusable: true
                Accessible.focused: activeFocus
                Accessible.onPressAction:
                    Battery.refreshPowerSettings()

                Keys.onPressed: event => {
                    if (
                        event.key === Qt.Key_Space
                        || event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter
                    ) {
                        Battery.refreshPowerSettings()
                        event.accepted = true
                    }
                }

                color:
                    refreshArea.containsMouse || activeFocus
                        ? Qt.rgba(
                            Appearance.colors.colOnSurfaceVariant.r,
                            Appearance.colors.colOnSurfaceVariant.g,
                            Appearance.colors.colOnSurfaceVariant.b,
                            0.08
                        )
                        : "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent

                    text: "refresh"

                    iconSize:
                        Appearance.font.pixelSize.small

                    color:
                        Appearance.colors.colOnSurfaceVariant
                }

                MouseArea {
                    id: refreshArea

                    anchors.fill: parent

                    hoverEnabled: true

                    cursorShape:
                        Qt.PointingHandCursor

                    onClicked:
                        Battery.refreshPowerSettings()
                }
            }
        }
        }
    }
}
