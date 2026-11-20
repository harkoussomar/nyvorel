pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    function reapplyTheme() {
        themeFileView.reload()
    }

    property var previewColors: null
    property var committedColors: null
    property var prePreviewColors: null

    function materialKey(key: string): string {
        return "m3" + key.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())
    }

    function useColors(colors): void {
        for (const key of Object.keys(colors)) {
            const propertyName = materialKey(key)
            if (propertyName in Appearance.m3colors)
                Appearance.m3colors[propertyName] = colors[key]
        }
        Appearance.m3colors.darkmode = Appearance.m3colors.m3background.hslLightness < 0.5
    }

    function applyColors(fileContent: string): void {
        let colors
        try {
            colors = JSON.parse(fileContent)
        } catch (error) {
            return
        }
        if (!colors?.background)
            return
        committedColors = colors
        if (!previewColors)
            useColors(colors)
    }

    onPreviewColorsChanged: {
        if (previewColors) {
            if (!prePreviewColors) {
                const saved = ({})
                for (const key of Object.keys(previewColors)) {
                    const propertyName = materialKey(key)
                    if (propertyName in Appearance.m3colors)
                        saved[key] = Appearance.m3colors[propertyName]
                }
                prePreviewColors = saved
            }
            useColors(previewColors)
        } else if (prePreviewColors) {
            useColors(Object.assign({}, prePreviewColors, committedColors ?? ({})))
            prePreviewColors = null
        }
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }
}
