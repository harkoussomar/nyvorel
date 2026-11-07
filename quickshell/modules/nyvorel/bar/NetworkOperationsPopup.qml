import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.services.network

StyledPopup {
    id: root
    property string barScreenName: ""
    showOnHover: false
    forceActive: GlobalStates.isBarPopupOpen("network", root.barScreenName)
    dismissOnOutsideClick: true
    irisAnimation: true
    popupRadius: Appearance.radius.bar
    contentMargin: 0
    onDismissRequested: GlobalStates.closeBarPopup("network", root.barScreenName)

    readonly property real screenWidth: root.QsWindow?.window?.screen?.width ?? 1280
    readonly property real screenHeight: root.QsWindow?.window?.screen?.height ?? 900
    readonly property real panelWidth: Math.max(300, Math.min(1128, screenWidth - (Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth + 32 : 32)))
    readonly property real panelHeight: Math.max(300, Math.min(696, screenHeight - (Config.options.bar.vertical ? 32 : Appearance.sizes.barHeight + 32)))
    readonly property color surface: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.62)
    readonly property color inset: ColorUtils.mix(Appearance.barVisual.attachedSurfaceFill, Appearance.colors.colLayer1, 0.82)
    readonly property color stroke: Appearance.colors.colLayer0Border
    readonly property color muted: Appearance.colors.colSubtext
    readonly property color textColor: Appearance.colors.colOnLayer0
    readonly property color accent: Appearance.colors.colPrimary
    readonly property color success: "#9acaad"
    readonly property color railShade: Qt.rgba(0, 0, 0, 0.17)

    component Kicker: StyledText {
        font.pixelSize: 9
        font.weight: Font.DemiBold
        font.letterSpacing: 1.15
        color: root.muted
    }
    component CardSurface: Rectangle {
        radius: 13
        color: root.surface
        border.width: 1
        border.color: root.stroke
    }
    component InnerSurface: Rectangle {
        radius: 10
        color: root.inset
        border.width: 1
        border.color: root.stroke
    }
    component AtlasAction: RippleButton {
        property string label: ""
        property string symbol: ""
        property bool accentFill: false
        implicitHeight: 32
        implicitWidth: Math.max(32, actionContent.implicitWidth + 20)
        buttonRadius: 8
        colBackground: accentFill ? root.accent : root.inset
        colBackgroundHover: accentFill ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
        colBackgroundToggled: colBackground
        colRipple: Appearance.colors.colLayer1Active
        RowLayout {
            id: actionContent
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol { text: parent.parent.symbol; iconSize: 15; color: parent.parent.accentFill ? Appearance.colors.colOnPrimary : root.textColor }
            StyledText { text: parent.parent.label; font.pixelSize: 11; font.weight: Font.DemiBold; color: parent.parent.accentFill ? Appearance.colors.colOnPrimary : root.textColor }
        }
    }
    component MetricCard: CardSurface {
        property string caption: ""
        property string value: "—"
        property string detail: ""
        property string symbol: ""
        implicitHeight: 116
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 5
            Kicker { text: parent.parent.caption.toUpperCase() }
            StyledText { text: parent.parent.value; font.pixelSize: 24; font.weight: Font.DemiBold; color: root.textColor; elide: Text.ElideRight; Layout.fillWidth: true }
            StyledText { text: parent.parent.detail; font.pixelSize: 11; color: root.muted; elide: Text.ElideRight; Layout.fillWidth: true }
        }
    }
    component DetailRow: InnerSurface {
        property string title: ""
        property string subtitle: ""
        property string symbol: ""
        property string status: ""
        property bool positive: false
        implicitHeight: 58
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 11
            MaterialSymbol { text: parent.parent.symbol; iconSize: 18; color: root.accent }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText { text: parent.parent.parent.title; font.pixelSize: 11; font.weight: Font.DemiBold; color: root.textColor; elide: Text.ElideRight; Layout.fillWidth: true }
                StyledText { text: parent.parent.parent.subtitle; font.pixelSize: 10; color: root.muted; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            StyledText { text: parent.parent.status; font.pixelSize: 10; color: parent.parent.positive ? Appearance.colors.colPrimary : root.muted }
        }
    }
    component SectionHeading: RowLayout {
        property string title: ""
        property string note: ""
        Layout.fillWidth: true
        StyledText { text: parent.title; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.textColor }
        Item { Layout.fillWidth: true }
        StyledText { text: parent.note; font.pixelSize: 10; color: root.muted }
    }
    Item {
        id: panel
        implicitWidth: root.panelWidth
        implicitHeight: root.panelHeight
        readonly property bool compact: root.panelWidth < 760
        property int tab: 0
        onTabChanged: viewport.contentItem.contentY = 0
        property var speedResult: ({})
        property string speedError: ""
        property bool speedLicenseRequired: false
        property string speedPhase: "idle"
        property real speedProgress: 0
        property real speedLiveMbps: 0
        property real speedLatency: 0
        property real speedDownload: 0
        property var speedSamples: []
        property bool speedCancelled: false
        readonly property bool speedBusy: speedProcess.running
        readonly property string speedPhaseLabel: speedLicenseRequired ? "Terms required" : speedPhase === "latency" ? "Measuring latency" : speedPhase === "download" ? "Measuring download" : speedPhase === "upload" ? "Measuring upload" : speedPhase === "done" ? "Test complete" : "Ready to test"
        readonly property var snapshotData: NetworkOperations.snapshot
        readonly property var activeConnection: snapshotData.active || ({})
        readonly property var dns: snapshotData.dns || ({})
        readonly property real signalDbm: parseFloat(snapshotData.wifi?.signal || "")
        readonly property real signalQuality: isNaN(signalDbm) ? 0 : Math.max(0, Math.min(100, Math.round((signalDbm + 90) * 100 / 55)))
        readonly property int checkedCount: NetworkOperations.checks.length
        readonly property int passingCount: NetworkOperations.checks.filter(c => c.passed).length
        readonly property var tabs: [
            {name:"Wi-Fi",icon:"wifi",path:"WIFI"},
            {name:"Interfaces",icon:"layers",path:"INTERFACES"},
            {name:"Network Doctor",icon:"healing",path:"DOCTOR"},
            {name:"DNS",icon:"dns",path:"DNS"},
            {name:"Security",icon:"shield",path:"SECURITY"}
        ]
        Component.onCompleted: {
            NetworkOperations.active = true
            NetworkOperations.runDoctor()
            if (Network.wifiEnabled) Network.rescanWifi()
        }
        Component.onDestruction: NetworkOperations.active = false
        function textOr(value, fallback) { return value && String(value).length ? String(value) : fallback }
        function list(value) { return value && value.length ? value.join(" · ") : "—" }
        function bytes(value) {
            const n = Number(value || 0)
            if (n >= 1073741824) return (n / 1073741824).toFixed(2) + " GB"
            if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
            if (n >= 1024) return (n / 1024).toFixed(1) + " KB"
            return Math.round(n) + " B"
        }
        function rate(value) { return bytes(value) + "/s" }
        function runSpeedTest(acceptTerms) {
            if (speedBusy) return
            speedError = ""
            speedLicenseRequired = false
            speedResult = ({})
            speedPhase = "latency"
            speedProgress = 0
            speedLiveMbps = 0
            speedLatency = 0
            speedDownload = 0
            speedSamples = []
            speedCancelled = false
            const command = [Quickshell.shellPath("scripts/system/nyvorel-speed-test")]
            if (acceptTerms) command.push("--accept-terms")
            speedProcess.exec(command)
        }
        function cancelSpeedTest() {
            if (!speedBusy) return
            speedCancelled = true
            speedProcess.running = false
            speedPhase = "idle"
            speedError = "Test cancelled"
        }
        Process {
            id: speedProcess
            stdout: SplitParser {
                onRead: line => {
                    if (panel.speedCancelled) return
                    try {
                        const event = JSON.parse(line)
                        if (event.kind === "phase") {
                            if (panel.speedPhase !== event.phase) panel.speedSamples = []
                            panel.speedPhase = event.phase
                            panel.speedProgress = event.progress || 0
                            panel.speedLiveMbps = event.mbps || 0
                        } else if (event.kind === "sample") {
                            panel.speedPhase = event.phase
                            panel.speedProgress = event.progress || 0
                            panel.speedLiveMbps = event.mbps || 0
                            panel.speedSamples = panel.speedSamples.slice(-39).concat([panel.speedLiveMbps])
                        } else if (event.kind === "latency") {
                            panel.speedLatency = event.latency_ms || 0
                        } else if (event.kind === "phase_result" && event.phase === "download") {
                            panel.speedDownload = event.mbps || 0
                        } else if (event.kind === "result") {
                            panel.speedResult = event
                            panel.speedPhase = "done"
                            panel.speedProgress = 1
                            panel.speedLiveMbps = event.download_mbps || 0
                            panel.speedSamples = []
                        } else if (event.kind === "error") {
                            panel.speedError = event.message || "Speed test failed"
                            panel.speedPhase = "idle"
                        } else if (event.kind === "license_required") {
                            panel.speedLicenseRequired = true
                            panel.speedPhase = "idle"
                        }
                    } catch (e) {
                        panel.speedError = "Speed test returned invalid progress data"
                    }
                }
            }
            onExited: (exitCode, exitStatus) => {
                if (exitCode !== 0 && !panel.speedError && !panel.speedCancelled && !panel.speedLicenseRequired)
                    panel.speedError = "Speed test could not start"
            }
        }
        function checkContains(name) {
            for (const c of NetworkOperations.checks) if (c.name.indexOf(name) >= 0) return c
            return null
        }
        function wifiChannel() {
            const f = Number(snapshotData.wifi?.frequency || 0)
            if (!f) return "—"
            if (f >= 5000) return String(Math.round((f - 5000) / 5))
            if (f >= 2412) return String(Math.round((f - 2407) / 5))
            return "—"
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                id: rail
                Layout.preferredWidth: panel.compact ? 58 : 183
                Layout.minimumWidth: panel.compact ? 58 : 183
                Layout.maximumWidth: panel.compact ? 58 : 183
                Layout.fillHeight: true
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Config.options.bar.vertical || Config.options.bar.bottom
                            ? root.railShade : "transparent"
                    }
                    GradientStop { position: 0.14; color: root.railShade }
                    GradientStop { position: 0.86; color: root.railShade }
                    GradientStop {
                        position: 1
                        color: !Config.options.bar.vertical && Config.options.bar.bottom
                            ? "transparent" : root.railShade
                    }
                }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: panel.compact ? 8 : 12
                    anchors.rightMargin: panel.compact ? 8 : 12
                    anchors.topMargin: 18
                    anchors.bottomMargin: 15
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 16
                        spacing: 9
                        Rectangle {
                            implicitWidth: 35; implicitHeight: 35; radius: 9
                            color: ColorUtils.transparentize(root.accent, 0.87)
                            border.width: 1
                            border.color: ColorUtils.transparentize(root.accent, 0.72)
                            MaterialSymbol { anchors.centerIn: parent; text: "hub"; iconSize: 19; color: root.accent }
                        }
                        ColumnLayout {
                            visible: !panel.compact
                            spacing: 1
                            StyledText { text: "Network Atlas"; font.pixelSize: 13; font.weight: Font.DemiBold; color: root.textColor }
                            StyledText { text: "Operations center"; font.pixelSize: 10; color: root.muted }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.stroke; Layout.bottomMargin: 18 }
                    Kicker { visible: !panel.compact; text: "WORKSPACE"; Layout.leftMargin: 10; Layout.bottomMargin: 8 }
                    Repeater {
                        model: panel.tabs
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            implicitHeight: 40
                            radius: 9
                            color: panel.tab === index ? ColorUtils.transparentize(root.accent, 0.88) : "transparent"
                            border.width: panel.tab === index ? 1 : 0
                            border.color: ColorUtils.transparentize(root.accent, 0.72)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: panel.compact ? 0 : 11
                                spacing: 10
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.leftMargin: panel.compact ? 8 : 0
                                    Layout.preferredWidth: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.icon; iconSize: 17
                                    color: panel.tab === index ? root.accent : root.muted
                                }
                                StyledText {
                                    visible: !panel.compact
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    text: modelData.name
                                    font.pixelSize: 11
                                    color: panel.tab === index ? root.textColor : root.muted
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.tab = index }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    CardSurface {
                        visible: !panel.compact
                        Layout.fillWidth: true
                        implicitHeight: 104
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 11; spacing: 5
                            StyledText {
                                text: panel.checkedCount ? (panel.passingCount === panel.checkedCount ? "● Network healthy" : "● Needs attention") : "● Checking network"
                                font.pixelSize: 11
                            color: panel.checkedCount && panel.passingCount === panel.checkedCount ? root.success : root.accent
                            }
                            StyledText { text: panel.checkedCount ? panel.passingCount + "/" + panel.checkedCount + " checks" : panel.textOr(panel.snapshotData.connectivity, "Waiting"); font.pixelSize: 13; font.weight: Font.DemiBold; color: root.textColor }
                            StyledText { text: panel.textOr(panel.activeConnection.name, "No active connection"); font.pixelSize: 10; color: root.muted; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                    AtlasAction { visible: panel.compact; Layout.fillWidth: true; symbol: "wifi"; onClicked: panel.tab = 0 }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: panel.compact ? 13 : 22
                Layout.rightMargin: panel.compact ? 13 : 21
                Layout.topMargin: 18
                Layout.bottomMargin: 12
                spacing: 11
                Controls.ScrollView {
                    id: viewport
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: panel.tab === 0 ? wifiPage.implicitHeight
                                 : panel.tab === 1 ? interfacesPage.implicitHeight
                                 : panel.tab === 2 ? doctorPage.implicitHeight
                                 : panel.tab === 3 ? dnsPage.implicitHeight
                                 : securityPage.implicitHeight
                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                    ColumnLayout {
                        id: wifiPage
                        width: viewport.availableWidth; spacing: 12; visible: panel.tab === 0
                        CardSurface {
                            Layout.fillWidth: true
                            implicitHeight: panel.compact ? 160 : 126
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 16; spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 12
                                    MaterialSymbol { text: Network.materialSymbol; iconSize: 25; color: root.accent }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        StyledText { text: Network.active?.ssid || (Network.wifiEnabled ? "Choose a Wi-Fi network" : "Wi-Fi is off"); font.pixelSize: 18; font.weight: Font.DemiBold; color: root.textColor; elide: Text.ElideRight; Layout.fillWidth: true }
                                        StyledText { text: Network.active ? "Connected · " + Network.active.strength + "% signal" : (Network.wifiEnabled ? "Nearby networks are listed below" : "Turn on Wi-Fi to discover networks"); font.pixelSize: 11; color: root.muted }
                                    }
                                    AtlasAction { label: Network.wifiEnabled ? "Turn off" : "Turn on"; symbol: Network.wifiEnabled ? "wifi_off" : "wifi"; onClicked: Network.toggleWifi() }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    AtlasAction { label: Network.wifiScanning ? "Scanning…" : "Scan again"; symbol: "refresh"; enabled: Network.wifiEnabled && !Network.wifiScanning; onClicked: Network.rescanWifi() }
                                    AtlasAction { visible: !!Network.active; label: "Disconnect"; symbol: "link_off"; onClicked: Network.disconnectWifiNetwork(panel.activeConnection.kind === "802-11-wireless" ? panel.activeConnection.device : "") }
                                    Item { Layout.fillWidth: true }
                                    StyledText { text: Network.wifiEnabled ? Network.friendlyWifiNetworks.length + " nearby" : "Radio off"; font.pixelSize: 10; color: root.muted }
                                }
                            }
                        }
                        CardSurface {
                            Layout.fillWidth: true
                            implicitHeight: (panel.compact ? 239 : 213) + (panel.speedLicenseRequired ? (panel.compact ? 110 : 90) : panel.speedPhase === "done" ? 18 : 0)
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 15; spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    MaterialSymbol { text: "speed"; iconSize: 19; color: root.accent }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 2
                                        StyledText { text: "Internet speed test"; font.pixelSize: 13; font.weight: Font.DemiBold; color: root.textColor }
                                        StyledText { text: "Ookla · nearby server · multiple connections"; font.pixelSize: 10; color: root.muted; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                    AtlasAction { label: panel.speedBusy ? "Cancel" : (panel.speedResult.kind === "result" ? "Run again" : "Start test"); symbol: panel.speedBusy ? "close" : "play_arrow"; accentFill: !panel.speedBusy; enabled: panel.speedBusy || Network.ethernet || Network.wifiStatus === "connected" || Network.wifiStatus === "limited"; onClicked: panel.speedBusy ? panel.cancelSpeedTest() : panel.runSpeedTest() }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 18
                                    Item {
                                        Layout.preferredWidth: panel.compact ? 96 : 116
                                        Layout.preferredHeight: panel.compact ? 96 : 116
                                        Canvas {
                                            anchors.fill: parent
                                            property real sweep: panel.speedProgress
                                            onSweepChanged: requestPaint()
                                            onWidthChanged: requestPaint()
                                            onHeightChanged: requestPaint()
                                            Behavior on sweep { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            onPaint: {
                                                const c = getContext("2d"); c.reset()
                                                const center = width / 2, radius = width / 2 - 8
                                                const start = Math.PI * 0.75, end = Math.PI * 2.25
                                                c.lineCap = "round"; c.lineWidth = 7
                                                c.strokeStyle = root.stroke
                                                c.beginPath(); c.arc(center, center, radius, start, end); c.stroke()
                                                if (sweep > 0) {
                                                    c.strokeStyle = panel.speedPhase === "upload" ? Appearance.colors.colSecondary : root.accent
                                                    c.beginPath(); c.arc(center, center, radius, start, start + (end - start) * Math.min(1, sweep)); c.stroke()
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            anchors.centerIn: parent; spacing: 0
                                            StyledText { text: panel.speedPhase === "idle" ? "—" : panel.speedPhase === "latency" ? "···" : panel.speedLiveMbps.toFixed(1); font.pixelSize: panel.compact ? 19 : 25; font.weight: Font.DemiBold; color: root.textColor; Layout.alignment: Qt.AlignHCenter }
                                            Kicker { text: panel.speedPhase === "upload" ? "UPLOAD" : panel.speedPhase === "download" ? "DOWNLOAD" : "MBPS"; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter }
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
                                        RowLayout { Layout.fillWidth: true
                                            StyledText { text: panel.speedPhaseLabel; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.textColor }
                                            Item { Layout.fillWidth: true }
                                            StyledText { text: panel.speedBusy ? Math.round(panel.speedProgress * 100) + "%" : ""; font.pixelSize: 10; color: root.muted }
                                        }
                                        Canvas {
                                            visible: panel.speedPhase !== "done"
                                            Layout.fillWidth: true; Layout.preferredHeight: panel.compact ? 30 : 44
                                            property var points: panel.speedSamples
                                            onPointsChanged: requestPaint()
                                            onWidthChanged: requestPaint()
                                            onPaint: {
                                                const c = getContext("2d"); c.reset()
                                                c.strokeStyle = root.stroke; c.lineWidth = 1
                                                c.beginPath(); c.moveTo(0, height - 2); c.lineTo(width, height - 2); c.stroke()
                                                if (points.length < 2) return
                                                const maximum = Math.max(1, ...points)
                                                c.strokeStyle = panel.speedPhase === "upload" ? Appearance.colors.colSecondary : root.accent
                                                c.lineWidth = 2; c.lineJoin = "round"
                                                c.beginPath()
                                                points.forEach((value, index) => {
                                                    const x = index * width / Math.max(1, points.length - 1)
                                                    const y = height - 3 - value / maximum * (height - 7)
                                                    if (index === 0) c.moveTo(x, y); else c.lineTo(x, y)
                                                })
                                                c.stroke()
                                            }
                                        }
                                        RowLayout { visible: !panel.compact && panel.speedPhase !== "done"; Layout.fillWidth: true; spacing: 16
                                            StyledText { text: "↓ " + (panel.speedResult.kind === "result" ? panel.speedResult.download_mbps : panel.speedDownload || (panel.speedPhase === "download" ? panel.speedLiveMbps.toFixed(1) : "—")) + " Mbps"; font.pixelSize: 11; color: root.textColor }
                                            StyledText { text: "↑ " + (panel.speedResult.kind === "result" ? panel.speedResult.upload_mbps : panel.speedPhase === "upload" ? panel.speedLiveMbps.toFixed(1) : "—") + " Mbps"; font.pixelSize: 11; color: root.textColor }
                                            StyledText { text: (panel.speedLatency || "—") + " ms"; font.pixelSize: 11; color: root.muted }
                                        }
                                        ColumnLayout { visible: panel.compact && panel.speedPhase !== "done"; Layout.fillWidth: true; spacing: 2
                                            StyledText { text: "↓ " + (panel.speedResult.kind === "result" ? panel.speedResult.download_mbps : panel.speedDownload || (panel.speedPhase === "download" ? panel.speedLiveMbps.toFixed(1) : "—")) + " Mbps"; font.pixelSize: 10; color: root.textColor }
                                            StyledText { text: "↑ " + (panel.speedResult.kind === "result" ? panel.speedResult.upload_mbps : panel.speedPhase === "upload" ? panel.speedLiveMbps.toFixed(1) : "—") + " Mbps · " + (panel.speedLatency || "—") + " ms"; font.pixelSize: 10; color: root.muted }
                                        }
                                        GridLayout {
                                            visible: panel.speedPhase === "done"
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            columns: panel.compact ? 1 : 3
                                            columnSpacing: 22; rowSpacing: 6
                                            ColumnLayout { spacing: 2
                                                Kicker { text: "DOWNLOAD" }
                                                StyledText { text: panel.speedResult.download_mbps + " Mbps"; font.pixelSize: panel.compact ? 13 : 20; font.weight: Font.DemiBold; color: root.accent }
                                            }
                                            ColumnLayout { spacing: 2
                                                Kicker { text: "UPLOAD" }
                                                StyledText { text: panel.speedResult.upload_mbps + " Mbps"; font.pixelSize: panel.compact ? 13 : 20; font.weight: Font.DemiBold; color: root.textColor }
                                            }
                                            ColumnLayout { spacing: 2
                                                Kicker { text: "LATENCY" }
                                                StyledText { text: panel.speedResult.latency_ms + " ms"; font.pixelSize: panel.compact ? 13 : 20; font.weight: Font.DemiBold; color: root.textColor }
                                            }
                                        }
                                    }
                                }
                                StyledText { visible: !!panel.speedError; text: panel.speedError; font.pixelSize: 10; color: Appearance.colors.colError; Layout.fillWidth: true; elide: Text.ElideRight }
                                StyledText { visible: panel.speedPhase === "done"; text: "Server: " + (panel.speedResult.server || "Nearby Speedtest server"); font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                                StyledText { visible: panel.speedLicenseRequired; text: "Ookla requires acceptance of its personal-use terms and privacy notice before the first test."; font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                StyledText { visible: panel.speedLicenseRequired; text: '<a href="https://www.speedtest.net/about/eula">License</a> · <a href="https://www.speedtest.net/about/terms">Terms</a> · <a href="https://www.speedtest.net/about/privacy">Privacy</a>'; textFormat: Text.RichText; font.pixelSize: 10; color: root.accent; Layout.fillWidth: true; onLinkActivated: link => Qt.openUrlExternally(link) }
                                AtlasAction { visible: panel.speedLicenseRequired; label: "Accept & run"; symbol: "check"; accentFill: true; onClicked: panel.runSpeedTest(true) }
                            }
                        }
                        SectionHeading { title: "Nearby networks"; note: Network.wifiScanning ? "SCANNING" : Network.friendlyWifiNetworks.length + " FOUND" }
                        StyledText { visible: !Network.wifiEnabled; text: "Turn on Wi-Fi to see available networks."; font.pixelSize: 11; color: root.muted }
                        StyledText { visible: Network.wifiEnabled && !Network.wifiScanning && Network.friendlyWifiNetworks.length === 0; text: "No networks found. Try scanning again."; font.pixelSize: 11; color: root.muted }
                        Repeater {
                            model: ScriptModel { values: Network.friendlyWifiNetworks }
                            delegate: InnerSurface {
                                required property WifiAccessPoint modelData
                                readonly property WifiAccessPoint accessPoint: modelData
                                Layout.fillWidth: true
                                implicitHeight: accessPoint.askingPassword ? 145 : 62
                                color: accessPoint.active ? ColorUtils.mix(root.inset, root.accent, 0.91) : root.inset
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 11; spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 10
                                        MaterialSymbol { text: accessPoint.strength > 75 ? "signal_wifi_4_bar" : accessPoint.strength > 45 ? "network_wifi_3_bar" : "network_wifi_1_bar"; iconSize: 20; color: root.accent }
                                        ColumnLayout { Layout.fillWidth: true; spacing: 2
                                            StyledText { text: accessPoint.ssid || "Hidden network"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.textColor; elide: Text.ElideRight; Layout.fillWidth: true; textFormat: Text.PlainText }
                                            StyledText { text: (accessPoint.isSecure ? "Secured" : "Open") + " · " + accessPoint.strength + "% signal"; font.pixelSize: 10; color: root.muted }
                                        }
                                        MaterialSymbol { visible: accessPoint.isSecure; text: "lock"; iconSize: 14; color: root.muted }
                                        AtlasAction { label: accessPoint.active ? "Connected" : (Network.wifiConnectTarget === accessPoint ? "Connecting…" : "Connect"); symbol: accessPoint.active ? "check" : "arrow_forward"; enabled: !accessPoint.active && !Network.wifiConnecting; onClicked: Network.connectToWifiNetwork(accessPoint) }
                                    }
                                    RowLayout { visible: accessPoint.askingPassword; Layout.fillWidth: true; spacing: 8
                                        MaterialTextField { id: wifiPassword; Layout.fillWidth: true; echoMode: TextInput.Password; inputMethodHints: Qt.ImhSensitiveData; placeholderText: "Wi-Fi password"; onAccepted: { Network.changePassword(accessPoint, text); text = "" } }
                                        AtlasAction { label: "Cancel"; symbol: "close"; onClicked: { accessPoint.askingPassword = false; wifiPassword.text = "" } }
                                        AtlasAction { label: "Join"; symbol: "check"; accentFill: true; enabled: wifiPassword.text.length > 0; onClicked: { Network.changePassword(accessPoint, wifiPassword.text); wifiPassword.text = "" } }
                                    }
                                }
                            }
                        }
                        StyledText { visible: !!Network.wifiError; text: Network.wifiError; font.pixelSize: 10; color: Appearance.colors.colError; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                    ColumnLayout {
                        id: interfacesPage
                        width: viewport.availableWidth; spacing: 12; visible: panel.tab === 1
                        CardSurface { Layout.fillWidth: true; implicitHeight: 52 + (panel.snapshotData.interfaces?.length || 0) * 66
                            ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 8
                                SectionHeading { title: "Detected interfaces"; note: (panel.snapshotData.interfaces?.length || 0) + " adapters" }
                                Repeater { model: panel.snapshotData.interfaces || []
                                    delegate: DetailRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        title: modelData.name + " · " + modelData.kind
                                        subtitle: modelData.driver ? "Kernel driver · " + modelData.driver : "Virtual or private network interface"
                                        symbol: modelData.kind === "Wi-Fi" ? "wifi" : modelData.kind === "Ethernet" ? "lan" : "device_hub"
                                        status: String(modelData.state).toUpperCase()
                                        positive: modelData.state === "up"
                                    }
                                }
                            }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 12
                            MetricCard { Layout.fillWidth: true; caption: "Wi-Fi driver"; value: panel.snapshotData.interfaces?.find(i => i.name === panel.activeConnection.device)?.driver || "—"; detail: panel.textOr(panel.activeConnection.device, "No Wi-Fi device") }
                            MetricCard { Layout.fillWidth: true; caption: "Link details"; value: panel.textOr(panel.snapshotData.wifi?.bitrate, "—"); detail: "BSSID " + panel.textOr(panel.snapshotData.wifi?.bssid, "—") + " · Ch " + panel.wifiChannel() }
                        }
                    }
                    ColumnLayout {
                        id: doctorPage
                        width: viewport.availableWidth; spacing: 12; visible: panel.tab === 2
                        CardSurface { Layout.fillWidth: true; implicitHeight: Math.max(152, 67 + Math.max(3, NetworkOperations.checks.length) * 66)
                            ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 9
                                RowLayout { Layout.fillWidth: true
                                    SectionHeading { title: "Guided diagnostics"; note: "" }
                                    AtlasAction { label: NetworkOperations.doctorBusy ? "Checking…" : "Run health check"; symbol: "play_arrow"; accentFill: true; enabled: !NetworkOperations.doctorBusy; onClicked: NetworkOperations.runDoctor() }
                                }
                                Repeater { model: NetworkOperations.checks
                                    delegate: DetailRow { required property var modelData; Layout.fillWidth: true; title: modelData.name; subtitle: panel.textOr(modelData.detail, "No detail reported"); symbol: modelData.passed ? "check_circle" : "warning"; status: modelData.passed ? "PASS" : "CHECK"; positive: modelData.passed }
                                }
                                StyledText { visible: NetworkOperations.checks.length === 0; text: "The adapter, gateway, link DNS, system DNS, and Internet are checked separately."; font.pixelSize: 11; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 12
                            MetricCard { Layout.fillWidth: true; caption: "Wi-Fi hardware"; value: panel.snapshotData.interfaces?.find(i => i.name === panel.activeConnection.device)?.driver || "—"; detail: "Active kernel driver" }
                            MetricCard { Layout.fillWidth: true; caption: "Recovery"; value: "Guided"; detail: "Use the Wi-Fi page for connection actions" }
                        }
                        AtlasAction { label: "Manage Wi-Fi"; symbol: "wifi"; onClicked: panel.tab = 0 }
                    }
                    ColumnLayout {
                        id: dnsPage
                        width: viewport.availableWidth; spacing: 12; visible: panel.tab === 3
                        CardSurface { Layout.fillWidth: true; implicitHeight: panel.dns.override_active ? 116 : 98
                            ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 5
                                SectionHeading { title: "DNS configuration"; note: panel.textOr(panel.activeConnection.name, "No active profile") }
                                StyledText { text: "Configured provider: " + panel.textOr(panel.dns.provider, "—"); font.pixelSize: 12; font.weight: Font.DemiBold; color: root.textColor }
                                StyledText { text: "Wi-Fi DNS: " + panel.list(panel.dns.link_servers); font.pixelSize: 11; color: root.muted }
                                StyledText { text: "Effective resolver: " + panel.textOr(panel.dns.route_interface, "—") + " · " + panel.list(panel.dns.effective_servers); font.pixelSize: 11; color: root.muted }
                                StyledText { visible: panel.dns.override_active === true; text: "A VPN or Tailscale catch-all DNS route overrides default queries."; font.pixelSize: 10; color: root.accent }
                            }
                        }
                        CardSurface { Layout.fillWidth: true; implicitHeight: panel.compact ? 382 : 244
                            ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 10
                                SectionHeading { title: "Provider for this connection"; note: "NETWORKMANAGER PROFILE" }
                                GridLayout { Layout.fillWidth: true; columns: panel.compact ? 1 : 2; columnSpacing: 9; rowSpacing: 9
                                    Repeater { model: [
                                        {name:"Automatic",key:"automatic",detail:"Network-supplied DNS"},
                                        {name:"Cloudflare",key:"cloudflare",detail:"1.1.1.1 · 1.0.0.1"},
                                        {name:"Google",key:"google",detail:"8.8.8.8 · 8.8.4.4"},
                                        {name:"Quad9",key:"quad9",detail:"9.9.9.9 · 149.112.112.112"},
                                        {name:"AdGuard DNS",key:"adguard",detail:"94.140.14.14 · 94.140.15.15"}
                                    ]
                                        delegate: InnerSurface { required property var modelData; Layout.fillWidth: true; implicitHeight: 56; border.width: panel.dns.provider === modelData.name ? 2 : 1; border.color: panel.dns.provider === modelData.name ? root.accent : root.stroke; opacity: NetworkOperations.operationBusy ? 0.6 : 1
                                            ColumnLayout { anchors.fill: parent; anchors.margins: 9; spacing: 2
                                                StyledText { text: modelData.name; font.pixelSize: 11; font.weight: Font.DemiBold; color: root.textColor }
                                                StyledText { text: modelData.detail; font.pixelSize: 9; color: root.muted }
                                            }
                                            MouseArea { anchors.fill: parent; enabled: !NetworkOperations.operationBusy; cursorShape: Qt.PointingHandCursor; onClicked: NetworkOperations.setDns(modelData.key, "", "") }
                                        }
                                    }
                                }
                            }
                        }
                        CardSurface { Layout.fillWidth: true; implicitHeight: 124
                            ColumnLayout { anchors.fill: parent; anchors.margins: 15; spacing: 9
                                SectionHeading { title: "Custom DNS"; note: "IPv4 OR IPv6" }
                                RowLayout { Layout.fillWidth: true; spacing: 8
                                    Controls.TextField { id: customPrimary; Layout.fillWidth: true; placeholderText: "Primary address"; color: root.textColor; background: InnerSurface {} }
                                    Controls.TextField { id: customSecondary; Layout.fillWidth: true; placeholderText: "Secondary (optional)"; color: root.textColor; background: InnerSurface {} }
                                    AtlasAction { label: "Apply"; symbol: "check"; enabled: !NetworkOperations.operationBusy; onClicked: NetworkOperations.setDns("custom", customPrimary.text, customSecondary.text) }
                                }
                                RowLayout { Layout.fillWidth: true; spacing: 8
                                    AtlasAction { label: NetworkOperations.comparisonBusy ? "Testing…" : "Compare latency"; symbol: "speed"; enabled: !NetworkOperations.comparisonBusy; onClicked: NetworkOperations.compareDns() }
                                    AtlasAction { visible: panel.dns.rollback_available === true; label: "Rollback"; symbol: "undo"; enabled: !NetworkOperations.operationBusy; onClicked: NetworkOperations.rollbackDns() }
                                }
                            }
                        }
                        Repeater { model: NetworkOperations.comparison
                            delegate: DetailRow { required property var modelData; Layout.fillWidth: true; title: modelData.name + " · " + modelData.address; subtitle: modelData.ok ? "Direct DNS query" : panel.textOr(modelData.error, "Unavailable"); symbol: "speed"; status: modelData.ok ? modelData.ms + " ms" : "UNAVAILABLE"; positive: modelData.ok }
                        }
                    }
                    ColumnLayout {
                        id: securityPage
                        width: viewport.availableWidth; spacing: 12; visible: panel.tab === 4
                        CardSurface { Layout.fillWidth: true; implicitHeight: 52 + (panel.snapshotData.connections?.length || 0) * 66
                            ColumnLayout { anchors.fill: parent; anchors.margins: 16; spacing: 8
                                SectionHeading { title: "Privacy and exposure"; note: "INSPECTION ONLY" }
                                Repeater { model: panel.snapshotData.connections || []
                                    delegate: DetailRow { required property var modelData; Layout.fillWidth: true; title: modelData.name; subtitle: modelData.device + " · " + modelData.kind; symbol: modelData.kind === "802-11-wireless" ? "wifi" : "route"; status: modelData.default ? "DEFAULT" : "ACTIVE"; positive: modelData.default }
                                }
                            }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 12
                            MetricCard { Layout.fillWidth: true; caption: "System DNS route"; value: panel.textOr(panel.dns.route_interface, "—"); detail: panel.dns.override_active ? "Catch-all VPN override" : "Physical connection" }
                            MetricCard { Layout.fillWidth: true; caption: "Resolver addresses"; value: (panel.dns.effective_servers || [])[0] || "—"; detail: "systemd-resolved link" }
                        }
                        AtlasAction { label: "Inspect DNS settings"; symbol: "dns"; onClicked: panel.tab = 3 }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; implicitHeight: 20; spacing: 7
                    MaterialSymbol { text: NetworkOperations.error.length ? "warning" : "info"; iconSize: 13; color: NetworkOperations.error.length ? Appearance.colors.colError : root.accent }
                    StyledText { text: NetworkOperations.error || NetworkOperations.message || (panel.dns.override_active ? "Wi-Fi DNS and Tailscale DNS are shown separately" : "Live NetworkManager data"); font.pixelSize: 10; color: root.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    StyledText { text: panel.textOr(panel.activeConnection.device, "—"); font.pixelSize: 10; color: root.muted }
                    Item {
                        implicitWidth: 24
                        implicitHeight: 20
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 16
                            color: refreshHit.containsMouse ? root.textColor : root.muted
                        }
                        MouseArea {
                            id: refreshHit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NetworkOperations.refresh()
                        }
                    }
                }
            }
        }
    }
}
