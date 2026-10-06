import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    signal closeRequested()

    property string helperPath: Quickshell.shellPath("scripts/arch-remote/control_center.py")
    property string screenName: ""
    property int selectedPage: 0
    property int activePage: 0
    property int previousPage: 0
    property bool pageShown: true
    property real pageShift: 0
    property int pageDirection: 1
    property bool pageTransitioning: false
    property bool modalShown: false

    // phase4e-consolidated-surface-deformation-v1
    // phase4d-large-surface-deformation-v1
    // prism-v2-phase7: final Prism modals use spatial lift + uniform scale.
    // Preserve the older non-uniform deformation path for other styles only.
    readonly property bool largeSurfaceDeformationEnabled:
        Appearance.surfaceDeformation.enabled
        && !Appearance.prismMode

    property real largeSurfaceScaleX: 1
    property real largeSurfaceScaleY: 1
    property real largeSurfaceRadiusScale: 1

    function resetLargeSurfaceDeformation() {
        largeSurfaceDeformAnimation.stop()
        root.largeSurfaceScaleX = 1
        root.largeSurfaceScaleY = 1
        root.largeSurfaceRadiusScale = 1
    }

    function kickLargeSurfaceDeformation() {
        largeSurfaceDeformAnimation.stop()

        if (!root.largeSurfaceDeformationEnabled) {
            root.resetLargeSurfaceDeformation()
            return
        }

        root.largeSurfaceScaleX = Appearance.surfaceDeformation.largeStartX
        root.largeSurfaceScaleY = Appearance.surfaceDeformation.largeStartY
        root.largeSurfaceRadiusScale = Appearance.surfaceDeformation.largeRadiusStart
        largeSurfaceDeformAnimation.restart()
    }

    onLargeSurfaceDeformationEnabledChanged: {
        if (!root.largeSurfaceDeformationEnabled)
            root.resetLargeSurfaceDeformation()
    }

    property bool loading: false
    readonly property int expectedSchemaVersion: 2
    readonly property string expectedUiContract: "2.4.1"
    readonly property int expectedReferenceSchemaVersion: 1
    property string contractError: ""

    property bool actionRunning: false
    property string operationId: ""
    property string operationHandledId: ""
    property var backendOperation: ({id:"",active:false,status:"idle",phase:"idle",label:"",kind:"",args:[],service:"",action:"",source:"",pid:0,started_at:0,updated_at:0,finished_at:0,message:"",result_state:""})
    property bool cachedStateLoaded: false
    property bool logsLoading: false
    property bool lockConfirmOpen: false
    property string toastMessage: ""
    property bool toastError: false
    property string selectedLogService: "wayvnc"
    property string logSeverity: "all"
    property string logWindow: "1h"
    property string logSearch: ""
    property bool logFollow: false
    property bool logWrap: false
    property string logText: "Choose a service to inspect recent logs."
    property var logKnownIssues: []
    property int logEntryCount: 0
    property bool showPassedChecks: false
    property bool detailOpen: false
    property string detailType: ""
    property var detailItem: ({})
    property string serviceTransitionName: ""
    property string serviceTransitionAction: ""
    property string operationLabel: ""
    property string actionPhase: ""
    property string lastActionState: ""

    // Searchable Reference & Recovery knowledge layer.
    property bool referenceOpen: false
    property bool referenceLoading: false
    property string referenceQuery: ""
    property string referenceContext: ""
    property var referenceData: ({ok:false, schema_version:1, generated_at:0, snapshot_generation:0, dynamic:({}), sections:[]})
    property var referenceExpanded: ({"phone-essential":true, "recovery":true})

    // Private Share pairing is intentionally NOT part of remoteState.
    // The QR is a temporary credential-equivalent and remains in memory only.
    property string pairingState: "none"
    property string pairingQrSource: ""
    property double pairingExpiresAt: 0
    property bool pairingSingleUse: false
    property bool pairingBusy: false
    property bool pairingServerCancelSupported: false
    property bool pairingBackendRevoked: false
    property string pairingError: ""
    property string pairingOperation: ""
    readonly property int pairingRemainingSeconds: pairingState === "ready" && pairingExpiresAt > 0
        ? Math.max(0, Math.ceil(pairingExpiresAt - nowMs / 1000))
        : 0

    property double nowMs: Date.now()

    property var remoteState: ({
        schema_version: 2,
        ui_contract: "2.4.1",
        backend_revision: "",
        generation: 0,
        generated_at: 0,
        fast_checked_at: 0,
        slow_checked_at: 0,
        health: {status:"unknown", label:"Checking", title:"Checking remote access…", summary:"Collecting evidence…", critical_count:0,
                 warning_count:0, verified_count:0, passed_count:0, local_unverified_count:0,
                 external_unverified_count:0, unverified_count:0, issue_count:0, check_count:0},
        profile:"Unknown",
        host:{hostname:"",user:"",home:"",kernel:"",uptime:"",load:"",
              storage:{percent:0,free:"—",total:"—"}},
        services:{
            sshd:{name:"sshd",loaded:false,active:false,running:false,ready:false,healthy:false,readiness:"unknown",readiness_reason:"",active_state:"unknown",enabled_state:"unknown",enabled:false,boot_enabled:false,expected_state:"running",health:"unknown",pid:0,restarts:0,fragment_path:"",started_at:"",memory:"—",cpu_time:"—",reachable:false,reachability:"unknown",listeners:[],bind:"none",evidence_sources:[]},
            tailscaled:{name:"tailscaled",loaded:false,active:false,running:false,ready:false,healthy:false,readiness:"unknown",readiness_reason:"",active_state:"unknown",enabled_state:"unknown",enabled:false,boot_enabled:false,expected_state:"running",health:"unknown",pid:0,restarts:0,fragment_path:"",started_at:"",memory:"—",cpu_time:"—",reachable:false,reachability:"unknown",evidence_sources:[]},
            lan_share:{name:"lan-share",loaded:false,active:false,running:false,ready:false,healthy:false,readiness:"unknown",readiness_reason:"",active_state:"unknown",enabled_state:"unknown",enabled:false,boot_enabled:false,expected_state:"on-demand",health:"unknown",pid:0,restarts:0,fragment_path:"",started_at:"",memory:"—",cpu_time:"—",reachable:false,reachability:"unknown",listeners:[],bind:"none",evidence_sources:[]},
            wayvnc:{name:"wayvnc-remote",loaded:false,active:false,running:false,ready:false,transport_ready:false,auth_ready:false,auth_mode:"unverified",auth_username:"",auth_summary:"Authentication policy unverified",healthy:false,readiness:"unknown",readiness_reason:"",active_state:"unknown",enabled_state:"unknown",enabled:false,boot_enabled:false,expected_state:"on-demand",health:"unknown",pid:0,restarts:0,fragment_path:"",started_at:"",memory:"—",cpu_time:"—",reachable:false,reachability:"unknown",listeners:[],bind:"none",graphical_ready:false,evidence_sources:[]}
        },
        tailscale:{available:false,active:false,running:false,connected:false,backend_state:"unknown",hostname:"",dns_name:"",
                   ipv4:"",ipv6:"",magic_dns:false,devices:[],phone:null,health:"unknown",health_messages:[],
                   serve:{available:false,active:false,configured:false,url:"",host:"",route_path:"",upstream:"",upstream_tested:false,upstream_reachable:false,upstream_status:0,tailnet_only:false,is_public:false,verification:"unknown",health:"unknown",source:""},
                   funnel:{available:false,active:false,configured:false,is_public:false,url:"",verification:"unknown",health:"unknown",source:""}},
        listeners:[],
        exposure:{listeners:[],groups:{private_network:[],local_network:[],loopback_only:[],unexpected:[],other:[]},unexpected_count:0,application_public_exposure_detected:false,router_nat_verified:false,summary:"",router_note:""},
        security_checks:[],
        activity:[],
        ssh:{source:"",effective_verified:false,effective_error:"",verification_available:false,configured:{permit_root_login:"unknown",pubkey_authentication:"unknown",password_authentication:"unknown",kbd_interactive_authentication:"unknown",allow_users:""},effective:{permit_root_login:"unknown",pubkey_authentication:"unknown",password_authentication:"unknown",kbd_interactive_authentication:"unknown",allow_users:""},permit_root_login:"unknown",pubkey_authentication:"unknown",password_authentication:"unknown",kbd_interactive_authentication:"unknown",allow_users:"",key_only:false,root_disabled:false,secure:false},
        ssh_host_fingerprint:{available:false,algorithm:"",fingerprint:"",source:""},
        interfaces:[],
        wake:{ethernet:{interface_name:"",mac:"",supported:false,enabled:false,capability:"unknown",configured:"unknown",raw_supported:"",raw_current:"",tested:false,test_status:"untested",error:""},
              wifi:{interface_name:"",phy:"",mac:"",supported:false,enabled:false,capability:"unknown",configured:"unknown",persistent:false,tested:false,test_status:"untested",error:""}},
        linger:{enabled:false,value:"unknown",source:""},
        lid:{exists:false,path:"",battery:"unknown",external_power:"unknown",docked:"unknown",configured:{battery:"unknown",external_power:"unknown",docked:"unknown"},effective:{verified:false,battery:"unverified",external_power:"unverified",docked:"unverified",source:""},pending_reboot:false,status:"unknown",logind_started_at:""},
        graphical:{hyprland_available:false,wayland_display:"",wayland_sockets:[]},
        phone_guide:{host:"",user:"",ssh_command:"ssh arch-pc",ssh_config:"",commands:"",fingerprint:{available:false,fingerprint:""},device:null,readiness:{tailscale:{state:"unknown",confidence:"unverified"},ssh:{state:"unknown",confidence:"unverified",last_observed_at:0},sftp:{state:"unknown",confidence:"unverified"},avnc:{state:"unknown",confidence:"unverified"},share:{state:"unknown",confidence:"unverified"}},
                     sftp:{host:"",port:22,user:"",root_path:"",fingerprint:""},
                     vnc:{endpoint:"",service_active:false,running:false,ready:false,state:"unknown",readiness_reason:"",start_available:false,unavailable_reason:""},
                     share:{url:"",service_active:false,running:false,ready:false,configured:false,upstream_reachable:false,is_private:false,tailnet_only:false,privacy_verification:"unverified",pairing_available:false,pairing_reason:"Pairing state unavailable",pairing_checks:({}),pairing_cancel_supported:false}}
    })

    readonly property var pages: [
        {name:"Overview", icon:"space_dashboard"},
        {name:"Services", icon:"dns"},
        {name:"Security", icon:"shield"},
        {name:"Network", icon:"lan"},
        {name:"Phone", icon:"smartphone"},
        {name:"Logs", icon:"terminal"},
        {name:"Power", icon:"power"}
    ]

    focus: true

    Component.onCompleted: {
        root.modalShown = false
        modalOpenKickTimer.restart()
        Qt.callLater(() => root.forceActiveFocus())
        Qt.callLater(() => root.syncCaptureRegion())
        root.loadCachedState()
        root.pollOperation()
        initialLiveRefresh.restart()
    }

    Connections {
        target: GlobalStates

        function onArchRemoteOpenChanged() {
            if (GlobalStates.archRemoteOpen) {
                root.resetLargeSurfaceDeformation()
                root.modalShown = false
                modalOpenKickTimer.restart()
            } else {
                root.resetLargeSurfaceDeformation()
                root.modalShown = false
            }
        }
    }

    Component.onDestruction: {
        // Never keep credential-equivalent QR data alive after the panel closes.
        root.pairingQrSource = ""
        root.pairingExpiresAt = 0
    }

    onScreenNameChanged:
        Qt.callLater(() => root.syncCaptureRegion())

    onLockConfirmOpenChanged: {
        if (root.lockConfirmOpen)
            Qt.callLater(() => lockCancelButton.forceActiveFocus())
        else
            Qt.callLater(() => root.forceActiveFocus())
    }

    onReferenceOpenChanged: {
        if (root.referenceOpen)
            Qt.callLater(() => referenceSearch.forceActiveFocus())
        else
            Qt.callLater(() => root.forceActiveFocus())
    }

    onDetailOpenChanged: {
        if (root.detailOpen)
            Qt.callLater(() => detailCloseButton.forceActiveFocus())
        else
            Qt.callLater(() => root.forceActiveFocus())
    }

    Keys.priority: Keys.AfterItem
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.referenceOpen) root.referenceOpen = false
            else if (root.detailOpen) root.detailOpen = false
            else if (root.lockConfirmOpen) root.lockConfirmOpen = false
            else root.closeRequested()
            event.accepted = true
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_R) {
            root.refresh(true)
            event.accepted = true
        } else if (event.modifiers === Qt.ControlModifier
                   && event.key >= Qt.Key_1 && event.key <= Qt.Key_7) {
            root.switchPage(event.key - Qt.Key_1)
            event.accepted = true
        }
    }

    function syncCaptureRegion() {
        if (!GlobalStates.archRemoteOpen || root.screenName.length === 0)
            return

        GlobalStates.archRemoteScreenName = root.screenName
        GlobalStates.archRemoteRegionX = modal.x
        GlobalStates.archRemoteRegionY = modal.y
        GlobalStates.archRemoteRegionWidth = modal.width
        GlobalStates.archRemoteRegionHeight = modal.height
    }

    function switchPage(index) {
        const next = Math.max(0, Math.min(root.pages.length - 1, index))
        if (next === root.selectedPage || root.pageTransitioning)
            return

        root.previousPage = root.selectedPage
        root.pageDirection = next > root.previousPage ? 1 : -1
        root.selectedPage = next
        root.pageTransitioning = true
        pageOutAnimation.restart()

        if (next === 5)
            Qt.callLater(() => root.requestLogs())
    }

    function snapshotContractAccepted(payload) {
        if (!payload || Number(payload.schema_version) !== root.expectedSchemaVersion) {
            const message = `Arch Remote state schema mismatch · expected ${root.expectedSchemaVersion}, received ${payload ? payload.schema_version : "missing"}`
            if (root.contractError !== message) root.toast(message, true)
            root.contractError = message
            return false
        }
        if (String(payload.ui_contract || "") !== root.expectedUiContract) {
            const message = `Arch Remote UI contract mismatch · expected ${root.expectedUiContract}, received ${payload.ui_contract || "missing"}`
            if (root.contractError !== message) root.toast(message, true)
            root.contractError = message
            return false
        }
        root.contractError = ""
        return true
    }

    function referenceContractAccepted(payload) {
        return payload && Number(payload.schema_version) === root.expectedReferenceSchemaVersion
    }

    function loadCachedState() {
        if (cachedSnapshotProc.running) return
        cachedSnapshotProc.command = ["python3", root.helperPath, "snapshot-cache"]
        cachedSnapshotProc.running = true
    }

    function refresh(full) {
        if (snapshotProc.running) return
        root.loading = !root.cachedStateLoaded
        const command = ["python3", root.helperPath, "snapshot"]
        if (full === true) command.push("--full")
        snapshotProc.command = command
        snapshotProc.running = true
    }

    function operationElapsedText() {
        const started = Number(root.backendOperation.started_at || 0)
        if (started <= 0) return ""
        const seconds = Math.max(0, Math.floor(root.nowMs / 1000 - started))
        if (seconds < 60) return `${seconds}s`
        const minutes = Math.floor(seconds / 60)
        return `${minutes}m ${seconds % 60}s`
    }

    function applyOperation(operation) {
        const op = operation || ({})
        const wasRunning = root.actionRunning
        root.backendOperation = op
        root.operationId = String(op.id || "")
        root.actionRunning = op.active === true
        root.actionPhase = String(op.phase || (root.actionRunning ? "running" : ""))
        root.operationLabel = String(op.label || "")
        root.serviceTransitionName = String(op.service || "")
        root.serviceTransitionAction = String(op.action || "")

        if (root.actionRunning) {
            root.lastActionState = "running"
            return
        }

        const status = String(op.status || "")
        if (root.operationId.length > 0
            && root.operationHandledId !== root.operationId
            && (status === "succeeded" || status === "failed")) {
            root.operationHandledId = root.operationId
            root.lastActionState = String(op.result_state || status)
            root.toast(String(op.message || (status === "failed" ? "Action failed" : "Action complete")), status === "failed")
            refreshAfterAction.restart()
        } else if (wasRunning && !root.actionRunning) {
            refreshAfterAction.restart()
        }
    }

    function pollOperation() {
        if (operationStatusProc.running) return
        operationStatusProc.command = ["python3", root.helperPath, "operation-status"]
        operationStatusProc.running = true
    }

    function action(args) {
        if (!args || args.length === 0) return
        const persistent = args[0] === "service"
            || args[0] === "system-service"
            || args[0] === "lockdown"
            || args[0] === "verify-ssh-effective"

        if (!persistent) {
            if (actionProc.running) return
            actionProc.command = ["python3", root.helperPath].concat(args)
            actionProc.running = true
            return
        }

        if (root.actionRunning || operationStartProc.running) {
            root.toast(root.operationLabel.length > 0 ? `${root.operationLabel} is already in progress` : "Another Arch Remote action is already in progress", true)
            return
        }

        if ((args.length >= 3 && args[0] === "service" && args[1] === "lan-share"
             && (args[2] === "stop" || args[2] === "restart"))
            || args[0] === "lockdown") {
            root.clearPairing("none", "")
        }

        operationStartProc.command = ["python3", root.helperPath, "operation-start"].concat(args)
        operationStartProc.running = true
    }

    function showDetail(type, item) {
        root.detailType = type
        root.detailItem = item || ({})
        root.detailOpen = true
    }

    function requestLogs() {
        if (logsProc.running) return
        root.logsLoading = true
        logsProc.command = ["python3", root.helperPath, "logs", root.selectedLogService,
                            root.logSeverity, root.logWindow, root.logSearch]
        logsProc.running = true
    }

    function requestReference() {
        if (referenceProc.running) return
        root.referenceLoading = true
        referenceProc.command = ["python3", root.helperPath, "reference"]
        referenceProc.running = true
    }

    function openReference(query) {
        root.detailOpen = false
        root.referenceContext = String(query || "")
        root.referenceQuery = String(query || "")
        root.referenceOpen = true
        if (!root.referenceData.sections || root.referenceData.sections.length === 0)
            root.requestReference()
    }

    function referenceEntryMatches(entry, query) {
        const q = String(query || "").trim().toLowerCase()
        if (q.length === 0) return true

        const values = [
            entry.title || "",
            entry.command || "",
            entry.value || "",
            entry.description || "",
            entry.category || "",
            entry.platform || "",
            entry.importance || "",
            entry.current_state || "",
            (entry.tags || []).join(" "),
            (entry.dependencies || []).join(" ")
        ]

        return values.join(" ").toLowerCase().indexOf(q) >= 0
    }

    function referenceEntries(section) {
        const entries = section && section.entries ? section.entries : []
        const q = String(root.referenceQuery || "").trim().toLowerCase()
        if (q.length === 0) return entries
        return entries.filter(entry => root.referenceEntryMatches(entry, q))
    }

    function referenceSections() {
        const sections = root.referenceData && root.referenceData.sections
            ? root.referenceData.sections
            : []
        const q = String(root.referenceQuery || "").trim().toLowerCase()
        if (q.length === 0) return sections
        return sections.filter(section => {
            const haystack = `${section.title || ""} ${section.description || ""}`.toLowerCase()
            return haystack.indexOf(q) >= 0 || root.referenceEntries(section).length > 0
        })
    }

    function referenceExpandedFor(sectionId) {
        if (String(root.referenceQuery || "").trim().length > 0) return true
        return root.referenceExpanded[sectionId] === true
    }

    function toggleReferenceSection(sectionId) {
        const next = ({})
        for (const key in root.referenceExpanded)
            next[key] = root.referenceExpanded[key]
        next[sectionId] = !(root.referenceExpanded[sectionId] === true)
        root.referenceExpanded = next
    }

    function copyReference(entry) {
        const text = entry.command && String(entry.command).length > 0
            ? String(entry.command)
            : String(entry.value || "")
        root.copyText(text)
    }

    function referenceTone(entry) {
        if (entry.importance === "essential") return "active"
        if (entry.importance === "recovery") return "danger"
        return "neutral"
    }

    function referenceStateTone(value) {
        const state = String(value || "").toLowerCase()
        if (state === "ready" || state === "running") return "active"
        if (state.indexOf("not ready") >= 0 || state.indexOf("error") >= 0) return "danger"
        return "neutral"
    }

    function exportLogs() {
        root.action(["export-logs", root.selectedLogService,
                     root.logSeverity, root.logWindow, root.logSearch])
    }

    function copyText(value) {
        if (!value || String(value).length === 0) {
            root.toast("Nothing to copy", true)
            return
        }
        root.action(["copy", String(value)])
    }

    function openUrl(value) {
        if (!value || String(value).length === 0) {
            root.toast("No private URL detected", true)
            return
        }
        root.action(["open-url", String(value)])
    }

    function formatPairingCountdown(seconds) {
        const safe = Math.max(0, Number(seconds || 0))
        const minutes = Math.floor(safe / 60)
        const remainder = safe % 60
        return `${minutes}:${remainder < 10 ? "0" : ""}${remainder}`
    }

    function clearPairing(nextState, errorText) {
        root.pairingQrSource = ""
        root.pairingExpiresAt = 0
        root.pairingSingleUse = false
        root.pairingServerCancelSupported = false
        root.pairingBackendRevoked = false
        root.pairingError = String(errorText || "")
        root.pairingState = nextState || "none"
    }

    function generatePairing() {
        if (pairingProc.running || root.pairingBusy || root.actionRunning) return
        const share = root.remoteState.phone_guide.share
        if (!share.pairing_available) {
            root.toast(share.pairing_reason || "Private Share is not ready for pairing", true)
            return
        }

        // Generating a new credential invalidates any old unused QR. Discard
        // the old credential-equivalent image before requesting the next one.
        root.clearPairing("generating", "")
        root.pairingBusy = true
        root.pairingOperation = "create"
        pairingProc.command = ["python3", root.helperPath, "pairing-create"]
        pairingProc.running = true
    }

    function cancelPairing() {
        if (pairingProc.running || root.pairingBusy || root.actionRunning || root.pairingState !== "ready") return
        root.pairingBusy = true
        root.pairingOperation = "cancel"
        pairingProc.command = ["python3", root.helperPath, "pairing-cancel"]
        pairingProc.running = true
    }

    function recordPairingEvent(title, detail, severity) {
        if (pairEventProc.running) return
        pairEventProc.command = [
            "python3", root.helperPath, "record-event",
            "pairing", String(title), String(detail), String(severity || "info")
        ]
        pairEventProc.running = true
    }

    function tickPairing() {
        if (root.pairingState !== "ready" || root.pairingExpiresAt <= 0) return
        if (root.pairingRemainingSeconds > 0) return
        root.clearPairing("expired", "")
        root.recordPairingEvent(
            "Private Share pairing expired",
            "One-time pairing credential expired and was removed from the UI.",
            "info"
        )
    }

    function toast(message, error) {
        root.toastMessage = String(message || "")
        root.toastError = error === true
        toastTimer.restart()
    }

    function cap(value) {
        const text = String(value || "unknown")
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    function endpoint(port) {
        const found = root.remoteState.listeners.filter(item => item.port === port)
        return found.length ? found.map(item => item.endpoint).join(", ") : "No listener"
    }

    function ageText(epochSeconds) {
        if (!epochSeconds || epochSeconds <= 0) return "Not checked"
        const seconds = Math.max(0, Math.floor((root.nowMs - epochSeconds * 1000) / 1000))
        if (seconds < 2) return "Updated now"
        if (seconds < 60) return `Updated ${seconds}s ago`
        return `Updated ${Math.floor(seconds / 60)}m ago`
    }

    function serviceStateText(service) {
        if (!service.loaded) return "Unavailable"
        if (root.serviceTransitionName === service.name && root.actionRunning) {
            if (root.actionPhase === "verify") return root.serviceTransitionAction === "stop" ? "Verifying stop…" : "Verifying readiness…"
            if (root.serviceTransitionAction === "start") return "Starting…"
            if (root.serviceTransitionAction === "stop") return "Stopping…"
            if (root.serviceTransitionAction === "restart") return "Restarting…"
        }
        if (service.running && service.ready) return "Ready"
        if (service.running && !service.ready) return "Running · not ready"
        if (service.expected_state === "on-demand") return "Expected off"
        return "Down"
    }

    function serviceTone(service) {
        if (service.running && service.ready) return "active"
        if (service.running && !service.ready) return "danger"
        if (!service.running && service.expected_state === "on-demand") return "neutral"
        return "danger"
    }


    function issueChecks() {
        return root.remoteState.security_checks.filter(
            item => item.status === "fail" || item.status === "warn"
        )
    }

    function verificationChecks() {
        return root.remoteState.security_checks.filter(
            item => item.status === "untested" || item.status === "external-unverified" || (item.status === "unknown" && item.verification_scope === "local")
        )
    }

    function passedChecks() {
        return root.remoteState.security_checks.filter(item => item.status === "pass")
    }

    function globalHealthLabel() {
        return root.remoteState.health.label || root.cap(root.remoteState.health.status)
    }

    function globalHealthState() {
        if (root.remoteState.health.status === "critical") return "danger"
        if (root.remoteState.health.status === "healthy") return "active"
        return "neutral"
    }

    function lastSeenText(value) {
        if (!value || value.indexOf("0001-") === 0) return "No recent session"
        const date = new Date(value)
        if (isNaN(date.getTime())) return String(value)
        const seconds = Math.max(0, Math.floor((root.nowMs - date.getTime()) / 1000))
        if (seconds < 60) return "Seen just now"
        if (seconds < 3600) return `Seen ${Math.floor(seconds / 60)}m ago`
        if (seconds < 86400) return `Seen ${Math.floor(seconds / 3600)}h ago`
        return `Seen ${Math.floor(seconds / 86400)}d ago`
    }

    function logicalListenerName(item) {
        if (item.service && item.service.indexOf("TCP ") !== 0) return item.service
        if (item.bind_scope === "tailnet" && item.port > 1024) return "Tailscale peer service"
        return item.service || `TCP ${item.port}`
    }

    function logicalListeners() {
        const source = root.remoteState.exposure.listeners || []
        const map = ({})
        const order = []
        for (let i = 0; i < source.length; ++i) {
            const item = source[i]
            const name = root.logicalListenerName(item)
            const key = `${name}|${item.group || "other"}`
            if (!map[key]) {
                map[key] = {
                    name: name,
                    group_name: item.group || "other",
                    endpoints: [],
                    ports: [],
                    reachable_scope: item.reachable_scope || "Unknown",
                    expected_policy: item.expected_policy || "No explicit policy",
                    policy_status: item.policy_status || "informational",
                    finding: item.finding || "info",
                    process: item.process || "",
                    pid: item.pid || 0,
                    unit: name === "SSH" ? "sshd" : name === "WayVNC" ? "wayvnc-remote" : name === "LAN Share" ? "lan-share" : name === "Tailscale HTTPS" ? "tailscaled" : "",
                    authentication: name === "SSH" ? (root.remoteState.ssh.key_only ? "Public key only" : "Review SSH policy") : "",
                    evidence_sources: name === "SSH" ? ["ss", "systemd", root.remoteState.ssh.source || "sshd -T"] : ["ss", "systemd"]
                }
                order.push(key)
            }
            map[key].endpoints.push(item.endpoint)
            if (map[key].ports.indexOf(item.port) === -1) map[key].ports.push(item.port)
            if (item.finding === "critical") map[key].finding = "critical"
            else if (item.finding === "warning" && map[key].finding !== "critical") map[key].finding = "warning"
            if (item.policy_status === "unexpected") map[key].policy_status = "unexpected"
        }
        return order.map(key => map[key])
    }

    function listenersForGroup(groupName) {
        return root.logicalListeners().filter(item => item.group_name === groupName)
    }

    function wakeCapabilityLabel(wake) {
        if (!wake || !wake.interface_name) return "Not detected"
        if (wake.capability === "supported") return "Magic packet supported"
        if (wake.capability === "unsupported") return "Magic packet unsupported"
        return "Capability unavailable"
    }

    function wakeConfigLabel(wake) {
        if (!wake || !wake.interface_name) return "Not configured"
        if (wake.configured === "enabled") return "Magic packet enabled"
        if (wake.configured === "disabled") return "Magic packet disabled"
        return "Configuration unavailable"
    }

    function verificationLabel(wake) {
        if (!wake || wake.test_status === "untested") return "Not tested end-to-end"
        return root.cap(wake.test_status)
    }

    Process {
        id: cachedSnapshotProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text)
                    if (!payload.error
                        && root.snapshotContractAccepted(payload)
                        && Number(payload.generation || 0) >= Number(root.remoteState.generation || 0)) {
                        root.remoteState = payload
                        root.cachedStateLoaded = true
                    }
                } catch (e) {
                    // Cache is only a fast first paint; live refresh remains authoritative.
                }
            }
        }
    }

    Process {
        id: snapshotProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const payload = JSON.parse(this.text)
                    if (payload.error) {
                        root.toast(payload.message || "Refresh failed", true)
                    } else if (!root.snapshotContractAccepted(payload)) {
                        return
                    } else {
                        root.remoteState = payload
                        root.cachedStateLoaded = true
                        const share = payload.phone_guide && payload.phone_guide.share
                            ? payload.phone_guide.share
                            : null
                        if ((!payload.services.lan_share.running
                             || !share
                             || !share.pairing_available)
                            && (root.pairingState === "ready"
                                || root.pairingState === "generating")) {
                            root.clearPairing("none", "")
                        }
                    }
                } catch (e) {
                    root.toast(`Remote state parse failed: ${e}`, true)
                }
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text)
                    root.toast(payload.message || (payload.error ? "Action failed" : "Action complete"), payload.error === true)
                } catch (e) {
                    root.toast(`Action response failed: ${e}`, true)
                }
            }
        }
    }

    Process {
        id: operationStartProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text)
                    if (payload.error || payload.ok === false) {
                        root.toast(payload.message || "Could not start operation", true)
                        if (payload.operation) root.applyOperation(payload.operation)
                    } else {
                        root.applyOperation(payload.operation || ({}))
                    }
                } catch (e) {
                    root.toast(`Operation start response failed: ${e}`, true)
                }
                root.pollOperation()
            }
        }
    }

    Process {
        id: operationStatusProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text)
                    if (!payload.error && payload.operation)
                        root.applyOperation(payload.operation)
                } catch (e) {
                    // The next lightweight poll will retry; do not spam toasts.
                }
            }
        }
    }

    Process {
        id: pairingProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.pairingBusy = false
                let payload = ({})
                try {
                    payload = JSON.parse(this.text)
                } catch (e) {
                    if (root.pairingOperation === "create") {
                        root.clearPairing("error", `Pairing response parse failed: ${e}`)
                    } else {
                        root.pairingError = `Pairing response parse failed: ${e}`
                    }
                    root.toast(root.pairingError, true)
                    root.pairingOperation = ""
                    return
                }

                if (root.pairingOperation === "create") {
                    if (payload.error || payload.state !== "ready" || !payload.qr_data_url) {
                        root.clearPairing("error", payload.message || "Pairing generation failed")
                        root.toast(root.pairingError, true)
                    } else {
                        root.pairingQrSource = String(payload.qr_data_url)
                        root.pairingExpiresAt = Number(payload.expires_at || 0)
                        root.pairingSingleUse = payload.single_use === true
                        root.pairingServerCancelSupported = payload.server_cancel_supported === true
                        root.pairingBackendRevoked = false
                        root.pairingError = ""
                        root.pairingState = "ready"
                        root.toast("One-scan pairing QR ready", false)
                    }
                } else if (root.pairingOperation === "cancel") {
                    if (payload.error) {
                        // Do not hide a still-valid QR when server-side cancellation failed.
                        root.pairingError = payload.message || "Pairing cancellation failed"
                        root.toast(root.pairingError, true)
                    } else {
                        const revoked = payload.backend_revoked === true
                        root.clearPairing("cancelled", "")
                        root.pairingBackendRevoked = revoked
                        root.toast(payload.message || "Pairing cancelled", false)
                    }
                }

                root.pairingOperation = ""
                refreshAfterAction.restart()
            }
        }
    }

    Process {
        id: pairEventProc
        stdout: StdioCollector { }
    }

    Process {
        id: referenceProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.referenceLoading = false
                try {
                    const payload = JSON.parse(this.text)
                    if (payload.error || payload.ok === false) {
                        root.toast(payload.message || "Reference could not be loaded", true)
                    } else if (!root.referenceContractAccepted(payload)) {
                        root.toast(`Reference schema mismatch · expected ${root.expectedReferenceSchemaVersion}, received ${payload.schema_version || "missing"}`, true)
                    } else {
                        root.referenceData = payload
                    }
                } catch (e) {
                    root.toast(`Reference parse failed: ${e}`, true)
                }
            }
        }
    }

    Process {
        id: logsProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.logsLoading = false
                try {
                    const payload = JSON.parse(this.text)
                    if (payload.error) {
                        root.logText = payload.message || "Log request failed"
                        root.logKnownIssues = []
                        root.logEntryCount = 0
                    } else {
                        root.logText = payload.text || "No recent log entries."
                        root.logKnownIssues = payload.known_issue_objects || []
                        root.logEntryCount = payload.entry_count || 0
                    }
                } catch (e) {
                    root.logText = `Could not parse logs: ${e}`
                    root.logKnownIssues = []
                    root.logEntryCount = 0
                }
            }
        }
    }

    Timer {
        id: operationPollTimer
        interval: root.actionRunning ? 700 : 4000
        repeat: true
        running: true
        onTriggered: root.pollOperation()
    }
    Timer {
        id: liveRefreshTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            if (!root.actionRunning)
                root.refresh(false)
        }
    }
    Timer {
        id: initialLiveRefresh
        interval: 90
        repeat: false
        onTriggered: root.refresh(false)
    }
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.nowMs = Date.now()
            root.tickPairing()
        }
    }
    Timer {
        interval: 3500
        repeat: true
        running: root.activePage === 5 && root.logFollow && !root.logsLoading
        onTriggered: root.requestLogs()
    }
    Timer { id: refreshAfterAction; interval: 450; repeat: false; onTriggered: root.refresh(false) }
    Timer {
        id: modalOpenKickTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (GlobalStates.archRemoteOpen) {
                root.kickLargeSurfaceDeformation()
                root.modalShown = true
            }
        }
    }

    // phase4d-large-surface-deformation-v1
    // Restrained production profile for large Prism modal surfaces.
    ParallelAnimation {
        id: largeSurfaceDeformAnimation

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "largeSurfaceScaleX"
                to: Appearance.surfaceDeformation.largeMiddleX
                duration: Math.max(1, Math.round(Appearance.surfaceDeformation.largeXCompressMs * Appearance.motionScale))
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance.animationCurves.expressiveFastSpatial
            }

            NumberAnimation {
                target: root
                property: "largeSurfaceScaleX"
                to: 1
                duration: Math.max(1, Math.round(Appearance.surfaceDeformation.largeXSettleMs * Appearance.motionScale))
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance.animationCurves.expressiveDefaultEffects
            }
        }

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "largeSurfaceScaleY"
                to: Appearance.surfaceDeformation.largeMiddleY
                duration: Math.max(1, Math.round(Appearance.surfaceDeformation.largeYCompressMs * Appearance.motionScale))
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance.animationCurves.expressiveFastSpatial
            }

            NumberAnimation {
                target: root
                property: "largeSurfaceScaleY"
                to: 1
                duration: Math.max(1, Math.round(Appearance.surfaceDeformation.largeYSettleMs * Appearance.motionScale))
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "largeSurfaceRadiusScale"
                to: Appearance.surfaceDeformation.largeRadiusMiddle
                duration: Math.max(1, Math.round(Appearance.surfaceDeformation.largeRadiusCompressMs * Appearance.motionScale))
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance.animationCurves.expressiveFastEffects
            }

            NumberAnimation {
                target: root
                property: "largeSurfaceRadiusScale"
                to: 1
                duration: Math.max(1, Math.round(Appearance.surfaceDeformation.largeRadiusSettleMs * Appearance.motionScale))
                easing.type: Easing.BezierSpline
                easing.bezierCurve:
                    Appearance.animationCurves.expressiveDefaultEffects
            }
        }
    }

    Timer { id: toastTimer; interval: 3200; repeat: false; onTriggered: root.toastMessage = "" }


    component HeaderButton: Rectangle {
        id: button
        property string iconName: ""
        property string tooltipText: ""
        property bool active: false
        signal clicked
        implicitWidth: 34
        implicitHeight: 34
        radius: height / 2
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: tooltipText
        Accessible.focusable: true
        Accessible.focused: button.activeFocus
        Accessible.onPressAction: button.clicked()

        Keys.onPressed: event => {
            if (
                event.key === Qt.Key_Space
                || event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter
            ) {
                button.clicked()
                event.accepted = true
            }
        }

        color:
            Appearance.prismMode
                ? (
                    active || headerButtonArea.containsMouse || button.activeFocus
                        ? Appearance.prism.persistentActiveFill
                        : "transparent"
                  )
                : (
                    active || headerButtonArea.containsMouse || button.activeFocus
                        ? Appearance.colors.colPrimary
                        : Qt.rgba(
                            Appearance.colors.colOnSurfaceVariant.r,
                            Appearance.colors.colOnSurfaceVariant.g,
                            Appearance.colors.colOnSurfaceVariant.b,
                            0.07
                          )
                  )

        border.width: 1
        border.color:
            Appearance.prismMode
                ? (active || button.activeFocus
                    ? Appearance.prism.focusBorder
                    : Appearance.prism.borderSubtle)
                : (
                    active || headerButtonArea.containsMouse || button.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                  )

        MaterialSymbol {
            anchors.centerIn: parent
            text: button.iconName
            iconSize: 19
            fill: button.active ? 1 : 0
            color:
                Appearance.prismMode
                    ? (active || headerButtonArea.containsMouse || button.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnSurfaceVariant)
                    : (active || headerButtonArea.containsMouse || button.activeFocus
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnSurfaceVariant)
        }

        MouseArea {
            id: headerButtonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }

        StyledToolTip {
            extraVisibleCondition: headerButtonArea.containsMouse
            delay: 450
            text: button.tooltipText
        }
    }

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property string state: "neutral"
        property bool compact: false
        implicitWidth: pillText.implicitWidth + (compact ? 14 : 20)
        implicitHeight: compact ? 24 : 28
        radius: Appearance.radius.full
        color: state === "danger" ? Appearance.colors.colErrorContainer
             : state === "active" ? Appearance.colors.colSecondaryContainer
             : Appearance.colors.colLayer2Base
        StyledText {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.state === "danger" ? Appearance.colors.colOnErrorContainer
                 : pill.state === "active" ? Appearance.colors.colOnSecondaryContainer
                 : Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
        }
    }

    component SmallButton: RippleButton {
        id: button
        property string iconName: ""
        property string label: ""
        property bool danger: false
        property bool emphasized: false
        implicitHeight: 38
        implicitWidth: Math.max(78, labelText.implicitWidth + 40)
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control
        colBackground: danger ? Appearance.colors.colErrorContainer
                     : emphasized ? Appearance.colors.colSecondaryContainer
                     : Appearance.colors.colLayer2Base
        colBackgroundHover: danger ? Appearance.colors.colErrorContainer
                          : emphasized ? Appearance.colors.colSecondaryContainerHover
                          : Appearance.colors.colLayer2Hover
        colRipple: danger ? Appearance.colors.colErrorContainer
                 : emphasized ? Appearance.colors.colSecondaryContainerActive
                 : Appearance.colors.colLayer2Active
        contentItem: Row {
            anchors.centerIn: parent
            spacing: 7
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: button.iconName
                iconSize: 16
                color: button.danger ? Appearance.colors.colOnErrorContainer
                     : button.emphasized ? Appearance.colors.colOnSecondaryContainer
                     : Appearance.colors.colOnLayer1
            }
            StyledText {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                text: button.label
                color: button.danger ? Appearance.colors.colOnErrorContainer
                     : button.emphasized ? Appearance.colors.colOnSecondaryContainer
                     : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }
        }
    }

    component NavButton: RippleButton {
        id: nav
        required property int pageIndex
        required property var pageData
        Layout.fillWidth: true
        implicitHeight: 44
        readonly property bool selected: root.selectedPage === pageIndex
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: pageData.name
        buttonRadius: Appearance.radius.control
        buttonRadiusPressed: Appearance.radius.control
        colBackground:
            selected
                ? (Appearance.prismMode
                    ? Appearance.prism.persistentActiveFill
                    : Appearance.colors.colLayer2Base)
                : "transparent"
        colBackgroundHover:
            Appearance.prismMode
                ? Appearance.prism.persistentHoverFill
                : Appearance.colors.colLayer2Hover
        colRipple:
            Appearance.prismMode
                ? Appearance.prism.persistentActiveFill
                : Appearance.colors.colLayer2Active
        onClicked: root.switchPage(pageIndex)
        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 9
            Rectangle {
                Layout.preferredWidth: 3
                Layout.preferredHeight: 22
                radius: Appearance.radius.full
                color: nav.selected ? Appearance.colors.colPrimary : "transparent"
            }
            MaterialSymbol {
                text: nav.pageData.icon
                iconSize: 19
                fill: nav.selected ? 1 : 0
                color: nav.selected || nav.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: nav.pageData.name
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: nav.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }
    }

    component Heading: RowLayout {
        id: heading
        property string title: ""
        property string subtitle: ""
        property string meta: ""
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: heading.title
                color: Appearance.colors.colOnLayer0
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: heading.subtitle
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }
        StyledText {
            visible: heading.meta.length > 0
            text: heading.meta
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
            horizontalAlignment: Text.AlignRight
        }
    }

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
            font.pixelSize: Appearance.font.pixelSize.smallest
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

    component Metric: Rectangle {
        id: metric
        property string iconName: ""
        property string value: "—"
        property string label: ""
        property string subtitle: ""
        property string state: "neutral"
        Layout.fillWidth: true
        implicitHeight: 76
        radius: Appearance.radius.card
        color:
            Appearance.prismMode
                ? Appearance.prism.persistentFill
                : Appearance.colors.colLayer1Base
        border.width: 1
        border.color:
            Appearance.prismMode
                ? Appearance.prism.borderSubtle
                : Appearance.colors.colLayer0Border
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 9
            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: Appearance.radius.control
                color: Appearance.colors.colLayer2Base
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: metric.iconName
                    iconSize: 18
                    color: metric.state === "danger" ? Appearance.colors.colError
                         : metric.state === "active" ? Appearance.colors.colPrimary
                         : Appearance.colors.colSubtext
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: metric.label
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: metric.value
                        color: metric.state === "danger" ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: metric.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }
        }
    }

    component InfoRow: RowLayout {
        id: row
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 12
        StyledText {
            Layout.preferredWidth: 126
            text: row.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            Layout.fillWidth: true
            text: row.value
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignLeft
        }
    }

    component ServiceCard: Rectangle {
        id: card
        required property var service
        property string title: ""
        property string subtitle: ""
        property string iconName: ""
        property bool controllable: false
        property bool canStart: true
        property string startUnavailableReason: ""
        property string logService: ""
        property string helpQuery: ""
        property bool allowStop: true
        property bool allowRestart: true
        signal requested(string action)
        signal detailsRequested()
        Layout.fillWidth: true
        implicitHeight: (controllable || logService.length > 0) ? 122 : 90
        radius: Appearance.radius.card
        color:
            Appearance.prismMode
                ? Appearance.prism.persistentFill
                : Appearance.colors.colLayer1Base
        border.width: 1
        border.color:
            Appearance.prismMode
                ? Appearance.prism.borderSubtle
                : Appearance.colors.colLayer0Border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 11
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 9
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer2Base
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.iconName
                        iconSize: 19
                        color: card.service.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: card.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: card.subtitle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideMiddle
                    }
                }
                Pill {
                    label: root.serviceStateText(card.service)
                    state: root.serviceTone(card.service)
                    compact: true
                }
                HeaderButton {
                    iconName: "info"
                    tooltipText: "Service evidence"
                    onClicked: card.detailsRequested()
                }
            }
            RowLayout {
                visible: card.controllable || card.logService.length > 0
                Layout.fillWidth: true
                spacing: 6
                SmallButton {
                    visible: card.controllable && !card.service.running && card.canStart
                    iconName: "play_arrow"
                    label: "Start"
                    emphasized: true
                    enabled: !root.actionRunning
                    onClicked: card.requested("start")
                }
                StyledText {
                    visible: card.controllable && !card.service.running && !card.canStart
                    Layout.fillWidth: true
                    text: card.startUnavailableReason
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
                SmallButton {
                    visible: card.controllable && card.service.running && card.allowRestart
                    iconName: "restart_alt"
                    label: "Restart"
                    enabled: !root.actionRunning
                    onClicked: card.requested("restart")
                }
                SmallButton {
                    visible: card.controllable && card.service.running && card.allowStop
                    iconName: "stop"
                    label: "Stop"
                    enabled: !root.actionRunning
                    onClicked: card.requested("stop")
                }
                Item { Layout.fillWidth: true }
                SmallButton {
                    visible: card.helpQuery.length > 0
                    iconName: "help"
                    label: "Help"
                    onClicked: root.openReference(card.helpQuery)
                }
                SmallButton {
                    visible: card.logService.length > 0
                    iconName: "terminal"
                    label: "Logs"
                    onClicked: {
                        root.selectedLogService = card.logService
                        root.switchPage(5)
                        Qt.callLater(() => root.requestLogs())
                    }
                }
            }
        }
    }

    component CheckRow: Rectangle {
        id: row
        required property var item
        signal detailsRequested()
        Layout.fillWidth: true
        implicitHeight: 64
        radius: Appearance.radius.control
        color: item.status === "fail" ? Appearance.colors.colErrorContainer : "transparent"
        border.width: item.status === "pass" ? 0 : 1
        border.color: item.status === "fail" ? Appearance.colors.colError : Appearance.colors.colLayer0Border
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.detailsRequested()
        }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 9
            MaterialSymbol {
                text: row.item.status === "pass" ? "check_circle"
                    : row.item.status === "fail" ? "error"
                    : row.item.status === "external-unverified" ? "public_off"
                    : row.item.status === "untested" ? "radio_button_unchecked" : "warning"
                iconSize: 18
                color: row.item.status === "fail" ? Appearance.colors.colOnErrorContainer
                     : row.item.status === "pass" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: row.item.title
                    color: row.item.status === "fail" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.item.status === "pass" ? (row.item.detected || "Verified")
                        : row.item.status === "external-unverified" ? "Outside local verification scope"
                        : `Detected: ${row.item.detected || "unknown"}`
                    color: row.item.status === "fail" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }
            Pill {
                visible: row.item.status !== "pass"
                label: row.item.status === "external-unverified" ? "External"
                    : row.item.status === "unknown" || row.item.status === "untested" ? "Not verified" : root.cap(row.item.status)
                state: row.item.status === "fail" ? "danger" : "neutral"
                compact: true
            }
            MaterialSymbol { text: "chevron_right"; iconSize: 17; color: row.item.status === "fail" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext }
        }
    }

    component ListenerRow: Rectangle {
        id: row
        required property var listener
        signal detailsRequested()
        Layout.fillWidth: true
        implicitHeight: 68
        radius: Appearance.radius.control
        color:
            listener.finding === "critical"
                ? Appearance.colors.colErrorContainer
                : (Appearance.prismMode
                    ? Appearance.prism.persistentFill
                    : Appearance.colors.colLayer1Base)
        border.width: 1
        border.color:
            listener.finding === "critical"
                ? Appearance.colors.colError
                : (Appearance.prismMode
                    ? Appearance.prism.borderSubtle
                    : Appearance.colors.colLayer0Border)
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.detailsRequested() }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 10
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Appearance.radius.control
                color: Appearance.colors.colLayer2Base
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: row.listener.name === "SSH" ? "key"
                        : row.listener.name === "WayVNC" ? "desktop_windows"
                        : row.listener.name === "Tailscale HTTPS" ? "lock"
                        : row.listener.name === "Tailscale peer service" ? "hub" : "lan"
                    iconSize: 17
                    color: row.listener.finding === "critical" ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: row.listener.name
                        color: row.listener.finding === "critical" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: row.listener.ports.map(port => `:${port}`).join(" · ")
                        color: row.listener.finding === "critical" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: `${row.listener.reachable_scope} · ${row.listener.endpoints.join("  ·  ")}`
                    color: row.listener.finding === "critical" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideMiddle
                }
            }
            Pill {
                visible: row.listener.policy_status === "unexpected" || row.listener.finding === "critical"
                label: row.listener.policy_status === "unexpected" ? "Unexpected" : "Critical"
                state: "danger"
                compact: true
            }
        }
    }

    component ActivityRow: RowLayout {
        id: activityRow
        required property var eventData
        Layout.fillWidth: true
        spacing: 8
        StyledText {
            Layout.preferredWidth: 46
            text: Qt.formatTime(new Date(activityRow.eventData.timestamp * 1000), "HH:mm")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
        MaterialSymbol {
            text: activityRow.eventData.severity === "critical" ? "error"
                : activityRow.eventData.severity === "warning" ? "warning"
                : activityRow.eventData.severity === "success" ? "check_circle" : "history"
            iconSize: 15
            color: activityRow.eventData.severity === "critical" ? Appearance.colors.colError
                 : activityRow.eventData.severity === "success" ? Appearance.colors.colPrimary
                 : Appearance.colors.colSubtext
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: activityRow.eventData.title
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: activityRow.eventData.detail
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                elide: Text.ElideRight
            }
        }
    }

    component EmptyState: Rectangle {
        id: empty
        property string iconName: "inbox"
        property string title: "Nothing here"
        property string detail: ""
        Layout.fillWidth: true
        implicitHeight: 136
        radius: Appearance.radius.card
        color:
            Appearance.prismMode
                ? Appearance.prism.persistentFill
                : Appearance.colors.colLayer1Base
        border.width: 1
        border.color:
            Appearance.prismMode
                ? Appearance.prism.borderSubtle
                : Appearance.colors.colLayer0Border
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 520)
            spacing: 5
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: empty.iconName
                iconSize: 24
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: empty.title
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: empty.detail
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallest
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: mouse => {
            if (mouse.x < modal.x || mouse.x > modal.x + modal.width
                || mouse.y < modal.y || mouse.y > modal.y + modal.height)
                root.closeRequested()
        }
    }

    // prism-v2-phase7: depth-4 spatial material lives beside the legacy modal
    // so Fluid/Mica/Default keep their exact Rectangle/shadow path.
    PrismSurface {
        visible: Appearance.prismMode
        x: modal.x
        y: modal.y
        width: modal.width
        height: modal.height
        depth: Appearance.prism.depthModal
        surfaceRadius: Appearance.prism.radiusModal
        elevated: true
        opacity: modal.opacity
        scale: modal.scale
        transformOrigin: Item.Center
        transform: Translate {
            y: modalTranslate.y
        }
    }

    Rectangle {
        id: modal
        enabled: !root.lockConfirmOpen && !root.referenceOpen && !root.detailOpen
        anchors.centerIn: parent
        width: Math.min(1160, parent.width - 48)
        height: Math.min(740, parent.height - 48)
        radius:
            Appearance.inlayMode
                ? 0
                : (Appearance.prismMode
                    ? Appearance.prism.radiusModal
                    : Appearance.radius.modal)
                * root.largeSurfaceRadiusScale
        color:
            Appearance.prismMode
                ? "transparent"
                : Appearance.inlayMode
                    ? Appearance.inlay.surfaceFill
                    : Appearance.colors.colLayer0Base
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
        clip: true
        transformOrigin: Item.Center
        opacity: root.modalShown ? 1 : 0
        scale:
            root.modalShown
                ? 1
                : Appearance.inlayMode
                    ? 1
                    : (Appearance.prismMode ? Appearance.prism.enterScale : 0.970)

        transform: [
            Translate {
                id: modalTranslate
                y:
                    root.modalShown
                        ? 0
                        : Appearance.inlayMode
                            ? Appearance.inlay.enterDistance
                            : (Appearance.prismMode ? Appearance.prism.enterDistance * 2 : 34)

                Behavior on y {
                    MotionExpressiveAnim {
                        phase:
                            root.modalShown
                                ? MotionExpressiveAnim.Enter
                                : MotionExpressiveAnim.Exit
                    }
                }
            },

            // phase4d-large-surface-deformation-v1
            Scale {
                id: modalDeformationScale
                origin.x: modal.width / 2
                origin.y: modal.height / 2
                xScale: root.largeSurfaceScaleX
                yScale: root.largeSurfaceScaleY
            }
        ]

        onXChanged: root.syncCaptureRegion()
        onYChanged: root.syncCaptureRegion()
        onWidthChanged: root.syncCaptureRegion()
        onHeightChanged: root.syncCaptureRegion()

        Behavior on opacity {
            MotionAnim {
                type:
                    root.modalShown
                        ? MotionAnim.DefaultEffects
                        : MotionAnim.FastEffects
                duration: root.modalShown ? 200 : 180
            }
        }

        Behavior on scale {
            MotionExpressiveAnim {
                phase:
                    root.modalShown
                        ? MotionExpressiveAnim.Enter
                        : MotionExpressiveAnim.Exit
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                Layout.leftMargin: 16
                Layout.rightMargin: 12
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: Appearance.radius.card
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "shield"
                        iconSize: 22
                        fill: 1
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: "Arch Remote"
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.loading ? `Refreshing snapshot #${root.remoteState.generation || 0}…`
                             : `${root.remoteState.health.summary || "Private access & recovery"} · ${root.ageText(root.remoteState.generated_at)} · snapshot #${root.remoteState.generation || 0}`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }

                Pill {
                    label: root.globalHealthLabel()
                    state: root.globalHealthState()
                }

                HeaderButton {
                    iconName: "help"
                    tooltipText: "Reference & Recovery"
                    onClicked: root.openReference("")
                }
                HeaderButton {
                    iconName: "refresh"
                    tooltipText: "Full refresh · Ctrl+R"
                    onClicked: root.refresh(true)
                }
                HeaderButton {
                    iconName: "close"
                    tooltipText: "Close · Esc"
                    onClicked: root.closeRequested()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 10
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 174
                    Layout.fillHeight: true
                    radius: Appearance.radius.sidebar
                    color: Appearance.colors.colLayer1Base
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        Repeater {
                            model: root.pages
                            delegate: NavButton {
                                required property int index
                                required property var modelData
                                pageIndex: index
                                pageData: modelData
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Appearance.colors.colLayer0Border
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 5
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: root.remoteState.host.hostname || "Host"
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.remoteState.profile
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    Item {
                        id: pageSurface
                        anchors.fill: parent
                        opacity: 1

                        transform: Translate {
                            id: pageTranslate
                            x: 0
                        }

                        ParallelAnimation {
                            id: pageOutAnimation

                            MotionAnim {
                                target: pageSurface
                                property: "opacity"
                                to: 0
                                type: MotionAnim.FastEffects
                                duration: 170
                            }

                            MotionAnim {
                                target: pageTranslate
                                property: "x"
                                to: -42 * root.pageDirection
                                type: MotionAnim.FastSpatial
                                duration: 220
                            }

                            onFinished: {
                                root.activePage = root.selectedPage
                                pageTranslate.x = 42 * root.pageDirection
                                pageSurface.opacity = 0
                                pageInAnimation.restart()
                            }
                        }

                        ParallelAnimation {
                            id: pageInAnimation

                            MotionAnim {
                                target: pageSurface
                                property: "opacity"
                                to: 1
                                type: MotionAnim.DefaultEffects
                                duration: 200
                            }

                            MotionAnim {
                                target: pageTranslate
                                property: "x"
                                to: 0
                                type: MotionAnim.DefaultSpatial
                                duration: 420
                            }

                            onFinished: root.pageTransitioning = false
                        }

                        Loader {
                            anchors.fill: parent
                            sourceComponent: root.activePage === 0 ? overviewPage
                                : root.activePage === 1 ? servicesPage
                                : root.activePage === 2 ? securityPage
                                : root.activePage === 3 ? networkPage
                                : root.activePage === 4 ? phonePage
                                : root.activePage === 5 ? logsPage : powerPage
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.lockConfirmOpen
        anchors.centerIn: modal
        width: Math.min(470, modal.width - 80)
        implicitHeight: 286
        z: 90
        radius: Appearance.radius.modal
        color: Appearance.colors.colLayer1Base
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            StyledText {
                text: "Lock interactive sharing"
                color: Appearance.colors.colOnLayer1
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: "LAN Share and WayVNC will be stopped and verified. SSH and Tailscale stay available for recovery."
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
            Section { title: "Will stop"; iconName: "stop_circle" }
            StyledText { text: "✓ LAN Share\n✓ WayVNC Remote Desktop"; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
            Section { title: "Recovery kept"; iconName: "verified_user" }
            StyledText { text: "✓ Tailscale\n✓ SSH recovery"; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                SmallButton { id: lockCancelButton; iconName: "close"; label: "Cancel"; onClicked: root.lockConfirmOpen = false }
                SmallButton {
                    iconName: "lock"
                    label: "Lock sharing"
                    danger: true
                    onClicked: {
                        root.lockConfirmOpen = false
                        root.action(["lockdown"])
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.referenceOpen
        anchors.top: modal.top
        anchors.right: modal.right
        anchors.bottom: modal.bottom
        width: Math.min(620, modal.width * 0.60)
        z: 92
        radius: Appearance.radius.sidebar
        color: Appearance.colors.colLayer1Base
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: Appearance.radius.control
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "menu_book"
                        iconSize: 19
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: "Reference & Recovery"
                        color: Appearance.colors.colOnLayer1
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.referenceLoading
                            ? "Loading operational reference…"
                            : `Commands, clients, endpoints, configuration and recovery · snapshot #${root.referenceData.snapshot_generation || root.remoteState.generation || 0}`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideRight
                    }
                }

                HeaderButton {
                    iconName: "refresh"
                    tooltipText: "Refresh reference"
                    onClicked: root.requestReference()
                }
                HeaderButton {
                    iconName: "close"
                    tooltipText: "Close reference"
                    onClicked: root.referenceOpen = false
                }
            }

            TextField {
                id: referenceSearch
                Layout.fillWidth: true
                implicitHeight: 38
                placeholderText: "Search commands, services, recovery…"
                activeFocusOnTab: true
                Accessible.name: "Search Arch Remote reference and recovery"
                text: root.referenceQuery
                color: Appearance.colors.colOnLayer1
                selectByMouse: true
                onTextChanged: root.referenceQuery = text
                background: Rectangle {
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer2Base
                    border.width: 1
                    border.color: referenceSearch.activeFocus
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                }
                leftPadding: 12
                rightPadding: 12
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        {label:"Phone", query:"phone"},
                        {label:"Share", query:"private share"},
                        {label:"Desktop", query:"remote desktop"},
                        {label:"SSH", query:"ssh"},
                        {label:"Recovery", query:"recovery"}
                    ]
                    delegate: SmallButton {
                        required property var modelData
                        iconName: "search"
                        label: modelData.label
                        onClicked: root.referenceQuery = modelData.query
                    }
                }
                Item { Layout.fillWidth: true }
                SmallButton {
                    visible: root.referenceQuery.length > 0
                    iconName: "close"
                    label: "Clear"
                    onClicked: root.referenceQuery = ""
                }
            }

            ScrollView {
                id: referenceScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: referenceScroll.availableWidth
                    spacing: 8

                    Rectangle {
                        visible: !root.referenceLoading
                            && root.referenceSections().length === 0
                        Layout.fillWidth: true
                        implicitHeight: 84
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer2Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 3
                            StyledText {
                                text: "No reference entries match this search"
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                text: "Try ssh, files, vnc, wake, share or recovery."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }

                    Repeater {
                        model: root.referenceSections()
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 5

                            RippleButton {
                                id: referenceSectionButton
                                Layout.fillWidth: true
                                implicitHeight: 42
                                activeFocusOnTab: true
                                buttonRadius: Appearance.radius.control
                                buttonRadiusPressed: Appearance.radius.control
                                colBackground: Appearance.colors.colLayer2Base
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.toggleReferenceSection(modelData.id)

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: modelData.icon || "menu_book"
                                        iconSize: 17
                                        color: Appearance.colors.colPrimary
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.description || ""
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Pill {
                                        label: String(root.referenceEntries(modelData).length)
                                        state: "neutral"
                                        compact: true
                                    }
                                    MaterialSymbol {
                                        text: root.referenceExpandedFor(modelData.id)
                                            ? "expand_less"
                                            : "expand_more"
                                        iconSize: 17
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            Repeater {
                                model: root.referenceExpandedFor(modelData.id)
                                    ? root.referenceEntries(modelData)
                                    : []

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: referenceEntryColumn.implicitHeight + 20
                                    radius: Appearance.radius.card
                                    color: Appearance.colors.colLayer1Base
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0Border

                                    ColumnLayout {
                                        id: referenceEntryColumn
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 10
                                        spacing: 7

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 7

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                color: Appearance.colors.colOnLayer1
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Pill {
                                                visible: modelData.current_state
                                                    && String(modelData.current_state).length > 0
                                                label: modelData.current_state || ""
                                                state: root.referenceStateTone(modelData.current_state)
                                                compact: true
                                            }

                                            Pill {
                                                visible: modelData.importance === "essential"
                                                    || modelData.importance === "recovery"
                                                    || modelData.advanced === true
                                                label: modelData.importance === "essential"
                                                    ? "Essential"
                                                    : modelData.importance === "recovery"
                                                        ? "Recovery"
                                                        : "Advanced"
                                                state: root.referenceTone(modelData)
                                                compact: true
                                            }
                                        }

                                        StyledText {
                                            visible: modelData.description
                                                && String(modelData.description).length > 0
                                            Layout.fillWidth: true
                                            text: modelData.description || ""
                                            color: Appearance.colors.colSubtext
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            wrapMode: Text.WordWrap
                                        }

                                        Rectangle {
                                            visible: (modelData.command && String(modelData.command).length > 0)
                                                || (modelData.value && String(modelData.value).length > 0)
                                            Layout.fillWidth: true
                                            implicitHeight: Math.max(44, referenceValue.implicitHeight + 16)
                                            radius: Appearance.radius.control
                                            color: Appearance.colors.colLayer2Base
                                            border.width: 1
                                            border.color: Appearance.colors.colLayer0Border

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 4
                                                anchors.topMargin: 4
                                                anchors.bottomMargin: 4
                                                spacing: 8

                                                StyledText {
                                                    id: referenceValue
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    text: modelData.command && String(modelData.command).length > 0
                                                        ? modelData.command
                                                        : modelData.value || ""
                                                    color: Appearance.colors.colOnLayer1
                                                    font.family: modelData.kind === "client"
                                                        ? Appearance.font.family.main
                                                        : Appearance.font.family.monospace
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    wrapMode: Text.WordWrap
                                                }

                                                HeaderButton {
                                                    visible: modelData.copyable === true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    iconName: "content_copy"
                                                    tooltipText: "Copy"
                                                    onClicked: root.copyReference(modelData)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            visible: (modelData.action_args && modelData.action_args.length > 0)
                                                || modelData.requires_root === true
                                                || modelData.mutates_state === true
                                            Layout.fillWidth: true
                                            Layout.topMargin: 1
                                            spacing: 6

                                            Pill {
                                                visible: modelData.requires_root === true
                                                label: "Root required"
                                                state: "neutral"
                                                compact: true
                                            }

                                            Pill {
                                                visible: modelData.mutates_state === true
                                                label: "Changes state"
                                                state: "neutral"
                                                compact: true
                                            }

                                            Item { Layout.fillWidth: true }

                                            SmallButton {
                                                visible: modelData.action_args
                                                    && modelData.action_args.length > 0
                                                    && modelData.action_label
                                                    && String(modelData.action_label).length > 0
                                                iconName: String(modelData.action_label || "").toLowerCase().indexOf("stop") >= 0
                                                    ? "stop"
                                                    : "play_arrow"
                                                label: modelData.action_label || "Run"
                                                emphasized: false
                                                enabled: !root.actionRunning
                                                onClicked: root.action(modelData.action_args)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 6 }
                }
            }
        }
    }

    Rectangle {
        visible: root.detailOpen
        anchors.top: modal.top
        anchors.right: modal.right
        anchors.bottom: modal.bottom
        width: Math.min(410, modal.width * 0.43)
        z: 96
        radius: Appearance.radius.sidebar
        color: Appearance.colors.colLayer1Base
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 9
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.detailType === "check" ? "Verification evidence"
                        : root.detailType === "listener" ? "Network evidence"
                        : root.detailType === "device" ? "Device evidence"
                        : root.detailType === "wake" ? "Wake evidence" : "Service evidence"
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                }
                HeaderButton { id: detailCloseButton; iconName: "close"; tooltipText: "Close details"; onClicked: root.detailOpen = false }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Appearance.colors.colLayer0Border }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: parent.width
                    spacing: 8
                    ColumnLayout {
                        visible: root.detailType === "check"
                        Layout.fillWidth: true
                        spacing: 7
                        InfoRow { label: "Status"; value: root.detailItem.status || "unknown" }
                        InfoRow { label: "Confidence"; value: root.detailItem.confidence || "unknown" }
                        InfoRow { label: "Scope"; value: root.detailItem.verification_scope || "local" }
                        InfoRow { label: "Expected"; value: root.detailItem.expected || "—" }
                        InfoRow { label: "Detected"; value: root.detailItem.detected || "—" }
                        InfoRow { label: "Source"; value: root.detailItem.source || "—" }
                        StyledText { Layout.fillWidth: true; text: root.detailItem.explanation || ""; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; wrapMode: Text.WordWrap }
                        StyledText { Layout.fillWidth: true; text: `Remediation: ${root.detailItem.remediation || "None required"}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small; wrapMode: Text.WordWrap }
                        SmallButton { visible: root.detailItem.id === "ssh-effective-proof" && root.detailItem.status !== "pass"; iconName: "fact_check"; label: "Verify SSH"; emphasized: true; onClicked: { root.detailOpen = false; root.action(["verify-ssh-effective"]) } }
                    }
                    ColumnLayout {
                        visible: root.detailType === "service"
                        Layout.fillWidth: true
                        spacing: 7
                        InfoRow { label: "Unit"; value: root.detailItem.name || "—" }
                        InfoRow { label: "Runtime"; value: root.detailItem.running ? "Running" : "Inactive" }
                        InfoRow { label: "Readiness"; value: root.detailItem.readiness || "unknown" }
                        InfoRow { label: "Reason"; value: root.detailItem.readiness_reason || "—" }
                        InfoRow { label: "PID"; value: String(root.detailItem.pid || 0) }
                        InfoRow { label: "Memory"; value: root.detailItem.memory || "—" }
                        InfoRow { label: "CPU time"; value: root.detailItem.cpu_time || "—" }
                        InfoRow { label: "Started"; value: root.detailItem.started_at || "Not running" }
                        InfoRow { label: "Restarts"; value: String(root.detailItem.restarts || 0) }
                        InfoRow { label: "Result"; value: root.detailItem.result || "unknown" }
                        InfoRow { label: "Boot policy"; value: `${root.detailItem.enabled_state || "unknown"} · expected ${root.detailItem.expected_state || "unknown"}` }
                        InfoRow { label: "Listener"; value: root.detailItem.bind || "—" }
                        InfoRow { label: "Config"; value: root.detailItem.fragment_path || "—" }
                        StyledText { Layout.fillWidth: true; text: `Evidence: ${(root.detailItem.evidence_sources || []).join(" · ") || "system state"}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small; wrapMode: Text.WordWrap }
                        RowLayout {
                            Layout.fillWidth: true
                            SmallButton { visible: root.detailItem.name === "lan-share" || root.detailItem.name === "wayvnc-remote" || root.detailItem.name === "tailscaled" || root.detailItem.name === "sshd"; iconName: "terminal"; label: "Logs"; onClicked: { root.selectedLogService = root.detailItem.name === "wayvnc-remote" ? "wayvnc" : root.detailItem.name; root.detailOpen = false; root.switchPage(5); Qt.callLater(() => root.requestLogs()) } }
                            SmallButton { visible: root.detailItem.name === "lan-share" || root.detailItem.name === "wayvnc-remote"; iconName: "restart_alt"; label: "Restart"; onClicked: { const name = root.detailItem.name; root.detailOpen = false; root.action(["service", name, "restart"]) } }
                            SmallButton { visible: root.detailItem.name === "tailscaled"; iconName: "restart_alt"; label: "Restart"; onClicked: { root.detailOpen = false; root.action(["system-service", "tailscaled", "restart"]) } }
                            SmallButton { iconName: "content_copy"; label: "Copy diagnostics"; onClicked: root.copyText(JSON.stringify(root.detailItem, null, 2)) }
                        }
                    }
                    ColumnLayout {
                        visible: root.detailType === "listener"
                        Layout.fillWidth: true
                        spacing: 7
                        InfoRow { label: "Service"; value: root.detailItem.name || "—" }
                        InfoRow { label: "Unit"; value: root.detailItem.unit || "—" }
                        InfoRow { label: "PID"; value: String(root.detailItem.pid || 0) }
                        InfoRow { label: "Process"; value: root.detailItem.process || "—" }
                        InfoRow { label: "Listeners"; value: (root.detailItem.endpoints || []).join(" · ") }
                        InfoRow { label: "Scope"; value: root.detailItem.reachable_scope || "—" }
                        InfoRow { label: "Policy"; value: root.detailItem.expected_policy || "—" }
                        InfoRow { visible: (root.detailItem.authentication || "").length > 0; label: "Authentication"; value: root.detailItem.authentication || "—" }
                        StyledText { Layout.fillWidth: true; text: `Evidence: ${(root.detailItem.evidence_sources || []).join(" · ")}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small; wrapMode: Text.WordWrap }
                    }
                    ColumnLayout {
                        visible: root.detailType === "device"
                        Layout.fillWidth: true
                        spacing: 7
                        InfoRow { label: "Device"; value: root.detailItem.hostname || "—" }
                        InfoRow { label: "DNS"; value: root.detailItem.dns_name || "—" }
                        InfoRow { label: "OS"; value: root.detailItem.os || "—" }
                        InfoRow { label: "State"; value: root.detailItem.online ? "Online" : "Offline" }
                        InfoRow { label: "Addresses"; value: (root.detailItem.addresses || []).join(" · ") }
                        InfoRow { label: "Last seen"; value: root.lastSeenText(root.detailItem.last_seen || "") }
                    }
                    ColumnLayout {
                        visible: root.detailType === "wake"
                        Layout.fillWidth: true
                        spacing: 7
                        InfoRow { label: "Interface"; value: root.detailItem.interface_name || "—" }
                        InfoRow { label: "Capability"; value: root.wakeCapabilityLabel(root.detailItem) }
                        InfoRow { label: "Configuration"; value: root.wakeConfigLabel(root.detailItem) }
                        InfoRow { label: "Verification"; value: root.verificationLabel(root.detailItem) }
                        InfoRow { label: "Raw support"; value: root.detailItem.raw_supported || "—" }
                        InfoRow { label: "Raw current"; value: root.detailItem.raw_current || "—" }
                        StyledText { visible: (root.detailItem.error || "").length > 0; Layout.fillWidth: true; text: root.detailItem.error || ""; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.actionRunning && root.operationLabel.length > 0
        Accessible.role: Accessible.StaticText
        Accessible.name: `${root.operationLabel} · ${root.actionPhase || "running"} ${root.operationElapsedText()}`
        anchors.horizontalCenter: modal.horizontalCenter
        anchors.bottom: modal.bottom
        anchors.bottomMargin: 18
        width: Math.min(620, modal.width - 48)
        implicitHeight: 44
        z: 99
        radius: Appearance.radius.control
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Appearance.colors.colPrimary
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 8
            MaterialSymbol { text: "progress_activity"; iconSize: 17; color: Appearance.colors.colPrimary }
            StyledText { Layout.fillWidth: true; text: root.operationLabel; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold }
            StyledText { text: `${root.actionPhase || "running"}${root.operationElapsedText().length > 0 ? " · " + root.operationElapsedText() : ""}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest }
        }
    }

    Rectangle {
        visible: root.toastMessage.length > 0
        Accessible.role: Accessible.StaticText
        Accessible.name: root.toastMessage
        anchors.horizontalCenter: modal.horizontalCenter
        anchors.bottom: modal.bottom
        anchors.bottomMargin: 18
        width: Math.min(540, modal.width - 48)
        implicitHeight: 44
        z: 100
        radius: Appearance.radius.control
        color: root.toastError ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2Base
        border.width: 1
        border.color: root.toastError ? Appearance.colors.colError : Appearance.colors.colLayer0Border
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 11
            spacing: 7
            MaterialSymbol {
                text: root.toastError ? "error" : "check_circle"
                iconSize: 17
                color: root.toastError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.toastMessage
                color: root.toastError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: overviewPage
        ColumnLayout {
            spacing: 9
            Heading {
                title: "Remote access"
                subtitle: "Recovery, private networking, sharing and remote desktop at a glance."
                meta: root.ageText(root.remoteState.fast_checked_at)
            }
            ScrollView {
                id: overviewScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ColumnLayout {
                    width: overviewScroll.availableWidth
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Metric {
                            iconName: "vpn_lock"
                            value: root.remoteState.tailscale.connected ? "Connected" : "Offline"
                            label: "Tailscale"
                            subtitle: root.remoteState.tailscale.connected ? "Private network ready" : "Recovery network unavailable"
                            state: root.remoteState.tailscale.connected ? "active" : "danger"
                        }
                        Metric {
                            iconName: "key"
                            value: root.remoteState.services.sshd.ready ? "Ready" : root.remoteState.services.sshd.running ? "Verify" : "Down"
                            label: "SSH recovery"
                            subtitle: root.remoteState.ssh.secure ? "Key-only · root disabled" : "Review security evidence"
                            state: root.remoteState.services.sshd.ready ? "active" : root.remoteState.services.sshd.running ? "neutral" : "danger"
                        }
                        Metric {
                            iconName: "folder_shared"
                            value: root.remoteState.services.lan_share.ready ? "Ready" : root.remoteState.services.lan_share.running ? "Degraded" : "Off"
                            label: "Private share"
                            subtitle: root.remoteState.services.lan_share.ready ? (root.remoteState.services.lan_share.reachable ? "Private Share Ready" : "Local listener ready · route offline") : root.remoteState.services.lan_share.readiness_reason || "Off · expected"
                            state: root.remoteState.services.lan_share.active ? "active" : "neutral"
                        }
                        Metric {
                            iconName: "desktop_windows"
                            value: root.remoteState.services.wayvnc.ready ? "Ready" : root.remoteState.services.wayvnc.running ? "Degraded" : "Off"
                            label: "Remote desktop"
                            subtitle: root.remoteState.services.wayvnc.ready ? "TLS auth + Tailnet :5900 verified" : root.remoteState.services.wayvnc.readiness_reason || "Off · expected"
                            state: root.remoteState.services.wayvnc.active ? "active" : "neutral"
                        }
                    }

                    Section { title: "Actions"; iconName: "bolt" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        SmallButton {
                            iconName: root.remoteState.services.lan_share.active ? "stop" : "play_arrow"
                            label: root.remoteState.services.lan_share.active ? "Stop share" : "Start share"
                            emphasized: !root.remoteState.services.lan_share.active
                            onClicked: root.action(["service", "lan-share", root.remoteState.services.lan_share.active ? "stop" : "start"])
                        }
                        SmallButton {
                            visible: root.remoteState.services.wayvnc.active || root.remoteState.phone_guide.vnc.start_available
                            iconName: root.remoteState.services.wayvnc.active ? "stop" : "play_arrow"
                            label: root.remoteState.services.wayvnc.active ? "Stop desktop" : "Start desktop"
                            onClicked: root.action(["service", "wayvnc-remote", root.remoteState.services.wayvnc.active ? "stop" : "start"])
                        }
                        SmallButton {
                            iconName: "content_copy"
                            label: "Copy SSH"
                            onClicked: root.copyText(root.remoteState.phone_guide.ssh_command)
                        }
                        SmallButton {
                            visible: root.remoteState.tailscale.serve.configured && root.remoteState.tailscale.serve.upstream_reachable && root.remoteState.tailscale.serve.url.length > 0
                            iconName: "open_in_new"
                            label: "Open share"
                            onClicked: root.openUrl(root.remoteState.tailscale.serve.url)
                        }
                        Item { Layout.fillWidth: true }
                        SmallButton {
                            iconName: "lock"
                            label: "Lock sharing"
                            danger: root.remoteState.services.lan_share.active || root.remoteState.services.wayvnc.active
                            onClicked: root.lockConfirmOpen = true
                        }
                    }

                    Rectangle {
                        visible: root.issueChecks().length > 0 || root.verificationChecks().length > 0
                        Layout.fillWidth: true
                        implicitHeight: attentionColumn.implicitHeight + 22
                        radius: Appearance.radius.card
                        color: root.remoteState.health.status === "critical" ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: root.remoteState.health.status === "critical" ? Appearance.colors.colError : Appearance.colors.colLayer0Border
                        ColumnLayout {
                            id: attentionColumn
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 7
                            RowLayout {
                                Layout.fillWidth: true
                                MaterialSymbol {
                                    text: root.remoteState.health.status === "critical" ? "error" : "verified_user"
                                    iconSize: 18
                                    color: root.remoteState.health.status === "critical" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.issueChecks().length > 0 ? "Attention" : "Verification remaining"
                                    color: root.remoteState.health.status === "critical" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    text: `${root.issueChecks().length} issue(s) · ${root.verificationChecks().length} untested`
                                    color: root.remoteState.health.status === "critical" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }
                            Repeater {
                                model: root.issueChecks().concat(root.verificationChecks()).slice(0, 3)
                                delegate: CheckRow { required property var modelData; item: modelData; onDetailsRequested: root.showDetail("check", modelData) }
                            }
                        }
                    }

                    Section { title: "Remote paths"; detail: "Current detected values"; iconName: "route" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 132
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 7
                            InfoRow { label: "SSH"; value: root.remoteState.phone_guide.ssh_command }
                            InfoRow {
                                label: "Private share"
                                value: !root.remoteState.tailscale.serve.configured ? "Serve not configured"
                                    : root.remoteState.tailscale.serve.upstream_reachable ? root.remoteState.tailscale.serve.url
                                    : "Serve configured · upstream offline"
                            }
                            InfoRow { label: "Remote desktop"; value: root.remoteState.phone_guide.vnc.endpoint || "No endpoint" }
                            InfoRow { label: "Exposure"; value: root.remoteState.tailscale.funnel.is_public ? "Public Funnel detected" : "No application-level public exposure detected" }
                        }
                    }

                    Section { visible: root.remoteState.activity.length > 0; title: "Recent activity"; detail: `${Math.min(3, root.remoteState.activity.length)} shown`; iconName: "history" }
                    Rectangle {
                        visible: root.remoteState.activity.length > 0
                        Layout.fillWidth: true
                        implicitHeight: activityColumn.implicitHeight + 16
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            id: activityColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 8
                            Repeater {
                                model: root.remoteState.activity.slice(0, 3)
                                delegate: ActivityRow { required property var modelData; eventData: modelData }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 6 }
                }
            }
        }
    }

    Component {
        id: servicesPage
        ColumnLayout {
            spacing: 9
            Heading {
                title: "Services"
                subtitle: "Recovery stays available; sharing stays on-demand. Only valid actions are shown."
                meta: root.ageText(root.remoteState.fast_checked_at)
            }
            ScrollView {
                id: servicesScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: servicesScroll.availableWidth
                    spacing: 10
                    Section { title: "Recovery"; detail: "Expected running"; iconName: "shield" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ServiceCard {
                            service: root.remoteState.services.sshd
                            title: "OpenSSH"
                            iconName: "key"
                            logService: "sshd"
                            helpQuery: "ssh"
                            subtitle: root.remoteState.services.sshd.readiness_reason || "SSH recovery"
                            onDetailsRequested: root.showDetail("service", root.remoteState.services.sshd)
                        }
                        ServiceCard {
                            service: root.remoteState.services.tailscaled
                            title: "Tailscale"
                            iconName: "vpn_lock"
                            logService: "tailscaled"
                            helpQuery: "tailscale"
                            controllable: true
                            allowStop: false
                            allowRestart: true
                            subtitle: root.remoteState.services.tailscaled.readiness_reason || (root.remoteState.tailscale.dns_name || root.remoteState.tailscale.hostname)
                            onRequested: action => root.action(["system-service", "tailscaled", action])
                            onDetailsRequested: root.showDetail("service", root.remoteState.services.tailscaled)
                        }
                    }
                    Section { title: "On-demand"; detail: "Off can be healthy"; iconName: "toggle_on" }
                    ServiceCard {
                        service: root.remoteState.services.lan_share
                        title: "LAN Share"
                        iconName: "folder_shared"
                        controllable: true
                        logService: "lan-share"
                        helpQuery: "private share"
                        subtitle: root.remoteState.services.lan_share.active
                            ? `${root.remoteState.services.lan_share.bind} · ${root.remoteState.tailscale.serve.upstream_reachable ? "private route reachable" : "Serve upstream unavailable"}`
                            : `Expected bind 127.0.0.1:8000 · Serve ${root.remoteState.tailscale.serve.configured ? "configured" : "not configured"}`
                        onRequested: action => root.action(["service", "lan-share", action])
                        onDetailsRequested: root.showDetail("service", root.remoteState.services.lan_share)
                    }
                    ServiceCard {
                        service: root.remoteState.services.wayvnc
                        title: "WayVNC Remote Desktop"
                        iconName: "desktop_windows"
                        controllable: true
                        canStart: root.remoteState.phone_guide.vnc.start_available
                        startUnavailableReason: root.remoteState.phone_guide.vnc.unavailable_reason
                        logService: "wayvnc"
                        helpQuery: "remote desktop"
                        subtitle: root.remoteState.services.wayvnc.active
                            ? `${root.remoteState.services.wayvnc.bind} · Wayland ${root.remoteState.graphical.wayland_display}`
                            : `Expected Tailscale :5900 · ${root.remoteState.graphical.wayland_display || "Wayland unavailable"}`
                        onRequested: action => root.action(["service", "wayvnc-remote", action])
                        onDetailsRequested: root.showDetail("service", root.remoteState.services.wayvnc)
                    }
                    Item { Layout.preferredHeight: 6 }
                }
            }
        }
    }

    Component {
        id: securityPage
        ColumnLayout {
            spacing: 9
            Heading {
                title: "Security"
                subtitle: "Issues and unverified claims first. Passed evidence stays collapsed until you need it."
                meta: `${root.passedChecks().length} passed`
            }
            ScrollView {
                id: securityScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: securityScroll.availableWidth
                    spacing: 9

                    Section {
                        title: root.issueChecks().length > 0 ? "Needs attention" : "Actionable findings"
                        detail: String(root.issueChecks().length)
                        iconName: root.issueChecks().length > 0 ? "warning" : "check_circle"
                    }
                    Rectangle {
                        visible: root.issueChecks().length === 0
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: Appearance.radius.control
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            MaterialSymbol { text: "check_circle"; iconSize: 17; color: Appearance.colors.colPrimary }
                            StyledText { Layout.fillWidth: true; text: "No actionable security findings"; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold }
                        }
                    }
                    Repeater {
                        model: root.issueChecks()
                        delegate: CheckRow { required property var modelData; item: modelData; onDetailsRequested: root.showDetail("check", modelData) }
                    }

                    Section {
                        visible: root.verificationChecks().length > 0
                        title: "Not verified"
                        detail: String(root.verificationChecks().length)
                        iconName: "fact_check"
                    }
                    Repeater {
                        model: root.verificationChecks()
                        delegate: CheckRow { required property var modelData; item: modelData; onDetailsRequested: root.showDetail("check", modelData) }
                    }

                    RowLayout {
                        visible: !root.remoteState.ssh.effective_verified
                        Layout.fillWidth: true
                        SmallButton { iconName: "fact_check"; label: "Verify effective SSH"; emphasized: true; onClicked: root.action(["verify-ssh-effective"]) }
                        StyledText { Layout.fillWidth: true; text: "Targeted sshd -T verification; Polkit may ask for authorization."; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest; elide: Text.ElideRight }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Section { title: "Passed checks"; detail: String(root.passedChecks().length); iconName: "verified" }
                        SmallButton {
                            iconName: root.showPassedChecks ? "expand_less" : "expand_more"
                            label: root.showPassedChecks ? "Hide passed" : `Show ${root.passedChecks().length} passed`
                            onClicked: root.showPassedChecks = !root.showPassedChecks
                        }
                    }
                    Repeater {
                        model: root.showPassedChecks ? root.passedChecks() : []
                        delegate: CheckRow { required property var modelData; item: modelData; onDetailsRequested: root.showDetail("check", modelData) }
                    }
                    Item { Layout.preferredHeight: 6 }
                }
            }
        }
    }

    Component {
        id: networkPage
        ColumnLayout {
            spacing: 9
            Heading {
                title: "Network & exposure"
                subtitle: "Service-first view. Individual sockets are evidence, not the primary navigation."
                meta: `${root.logicalListeners().length} logical service(s)`
            }
            ScrollView {
                id: networkScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: networkScroll.availableWidth
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 132
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: root.remoteState.tailscale.funnel.is_public ? Appearance.colors.colError : Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 6
                            InfoRow { label: "Tailscale"; value: root.remoteState.tailscale.connected ? (root.remoteState.tailscale.dns_name || root.remoteState.tailscale.hostname) : "Disconnected" }
                            InfoRow {
                                label: "Private Serve"
                                value: !root.remoteState.tailscale.serve.configured ? "Not configured"
                                    : root.remoteState.tailscale.serve.upstream_reachable ? `Reachable · ${root.remoteState.tailscale.serve.url}`
                                    : "Configured · upstream offline"
                            }
                            InfoRow { label: "Upstream"; value: root.remoteState.tailscale.serve.upstream || "None" }
                            InfoRow { label: "Public Funnel"; value: root.remoteState.tailscale.funnel.is_public ? "PUBLIC · review now" : "Off · tailnet only" }
                            InfoRow { label: "Router/NAT"; value: root.remoteState.exposure.router_nat_verified ? "Verified" : "Not verified externally" }
                        }
                    }

                    Section { title: "Private tailnet"; detail: String(root.listenersForGroup("private-network").length); iconName: "vpn_lock" }
                    Repeater {
                        model: root.listenersForGroup("private-network")
                        delegate: ListenerRow { required property var modelData; listener: modelData; onDetailsRequested: root.showDetail("listener", modelData) }
                    }

                    Section { title: "Local network"; detail: String(root.listenersForGroup("local-network").length); iconName: "router" }
                    Repeater {
                        model: root.listenersForGroup("local-network")
                        delegate: ListenerRow { required property var modelData; listener: modelData; onDetailsRequested: root.showDetail("listener", modelData) }
                    }

                    Section { title: "Loopback only"; detail: String(root.listenersForGroup("loopback").length); iconName: "developer_board" }
                    Repeater {
                        model: root.listenersForGroup("loopback")
                        delegate: ListenerRow { required property var modelData; listener: modelData; onDetailsRequested: root.showDetail("listener", modelData) }
                    }

                    Section { visible: root.listenersForGroup("unexpected").length > 0; title: "Unexpected exposure"; detail: String(root.listenersForGroup("unexpected").length); iconName: "error" }
                    Repeater {
                        model: root.listenersForGroup("unexpected")
                        delegate: ListenerRow { required property var modelData; listener: modelData; onDetailsRequested: root.showDetail("listener", modelData) }
                    }

                    Section { visible: root.listenersForGroup("other").length > 0; title: "Other listeners"; detail: String(root.listenersForGroup("other").length); iconName: "more_horiz" }
                    Repeater {
                        model: root.listenersForGroup("other")
                        delegate: ListenerRow { required property var modelData; listener: modelData; onDetailsRequested: root.showDetail("listener", modelData) }
                    }

                    Section { title: "Tailnet devices"; detail: String(root.remoteState.tailscale.devices.length); iconName: "devices" }
                    Repeater {
                        model: root.remoteState.tailscale.devices
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 62
                            radius: Appearance.radius.control
                            color: Appearance.colors.colLayer1Base
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showDetail("device", modelData) }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 9
                                MaterialSymbol {
                                    text: String(modelData.os).toLowerCase().includes("android") ? "smartphone" : "computer"
                                    iconSize: 18
                                    color: modelData.online ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.hostname + (modelData.is_self ? " · this PC" : "")
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.dns_name || (modelData.addresses.length ? modelData.addresses[0] : "No address")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        elide: Text.ElideMiddle
                                    }
                                }
                                Pill { label: modelData.online ? "Online" : "Offline"; state: modelData.online ? "active" : "neutral"; compact: true }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 6 }
                }
            }
        }
    }

    Component {
        id: phonePage
        ColumnLayout {
            spacing: 9
            Heading {
                title: "Phone"
                subtitle: "Task-oriented setup for Termux, Voyager, AVNC and the private share."
                meta: root.remoteState.tailscale.phone ? (root.remoteState.tailscale.phone.online ? "Phone online" : "Phone offline") : "Phone not detected"
            }
            ScrollView {
                id: phoneScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: phoneScroll.availableWidth
                    spacing: 10

                    Rectangle {
                        visible: root.remoteState.tailscale.phone !== null
                        Layout.fillWidth: true
                        implicitHeight: 74
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 10
                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: Appearance.radius.control
                                color: Appearance.colors.colLayer2Base
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "smartphone"
                                    iconSize: 20
                                    color: root.remoteState.tailscale.phone && root.remoteState.tailscale.phone.online ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.remoteState.tailscale.phone ? root.remoteState.tailscale.phone.hostname : "Phone"
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.remoteState.tailscale.phone ? root.lastSeenText(root.remoteState.tailscale.phone.last_seen) : ""
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    elide: Text.ElideRight
                                }
                            }
                            Pill {
                                label: root.remoteState.tailscale.phone && root.remoteState.tailscale.phone.online ? "Online" : "Offline"
                                state: root.remoteState.tailscale.phone && root.remoteState.tailscale.phone.online ? "active" : "neutral"
                            }
                        }
                    }

                    Section { title: "Readiness"; detail: "Evidence-derived · no intrusive phone probe"; iconName: "fact_check" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [
                                {label:"Tailscale", icon:"vpn_lock", state:root.remoteState.phone_guide.readiness.tailscale.state, confidence:root.remoteState.phone_guide.readiness.tailscale.confidence},
                                {label:"SSH", icon:"key", state:root.remoteState.phone_guide.readiness.ssh.state, confidence:root.remoteState.phone_guide.readiness.ssh.confidence},
                                {label:"SFTP", icon:"folder", state:root.remoteState.phone_guide.readiness.sftp.state, confidence:root.remoteState.phone_guide.readiness.sftp.confidence},
                                {label:"AVNC", icon:"desktop_windows", state:root.remoteState.phone_guide.readiness.avnc.state, confidence:root.remoteState.phone_guide.readiness.avnc.confidence},
                                {label:"Share", icon:"folder_shared", state:root.remoteState.phone_guide.readiness.share.state, confidence:root.remoteState.phone_guide.readiness.share.confidence}
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 58
                                radius: Appearance.radius.control
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        MaterialSymbol { text: modelData.icon; iconSize: 15; color: modelData.state === "ready" || modelData.state === "connected" || modelData.state === "observed" || modelData.state === "configured" || modelData.state === "available" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                                        StyledText { Layout.fillWidth: true; text: modelData.label; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    }
                                    StyledText { Layout.fillWidth: true; text: `${root.cap(modelData.state)} · ${modelData.confidence}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest; elide: Text.ElideRight }
                                }
                            }
                        }
                    }

                    Section { title: "Quick reference"; detail: "Everyday use"; iconName: "menu_book" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 154
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    InfoRow { label: "Terminal"; value: "archctl shell" }
                                    InfoRow { label: "Files"; value: "Voyager" }
                                    InfoRow { label: "Private Share"; value: "Generate QR" }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    InfoRow { label: "Desktop"; value: "archctl desktop-on → AVNC" }
                                    InfoRow { label: "Status"; value: "archctl status" }
                                    InfoRow { label: "Recovery"; value: "desktop-restart / share-restart" }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                SmallButton {
                                    iconName: "menu_book"
                                    label: "View all commands"
                                    emphasized: true
                                    onClicked: root.openReference("phone")
                                }
                            }
                        }
                    }

                    Section { title: "Termux · SSH"; iconName: "terminal" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 178
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 7
                            StyledText { text: "Persistent SSH alias"; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 90
                                radius: Appearance.radius.control
                                color: Appearance.colors.colLayer2Base
                                StyledText {
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    text: root.remoteState.phone_guide.ssh_config
                                    color: Appearance.colors.colOnLayer1
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    wrapMode: Text.WordWrap
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                SmallButton { iconName: "content_copy"; label: "Copy config"; onClicked: root.copyText(root.remoteState.phone_guide.ssh_config) }
                                SmallButton { iconName: "content_copy"; label: "Copy commands"; onClicked: root.copyText(root.remoteState.phone_guide.commands) }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }

                    Section { title: "Voyager · SFTP"; iconName: "folder" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 142
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 6
                            InfoRow { label: "Host"; value: root.remoteState.phone_guide.sftp.host || "Not detected" }
                            InfoRow { label: "Login"; value: `${root.remoteState.phone_guide.sftp.user} · port ${root.remoteState.phone_guide.sftp.port}` }
                            InfoRow { label: "Root path"; value: root.remoteState.phone_guide.sftp.root_path }
                            RowLayout {
                                Layout.fillWidth: true
                                SmallButton { iconName: "content_copy"; label: "Copy host"; onClicked: root.copyText(root.remoteState.phone_guide.sftp.host) }
                                SmallButton {
                                    visible: root.remoteState.phone_guide.sftp.fingerprint.length > 0
                                    iconName: "fingerprint"
                                    label: "Copy fingerprint"
                                    onClicked: root.copyText(root.remoteState.phone_guide.sftp.fingerprint)
                                }
                                Item { Layout.fillWidth: true }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Use Voyager’s own keypair. Private SSH keys are never shown or copied here."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Section { title: "AVNC · Remote desktop"; iconName: "desktop_windows" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 94
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 10
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    text: root.serviceTransitionName === "wayvnc-remote" && root.actionRunning ? (root.serviceTransitionAction === "start" ? "Starting…" : root.serviceTransitionAction === "stop" ? "Stopping…" : "Restarting…") : root.remoteState.phone_guide.vnc.ready ? "Remote desktop · Ready" : root.remoteState.phone_guide.vnc.running ? "Remote desktop · Degraded" : root.remoteState.phone_guide.vnc.state === "unavailable" ? "Remote desktop · Unavailable" : "Remote desktop · Off"
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.remoteState.phone_guide.vnc.endpoint || "No endpoint detected"
                                    color: Appearance.colors.colSubtext
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    elide: Text.ElideMiddle
                                }
                            }
                            SmallButton {
                                visible: !root.remoteState.phone_guide.vnc.running && root.remoteState.phone_guide.vnc.start_available
                                iconName: "play_arrow"
                                label: "Start"
                                emphasized: true
                                onClicked: root.action(["service", "wayvnc-remote", "start"])
                            }
                            SmallButton { iconName: "content_copy"; label: "Copy"; onClicked: root.copyText(root.remoteState.phone_guide.vnc.endpoint) }
                            SmallButton { visible: root.remoteState.phone_guide.vnc.state === "unavailable" || root.remoteState.phone_guide.vnc.state === "degraded"; iconName: "troubleshoot"; label: "Diagnostics"; onClicked: root.showDetail("service", root.remoteState.services.wayvnc) }
                        }
                    }

                    Section { title: "Private share"; iconName: "folder_shared" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: root.pairingState === "ready" ? 278 : 188
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: root.remoteState.tailscale.funnel.is_public
                            ? Appearance.colors.colError
                            : Appearance.colors.colLayer0Border

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 7
                                        StyledText {
                                            text: "Private Share"
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                        }
                                        Pill {
                                            label: root.remoteState.services.lan_share.ready
                                                && root.remoteState.phone_guide.share.tailnet_only
                                                ? "Ready · Tailnet only"
                                                : root.remoteState.services.lan_share.running
                                                    ? "Degraded"
                                                    : "Off"
                                            state: root.remoteState.services.lan_share.ready
                                                && root.remoteState.phone_guide.share.tailnet_only
                                                ? "active"
                                                : root.remoteState.services.lan_share.running
                                                    ? "danger"
                                                    : "neutral"
                                            compact: true
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.remoteState.phone_guide.share.url.length > 0
                                            ? root.remoteState.phone_guide.share.url
                                            : root.remoteState.phone_guide.share.pairing_reason
                                        color: Appearance.colors.colSubtext
                                        font.family: root.remoteState.phone_guide.share.url.length > 0
                                            ? Appearance.font.family.monospace
                                            : Appearance.font.family.main
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        elide: Text.ElideMiddle
                                    }
                                }

                                SmallButton {
                                    visible: root.remoteState.phone_guide.share.url.length > 0
                                        && root.remoteState.phone_guide.share.upstream_reachable
                                    iconName: "open_in_new"
                                    label: "Open"
                                    onClicked: root.openUrl(root.remoteState.phone_guide.share.url)
                                }
                                SmallButton {
                                    visible: root.remoteState.phone_guide.share.url.length > 0
                                    iconName: "content_copy"
                                    label: "Copy URL"
                                    onClicked: root.copyText(root.remoteState.phone_guide.share.url)
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Appearance.colors.colLayer0Border
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                StyledText {
                                    text: "ONE-SCAN PHONE ACCESS"
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                }
                                Item { Layout.fillWidth: true }
                                Pill {
                                    visible: root.pairingState !== "none"
                                    label: root.pairingState === "ready" ? "Pairing ready"
                                        : root.pairingState === "generating" ? "Generating"
                                        : root.pairingState === "expired" ? "Expired"
                                        : root.pairingState === "cancelled" ? "Cancelled"
                                        : root.pairingState === "error" ? "Error"
                                        : root.cap(root.pairingState)
                                    state: root.pairingState === "ready" ? "active"
                                        : root.pairingState === "error" ? "danger"
                                        : "neutral"
                                    compact: true
                                }
                            }

                            RowLayout {
                                visible: root.pairingState === "ready"
                                Layout.fillWidth: true
                                spacing: 14

                                Rectangle {
                                    Layout.preferredWidth: 142
                                    Layout.preferredHeight: 142
                                    radius: Appearance.radius.control
                                    color: "white"
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        source: root.pairingQrSource
                                        fillMode: Image.PreserveAspectFit
                                        cache: false
                                        asynchronous: false
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Scan to connect automatically"
                                        color: Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: `${root.pairingSingleUse ? "Single use" : "One-time access"} · expires in ${root.formatPairingCountdown(root.pairingRemainingSeconds)}`
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "The QR contains a temporary authentication credential. The permanent Serve URL above does not."
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        wrapMode: Text.WordWrap
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        SmallButton {
                                            iconName: "qr_code_2"
                                            label: "Generate new"
                                            emphasized: true
                                            enabled: !root.pairingBusy && !root.actionRunning
                                            onClicked: root.generatePairing()
                                        }
                                        SmallButton {
                                            iconName: "close"
                                            label: root.pairingBusy && root.pairingOperation === "cancel"
                                                ? "Cancelling…"
                                                : "Cancel pairing"
                                            enabled: !root.pairingBusy && !root.actionRunning
                                            onClicked: root.cancelPairing()
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }

                            RowLayout {
                                visible: root.pairingState !== "ready"
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.pairingState === "generating"
                                            ? "Generating secure pairing…"
                                            : root.pairingState === "expired"
                                                ? "Pairing expired"
                                                : root.pairingState === "cancelled"
                                                    ? (root.pairingBackendRevoked ? "Pairing cancelled" : "Pairing dismissed locally")
                                                    : root.pairingState === "error"
                                                        ? "Cannot generate pairing QR"
                                                        : root.remoteState.phone_guide.share.pairing_available
                                                            ? "No active pairing"
                                                            : "Pairing unavailable"
                                        color: root.pairingState === "error"
                                            ? Appearance.colors.colError
                                            : Appearance.colors.colOnLayer1
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.pairingState === "cancelled" && !root.pairingBackendRevoked
                                            ? "The QR was removed locally. The server credential expires automatically or is invalidated by the next QR."
                                            : root.pairingState === "error"
                                                ? root.pairingError
                                                : root.pairingState === "expired"
                                                    ? "The expired credential was removed from memory. Generate a new QR when needed."
                                                    : root.remoteState.phone_guide.share.pairing_available
                                                        ? "Generate a short-lived, single-use QR only when you want to connect a phone."
                                                        : root.remoteState.phone_guide.share.pairing_reason
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                SmallButton {
                                    visible: root.remoteState.phone_guide.share.pairing_available
                                        && root.pairingState !== "generating"
                                    iconName: "qr_code_2"
                                    label: root.pairingState === "expired" || root.pairingState === "cancelled" || root.pairingState === "error"
                                        ? "Generate new QR"
                                        : "Generate QR"
                                    emphasized: true
                                    enabled: !root.pairingBusy && !root.actionRunning
                                    onClicked: root.generatePairing()
                                }

                                SmallButton {
                                    visible: !root.remoteState.services.lan_share.running
                                    iconName: "play_arrow"
                                    label: "Start Share"
                                    emphasized: true
                                    onClicked: root.action(["service", "lan-share", "start"])
                                }

                                SmallButton {
                                    visible: root.remoteState.services.lan_share.running
                                        && !root.remoteState.phone_guide.share.pairing_available
                                        && !root.remoteState.phone_guide.share.configured
                                    iconName: "lan"
                                    label: "View Network"
                                    onClicked: root.switchPage(3)
                                }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 6 }
                }
            }
        }
    }

    Component {
        id: logsPage
        ColumnLayout {
            spacing: 9
            Heading {
                title: "Logs"
                subtitle: "Bounded journal diagnostics stay inside the control center."
                meta: root.logsLoading ? "Refreshing…" : `${root.logEntryCount} entr${root.logEntryCount === 1 ? "y" : "ies"}`
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                Layout.maximumHeight: 38
                Layout.alignment: Qt.AlignTop
                spacing: 5
                Repeater {
                    model: [
                        {id:"sshd", label:"SSH"},
                        {id:"tailscaled", label:"Tailscale"},
                        {id:"lan-share", label:"Share"},
                        {id:"wayvnc", label:"WayVNC"}
                    ]
                    delegate: RippleButton {
                        id: tab
                        required property var modelData
                        Layout.preferredWidth: 96
                        implicitHeight: 38
                        activeFocusOnTab: true
                        readonly property bool selected: root.selectedLogService === modelData.id
                        buttonRadius: Appearance.radius.control
                        buttonRadiusPressed: Appearance.radius.control
                        colBackground: selected ? Appearance.colors.colLayer2Base : "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: { root.selectedLogService = modelData.id; root.requestLogs() }
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: tab.modelData.label
                            color: tab.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: tab.selected ? Font.DemiBold : Font.Normal
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                Layout.maximumHeight: 38
                Layout.alignment: Qt.AlignTop
                spacing: 6
                SmallButton {
                    iconName: "filter_alt"
                    label: root.logSeverity === "all" ? "All levels" : root.logSeverity === "warning" ? "Warnings+" : "Errors"
                    onClicked: {
                        root.logSeverity = root.logSeverity === "all" ? "warning" : root.logSeverity === "warning" ? "error" : "all"
                        root.requestLogs()
                    }
                }
                SmallButton {
                    iconName: "schedule"
                    label: root.logWindow
                    onClicked: {
                        root.logWindow = root.logWindow === "1h" ? "6h" : root.logWindow === "6h" ? "24h" : "1h"
                        root.requestLogs()
                    }
                }
                TextField {
                    id: logSearchField
                    Layout.fillWidth: true
                    implicitHeight: 38
                    placeholderText: "Search this bounded window…"
                    activeFocusOnTab: true
                    Accessible.name: "Search Arch Remote logs"
                    text: root.logSearch
                    color: Appearance.colors.colOnLayer1
                    selectByMouse: true
                    onAccepted: { root.logSearch = text; root.requestLogs() }
                    background: Rectangle {
                        radius: Appearance.radius.control
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: logSearchField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                    }
                }
                SmallButton {
                    iconName: root.logFollow ? "pause" : "play_arrow"
                    label: root.logFollow ? "Follow ●" : "Follow"
                    emphasized: root.logFollow
                    onClicked: root.logFollow = !root.logFollow
                }
                SmallButton { iconName: "content_copy"; label: "Copy"; onClicked: root.copyText(root.logText) }
                SmallButton { iconName: "download"; label: "Export"; onClicked: root.exportLogs() }
            }

            Repeater {
                model: root.logKnownIssues
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: Appearance.radius.control
                    color: Appearance.colors.colLayer1Base
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 9
                        MaterialSymbol { text: modelData.severity === "warning" ? "warning" : "info"; iconSize: 18; color: Appearance.colors.colSubtext }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText { text: modelData.title; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold }
                            StyledText { Layout.fillWidth: true; text: `${modelData.detail} ${modelData.recovery}`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest; wrapMode: Text.WordWrap }
                        }
                        SmallButton {
                            visible: modelData.action === "restart-wayvnc" || modelData.action === "restart-share"
                            iconName: "restart_alt"
                            label: "Restart"
                            onClicked: root.action(["service", modelData.action === "restart-wayvnc" ? "wayvnc-remote" : "lan-share", "restart"])
                        }
                    }
                }
            }

            Rectangle {
                visible: !root.logsLoading && root.logEntryCount === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 98
                Layout.maximumHeight: 98
                Layout.alignment: Qt.AlignTop
                implicitHeight: 98
                radius: Appearance.radius.card
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 10
                    MaterialSymbol { text: "description"; iconSize: 20; color: Appearance.colors.colSubtext }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText { Layout.fillWidth: true; text: `No ${root.selectedLogService} entries in ${root.logWindow}`; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold }
                        StyledText { Layout.fillWidth: true; text: root.logSearch.length > 0 ? "No entries match the current search." : "No recent journal activity is a valid state."; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest; elide: Text.ElideRight }
                    }
                    SmallButton { visible: root.logWindow !== "6h"; iconName: "schedule"; label: "Show 6h"; onClicked: { root.logWindow = "6h"; root.requestLogs() } }
                    SmallButton { visible: root.logWindow !== "24h"; iconName: "history"; label: "Show 24h"; onClicked: { root.logWindow = "24h"; root.requestLogs() } }
                    SmallButton { iconName: "refresh"; label: "Refresh"; onClicked: root.requestLogs() }
                }
            }

            Item {
                visible: !root.logsLoading && root.logEntryCount === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            Rectangle {
                visible: root.logsLoading || root.logEntryCount > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.radius.card
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                clip: true
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    ScrollBar.horizontal.policy: root.logWrap ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    TextEdit {
                        width: root.logWrap ? parent.width : Math.max(parent.width, implicitWidth)
                        text: root.logsLoading ? "Loading bounded journal entries…" : root.logText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: root.logWrap ? TextEdit.Wrap : TextEdit.NoWrap
                        color: Appearance.colors.colOnLayer1
                        selectionColor: Appearance.colors.colSecondaryContainer
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }

    Component {
        id: powerPage
        ColumnLayout {
            spacing: 9
            Heading {
                title: "Power & wake"
                subtitle: "Capability, configuration and end-to-end verification are separate claims."
                meta: `Slow state · ${root.ageText(root.remoteState.slow_checked_at)}`
            }
            ScrollView {
                id: powerScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: powerScroll.availableWidth
                    spacing: 10

                    Section { title: "Ethernet WoL"; detail: root.remoteState.wake.ethernet.interface_name || "No interface"; iconName: "settings_ethernet" }
                    SmallButton { iconName: "info"; label: "Ethernet evidence"; onClicked: root.showDetail("wake", root.remoteState.wake.ethernet) }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 142
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Metric { iconName: "memory"; label: "Capability"; value: root.remoteState.wake.ethernet.capability === "supported" ? "Supported" : root.remoteState.wake.ethernet.capability === "unsupported" ? "Unsupported" : "Unknown"; subtitle: root.wakeCapabilityLabel(root.remoteState.wake.ethernet); state: root.remoteState.wake.ethernet.capability === "supported" ? "active" : "neutral" }
                                Metric { iconName: "settings"; label: "Configuration"; value: root.remoteState.wake.ethernet.configured === "enabled" ? "Enabled" : root.remoteState.wake.ethernet.configured === "disabled" ? "Disabled" : "Unknown"; subtitle: root.remoteState.wake.ethernet.raw_current ? `Wake-on: ${root.remoteState.wake.ethernet.raw_current}` : "Link down / unavailable"; state: root.remoteState.wake.ethernet.configured === "enabled" ? "active" : "neutral" }
                                Metric { iconName: "fact_check"; label: "Verification"; value: root.remoteState.wake.ethernet.test_status === "untested" ? "Not tested" : root.cap(root.remoteState.wake.ethernet.test_status); subtitle: "End-to-end wake path"; state: "neutral" }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.remoteState.wake.ethernet.interface_name ? `Interface ${root.remoteState.wake.ethernet.interface_name} · capability can be unknown while Ethernet is disconnected.` : "No physical Ethernet interface was detected."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Section { title: "Wi-Fi WoWLAN"; detail: root.remoteState.wake.wifi.interface_name || "No interface"; iconName: "wifi" }
                    SmallButton { iconName: "info"; label: "Wi-Fi evidence"; onClicked: root.showDetail("wake", root.remoteState.wake.wifi) }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 142
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Metric { iconName: "memory"; label: "Capability"; value: root.remoteState.wake.wifi.capability === "supported" ? "Supported" : root.remoteState.wake.wifi.capability === "unsupported" ? "Unsupported" : "Unknown"; subtitle: root.wakeCapabilityLabel(root.remoteState.wake.wifi); state: root.remoteState.wake.wifi.capability === "supported" ? "active" : "neutral" }
                                Metric { iconName: "settings"; label: "Configuration"; value: root.remoteState.wake.wifi.configured === "enabled" ? "Enabled" : root.remoteState.wake.wifi.configured === "disabled" ? "Disabled" : "Unknown"; subtitle: root.remoteState.wake.wifi.persistent ? "Dispatcher persistence installed" : "Persistence not detected"; state: root.remoteState.wake.wifi.configured === "enabled" ? "active" : "neutral" }
                                Metric { iconName: "fact_check"; label: "Verification"; value: root.remoteState.wake.wifi.test_status === "untested" ? "Not tested" : root.cap(root.remoteState.wake.wifi.test_status); subtitle: "End-to-end wake path"; state: "neutral" }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.remoteState.wake.wifi.error ? root.remoteState.wake.wifi.error : `PHY ${root.remoteState.wake.wifi.phy || "unknown"} · current state read dynamically.`
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Section { title: "Lid policy"; detail: root.remoteState.lid.pending_reboot ? "Pending reboot" : root.remoteState.lid.status; iconName: "laptop" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 154
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 7
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText { Layout.fillWidth: true; text: "Configured policy"; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold }
                                Pill { label: root.remoteState.lid.pending_reboot ? "Pending reboot" : root.remoteState.lid.effective.verified ? "Effective verified" : "Not verified"; state: root.remoteState.lid.effective.verified ? "active" : "neutral"; compact: true }
                            }
                            InfoRow { label: "On battery"; value: root.remoteState.lid.configured.battery }
                            InfoRow { label: "External power"; value: root.remoteState.lid.configured.external_power }
                            InfoRow { label: "Docked"; value: root.remoteState.lid.configured.docked }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.remoteState.lid.pending_reboot ? "The drop-in is newer than the current logind instance. Reboot later to apply it safely; logind is never restarted automatically here." : "Configured and effective state are reported separately."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 72
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 11
                            spacing: 9
                            MaterialSymbol { text: "info"; iconSize: 18; color: Appearance.colors.colSubtext }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Tailscale does not wake a sleeping laptop by itself. A tested always-awake sender on the home network is still required for a real remote-wake path."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.remoteState.linger.enabled ? "User-service persistence: linger enabled." : "User-service persistence needs review; linger is not enabled."
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                    Item { Layout.preferredHeight: 6 }
                }
            }
        }
    }
}
