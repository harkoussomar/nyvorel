import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property int favoriteCount: 0
    property int historyCount: 0
    property bool canUndo: false
    property bool diagnosticsOk: true
    property bool diagnosticsWarning: false
    property bool entered: false

    signal searchRequested()
    signal favoritesRequested()
    signal recentRequested()
    signal contextRequested()
    signal appearanceRequested()
    signal undoRequested()
    signal diagnosticsRequested()
    signal configRequested()

    implicitWidth: 58
    radius:
        Appearance.inlayMode
            ? 0
            : Appearance.prismMode
                ? Appearance.prism.radiusInteractive
                : Appearance.radius.sidebar
    color:
        Appearance.prismMode
            ? Appearance.prism.interactiveFill
            : Appearance.inlayMode
                ? Appearance.inlay.surfaceFill
                : Appearance.colors.colLayer0
    border.width: 1
    border.color:
        Appearance.inlayMode
            ? Appearance.inlay.borderControl
            : Appearance.prismMode
                ? Appearance.prism.borderStrong
                : Appearance.colors.colLayer0Border
    clip: true

    opacity: root.entered ? 1 : 0

    transform: Translate {
        x: root.entered ? 0 : (Appearance.inlayMode ? -Appearance.inlay.enterDistance : -8)

        Behavior on x {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }
    }

    Behavior on opacity {
        MotionAnim {
            type: MotionAnim.DefaultEffects
        }
    }

    Component.onCompleted: Qt.callLater(() => root.entered = true)

    component RailButton: RippleButton {
        id: button

        property string iconName: ""
        property string tooltipText: ""
        property bool selected: false
        property bool statusDot: false
        property bool attention: false

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 40
        implicitHeight: 40

        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: tooltipText

        buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
        buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.radius.control

        colBackground:
            selected
                ? (Appearance.inlayMode
                    ? Appearance.inlay.selectedFill
                    : Appearance.prismMode
                        ? Appearance.prism.persistentActiveFill
                        : Appearance.colors.colSecondaryContainer)
                : "transparent"

        colBackgroundHover:
            Appearance.inlayMode
                ? Appearance.inlay.hoverFill
                : Appearance.prismMode
                    ? Appearance.prism.persistentHoverFill
                    : (selected
                        ? Appearance.colors.colSecondaryContainerHover
                        : Appearance.colors.colLayer2Hover)

        colRipple:
            Appearance.inlayMode
                ? Appearance.inlay.pressedFill
                : Appearance.prismMode
                    ? Appearance.prism.persistentActiveFill
                    : (selected
                        ? Appearance.colors.colSecondaryContainerActive
                        : Appearance.colors.colLayer2Active)

        background: Rectangle {
            radius: button.buttonEffectiveRadius
            color: button.buttonColor
            border.width: Appearance.inlayMode ? Appearance.inlay.borderWidth : 0
            border.color:
                Appearance.inlayMode
                    ? (button.selected ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                    : "transparent"
        }

        contentItem: Item {
            anchors.fill: parent

            MaterialSymbol {
                anchors.centerIn: parent
                text: button.iconName
                iconSize: 20
                fill: button.selected ? 1 : 0
                color:
                    button.selected
                        ? (Appearance.prismMode
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colOnSecondaryContainer)
                        : button.attention
                            ? Appearance.m3colors.m3error
                            : button.hovered
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnLayer0

                Behavior on color {
                    MotionColorAnim {
                        type: MotionColorAnim.FastEffects
                    }
                }
            }

            Rectangle {
                visible: button.statusDot
                anchors {
                    right: parent.right
                    top: parent.top
                    rightMargin: 6
                    topMargin: 6
                }

                width: 6
                height: 6
                radius: Appearance.inlayMode ? 0 : Appearance.radius.full
                color:
                    button.attention
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colPrimary
            }
        }

        StyledToolTip {
            extraVisibleCondition: parent?.hovered === true
            delay: 450
            text: button.tooltipText
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 8
        }

        spacing: 5

        RailButton {
            iconName: "search"
            tooltipText: "Search settings · Ctrl+K"
            onClicked: root.searchRequested()
        }

        RailButton {
            iconName: "star"
            tooltipText:
                root.favoriteCount > 0
                    ? `Favorites · ${root.favoriteCount}`
                    : "Favorites"
            statusDot: root.favoriteCount > 0
            onClicked: root.favoritesRequested()
        }

        RailButton {
            iconName: "history"
            tooltipText:
                root.historyCount > 0
                    ? `Recent changes · ${root.historyCount}`
                    : "Recent changes"
            statusDot: root.historyCount > 0
            onClicked: root.recentRequested()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            color:
                Appearance.inlayMode
                    ? Appearance.inlay.borderSection
                    : Appearance.prismMode
                        ? Appearance.prism.borderSubtle
                        : Appearance.colors.colLayer0Border
        }

        RailButton {
            iconName: "segment"
            tooltipText: "Current page controls"
            onClicked: root.contextRequested()
        }

        RailButton {
            iconName: "palette"
            tooltipText: "Appearance Studio"
            onClicked: root.appearanceRequested()
        }

        Item {
            Layout.fillHeight: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            color:
                Appearance.inlayMode
                    ? Appearance.inlay.borderSection
                    : Appearance.prismMode
                        ? Appearance.prism.borderSubtle
                        : Appearance.colors.colLayer0Border
        }

        RailButton {
            iconName: "undo"
            tooltipText:
                root.canUndo
                    ? "Undo last settings change"
                    : "Nothing to undo"
            enabled: root.canUndo
            opacity: enabled ? 1 : 0.38
            onClicked: root.undoRequested()
        }

        RailButton {
            iconName:
                !root.diagnosticsOk
                    ? "error"
                    : root.diagnosticsWarning
                        ? "warning"
                        : "monitor_heart"

            tooltipText:
                !root.diagnosticsOk
                    ? "Settings diagnostics · attention needed"
                    : root.diagnosticsWarning
                        ? "Settings diagnostics · warning"
                        : "Settings diagnostics"

            attention: !root.diagnosticsOk
            statusDot:
                !root.diagnosticsOk
                || root.diagnosticsWarning

            onClicked: root.diagnosticsRequested()
        }

        RailButton {
            iconName: "edit"
            tooltipText: "Open config file"
            onClicked: root.configRequested()
        }
    }
}
