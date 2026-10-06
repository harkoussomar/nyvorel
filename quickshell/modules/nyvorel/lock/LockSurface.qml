import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.nyvorel.bar as Bar
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property LockContext context
    property bool active: false
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower

    // Force focus on entry
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        forceFieldFocus();
    }
    onPositionChanged: mouse => {
        forceFieldFocus();
    }

    // Style-aware lock presentation. Fluid intentionally keeps the original
    // 0.9 -> 1.0 expressive entrance; Inlay is direct with no scale deformation.
    property real toolbarScale:
        Appearance.fluidMode
            ? 0.9
            : Appearance.prismMode
                ? 0.96
                : 1.0
    property real toolbarOpacity: 0

    readonly property real islandGap:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? 12
                : 10

    readonly property real islandBottomMargin:
        Appearance.prismMode ? 26 : 20

    readonly property color islandFill:
        Appearance.inlayMode
            ? "transparent"
            : Appearance.prismMode
                ? Appearance.prism.interactiveFill
                : Appearance.fluidMode
                    ? Appearance.m3colors.m3surfaceContainer
                    : Appearance.colors.colLayer0

    readonly property real islandRadius:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.prism.radiusInteractive
                : Appearance.fluidMode
                    ? 28
                    : Appearance.radius.control

    readonly property bool islandShadow:
        Appearance.fluidMode || Appearance.prismMode
    Behavior on toolbarScale {
        MotionAnim {
            type: MotionAnim.DefaultSpatial
        }
    }
    Behavior on toolbarOpacity {
        MotionAnim {
            type: MotionAnim.DefaultEffects
        }
    }

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        toolbarScale = 1;
        toolbarOpacity = 1;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        } 
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // RippleButton {
    //     anchors {
    //         top: parent.top
    //         left: parent.left
    //         leftMargin: 10
    //         topMargin: 10
    //     }
    //     implicitHeight: 40
    //     colBackground: Appearance.colors.colLayer2
    //     onClicked: {
    //         context.unlocked(LockContext.ActionEnum.Unlock);
    //         GlobalStates.screenLocked = false;
    //     }
    //     contentItem: StyledText {
    //         text: "[[ DEBUG BYPASS ]]"
    //     }
    // }

    // Main toolbar: password box
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: root.islandBottomMargin
        }
        Behavior on anchors.bottomMargin {
            MotionAnim {
                type: MotionAnim.DefaultSpatial
            }
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        enableShadow: root.islandShadow
        colBackground: root.islandFill
        radius: root.islandRadius
        padding: Appearance.inlayMode ? 6 : Appearance.prismMode ? 10 : 8
        spacing: Appearance.inlayMode ? 2 : Appearance.prismMode ? 6 : 4

        // Fingerprint
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured
            visible: active

            sourceComponent: MaterialSymbol {
                id: fingerprintIcon
                fill: 1
                text: "fingerprint"
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ToolbarTextField {
            id: passwordBox
            Layout.rightMargin: -Layout.leftMargin
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // Style
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
            selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

            // Password
            enabled: !root.context.unlockInProgress
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            onAccepted: {
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                root.context.resetClearTimer();
            }
            
            // Fluid/Prism keep the soft clipping language. Inlay is a square
            // embedded field, so no rounded opacity mask is applied.
            layer.enabled: !Appearance.inlayMode
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: Appearance.inlayMode ? 0 : height / 2
                }
            }

            // Shake when wrong password
            SequentialAnimation {
                id: wrongPasswordShakeAnim
                NumberAnimation { target: passwordBox; property: "Layout.leftMargin"; to: -30; duration: 50 }
                NumberAnimation { target: passwordBox; property: "Layout.leftMargin"; to: 30; duration: 50 }
                NumberAnimation { target: passwordBox; property: "Layout.leftMargin"; to: -15; duration: 40 }
                NumberAnimation { target: passwordBox; property: "Layout.leftMargin"; to: 15; duration: 40 }
                NumberAnimation { target: passwordBox; property: "Layout.leftMargin"; to: 0; duration: 30 }
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }

            // We're drawing dots manually
            property bool materialShapeChars: Config.options.lock.materialShapeChars
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
            Loader {
                active: passwordBox.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: root.context.currentText.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        ToolbarButton {
            id: confirmButton
            implicitWidth: height
            buttonRadius:
                Appearance.inlayMode
                    ? 0
                    : Appearance.prismMode
                        ? Appearance.prism.radiusControl
                        : Appearance.rounding.full
            toggled: true
            enabled: !root.context.unlockInProgress
            colBackgroundToggled: Appearance.colors.colPrimary

            onClicked: root.context.tryUnlock()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: {
                    if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                        return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        return "power_settings_new";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        return "restart_alt";
                    }
                }
                color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: root.islandGap
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        enableShadow: root.islandShadow
        colBackground: root.islandFill
        radius: root.islandRadius
        padding: Appearance.inlayMode ? 6 : Appearance.prismMode ? 10 : 8
        spacing: Appearance.inlayMode ? 2 : Appearance.prismMode ? 6 : 4

        // Username
        IconAndTextPair {
            Layout.leftMargin: 8
            icon: "account_circle"
            text: SystemInfo.username
        }

        // Keyboard layout (Xkb)
        Loader {
            Layout.rightMargin: 8
            Layout.fillHeight: true

            active: true
            visible: active

            sourceComponent: Row {
                spacing: 8

                MaterialSymbol {
                    id: keyboardIcon
                    anchors.verticalCenter: parent.verticalCenter
                    fill: 1
                    text: "keyboard_alt"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurfaceVariant
                }
                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: StyledText {
                        text: HyprlandXkb.currentLayoutCode
                        color: Appearance.colors.colOnSurfaceVariant
                        animateChange: true
                    }
                }
            }
        }

        // Keyboard layout (Fcitx)
        Bar.SysTray {
            Layout.rightMargin: 10
            Layout.alignment: Qt.AlignVCenter
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
            visible: pinnedItems.length > 0
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: root.islandGap
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        enableShadow: root.islandShadow
        colBackground: root.islandFill
        radius: root.islandRadius
        padding: Appearance.inlayMode ? 6 : Appearance.prismMode ? 10 : 8
        spacing: Appearance.inlayMode ? 2 : Appearance.prismMode ? 6 : 4

        IconAndTextPair {
            visible: Battery.available
            icon: Battery.isCharging ? "bolt" : "battery_android_full"
            text: Math.round(Battery.percentage * 100)
            color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        }

        IconToolbarButton {
            id: sleepButton
            onClicked: Session.suspend()
            text: "dark_mode"
            buttonRadius:
                Appearance.inlayMode
                    ? 0
                    : Appearance.prismMode
                        ? Appearance.prism.radiusControl
                        : Appearance.rounding.full
            colBackgroundHover:
                Appearance.inlayMode
                    ? Appearance.inlay.hoverFill
                    : Appearance.colors.colLayer1Hover
            colRipple:
                Appearance.inlayMode
                    ? Appearance.inlay.pressedFill
                    : Appearance.colors.colLayer1Active
        }

        PasswordGuardedIconToolbarButton {
            id: powerButton
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }

        PasswordGuardedIconToolbarButton {
            id: rebootButton
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }

    // Inlay turns the three legacy floating islands into one embedded bottom
    // workstation rail. The toolbars themselves become transparent sections;
    // this owner supplies the matte substrate, outer frame and separators.
    Rectangle {
        id: inlayRail
        visible: Appearance.inlayMode
        anchors {
            left: leftIsland.left
            right: rightIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
        }
        z: -1
        color: Appearance.inlay.surfaceFill
        radius: 0
        border.width: Appearance.inlay.borderWidth
        border.color: Appearance.inlay.borderControl
    }

    Rectangle {
        visible: Appearance.inlayMode
        x: mainIsland.x
        y: mainIsland.y
        width: Appearance.inlay.borderWidth
        height: mainIsland.height
        color: Appearance.inlay.borderSection
    }

    Rectangle {
        visible: Appearance.inlayMode
        x: mainIsland.x + mainIsland.width - Appearance.inlay.borderWidth
        y: mainIsland.y
        width: Appearance.inlay.borderWidth
        height: mainIsland.height
        color: Appearance.inlay.borderSection
    }

    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        buttonRadius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusControl
                    : Appearance.rounding.full
        colBackgroundToggled:
            Appearance.inlayMode
                ? Appearance.inlay.selectedFill
                : Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover:
            Appearance.inlayMode
                ? Appearance.inlay.hoverFill
                : Appearance.colors.colSecondaryContainerHover
        colRippleToggled:
            Appearance.inlayMode
                ? Appearance.inlay.pressedFill
                : Appearance.colors.colSecondaryContainerActive

        toggled: root.context.targetAction === guardedBtn.targetAction

        onClicked: {
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pair.text
            color: pair.color
        }
    }
}
