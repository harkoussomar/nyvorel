import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import "SettingsSearchIndex.js" as SearchIndex

Item {
    id: root

    property var pages: []
    property int currentPage: 0
    property string helperPath: ""

    property bool opened: false
    property string mode: "search"
    property var favoriteIds: []
    property var historyItems: []
    property var diagnostics: ({})
    property int favoriteCount: 0
    property int historyCount: 0
    property bool canUndo: false
    property bool diagnosticsOk: true
    property bool diagnosticsLoaded: false
    property bool diagnosticsWarning: false
    property string message: ""
    property bool restoreArmed: false

    signal navigateRequested(int pageIndex, string label)

    visible: root.opened || root.opacity > 0.01
    enabled: root.opened
    opacity: root.opened ? 1 : 0

    Behavior on opacity {
        MotionAnim {
            type: MotionAnim.DefaultEffects
        }
    }

    function titleForMode(): string {
        if (root.mode === "favorites")
            return "Favorite settings"
        if (root.mode === "recent")
            return "Recent changes"
        if (root.mode === "context")
            return (
                root.pages[root.currentPage]?.name
                    ? `${root.pages[root.currentPage].name} controls`
                    : "Current page controls"
            )
        if (root.mode === "diagnostics")
            return "Settings diagnostics"
        return "Search settings"
    }

    function subtitleForMode(): string {
        if (root.mode === "favorites")
            return "Pinned controls you want close at hand"
        if (root.mode === "recent")
            return "Changes observed while Settings is open"
        if (root.mode === "context")
            return "Search only inside the current Settings page"
        if (root.mode === "diagnostics")
            return "Configuration and shell integration health"
        return "Search pages, sections and individual controls"
    }

    function containsFavorite(id): bool {
        for (let i = 0; i < root.favoriteIds.length; ++i) {
            if (root.favoriteIds[i] === id)
                return true
        }
        return false
    }

    function normalized(value): string {
        return String(value === undefined || value === null ? "" : value).toLowerCase().trim()
    }

    function searchEntries(): var {
        const query = root.normalized(searchInput.text)
        let output = []

        for (let i = 0; i < SearchIndex.entries.length; ++i) {
            const entry = SearchIndex.entries[i]

            if (
                root.mode === "context"
                && entry.pageIndex !== root.currentPage
            ) {
                continue
            }

            if (
                root.mode === "favorites"
                && !root.containsFavorite(entry.id)
            ) {
                continue
            }

            if (query.length > 0) {
                const haystack =
                    root.normalized(
                        `${entry.page} ${entry.label} ${entry.path} ${entry.keywords}`
                    )

                const words = query.split(/\s+/)
                let matches = true

                for (let w = 0; w < words.length; ++w) {
                    if (
                        words[w].length > 0
                        && haystack.indexOf(words[w]) < 0
                    ) {
                        matches = false
                        break
                    }
                }

                if (!matches)
                    continue
            }

            output.push(entry)

            if (output.length >= 80)
                break
        }

        return output
    }

    function flattenHistory(events): var {
        let rows = []

        for (let i = events.length - 1; i >= 0; --i) {
            const event = events[i]
            const changes = event.changes ?? []

            for (let j = 0; j < changes.length; ++j) {
                rows.push({
                    "timestamp": event.timestamp ?? 0,
                    "path": changes[j].path ?? "",
                    "old": changes[j].old,
                    "new": changes[j].new
                })

                if (rows.length >= 40)
                    return rows
            }
        }

        return rows
    }

    function displayValue(value): string {
        if (
            value
            && typeof value === "object"
            && value.__missing__ === true
        ) {
            return "unset"
        }

        if (value === null)
            return "null"

        if (typeof value === "boolean")
            return value ? "On" : "Off"

        if (typeof value === "string")
            return value

        try {
            const encoded = JSON.stringify(value)
            return encoded.length > 52
                ? encoded.slice(0, 49) + "…"
                : encoded
        } catch (error) {
            return String(value)
        }
    }

    function formatAge(timestamp): string {
        if (!timestamp)
            return ""

        const delta =
            Math.max(0, Date.now() / 1000 - Number(timestamp))

        if (delta < 60)
            return "now"
        if (delta < 3600)
            return `${Math.floor(delta / 60)}m`
        if (delta < 86400)
            return `${Math.floor(delta / 3600)}h`

        return `${Math.floor(delta / 86400)}d`
    }

    function open(modeName): void {
        root.mode = modeName
        root.message = ""
        root.restoreArmed = false
        root.opened = true
        root.forceActiveFocus()

        if (
            modeName === "search"
            || modeName === "favorites"
            || modeName === "context"
        ) {
            searchInput.text = ""
            root.loadFavorites()
            Qt.callLater(() => searchInput.forceActiveFocus())
        } else if (modeName === "recent") {
            root.loadHistory()
        } else if (modeName === "diagnostics") {
            root.loadDiagnostics()
        }
    }

    function close(): void {
        root.opened = false
        root.restoreArmed = false
    }

    function runAction(kind, args): void {
        if (actionProc.running || root.helperPath.length === 0)
            return

        actionProc.actionKind = kind
        const command = ["python3", root.helperPath, kind]

        if (args) {
            for (let i = 0; i < args.length; ++i)
                command.push(String(args[i]))
        }

        actionProc.exec(command)
    }

    function refreshSummary(): void {
        root.runAction("status", [])
    }

    function loadFavorites(): void {
        root.runAction("favorites", [])
    }

    function loadHistory(): void {
        root.runAction("history", [])
    }

    function loadDiagnostics(): void {
        root.diagnosticsLoaded = false

        if (actionProc.running) {
            diagnosticsRetryTimer.restart()
            return
        }

        root.runAction("status", [])
    }

    function toggleFavorite(id): void {
        root.runAction("toggle-favorite", [id])
    }

    function undoLast(): void {
        root.runAction("undo", [])
    }

    function backupConfig(): void {
        root.runAction("backup", [])
    }

    function requestRestore(): void {
        if (!root.restoreArmed) {
            root.restoreArmed = true
            restoreArmTimer.restart()
            root.message =
                "Press Restore latest again to confirm."
            return
        }

        root.restoreArmed = false
        root.runAction("restore-latest", [])
    }

    function consumeAction(kind, payload): void {
        if (payload.favorite_count !== undefined)
            root.favoriteCount = payload.favorite_count

        if (payload.history_count !== undefined)
            root.historyCount = payload.history_count

        if (payload.can_undo !== undefined)
            root.canUndo = payload.can_undo

        if (payload.diagnostics_ok !== undefined)
            root.diagnosticsOk = payload.diagnostics_ok

        if (payload.favorites !== undefined) {
            root.favoriteIds = payload.favorites
            root.favoriteCount = payload.favorites.length
        }

        if (payload.history !== undefined) {
            root.historyItems =
                root.flattenHistory(payload.history)
            root.historyCount = root.historyItems.length
        }

        if (kind === "status") {
            root.diagnostics = payload
            root.diagnosticsLoaded = true
            root.diagnosticsWarning =
                Number(payload.warning_count ?? 0) > 0
        }

        if (payload.message !== undefined)
            root.message = payload.message

        if (
            kind === "toggle-favorite"
            || kind === "undo"
            || kind === "backup"
            || kind === "restore-latest"
        ) {
            Qt.callLater(() => root.refreshSummary())

            if (root.mode === "favorites")
                Qt.callLater(() => root.loadFavorites())

            if (root.mode === "recent")
                Qt.callLater(() => root.loadHistory())

            if (root.mode === "diagnostics")
                Qt.callLater(() => root.loadDiagnostics())
        }
    }

    Process {
        id: actionProc

        property string actionKind: ""

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.consumeAction(
                        actionProc.actionKind,
                        JSON.parse(this.text)
                    )
                } catch (error) {
                    root.message =
                        `Control action failed: ${error}`
                }
            }
        }
    }

    Process {
        id: snapshotProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const payload = JSON.parse(this.text)

                    if (payload.history_count !== undefined)
                        root.historyCount = payload.history_count

                    if (payload.favorite_count !== undefined)
                        root.favoriteCount = payload.favorite_count

                    if (payload.can_undo !== undefined)
                        root.canUndo = payload.can_undo
                } catch (error) {
                }
            }
        }
    }

    Timer {
        interval: 1200
        repeat: true
        running: true

        onTriggered: {
            if (
                !snapshotProc.running
                && root.helperPath.length > 0
            ) {
                snapshotProc.exec([
                    "python3",
                    root.helperPath,
                    "snapshot"
                ])
            }
        }
    }

    Timer {
        id: diagnosticsRetryTimer
        interval: 180
        repeat: false

        onTriggered: {
            if (root.mode === "diagnostics" && root.opened)
                root.loadDiagnostics()
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true

        onTriggered: {
            if (!actionProc.running)
                root.refreshSummary()
        }
    }

    Timer {
        id: restoreArmTimer
        interval: 5000
        repeat: false
        onTriggered: root.restoreArmed = false
    }

    Component.onCompleted: {
        if (root.helperPath.length > 0) {
            snapshotProc.exec([
                "python3",
                root.helperPath,
                "snapshot"
            ])
            Qt.callLater(() => root.refreshSummary())
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if (!root.opened)
            return

        if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.16)

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // prism-v2-phase7: settings search/favorites/history is a depth-2
    // interactive surface, not a generic card floating beside the rail.
    PrismSurface {
        visible: Appearance.prismMode
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        depth: Appearance.prism.depthInteractive
        surfaceRadius: Appearance.prism.radiusInteractive
        elevated: true
    }

    Rectangle {
        id: panel

        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            leftMargin: root.opened ? 72 : 60
            topMargin: 70
            bottomMargin: 18
        }

        width: Math.min(520, parent.width - 96)

        radius:
            Appearance.inlayMode
                ? 0
                : Appearance.prismMode
                    ? Appearance.prism.radiusInteractive
                    : Appearance.radius.card
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

        Behavior on anchors.leftMargin {
            MotionAnim {
                type: MotionAnim.FastSpatial
            }
        }

        ColumnLayout {
            anchors {
                fill: parent
                margins: 14
            }

            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.titleForMode()
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight

                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.large
                            weight: Font.DemiBold
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.subtitleForMode()
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    activeFocusOnTab: true
                    Accessible.name: "Close panel"

                    buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
                    buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.radius.control
                    colBackground: Appearance.inlayMode ? Appearance.inlay.controlFill : "transparent"
                    colBackgroundHover: Appearance.inlayMode ? Appearance.inlay.hoverFill : Appearance.colors.colLayer2Hover
                    colRipple: Appearance.inlayMode ? Appearance.inlay.pressedFill : Appearance.colors.colLayer2Active

                    onClicked: root.close()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            Rectangle {
                visible:
                    root.mode === "search"
                    || root.mode === "favorites"
                    || root.mode === "context"

                Layout.fillWidth: true
                Layout.preferredHeight: 42

                radius: Appearance.inlayMode ? 0 : Appearance.radius.control
                color: Appearance.inlayMode ? Appearance.inlay.controlFill : Appearance.colors.colLayer1Base
                border.width: searchInput.activeFocus ? 2 : 1
                border.color:
                    Appearance.inlayMode
                        ? (searchInput.activeFocus ? Appearance.inlay.borderFocus : Appearance.inlay.borderControl)
                        : searchInput.activeFocus
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer0Border

                TextField {
                    id: searchInput

                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12
                    }

                    leftPadding: 24
                    rightPadding: 4

                    placeholderText:
                        root.mode === "favorites"
                            ? "Filter favorites…"
                            : root.mode === "context"
                                ? "Find on this page…"
                                : "Search settings…"

                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colSubtext
                    selectionColor: Appearance.colors.colPrimaryContainer
                    selectedTextColor:
                        Appearance.colors.colOnPrimaryContainer

                    font {
                        family: Appearance.font.family.main
                        pixelSize: Appearance.font.pixelSize.small
                    }

                    background: null

                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => {
                        if (event.modifiers !== Qt.NoModifier)
                            return

                        if (event.key === Qt.Key_Down) {
                            root.focusSearchResult(0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            root.focusSearchResult(
                                searchResults.count - 1
                            )
                            event.accepted = true
                        }
                    }

                    Keys.onReturnPressed: {
                        const entries = root.searchEntries()

                        if (entries.length > 0)
                            root.activateSearchEntry(entries[0])
                    }
                }

                MaterialSymbol {
                    anchors {
                        left: parent.left
                        leftMargin: 12
                        verticalCenter: parent.verticalCenter
                    }

                    text: "search"
                    iconSize: 17
                    color: Appearance.colors.colSubtext
                }
            }

            Item {
                visible:
                    root.mode === "search"
                    || root.mode === "favorites"
                    || root.mode === "context"

                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: searchResults
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: root.searchEntries()

                    delegate: RippleButton {
                        id: resultButton

                        required property int index
                        required property var modelData

                        width: ListView.view.width
                        implicitHeight: 54

                        activeFocusOnTab: true
                        Accessible.name:
                            `${modelData.page}: ${modelData.label}`

                        buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
                        buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.radius.control
                        colBackground:
                            resultButton.activeFocus
                                ? Appearance.colors.colLayer2Base
                                : "transparent"
                        colBackgroundHover:
                            Appearance.colors.colLayer2Hover
                        colRipple:
                            Appearance.colors.colLayer2Active

                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => {
                            if (event.modifiers !== Qt.NoModifier)
                                return

                            if (event.key === Qt.Key_Down) {
                                root.focusSearchResult(index + 1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                if (index <= 0)
                                    searchInput.forceActiveFocus(Qt.TabFocusReason)
                                else
                                    root.focusSearchResult(index - 1)

                                event.accepted = true
                            } else if (event.key === Qt.Key_Home) {
                                root.focusSearchResult(0)
                                event.accepted = true
                            } else if (event.key === Qt.Key_End) {
                                root.focusSearchResult(
                                    searchResults.count - 1
                                )
                                event.accepted = true
                            } else if (
                                event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter
                            ) {
                                root.activateSearchEntry(modelData)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Left) {
                                searchInput.forceActiveFocus(Qt.TabFocusReason)
                                event.accepted = true
                            }
                        }

                        onClicked:
                            root.activateSearchEntry(modelData)

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 6
                            }

                            spacing: 8

                            MaterialSymbol {
                                text: "tune"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: resultButton.modelData.label
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize:
                                        Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text:
                                        resultButton.modelData.path.length > 0
                                            ? `${resultButton.modelData.page} › ${resultButton.modelData.path}`
                                            : resultButton.modelData.page

                                    color: Appearance.colors.colSubtext
                                    font.pixelSize:
                                        Appearance.font.pixelSize.smallest
                                    elide: Text.ElideRight
                                }
                            }

                            RippleButton {
                                implicitWidth: 34
                                implicitHeight: 34
                                activeFocusOnTab: true

                                Accessible.name:
                                    root.containsFavorite(
                                        resultButton.modelData.id
                                    )
                                        ? "Remove favorite"
                                        : "Add favorite"

                                buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
                                buttonRadiusPressed:
                                    Appearance.inlayMode ? 0 : Appearance.radius.control
                                colBackground: "transparent"
                                colBackgroundHover:
                                    Appearance.colors.colLayer2Hover
                                colRipple:
                                    Appearance.colors.colLayer2Active

                                onClicked:
                                    root.toggleFavorite(
                                        resultButton.modelData.id
                                    )

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text:
                                        root.containsFavorite(
                                            resultButton.modelData.id
                                        )
                                            ? "star"
                                            : "star_outline"

                                    fill:
                                        root.containsFavorite(
                                            resultButton.modelData.id
                                        ) ? 1 : 0

                                    iconSize: 18
                                    color:
                                        root.containsFavorite(
                                            resultButton.modelData.id
                                        )
                                            ? Appearance.colors.colPrimary
                                            : Appearance.colors.colSubtext
                                }
                            }
                        }
                    }

                    footer: Item {
                        width: searchResults.width
                        height: searchResults.count === 0 ? 92 : 0

                        Column {
                            visible: searchResults.count === 0
                            anchors.centerIn: parent
                            spacing: 4

                            MaterialSymbol {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter
                                text:
                                    root.mode === "favorites"
                                        ? "star_outline"
                                        : "search_off"
                                iconSize: 24
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter
                                text:
                                    root.mode === "favorites"
                                        ? "No favorite settings yet"
                                        : "No matching settings"
                                color: Appearance.colors.colSubtext
                                font.pixelSize:
                                    Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.mode === "recent"
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: historyList

                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: root.historyItems

                    delegate: Rectangle {
                        required property var modelData

                        width: ListView.view.width
                        implicitHeight: 58
                        radius: Appearance.inlayMode ? 0 : Appearance.radius.control
                        color: Appearance.inlayMode ? Appearance.inlay.insetFill : Appearance.colors.colLayer1Base

                        RowLayout {
                            anchors {
                                fill: parent
                                margins: 10
                            }

                            spacing: 8

                            MaterialSymbol {
                                text: "history"
                                iconSize: 17
                                color: Appearance.colors.colSubtext
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.path
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize:
                                        Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideMiddle
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text:
                                        `${root.displayValue(modelData.old)} → ${root.displayValue(modelData.new)}`

                                    color: Appearance.colors.colSubtext
                                    font.pixelSize:
                                        Appearance.font.pixelSize.smallest
                                    elide: Text.ElideRight
                                }
                            }

                            StyledText {
                                text:
                                    root.formatAge(modelData.timestamp)
                                color: Appearance.colors.colSubtext
                                font.pixelSize:
                                    Appearance.font.pixelSize.smallest
                            }
                        }
                    }

                    footer: Item {
                        width: historyList.width
                        height: historyList.count === 0 ? 110 : 0

                        Column {
                            visible: historyList.count === 0
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialSymbol {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter
                                text: "history"
                                iconSize: 26
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter
                                text: "No changes recorded yet"
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.mode === "diagnostics"
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 174

                        radius: Appearance.inlayMode ? 0 : Appearance.radius.card
                        color: Appearance.inlayMode ? Appearance.inlay.insetFill : Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.inlayMode ? Appearance.inlay.borderSection : Appearance.colors.colLayer0Border

                        ColumnLayout {
                            anchors {
                                fill: parent
                                margins: 12
                            }

                            spacing: 6

                            StyledText {
                                text: "Health"
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                visible: !root.diagnosticsLoaded
                                text: "Checking Settings, Hyprland and Quickshell…"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                visible: root.diagnosticsLoaded
                                text:
                                    root.diagnostics.config_valid
                                        ? "✓ config.json is valid"
                                        : "✕ config.json is invalid"
                                color:
                                    root.diagnostics.config_valid
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.m3colors.m3error
                            }

                            StyledText {
                                visible: root.diagnosticsLoaded
                                text:
                                    root.diagnostics.hyprland_ok
                                        ? "✓ Hyprland integration available"
                                        : "✕ Hyprland integration unavailable"
                                color:
                                    root.diagnostics.hyprland_ok
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.m3colors.m3error
                            }

                            StyledText {
                                visible: root.diagnosticsLoaded
                                text:
                                    root.diagnostics.shell_running
                                        ? "✓ Main Quickshell instance running"
                                        : "! Main Quickshell instance not detected"
                                color:
                                    root.diagnostics.shell_running
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.m3colors.m3error
                            }

                            StyledText {
                                visible: root.diagnosticsLoaded
                                text:
                                    root.diagnostics.hyprland_config_errors_available
                                        ? Number(root.diagnostics.hyprland_config_error_count ?? 0) === 0
                                            ? "✓ No Hyprland config errors"
                                            : `✕ ${root.diagnostics.hyprland_config_error_count} Hyprland config error(s)`
                                        : "• Hyprland config-error check unavailable"
                                color:
                                    Number(root.diagnostics.hyprland_config_error_count ?? 0) === 0
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.m3colors.m3error
                            }

                            StyledText {
                                visible:
                                    root.diagnosticsLoaded
                                    && root.diagnosticsWarning
                                text:
                                    "⚠ Legacy Hyprland .conf config — migrate before 0.57"
                                color: Appearance.colors.colPrimary
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 104

                        radius: Appearance.inlayMode ? 0 : Appearance.radius.card
                        color: Appearance.inlayMode ? Appearance.inlay.insetFill : Appearance.colors.colLayer1Base
                        border.width: 1
                        border.color: Appearance.inlayMode ? Appearance.inlay.borderSection : Appearance.colors.colLayer0Border

                        ColumnLayout {
                            anchors {
                                fill: parent
                                margins: 12
                            }

                            spacing: 5

                            StyledText {
                                text: "Settings tools"
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                text:
                                    `${SearchIndex.entries.length} indexed search targets · ${root.favoriteCount} favorites · ${root.historyCount} recent changes`

                                color: Appearance.colors.colSubtext
                                font.pixelSize:
                                    Appearance.font.pixelSize.smallest
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text:
                                    root.diagnostics.config_path ?? ""
                                color: Appearance.colors.colSubtext
                                font.pixelSize:
                                    Appearance.font.pixelSize.smallest
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 38
                            activeFocusOnTab: true
                            Accessible.name: "Backup configuration"

                            buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
                            buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.radius.control
                            colBackground:
                                Appearance.colors.colLayer2Base
                            colBackgroundHover:
                                Appearance.colors.colLayer2Hover
                            colRipple:
                                Appearance.colors.colLayer2Active

                            onClicked: root.backupConfig()

                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: "Backup config"
                                color: Appearance.colors.colOnLayer2
                                font.weight: Font.DemiBold
                            }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 38
                            activeFocusOnTab: true
                            Accessible.name: "Restore latest backup"

                            buttonRadius: Appearance.inlayMode ? 0 : Appearance.radius.control
                            buttonRadiusPressed: Appearance.inlayMode ? 0 : Appearance.radius.control

                            colBackground:
                                root.restoreArmed
                                    ? Appearance.colors.colErrorContainer
                                    : Appearance.colors.colLayer2Base

                            colBackgroundHover:
                                root.restoreArmed
                                    ? Appearance.colors.colErrorContainerHover
                                    : Appearance.colors.colLayer2Hover

                            colRipple:
                                root.restoreArmed
                                    ? Appearance.colors.colErrorContainerActive
                                    : Appearance.colors.colLayer2Active

                            onClicked: root.requestRestore()

                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text:
                                    root.restoreArmed
                                        ? "Confirm restore"
                                        : "Restore latest"
                                color:
                                    root.restoreArmed
                                        ? Appearance.colors.colOnErrorContainer
                                        : Appearance.colors.colOnLayer2
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            Rectangle {
                visible: root.message.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: Appearance.inlayMode ? 0 : Appearance.radius.control
                color: Appearance.inlayMode ? Appearance.inlay.controlFill : Appearance.colors.colLayer2Base

                StyledText {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                    }

                    verticalAlignment: Text.AlignVCenter
                    text: root.message
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }
        }
    }
}
