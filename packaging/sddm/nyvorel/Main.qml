pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import QtQuick.Templates as Templates
import Qt5Compat.GraphicalEffects
import "widgets" as Shared

Rectangle {
    id: root

    color: root.backdrop

    // SDDM supplies these context properties when it creates the greeter view.
    // qmllint disable unqualified
    readonly property var greeter: sddm
    readonly property var accounts: userModel
    readonly property var sessions: sessionModel
    readonly property var greeterKeyboard: keyboard
    readonly property var themeConfig: config
    // qmllint enable unqualified

    readonly property color backdrop: themeConfig.stringValue("backgroundColor") || "#19120d"
    readonly property color surface: themeConfig.stringValue("surfaceContainer") || "#261e18"
    readonly property color menuSurface: themeConfig.stringValue("surfaceContainerHigh") || "#312822"
    readonly property color line: themeConfig.stringValue("outlineVariant") || "#52443b"
    readonly property color foreground: themeConfig.stringValue("onSurface") || "#f0dfd5"
    readonly property color muted: themeConfig.stringValue("onSurfaceVariant") || "#d6c3b7"
    readonly property color accent: themeConfig.stringValue("primary") || "#ffb784"
    readonly property color accentInk: themeConfig.stringValue("onPrimary") || "#4f2500"
    readonly property color primaryContainer: themeConfig.stringValue("primaryContainer") || "#6d390c"
    readonly property color secondary: themeConfig.stringValue("secondary") || "#e4bfa7"
    readonly property color secondaryContainer: themeConfig.stringValue("secondaryContainer") || "#5b412f"
    readonly property color secondaryContainerText: themeConfig.stringValue("onSecondaryContainer") || "#ffdcc5"
    readonly property color tertiary: themeConfig.stringValue("tertiary") || "#c8ca94"
    readonly property color tertiaryContainer: themeConfig.stringValue("tertiaryContainer") || "#47491f"
    readonly property color tertiaryContainerText: themeConfig.stringValue("onTertiaryContainer") || "#e4e6ae"
    readonly property color errorColor: themeConfig.stringValue("error") || "#ffb4ab"
    readonly property string mainFont: "Google Sans Flex"
    readonly property string symbolFont: "Material Symbols Rounded"
    readonly property bool hasSymbols: Qt.fontFamilies().includes(symbolFont)
    readonly property int margin: width < 640 ? 12 : 20
    readonly property int columnCount: width >= 750 ? 3 : width >= 500 ? 2 : 1
    readonly property string accountName: account.editText.trim()
    readonly property bool hasSession: session.currentIndex >= 0
    readonly property bool showPower: greeter.canSuspend || greeter.canReboot || greeter.canPowerOff
    property bool signingIn: false
    property bool loginError: false
    property string message: ""
    property date now: new Date()

    function focusCredentials() {
        if (accountName.length === 0)
            account.contentItem.forceActiveFocus();
        else
            password.forceActiveFocus();
    }

    function signIn() {
        if (signingIn || !hasSession)
            return;
        if (accountName.length === 0) {
            focusCredentials();
            return;
        }
        signingIn = true;
        loginError = false;
        message = qsTr("Signing in…");
        greeter.login(accountName, password.text, session.currentIndex);
        password.clear();
    }

    Component.onCompleted: focusCredentials()

    Connections {
        target: root.greeter

        function onLoginFailed() {
            root.signingIn = false;
            root.loginError = true;
            root.message = qsTr("Sign-in failed. Check your username and password.");
            root.focusCredentials();
        }

        function onInformationMessage(message) {
            root.message = message;
        }
    }

    Image {
        readonly property bool gpuBlur: GraphicsInfo.api !== GraphicsInfo.Software

        anchors.fill: parent
        scale: 1.1
        source: Qt.resolvedUrl(root.themeConfig.stringValue("background") || "wallpaper.png")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: gpuBlur ? Math.min(Math.ceil(width * Screen.devicePixelRatio), 2560) : 36
        layer.enabled: gpuBlur
        layer.effect: GaussianBlur {
            radius: 100
            samples: 201
            cached: true
        }
        onStatusChanged: {
            if (status === Image.Error && source.toString() !== Qt.resolvedUrl("wallpaper.png").toString())
                source = Qt.resolvedUrl("wallpaper.png");
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.backdrop
        opacity: 0.3
    }

    Timer {
        interval: 60000 - (root.now.getTime() % 60000)
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    ClockFace {
        id: clock

        width: Math.min(implicitWidth, root.width - 2 * root.margin, Math.max(92, toolbar.y * 0.54))
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(root.margin, Math.min((root.height - height) / 2, toolbar.y - height - 44))
        time: root.now
        faceColor: root.primaryContainer
        dialColor: Qt.tint(root.primaryContainer, Qt.rgba(root.secondary.r, root.secondary.g, root.secondary.b, 0.85))
        hourColor: root.accent
        minuteColor: root.tertiary
        monthColor: root.secondaryContainer
        monthTextColor: root.secondaryContainerText
        dayColor: root.tertiaryContainer
        dayTextColor: root.tertiaryContainerText
    }

    Text {
        anchors.bottom: toolbar.top
        anchors.bottomMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(400, root.width - 2 * root.margin)
        visible: text.length > 0
        text: root.hasSession ? root.message : qsTr("No desktop sessions are available.")
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: root.loginError || !root.hasSession ? root.errorColor : root.foreground
        style: Text.Outline
        styleColor: root.backdrop
        font.family: root.mainFont
        font.pixelSize: 15
    }

    GridLayout {
        id: toolbar

        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.margin
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width - 2 * root.margin, 724)
        columns: root.columnCount
        columnSpacing: 10
        rowSpacing: 10

        Island {
            id: identity

            Layout.row: root.columnCount === 3 ? 0 : 1
            Layout.column: 0
            Layout.fillWidth: true
            Layout.preferredWidth: 232
            Layout.maximumWidth: root.columnCount === 3 ? 232 : Number.POSITIVE_INFINITY

            Picker {
                id: account

                Layout.fillWidth: true
                symbol: "account_circle"
                fallbackSymbol: "●"
                enabled: !root.signingIn
                model: root.accounts
                textRole: "name"
                currentIndex: count ? Math.max(0, root.accounts.lastIndex) : -1
                editable: true
                flat: true
                selectTextByMouse: true
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                Accessible.name: qsTr("Username")
                Accessible.description: qsTr("Choose an account or enter a username")
                Component.onCompleted: (contentItem as Templates.TextField).placeholderText = qsTr("Username")
                onAccepted: password.forceActiveFocus()
                onActivated: password.forceActiveFocus()
            }

            Picker {
                id: layoutPicker

                visible: root.greeterKeyboard.enabled && count > 0
                enabled: !root.signingIn && count > 1
                Layout.preferredWidth: 78
                menuWidth: 220
                symbol: "keyboard_alt"
                fallbackSymbol: "⌨"
                model: root.greeterKeyboard.layouts
                textRole: "longName"
                currentIndex: root.greeterKeyboard.currentLayout
                displayText: currentIndex >= 0 && currentIndex < count
                    ? root.greeterKeyboard.layouts[currentIndex].shortName.toUpperCase() : ""
                Accessible.name: qsTr("Keyboard layout")
                onActivated: index => {
                    root.greeterKeyboard.currentLayout = index;
                    root.focusCredentials();
                }
            }
        }

        Island {
            Layout.row: 0
            Layout.column: root.columnCount === 3 ? 1 : 0
            Layout.columnSpan: root.columnCount === 2 ? 2 : 1
            Layout.minimumWidth: 0
            Layout.fillWidth: true
            Layout.maximumWidth: 260
            Layout.alignment: Qt.AlignHCenter

            Shared.ToolbarInput {
                id: password

                Layout.fillWidth: true
                Layout.minimumWidth: 0
                colBackground: root.menuSurface
                font.family: root.mainFont
                font.pixelSize: 15
                font.variableAxes: ({ "wght": 450, "wdth": 100 })
                verticalAlignment: TextInput.AlignVCenter
                color: root.foreground
                placeholderTextColor: root.muted
                selectionColor: root.secondaryContainer
                selectedTextColor: root.secondaryContainerText
                placeholderText: qsTr("Enter password")
                Accessible.name: qsTr("Password")
                enabled: !root.signingIn && root.hasSession
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                onAccepted: root.signIn()
                onTextEdited: {
                    if (root.loginError) {
                        root.loginError = false;
                        root.message = "";
                    }
                }
            }

            Controls.Button {
                id: signInButton

                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                enabled: !root.signingIn && root.hasSession && root.accountName.length > 0
                Accessible.name: qsTr("Sign in")
                onClicked: root.signIn()

                background: Rectangle {
                    radius: width / 2
                    color: signInButton.down ? Qt.darker(root.accent, 1.15) : root.accent
                    border.width: signInButton.visualFocus ? 1 : 0
                    border.color: root.foreground
                    opacity: signInButton.enabled ? 1 : 0.42
                }

                contentItem: Glyph {
                    symbol: "arrow_right_alt"
                    fallbackSymbol: "→"
                    color: root.accentInk
                    iconSize: 24
                }
            }
        }

        Island {
            id: systemControls

            readonly property bool hasControls: session.count > 1 || root.showPower
            visible: root.columnCount === 3 || hasControls
            frameBackground.visible: hasControls
            Layout.row: root.columnCount === 3 ? 0 : root.columnCount === 2 ? 1 : 2
            Layout.column: root.columnCount === 3 ? 2 : root.columnCount === 2 ? 1 : 0
            Layout.fillWidth: true
            Layout.preferredWidth: 232
            Layout.maximumWidth: root.columnCount === 3 ? 232 : Number.POSITIVE_INFINITY

            Picker {
                id: session

                visible: count > 1
                enabled: !root.signingIn
                Layout.fillWidth: true
                menuWidth: 250
                symbol: "desktop_windows"
                fallbackSymbol: "▣"
                model: root.sessions
                textRole: "name"
                currentIndex: count ? Math.max(0, Math.min(root.sessions.lastIndex, count - 1)) : -1
                Accessible.name: qsTr("Desktop session")
                onActivated: root.focusCredentials()
            }

            Controls.Button {
                id: power

                visible: root.showPower
                enabled: !root.signingIn
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Accessible.name: qsTr("Power")
                onClicked: powerMenu.open()

                background: Rectangle {
                    radius: height / 2
                    color: power.hovered || power.down || powerMenu.visible ? root.line : "transparent"
                    border.width: power.visualFocus ? 1 : 0
                    border.color: root.accent
                }

                contentItem: Glyph {
                    symbol: "power_settings_new"
                    fallbackSymbol: "⏻"
                    color: root.foreground
                }

                Controls.Menu {
                    id: powerMenu

                    width: 156
                    x: power.width - width
                    y: -height - 10
                    margins: 8
                    padding: 4
                    font.family: root.mainFont
                    font.pixelSize: 15
                    palette.windowText: root.foreground
                    palette.window: root.menuSurface
                    palette.light: root.line
                    palette.midlight: root.line
                    background: Rectangle {
                        radius: 12
                        color: root.menuSurface
                        border.color: root.line
                    }

                    Controls.MenuItem {
                        visible: root.greeter.canSuspend
                        height: visible ? implicitHeight : 0
                        text: qsTr("Sleep")
                        onTriggered: root.greeter.suspend()
                    }

                    Controls.MenuItem {
                        visible: root.greeter.canReboot
                        height: visible ? implicitHeight : 0
                        text: qsTr("Restart")
                        onTriggered: root.greeter.reboot()
                    }

                    Controls.MenuItem {
                        visible: root.greeter.canPowerOff
                        height: visible ? implicitHeight : 0
                        text: qsTr("Shut down")
                        onTriggered: root.greeter.powerOff()
                    }
                }
            }
        }
    }

    component Island: Shared.ToolbarFrame {
        colBackground: root.surface
        radius: 28
    }

    component Glyph: Text {
        required property string symbol
        required property string fallbackSymbol
        property int iconSize: 22

        text: root.hasSymbols ? symbol : fallbackSymbol
        color: root.muted
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: root.hasSymbols ? root.symbolFont : root.mainFont
        font.pixelSize: iconSize
        font.variableAxes: ({ "FILL": 1.0, "opsz": iconSize })
        renderType: Text.NativeRendering
    }

    component Picker: Controls.ComboBox {
        id: picker

        property int menuWidth: 190
        required property string symbol
        required property string fallbackSymbol
        font.family: root.mainFont
        font.pixelSize: 15
        implicitHeight: 40
        padding: 5
        leftPadding: 25
        rightPadding: indicator.visible ? indicator.width + 8 : 5
        contentItem.clip: true
        palette.text: root.foreground
        palette.buttonText: root.foreground
        palette.placeholderText: root.muted
        palette.dark: root.muted
        palette.base: root.surface
        palette.highlight: root.accent
        palette.highlightedText: root.accentInk

        indicator: Glyph {
            visible: picker.count > 1 || (picker.editable && picker.count > 0)
            width: 15
            height: picker.height
            x: picker.width - width - 4
            symbol: "expand_more"
            fallbackSymbol: "⌄"
            iconSize: 15
        }

        Glyph {
            x: 5
            width: 22
            height: picker.height
            symbol: picker.symbol
            fallbackSymbol: picker.fallbackSymbol
        }

        background: Rectangle {
            radius: height / 2
            color: (picker.hovered && picker.enabled) || picker.down ? root.line : "transparent"
            border.width: picker.activeFocus ? 1 : 0
            border.color: root.accent
        }

        delegate: Controls.ItemDelegate {
            id: option

            required property int index
            required property var model
            width: ListView.view.width
            height: 38
            text: model[picker.textRole]
            highlighted: picker.highlightedIndex === index
            hoverEnabled: true
            contentItem: Text {
                text: option.text
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                color: picker.currentIndex === option.index ? root.accent : root.foreground
                font: picker.font
            }
            background: Rectangle {
                radius: 8
                color: option.highlighted || option.hovered ? root.line : "transparent"
            }
        }

        popup: Controls.Popup {
            width: Math.min(root.width - 16, Math.max(picker.menuWidth, picker.width))
            height: Math.min(picker.count * 38 + 8, Math.max(46, toolbar.y - 18), 274)
            y: -height - 10
            margins: 8
            padding: 4
            contentItem: ListView {
                clip: true
                model: picker.delegateModel
                currentIndex: picker.highlightedIndex
                highlightMoveDuration: 0
                Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
            }
            background: Rectangle {
                radius: 12
                color: root.menuSurface
                border.color: root.line
            }
        }
    }
}
