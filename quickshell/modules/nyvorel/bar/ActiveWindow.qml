import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets


Item {
    id: root

    readonly property HyprlandMonitor monitor:
        Hyprland.monitorFor(root.QsWindow.window?.screen)

    readonly property Toplevel activeWindow:
        ToplevelManager.activeToplevel

    readonly property bool focusingThisMonitor:
        HyprlandData.activeWorkspace?.monitor === monitor?.name

    readonly property var biggestWindow:
        HyprlandData.biggestWindowForWorkspace(
            HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id
        )


    // ============================================================
    // APP ID
    // ============================================================

    readonly property string currentAppId: {
        if (
            root.focusingThisMonitor
            && root.activeWindow?.activated
        ) {
            return root.activeWindow?.appId ?? ""
        }

        return root.biggestWindow?.class ?? ""
    }


    // ============================================================
    // WINDOW TITLE
    // ============================================================

    readonly property string currentWindowTitle: {
        if (
            !root.focusingThisMonitor
            || !root.activeWindow?.activated
        ) {
            return ""
        }

        return root.activeWindow?.title ?? ""
    }


    // ============================================================
    // PRETTY APP NAME
    // ============================================================

    function prettyAppName(appId) {
        if (!appId || appId.length === 0) {
            return `${Translation.tr("Workspace")} ${
                monitor?.activeWorkspace?.id ?? 1
            }`
        }

        const id = appId.toLowerCase()

        if (
            id === "code"
            || id.includes("visual-studio-code")
        ) {
            return "VS Code"
        }

        if (id.includes("chatgpt"))
            return "ChatGPT"

        if (id.includes("firefox"))
            return "Firefox"

        if (id.includes("chromium"))
            return "Chromium"

        if (
            id.includes("google-chrome")
            || id.includes("google_chrome")
        ) {
            return "Chrome"
        }

        if (id.includes("kitty"))
            return "Kitty"

        if (id.includes("dolphin"))
            return "Dolphin"

        if (id.includes("spotify"))
            return "Spotify"

        if (id.includes("discord"))
            return "Discord"

        if (id.includes("telegram"))
            return "Telegram"

        if (id.includes("obsidian"))
            return "Obsidian"

        if (id.includes("thunderbird"))
            return "Thunderbird"


        // Example:
        // org.kde.dolphin -> dolphin
        let name = appId.split(".").pop()

        // foo-bar -> Foo Bar
        name = name
            .replace(/[-_]/g, " ")
            .replace(
                /\b\w/g,
                character => character.toUpperCase()
            )

        return name
    }


    readonly property string appName:
        prettyAppName(currentAppId)


    // ============================================================
    // CLEAN WINDOW TITLE
    // ============================================================

    function cleanWindowTitle(title, appName) {
        if (!title || title.length === 0)
            return ""

        let cleaned = title.trim()

        // Kitty publishes machine-readable metadata in its window title
        // for the custom developer tab/status bar. Keep that protocol
        // untouched for Kitty, but present a human-friendly title here.
        if (
            appName === "Kitty"
            && cleaned.startsWith("NYVOREL_DEVBAR::")
        ) {
            const fields = cleaned.split("::")

            const location =
                fields.length > 7
                    ? fields[7].trim()
                    : ""

            if (location.length > 0)
                return location

            const projectRoot =
                fields.length > 8
                    ? fields[8].trim()
                    : ""

            if (projectRoot.length > 0) {
                const parts = projectRoot.split("/")

                for (let i = parts.length - 1; i >= 0; --i) {
                    if (parts[i].length > 0)
                        return parts[i]
                }
            }

            return Translation.tr("Terminal")
        }

        // Remove common app suffixes.
        const suffixes = [
            " - Visual Studio Code",
            " — Visual Studio Code",
            " - Mozilla Firefox",
            " — Mozilla Firefox",
            " - Google Chrome",
            " — Google Chrome",
            " - Chromium",
            " — Chromium"
        ]

        for (const suffix of suffixes) {
            if (cleaned.endsWith(suffix)) {
                cleaned = cleaned.slice(
                    0,
                    cleaned.length - suffix.length
                ).trim()
            }
        }

        // Don't display duplicate content:
        //
        // ChatGPT · ChatGPT
        //
        if (
            cleaned.toLowerCase()
            === appName.toLowerCase()
        ) {
            return ""
        }

        return cleaned
    }


    readonly property string cleanTitle:
        cleanWindowTitle(
            currentWindowTitle,
            appName
        )


    // ============================================================
    // FINAL TEXT
    // ============================================================

    readonly property string displayText: {
        if (cleanTitle.length === 0)
            return appName

        return `${appName} · ${cleanTitle}`
    }


    // ============================================================
    // APP ICON
    // ============================================================

    readonly property string appIcon: {
        if (
            !currentAppId
            || currentAppId.length === 0
        ) {
            return ""
        }

        return Quickshell.iconPath(
            AppSearch.guessIcon(currentAppId),
            "image-missing"
        )
    }


    // ============================================================
    // SIZE
    // ============================================================

    implicitWidth:
        Math.min(content.implicitWidth, 280)

    implicitHeight:
        Appearance.sizes.barHeight


    // ============================================================
    // CONTENT
    // ============================================================

    RowLayout {
        id: content

        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }

        spacing: 6


        IconImage {
            Layout.alignment:
                Qt.AlignVCenter

            source:
                root.appIcon

            implicitSize:
                18

            // IconImage exposes its backing QtQuick Image through `backer`.
            // Image-only sampling properties must be applied there.
            backer.sourceSize:
                Qt.size(64, 64)

            backer.smooth:
                true

            asynchronous:
                true

            mipmap:
                true
        }


        StyledText {
            Layout.alignment:
                Qt.AlignVCenter

            Layout.maximumWidth:
                245

            font {
                pixelSize:
                    Appearance.font.pixelSize.small

                weight:
                    Font.Medium
            }

            color:
                Appearance.colors.colOnLayer0

            text:
                root.displayText

            elide:
                Text.ElideRight

            maximumLineCount:
                1
        }
    }
}