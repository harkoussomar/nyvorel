import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property bool quiet: false
    // prism-v2-phase2a: parent compositions can opt a group out of creating
    // another elevated island while preserving all non-Prism behavior.
    property bool prismSurface: true
    property bool prismElevated: true
    property real prismSurfaceOpacity: 1.0
    property bool prismActive: false
    property real padding: 5
    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight
    default property alias items: gridLayout.children

    PrismSurface {
        visible: Appearance.prismMode && !root.quiet && root.prismSurface
        depth: Appearance.prism.depthPersistent
        surfaceRadius: Appearance.prism.radiusPersistent
        elevated: root.prismElevated
        surfaceOpacity: root.prismSurfaceOpacity
        active: root.prismActive
        anchors {
            fill: parent
            // prism-v2-phase2a3: the BarGroup itself is the 40px persistent
            // host; Prism fills that host so every island has equal height.
            topMargin: 0
            bottomMargin: 0
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
    }

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        // prism-v2-phase2a: Prism's elevation is owned by PrismSurface above.
        // This legacy rectangle stays render-neutral in Prism and preserves the
        // exact Default/Fluid material paths.
        color:
            (Appearance.prismMode || Appearance.inlayMode)
                ? "transparent"
                : root.quiet
                    ? "transparent"
                    : Config.options && Config.options.bar && Config.options.bar.borderless
                        ? "transparent"
                        : Appearance.fluidMode
                            ? Appearance.colors.colLayer1Base
                            : Appearance.colors.colLayer1
        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusPersistent
                    : (
                        Appearance.fluidMode
                            ? Appearance.radius.bar
                            : Appearance.rounding.small
                    )
        // Fluid uses tonal glass hierarchy rather than framing every group.
        border.width: 0
        border.color: Appearance.colors.colLayer0Border
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors {
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            left: root.vertical ? undefined : parent.left
            right: root.vertical ? undefined : parent.right
            top: root.vertical ? parent.top : undefined
            bottom: root.vertical ? parent.bottom : undefined
            margins: root.padding
        }
        columnSpacing: Appearance.fluidMode ? 6 : (Appearance.prismMode ? Appearance.spacing.sm : 4)
        rowSpacing: 12
    }
}