//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ApplicationWindow {
    id: root

    title: "Nyvorel Welcome"
    visible: true
    color: "transparent"
    minimumWidth: 700
    minimumHeight: 530
    width: 1000
    height: 670

    readonly property string managerPath:
        FileUtils.trimFileProtocol(Directories.scriptPath)
        + "/system/nyvorel-appearance-studio"
    readonly property bool motionEnabled: !Appearance.reducedMotion
    property int currentStep: 0
    property int nextStep: 0
    property int stepDirection: 1
    property bool closing: false
    property bool allowImmediateClose: false
    property bool pendingClose: false
    property bool statusLoaded: false
    property bool previewActive: false
    property bool previewQueued: false
    property real previewExpiresAt: 0
    property int previewSeconds: 0
    property string selectedProfile:
        Config.options.appearance.interfaceStyle === "default"
            ? "default" : "fluid"
    property string originalProfile: selectedProfile
    property string selectedMode:
        Appearance.m3colors.darkmode ? "dark" : "light"
    property string originalMode: selectedMode
    property string selectedScheme: "auto"
    property var studioStatus: ({})
    property string notice: ""
    property bool noticeError: false

    readonly property bool busy: previewProc.running || controlProc.running
    readonly property string stepTitle:
        currentStep === 0 ? "Welcome"
        : currentStep === 1 ? "Make it yours"
        : "Ready"

    function fitToScreen() {
        if (!root.screen)
            return
        const geometry = root.screen.availableGeometry ?? root.screen.geometry
        if (!geometry)
            return
        root.width = Math.min(1000, Math.max(root.minimumWidth, geometry.width - 72))
        root.height = Math.min(670, Math.max(root.minimumHeight, geometry.height - 72))
    }

    function setStep(index) {
        if (index < 0 || index > 2 || index === currentStep || stepTransition.running)
            return
        root.nextStep = index
        root.stepDirection = index > currentStep ? 1 : -1
        stepTransition.restart()
    }

    function profilePatch(profileId) {
        const profiles = studioStatus.uiProfiles ?? []
        for (let i = 0; i < profiles.length; ++i) {
            if (profiles[i].id === profileId)
                return profiles[i].patch ?? ({})
        }
        return null
    }

    function requestPreview() {
        if (!statusLoaded)
            return
        if (previewProc.running || controlProc.running) {
            previewQueued = true
            return
        }

        const patch = profilePatch(selectedProfile)
        if (!patch) {
            notice = "Appearance profiles are unavailable. You can set them in Appearance Studio."
            noticeError = true
            return
        }

        notice = "Building your live preview…"
        noticeError = false
        previewProc.resultText = ""
        const command = [
            "/usr/bin/env", managerPath, "apply",
            "--source", "wallpaper",
            "--mode", selectedMode,
            "--scheme", selectedScheme,
            "--ui-json", JSON.stringify(patch),
            "--preview"
        ]
        previewProc.command = command
        previewProc.running = true
    }

    function chooseProfile(profileId) {
        if (selectedProfile === profileId)
            return
        selectedProfile = profileId
        previewDebounce.restart()
    }

    function chooseMode(mode) {
        if (selectedMode === mode)
            return
        selectedMode = mode
        previewDebounce.restart()
    }

    function runControl(action) {
        if (controlProc.running)
            return
        controlProc.action = action
        controlProc.resultText = ""
        controlProc.command = ["/usr/bin/env", managerPath, action]
        controlProc.running = true
    }

    function continueFlow() {
        if (currentStep === 0) {
            setStep(1)
            return
        }
        if (currentStep === 1) {
            if (busy || previewQueued || previewDebounce.running)
                return
            if (previewActive) {
                runControl("keep-preview")
                return
            }
            setStep(2)
            return
        }
        requestClose()
    }

    function revertLook() {
        previewDebounce.stop()
        previewQueued = false
        if (busy)
            return
        if (previewActive) {
            runControl("revert-preview")
        } else {
            selectedProfile = originalProfile
            selectedMode = originalMode
            notice = ""
        }
    }

    function requestClose() {
        if (closing || allowImmediateClose)
            return
        if (busy) {
            pendingClose = true
            return
        }
        if (previewActive) {
            pendingClose = true
            runControl("revert-preview")
            return
        }
        closing = true
        closeAnimation.restart()
    }

    onClosing: event => {
        if (allowImmediateClose) {
            event.accepted = true
            return
        }
        event.accepted = false
        requestClose()
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        root.fitToScreen()
        Config.readWriteDelay = 0
        frame.opacity = root.motionEnabled ? 0 : 1
        frame.scale = root.motionEnabled ? 0.965 : 1
        frameLift.y = root.motionEnabled ? 20 : 0
        Qt.callLater(() => {
            openAnimation.restart()
            frameFocus.forceActiveFocus()
        })
    }

    Process {
        id: statusProc
        running: true
        command: ["/usr/bin/env", root.managerPath, "status"]
        property string resultText: ""
        stdout: StdioCollector {
            onStreamFinished: statusProc.resultText = text
        }
        onExited: (exitCode, exitStatus) => {
            try {
                const data = JSON.parse(resultText)
                if (exitCode !== 0 || data.ok === false)
                    throw new Error(data.error ?? "Appearance status unavailable")
                root.studioStatus = data
                root.selectedScheme = data.active?.scheme ?? "auto"
                const profile = data.active?.uiProfile
                    ?? Config.options.appearance.interfaceStyle
                root.selectedProfile = profile === "default" ? "default" : "fluid"
                root.originalProfile = root.selectedProfile
                const mode = data.active?.mode
                root.selectedMode = mode === "light" ? "light" : "dark"
                root.originalMode = root.selectedMode
                root.statusLoaded = true
            } catch (error) {
                root.notice = "Appearance preview is unavailable. Other setup steps still work."
                root.noticeError = true
            }
        }
    }

    Process {
        id: previewProc
        property string resultText: ""
        stdout: StdioCollector {
            onStreamFinished: previewProc.resultText = text
        }
        onExited: (exitCode, exitStatus) => {
            try {
                const result = JSON.parse(resultText)
                if (exitCode !== 0 || result.ok === false)
                    throw new Error(result.error ?? "Preview failed")
                const preview = result.previewState ?? ({})
                root.previewActive = true
                root.previewExpiresAt = preview.expiresAt ?? 0
                root.previewSeconds = Math.max(
                    0, Math.ceil(root.previewExpiresAt - Date.now() / 1000)
                )
                root.notice = "Preview active. Keep this look to save it."
                root.noticeError = false
            } catch (error) {
                root.notice = String(error.message ?? error)
                root.noticeError = true
            }
            if (root.pendingClose) {
                Qt.callLater(() => root.requestClose())
            } else if (root.previewQueued) {
                root.previewQueued = false
                previewDebounce.restart()
            }
        }
    }

    Process {
        id: controlProc
        property string action: ""
        property string resultText: ""
        stdout: StdioCollector {
            onStreamFinished: controlProc.resultText = text
        }
        onExited: (exitCode, exitStatus) => {
            try {
                const result = JSON.parse(resultText)
                if (exitCode !== 0 || result.ok === false)
                    throw new Error(result.error ?? "Could not update appearance")
                root.previewActive = false
                root.previewSeconds = 0
                root.previewExpiresAt = 0
                root.notice = ""
                root.noticeError = false
                if (action === "keep-preview") {
                    root.originalProfile = root.selectedProfile
                    root.originalMode = root.selectedMode
                    root.setStep(2)
                } else {
                    root.selectedProfile = root.originalProfile
                    root.selectedMode = root.originalMode
                }
            } catch (error) {
                root.notice = String(error.message ?? error)
                root.noticeError = true
                // The backend watchdog restores an unkept preview. Do not
                // trap a closing window in a repeated failed revert request.
                if (root.pendingClose && action === "revert-preview")
                    root.previewActive = false
            }
            if (root.pendingClose) {
                root.pendingClose = false
                Qt.callLater(() => root.requestClose())
            }
        }
    }

    Timer {
        id: previewDebounce
        interval: 260
        onTriggered: root.requestPreview()
    }

    Timer {
        interval: 500
        running: root.previewActive
        repeat: true
        onTriggered: {
            root.previewSeconds = Math.max(
                0, Math.ceil(root.previewExpiresAt - Date.now() / 1000)
            )
            if (root.previewSeconds === 0) {
                root.previewActive = false
                root.notice = "Preview expired. Choose a look to try again."
                root.noticeError = false
            }
        }
    }

    Item {
        id: frame
        anchors.fill: parent
        opacity: 1
        scale: 1
        transformOrigin: Item.Center
        transform: Translate { id: frameLift; y: 0 }

        ParallelAnimation {
            id: openAnimation
            MotionAnim {
                target: frame
                property: "opacity"
                to: 1
                type: MotionAnim.DefaultEffects
            }
            MotionAnim {
                target: frame
                property: "scale"
                to: 1
                type: MotionAnim.DefaultSpatial
            }
            MotionAnim {
                target: frameLift
                property: "y"
                to: 0
                type: MotionAnim.DefaultSpatial
            }
        }

        ParallelAnimation {
            id: closeAnimation
            MotionAnim {
                target: frame
                property: "opacity"
                to: 0
                type: MotionAnim.FastEffects
            }
            MotionAnim {
                target: frame
                property: "scale"
                to: 0.98
                type: MotionAnim.FastEffects
            }
            MotionAnim {
                target: frameLift
                property: "y"
                to: 8
                type: MotionAnim.FastEffects
            }
            onFinished: {
                root.allowImmediateClose = true
                Qt.quit()
            }
        }

        Rectangle {
            id: frameSurface
            anchors.fill: parent
            radius: Appearance.radius.modal
            antialiasing: true
            color: Appearance.colors.colLayer0Base
            border.width: 1
            border.color: Appearance.fluidMode
                ? Appearance.colors.fluidBorderStrong
                : Appearance.colors.colLayer0Border
            clip: true

            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: root.width >= 830 ? 270 : 205
                color: Appearance.colors.colLayer1Base
            }

            Rectangle {
                x: root.width >= 830 ? 269 : 204
                width: 1
                height: parent.height
                color: Appearance.colors.colLayer0Border
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.preferredWidth: root.width >= 830 ? 270 : 205
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: root.width >= 830 ? 28 : 20
                        }
                        spacing: 0

                        RowLayout {
                            spacing: root.width >= 830 ? 12 : 8
                            Image {
                                source: Quickshell.shellPath(
                                    "assets/icons/nyvorel.svg"
                                )
                                sourceSize.width: root.width >= 830 ? 42 : 34
                                sourceSize.height: root.width >= 830 ? 42 : 34
                                Layout.preferredWidth: root.width >= 830 ? 42 : 34
                                Layout.preferredHeight: root.width >= 830 ? 42 : 34
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: "NYVOREL"
                                    color: Appearance.colors.colOnLayer0
                                    font.family: Appearance.font.family.title
                                    font.pixelSize: root.width >= 830 ? 17 : 15
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: root.width >= 830 ? 2.4 : 1.7
                                }
                                Text {
                                    text: "YOUR DESKTOP, YOUR WAY"
                                    color: Appearance.colors.colSubtext
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: root.width >= 830 ? 9 : 7
                                    font.letterSpacing: root.width >= 830 ? 1.0 : 0.5
                                }
                            }
                        }

                        Item {
                            Layout.preferredHeight: root.height >= 600 ? 54 : 30
                        }

                        Text {
                            text: root.height >= 600
                                ? "A quieter place\nto begin."
                                : "A quieter\nplace to begin."
                            color: Appearance.colors.colOnLayer0
                            font.family: Appearance.font.family.title
                            font.pixelSize: root.width >= 830 ? 29
                                : root.height >= 600 ? 25 : 22
                            font.weight: Font.Medium
                            lineHeight: 1.08
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            text: "A few thoughtful choices, then the desktop is yours."
                            color: Appearance.colors.colSubtext
                            font.family: Appearance.font.family.main
                            font.pixelSize: root.height >= 600 ? 13 : 12
                            lineHeight: 1.35
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            wrapMode: Text.WordWrap
                        }

                        Item {
                            Layout.preferredHeight: root.height >= 600 ? 48 : 27
                        }

                        Repeater {
                            model: [
                                { title: "Welcome", icon: "waving_hand" },
                                { title: "Make it yours", icon: "palette" },
                                { title: "Ready", icon: "check_circle" }
                            ]
                            delegate: Item {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.height >= 600 ? 54 : 48

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 11
                                    Rectangle {
                                        Layout.preferredWidth: 27
                                        Layout.preferredHeight: 27
                                        radius: 14
                                        color: index <= root.currentStep
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colLayer2Base
                                        border.width: index > root.currentStep ? 1 : 0
                                        border.color: Appearance.colors.colLayer0Border
                                        Text {
                                            anchors.centerIn: parent
                                            text: String(index + 1)
                                            color: index <= root.currentStep
                                                ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colSubtext
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }
                                        Behavior on color {
                                            MotionColorAnim {
                                                type: MotionColorAnim.DefaultEffects
                                            }
                                        }
                                    }
                                    Text {
                                        text: modelData.title
                                        color: index === root.currentStep
                                            ? Appearance.colors.colOnLayer0
                                            : Appearance.colors.colSubtext
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: 13
                                        font.weight: index === root.currentStep
                                            ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            visible: root.height >= 600
                            color: Appearance.colors.colLayer0Border
                        }
                        Text {
                            Layout.topMargin: 16
                            Layout.fillWidth: true
                            visible: root.height >= 600
                            text: "Everything can be changed later in Settings."
                            color: Appearance.colors.colSubtext
                            font.family: Appearance.font.family.main
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors {
                            fill: parent
                            leftMargin: root.width >= 830 ? 42 : 24
                            rightMargin: root.width >= 830 ? 42 : 24
                            topMargin: 25
                            bottomMargin: 25
                        }
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "FIRST RUN  /  " + String(root.currentStep + 1).padStart(2, "0")
                                    + " OF 03"
                                color: Appearance.colors.colSubtext
                                font.family: Appearance.font.family.main
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.7
                                Layout.fillWidth: true
                            }
                            WelcomeButton {
                                label: "Skip setup"
                                quiet: true
                                compact: true
                                onClicked: root.requestClose()
                            }
                        }

                        Rectangle {
                            Layout.topMargin: 19
                            Layout.fillWidth: true
                            Layout.preferredHeight: 2
                            radius: 1
                            color: Appearance.colors.colLayer2Base
                            Rectangle {
                                height: parent.height
                                width: parent.width * (root.currentStep + 1) / 3
                                radius: 1
                                color: Appearance.colors.colPrimary
                                Behavior on width {
                                    MotionAnim { type: MotionAnim.DefaultSpatial }
                                }
                            }
                        }

                        Item {
                            id: contentShell
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.topMargin: 26
                            clip: true
                            opacity: 1
                            transform: Translate { id: stepShift; x: 0 }

                            SequentialAnimation {
                                id: stepTransition
                                ParallelAnimation {
                                    MotionAnim {
                                        target: contentShell
                                        property: "opacity"
                                        to: 0
                                        type: MotionAnim.FastEffects
                                    }
                                    MotionAnim {
                                        target: stepShift
                                        property: "x"
                                        to: -14 * root.stepDirection
                                        type: MotionAnim.FastSpatial
                                    }
                                }
                                ScriptAction {
                                    script: {
                                        root.currentStep = root.nextStep
                                        stepShift.x = 18 * root.stepDirection
                                    }
                                }
                                ParallelAnimation {
                                    MotionAnim {
                                        target: contentShell
                                        property: "opacity"
                                        to: 1
                                        type: MotionAnim.DefaultEffects
                                    }
                                    MotionAnim {
                                        target: stepShift
                                        property: "x"
                                        to: 0
                                        type: MotionAnim.DefaultSpatial
                                    }
                                }
                            }

                            Loader {
                                anchors.fill: parent
                                sourceComponent:
                                    root.currentStep === 0 ? welcomePage
                                    : root.currentStep === 1 ? personalizePage
                                    : readyPage
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            spacing: 10
                            WelcomeButton {
                                label: "Back"
                                iconName: "arrow_back"
                                quiet: true
                                visible: root.currentStep > 0
                                onClicked: root.setStep(root.currentStep - 1)
                            }
                            Item { Layout.fillWidth: true }
                            WelcomeButton {
                                label: root.currentStep === 2 ? "Enter Nyvorel"
                                    : root.currentStep === 1
                                    ? (root.previewActive ? "Keep this look" : "Continue")
                                    : "Get started"
                                iconName: root.currentStep === 2 ? "arrow_forward"
                                    : "arrow_forward"
                                primary: true
                                enabled: !root.busy
                                    && !root.previewQueued
                                    && !previewDebounce.running
                                onClicked: root.continueFlow()
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: welcomePage
        Item {
            Flickable {
                id: welcomeFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: welcomeContent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: welcomeFlick.contentHeight > welcomeFlick.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: welcomeContent
                    width: welcomeFlick.width
                    height: Math.max(welcomeFlick.height, implicitHeight)
                    spacing: 0
                    Item { Layout.fillHeight: true }
                    Text {
                        text: "Welcome to\na desktop that feels like yours."
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.width >= 830 ? 36
                            : root.height >= 600 ? 31 : 28
                        font.weight: Font.Medium
                        lineHeight: 1.06
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        text: "Choose the atmosphere you want. Nyvorel will shape the shell around it."
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: root.height >= 600 ? 15 : 13
                        Layout.fillWidth: true
                        Layout.topMargin: root.height >= 600 ? 16 : 10
                        wrapMode: Text.WordWrap
                    }
                    Item {
                        Layout.preferredHeight: root.height >= 600 ? 34 : 18
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.height >= 600 ? 132 : 100
                        radius: Appearance.radius.card
                        color: Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: Quickshell.shellPath(
                                "assets/images/default_wallpaper.png"
                            )
                            fillMode: Image.PreserveAspectCrop
                            opacity: 0.42
                            smooth: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: Appearance.colors.colLayer1Base
                            opacity: 0.48
                        }
                        RowLayout {
                            anchors {
                                fill: parent
                                margins: 22
                            }
                            spacing: 18
                            MaterialSymbol {
                                text: "auto_awesome"
                                iconSize: 30
                                color: Appearance.colors.colPrimary
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Text {
                                    text: "A live preview, with a way back."
                                    color: Appearance.colors.colOnLayer0
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "Try Default or Fluid. Keep the result only when it feels right."
                                    color: Appearance.colors.colSubtext
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                    Item {
                        Layout.preferredHeight: root.height >= 600 ? 26 : 16
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 9

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            MaterialSymbol {
                                text: "language"
                                iconSize: 20
                                color: Appearance.colors.colSubtext
                            }
                            Text {
                                text: "Shell language"
                                Layout.preferredWidth: 125
                                color: Appearance.colors.colOnLayer0
                                font.family: Appearance.font.family.main
                                font.pixelSize: 13
                            }
                            StyledComboBox {
                                id: languageSelector
                                Layout.fillWidth: true
                                Layout.maximumWidth: 260
                                buttonRadius: Appearance.radius.control
                                openUpward: true
                                textRole: "displayName"
                                model: [
                                    { displayName: Translation.tr("System language"), value: "auto" },
                                    ...Translation.allAvailableLanguages.map(lang => {
                                        return {
                                            displayName: Translation.displayLanguage(lang),
                                            value: lang
                                        }
                                    })
                                ]
                                currentIndex: {
                                    const index = model.findIndex(
                                        item => item.value === Config.options.language.ui
                                    )
                                    return index >= 0 ? index : 0
                                }
                                onActivated: index => {
                                    Config.options.language.ui = model[index].value
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Current shell language: "
                                + (Translation.allAvailableLanguages.includes(Translation.languageCode)
                                    ? Translation.displayLanguage(Translation.languageCode)
                                    : "English (fallback)")
                            color: Appearance.colors.colSubtext
                            font.family: Appearance.font.family.main
                            font.pixelSize: 11
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            MaterialSymbol {
                                text: "keyboard"
                                iconSize: 20
                                color: Appearance.colors.colSubtext
                            }
                            Text {
                                text: "Keyboard layout"
                                Layout.preferredWidth: 125
                                color: Appearance.colors.colOnLayer0
                                font.family: Appearance.font.family.main
                                font.pixelSize: 13
                            }
                            KeyboardLayoutSelector {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 260
                                openUpward: true
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: KeyboardLayout.lastError.length > 0
                            text: KeyboardLayout.lastError
                            color: Appearance.m3colors.m3error
                            font.family: Appearance.font.family.main
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    Component {
        id: personalizePage
        Item {
            Flickable {
                id: personalizeFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: personalizeContent.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: personalizeFlick.contentHeight > personalizeFlick.height
                        ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                    active: true
                    width: 4
                    contentItem: Rectangle {
                        implicitWidth: 3
                        radius: 2
                        color: Appearance.colors.colPrimary
                    }
                }
                ColumnLayout {
                    id: personalizeContent
                    width: parent.width
                    spacing: 0

                    Text {
                        text: "Make it yours."
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.title
                        font.pixelSize: 32
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    Text {
                        text: "Choose a shell style. The desktop changes while you preview it."
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: 13
                        Layout.fillWidth: true
                        Layout.topMargin: 7
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: root.height >= 600 ? 24 : 18
                        spacing: 12
                        WelcomeProfile {
                            Layout.fillWidth: true
                            profileName: "Default"
                            description: "Clear surfaces and a calm, focused layout."
                            fluid: false
                            selected: root.selectedProfile === "default"
                            enabled: root.statusLoaded
                            onClicked: root.chooseProfile("default")
                        }
                        WelcomeProfile {
                            Layout.fillWidth: true
                            profileName: "Fluid"
                            description: "A lighter surface that lets the wallpaper breathe."
                            fluid: true
                            selected: root.selectedProfile === "fluid"
                            enabled: root.statusLoaded
                            onClicked: root.chooseProfile("fluid")
                        }
                    }

                    Text {
                        text: "Appearance"
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        Layout.topMargin: root.height >= 600 ? 25 : 18
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        spacing: 10
                        WelcomeButton {
                            Layout.fillWidth: true
                            label: "Light"
                            iconName: "light_mode"
                            selected: root.selectedMode === "light"
                            enabled: root.statusLoaded
                            onClicked: root.chooseMode("light")
                        }
                        WelcomeButton {
                            Layout.fillWidth: true
                            label: "Dark"
                            iconName: "dark_mode"
                            selected: root.selectedMode === "dark"
                            enabled: root.statusLoaded
                            onClicked: root.chooseMode("dark")
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 18
                        text: "The default wallpaper stays in place. Change it later in Settings."
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 21
                        Layout.preferredHeight: 42
                        radius: Appearance.radius.control
                        color: root.noticeError
                            ? Appearance.m3colors.m3errorContainer
                            : Appearance.colors.colLayer1Base
                        visible: root.notice.length > 0 || root.previewActive
                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 12
                            }
                            spacing: 9
                            MaterialSymbol {
                                text: root.noticeError ? "error" : "auto_awesome"
                                iconSize: 16
                                color: root.noticeError
                                    ? Appearance.m3colors.m3onErrorContainer
                                    : Appearance.colors.colPrimary
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.notice
                                color: root.noticeError
                                    ? Appearance.m3colors.m3onErrorContainer
                                    : Appearance.colors.colOnLayer1
                                font.family: Appearance.font.family.main
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: root.previewActive
                                text: root.previewSeconds + "s"
                                color: Appearance.colors.colPrimary
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: 11
                            }
                        }
                    }

                    WelcomeButton {
                        Layout.topMargin: 10
                        label: "Revert preview"
                        iconName: "undo"
                        quiet: true
                        visible: root.previewActive
                        enabled: !root.busy
                        onClicked: root.revertLook()
                    }
                    Item { Layout.preferredHeight: 16 }
                }
            }
        }
    }

    Component {
        id: readyPage
        Item {
            Flickable {
                id: readyFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: readyContent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: readyFlick.contentHeight > readyFlick.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: readyContent
                    width: readyFlick.width
                    height: Math.max(readyFlick.height, implicitHeight)
                    spacing: 0
                    Item { Layout.fillHeight: true }
                    MaterialSymbol {
                        text: "check_circle"
                        iconSize: 40
                        color: Appearance.colors.colPrimary
                    }
                    Text {
                        text: "You're home."
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.title
                        font.pixelSize: 34
                        font.weight: Font.Medium
                        Layout.topMargin: 16
                    }
                    Text {
                        text: "Your desktop is ready. These three shortcuts will take you anywhere."
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.preferredHeight: 27 }
                    Repeater {
                        model: [
                            { keys: "Tap Super", action: "Open search", icon: "search" },
                            { keys: "Super + I", action: "Open Settings", icon: "settings" },
                            { keys: "Super + /", action: "See all shortcuts", icon: "keyboard" }
                        ]
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 58
                            RowLayout {
                                anchors.fill: parent
                                spacing: 11
                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: 19
                                    color: Appearance.colors.colPrimary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.action
                                    color: Appearance.colors.colOnLayer0
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: modelData.keys
                                    color: Appearance.colors.colSubtext
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: 11
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Appearance.colors.colLayer0Border
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 20 }
                    Text {
                        text: "Reopen this guide any time with Super + Shift + Alt + /."
                        color: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    component WelcomeButton: Rectangle {
        id: button
        property string label: ""
        property string iconName: ""
        property bool primary: false
        property bool selected: false
        property bool quiet: false
        property bool compact: false
        signal clicked()

        implicitWidth: Math.max(
            compact ? 92 : 130,
            buttonText.implicitWidth + (iconName.length > 0 ? 45 : 30)
        )
        implicitHeight: compact ? 34 : 44
        radius: Appearance.radius.control
        color: primary
            ? Appearance.colors.colPrimary
            : selected
                ? Appearance.colors.colSecondaryContainer
                : hoveredArea.containsMouse
                    ? Appearance.colors.colLayer1Hover
                    : quiet ? "transparent" : Appearance.colors.colLayer1Base
        border.width: activeFocus || selected ? 1 : 0
        border.color: activeFocus
            ? Appearance.colors.colPrimary
            : Appearance.colors.colLayer0Border
        opacity: enabled ? 1 : 0.45
        scale: hoveredArea.pressed && enabled && !Appearance.reducedMotion
            ? 0.975 : 1
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Button
        Accessible.name: label
        Keys.onReturnPressed: clicked()
        Keys.onSpacePressed: clicked()
        Behavior on color {
            MotionColorAnim { type: MotionColorAnim.FastEffects }
        }
        Behavior on scale {
            MotionAnim { type: MotionAnim.FastSpatial }
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                visible: button.iconName.length > 0
                text: button.iconName
                iconSize: button.compact ? 15 : 18
                color: button.primary
                    ? Appearance.colors.colOnPrimary
                    : button.selected
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnLayer1
            }
            Text {
                id: buttonText
                text: button.label
                color: button.primary
                    ? Appearance.colors.colOnPrimary
                    : button.selected
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnLayer1
                font.family: Appearance.font.family.main
                font.pixelSize: button.compact ? 11 : 13
                font.weight: button.primary ? Font.DemiBold : Font.Medium
            }
        }
        MouseArea {
            id: hoveredArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: button.enabled
                ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: button.enabled
            onClicked: button.clicked()
        }
    }

    component WelcomeProfile: Rectangle {
        id: profile
        property string profileName: ""
        property string description: ""
        property bool fluid: false
        property bool selected: false
        signal clicked()

        implicitHeight: root.height >= 600 ? 166 : 140
        radius: Appearance.radius.card
        color: selected
            ? Appearance.colors.colLayer2Base
            : Appearance.colors.colLayer1Base
        border.width: selected || activeFocus ? 2 : 1
        border.color: selected || activeFocus
            ? Appearance.colors.colPrimary
            : Appearance.colors.colLayer0Border
        opacity: enabled ? 1 : 0.55
        scale: selected && !Appearance.reducedMotion ? 1.01 : 1
        clip: true
        activeFocusOnTab: enabled
        Accessible.role: Accessible.RadioButton
        Accessible.name: profileName
        Accessible.checked: selected
        Keys.onReturnPressed: clicked()
        Keys.onSpacePressed: clicked()
        Behavior on color {
            MotionColorAnim { type: MotionColorAnim.DefaultEffects }
        }
        Behavior on scale {
            MotionAnim { type: MotionAnim.DefaultSpatial }
        }

        ColumnLayout {
            anchors {
                fill: parent
                margins: 13
            }
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.height >= 600 ? 70 : 55
                radius: 5
                clip: true
                color: Appearance.colors.colLayer0Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                Image {
                    anchors.fill: parent
                    source: Quickshell.shellPath(
                        "assets/images/default_wallpaper.png"
                    )
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.32
                    smooth: true
                }
                Rectangle {
                    x: 6
                    y: 6
                    width: parent.width - 12
                    height: 10
                    radius: fluid ? 5 : 2
                    color: fluid
                        ? Appearance.colors.fluidLayer0Base
                        : Appearance.colors.colLayer0Base
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }
                Row {
                    x: 13
                    y: 29
                    spacing: 5
                    Repeater {
                        model: 5
                        Rectangle {
                            width: 9
                            height: 9
                            radius: fluid ? 5 : 2
                            color: index === 0
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer2Base
                        }
                    }
                }
                Rectangle {
                    x: parent.width - 68
                    y: 27
                    width: 51
                    height: 28
                    radius: fluid ? 10 : 4
                    color: Appearance.colors.colLayer1Base
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 8
                Text {
                    text: profile.profileName
                    color: Appearance.colors.colOnLayer0
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                MaterialSymbol {
                    text: profile.selected ? "check_circle" : "circle"
                    iconSize: 18
                    color: profile.selected
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                }
            }
            Text {
                Layout.fillWidth: true
                text: profile.description
                color: Appearance.colors.colSubtext
                font.family: Appearance.font.family.main
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: profile.enabled
                ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: profile.enabled
            onClicked: profile.clicked()
        }
    }

    Item {
        id: frameFocus
        anchors.fill: parent
        focus: true
        z: -1
        Keys.onEscapePressed: root.requestClose()
        Keys.onLeftPressed: {
            if (root.currentStep > 0)
                root.setStep(root.currentStep - 1)
        }
        Keys.onRightPressed: {
            if (root.currentStep < 2)
                root.continueFlow()
        }
    }
}
