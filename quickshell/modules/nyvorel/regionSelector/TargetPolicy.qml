pragma Singleton

import Quickshell

Singleton {
    id: root

    function area(region) {
        if (!region || !region.size)
            return 0
        return Math.max(0, region.size[0]) * Math.max(0, region.size[1])
    }

    function contains(region, x, y) {
        if (!region || !region.at || !region.size)
            return false
        return (
            region.at[0] <= x
            && x <= region.at[0] + region.size[0]
            && region.at[1] <= y
            && y <= region.at[1] + region.size[1]
        )
    }

    function centerDistance(region, x, y) {
        const centerX = region.at[0] + region.size[0] / 2
        const centerY = region.at[1] + region.size[1] / 2
        const dx = centerX - x
        const dy = centerY - y
        return Math.sqrt(dx * dx + dy * dy)
    }

    function normalizedCenterAffinity(region, x, y) {
        const halfDiagonal = Math.max(
            1,
            Math.sqrt(
                region.size[0] * region.size[0]
                + region.size[1] * region.size[1]
            ) / 2
        )
        return 1 - Math.min(
            1,
            root.centerDistance(region, x, y) / halfDiagonal
        )
    }

    function isTerminalWindow(region) {
        if (!region)
            return false

        const identity = (
            `${region.class ?? ""} ${region.title ?? ""}`
        ).toLowerCase()

        return (
            identity.includes("kitty")
            || identity.includes("alacritty")
            || identity.includes("wezterm")
            || identity.includes("konsole")
            || identity.includes("gnome-terminal")
            || identity.includes("xterm")
            || identity.includes("foot")
            || identity.includes("terminal")
        )
    }

    function compactHighConfidence(region, screenWidth, screenHeight) {
        if (!region)
            return false

        const width = region.size[0]
        const height = region.size[1]
        const screenArea = Math.max(1, screenWidth * screenHeight)
        const regionArea = root.area(region)
        const aspect = width / Math.max(1, height)
        const score = region.score ?? 0
        const rectangularity = region.rectangularity ?? 0
        const edgeSupport = region.edgeSupport ?? region.edge_support ?? 0

        return (
            width >= Math.max(84, screenWidth * 0.044)
            && height >= Math.max(36, screenHeight * 0.032)
            && regionArea >= screenArea * 0.0010
            && aspect >= 0.16
            && aspect <= 9.0
            && score >= 0.80
            && (
                rectangularity >= 0.32
                || edgeSupport >= 0.035
                || score >= 1.10
            )
        )
    }

    function contentUseful(region, container, screenWidth, screenHeight) {
        if (!region || !region.size)
            return false

        const width = region.size[0]
        const height = region.size[1]
        const screenArea = Math.max(1, screenWidth * screenHeight)
        const regionArea = root.area(region)
        const aspect = width / Math.max(1, height)
        const compact = root.compactHighConfidence(
            region,
            screenWidth,
            screenHeight
        )

        // Broad low-level detector, conservative policy layer.
        if (!compact && (width < 132 || height < 64))
            return false

        if (aspect < 0.16 || aspect > (compact ? 9.0 : 6.2))
            return false

        if (
            regionArea < screenArea * 0.0010
            || regionArea > screenArea * 0.66
        ) {
            return false
        }

        if (container) {
            const containerArea = root.area(container)
            if (containerArea <= 0)
                return false

            const ratio = regionArea / containerArea
            const evidence = region.score ?? 0
            const minRatio = evidence >= 1.05
                ? 0.008
                : (compact ? 0.012 : 0.028)

            if (ratio < minRatio || ratio > 0.68)
                return false

            // Keep inferred content genuinely inside the client. This rejects
            // titlebar/window-edge contours while allowing compact cards.
            const margin = 4
            if (
                region.at[0] < container.at[0] + margin
                || region.at[1] < container.at[1] + margin
                || region.at[0] + width
                    > container.at[0] + container.size[0] - margin
                || region.at[1] + height
                    > container.at[1] + container.size[1] - margin
            ) {
                return false
            }
        }

        return true
    }

    function windowEdgeDistance(windowRegion, x, y) {
        if (!windowRegion)
            return 1000000000

        return Math.min(
            Math.abs(x - windowRegion.at[0]),
            Math.abs(y - windowRegion.at[1]),
            Math.abs(windowRegion.at[0] + windowRegion.size[0] - x),
            Math.abs(windowRegion.at[1] + windowRegion.size[1] - y)
        )
    }

    function contentScore(region, container, x, y, screenWidth, screenHeight) {
        const evidence = region.score ?? 0
        const rectangularity = region.rectangularity ?? 0
        const edgeSupport = region.edgeSupport ?? region.edge_support ?? 0
        const radiusConfidence = region.radiusConfidence ?? 0
        const compact = root.compactHighConfidence(
            region,
            screenWidth,
            screenHeight
        )
        const affinity = root.normalizedCenterAffinity(region, x, y)

        let specificity = 0
        if (container) {
            const ratio = root.area(region) / Math.max(1, root.area(container))
            specificity = Math.max(0, 1 - Math.min(1, ratio / 0.55))
        }

        return (
            700
            + Math.min(2.5, evidence) * 72
            + Math.min(1, rectangularity) * 48
            + Math.min(0.25, edgeSupport) * 160
            + specificity * 100
            + affinity * 35
            + Math.min(1, radiusConfidence) * 22
            + (compact ? 55 : 0)
        )
    }

    function bestShellAt(x, y, shellRegions) {
        const candidates = shellRegions.filter(
            region => root.contains(region, x, y)
        )

        if (candidates.length === 0)
            return null

        candidates.sort((a, b) => {
            const priorityDiff = (b.priority ?? 0) - (a.priority ?? 0)
            if (priorityDiff !== 0)
                return priorityDiff
            return root.area(a) - root.area(b)
        })
        return candidates[0]
    }

    function bestTargetAt(
        x,
        y,
        shellRegions,
        contentRegions,
        windowRegions,
        layerRegions,
        enableContent,
        enableWindows,
        enableLayers,
        screenWidth,
        screenHeight
    ) {
        const shell = root.bestShellAt(x, y, shellRegions)
        if (shell)
            return shell

        const containingWindow = windowRegions.find(
            region => root.contains(region, x, y)
        ) ?? null

        // Terminal contents are visually noisy and command text is often
        // mistaken for cards. Preserve predictable whole-window behavior.
        if (
            enableWindows
            && containingWindow
            && root.isTerminalWindow(containingWindow)
        ) {
            return containingWindow
        }

        const candidates = []

        if (enableContent) {
            for (const region of contentRegions) {
                if (
                    root.contains(region, x, y)
                    && root.contentUseful(
                        region,
                        containingWindow,
                        screenWidth,
                        screenHeight
                    )
                ) {
                    candidates.push({
                        target: region,
                        score: root.contentScore(
                            region,
                            containingWindow,
                            x,
                            y,
                            screenWidth,
                            screenHeight
                        )
                    })
                }
            }
        }

        if (enableLayers) {
            const layer = layerRegions.find(
                region => root.contains(region, x, y)
            )
            if (layer) {
                candidates.push({
                    target: layer,
                    score: 610 + root.normalizedCenterAffinity(layer, x, y) * 20
                })
            }
        }

        if (enableWindows && containingWindow) {
            const edgeDistance = root.windowEdgeDistance(
                containingWindow,
                x,
                y
            )
            const edgeBonus = edgeDistance <= 14 ? 380 : 0
            candidates.push({
                target: containingWindow,
                score: 430 + edgeBonus
            })
        }

        if (candidates.length === 0)
            return null

        candidates.sort((a, b) => {
            if (a.score !== b.score)
                return b.score - a.score
            return root.area(a.target) - root.area(b.target)
        })

        return candidates[0].target
    }
}
