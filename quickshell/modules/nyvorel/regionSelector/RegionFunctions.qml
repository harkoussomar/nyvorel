pragma Singleton
import Quickshell

Singleton {
    id: root

    function intersectionOverUnion(regionA, regionB) {
        // region: { at: [x, y], size: [w, h] }
        const ax1 = regionA.at[0], ay1 = regionA.at[1];
        const ax2 = ax1 + regionA.size[0], ay2 = ay1 + regionA.size[1];
        const bx1 = regionB.at[0], by1 = regionB.at[1];
        const bx2 = bx1 + regionB.size[0], by2 = by1 + regionB.size[1];

        const interX1 = Math.max(ax1, bx1);
        const interY1 = Math.max(ay1, by1);
        const interX2 = Math.min(ax2, bx2);
        const interY2 = Math.min(ay2, by2);

        const interArea = Math.max(0, interX2 - interX1) * Math.max(0, interY2 - interY1);
        const areaA = (ax2 - ax1) * (ay2 - ay1);
        const areaB = (bx2 - bx1) * (by2 - by1);
        const unionArea = areaA + areaB - interArea;

        return unionArea > 0 ? interArea / unionArea : 0;
    }

    function filterOverlappingImageRegions(regions, duplicateThreshold = 0.82) {
        // Preserve nested targets. Only collapse near-identical detector boxes.
        const sorted = [...regions].sort((a, b) => {
            const scoreDiff = (b.score ?? 0) - (a.score ?? 0)
            if (scoreDiff !== 0)
                return scoreDiff
            const areaA = a.size[0] * a.size[1]
            const areaB = b.size[0] * b.size[1]
            return areaA - areaB
        })

        const keep = []
        for (const region of sorted) {
            const duplicate = keep.some(
                kept =>
                    root.intersectionOverUnion(region, kept)
                    >= duplicateThreshold
            )
            if (!duplicate)
                keep.push(region)
        }
        return keep
    }

    function filterWindowRegionsByLayers(windowRegions, layerRegions) {
        return windowRegions.filter(windowRegion => {
            for (let i = 0; i < layerRegions.length; ++i) {
                if (intersectionOverUnion(windowRegion, layerRegions[i]) > 0)
                    return false;
            }
            return true;
        });
    }

    function filterImageRegions(regions, windowRegions) {
        // A content rectangle is expected to live inside a window. Do not
        // discard it just because it overlaps its parent. Reject only boxes
        // that are effectively a duplicate of the whole client.
        const filtered = regions.filter(region => {
            const regionArea = region.size[0] * region.size[1]

            for (const windowRegion of windowRegions) {
                const windowArea =
                    windowRegion.size[0] * windowRegion.size[1]
                if (windowArea <= 0)
                    continue

                const ratio = regionArea / windowArea
                const iou = root.intersectionOverUnion(
                    region,
                    windowRegion
                )

                if (ratio > 0.72 && iou > 0.55)
                    return false
            }
            return true
        })

        return root.filterOverlappingImageRegions(filtered)
    }
}
