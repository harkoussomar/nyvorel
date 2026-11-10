# Command Atlas art

This folder preserves the editable design references for the Nyvorel shortcut guide's Universe tab. The active shell loads the smaller images from [`quickshell/assets/planets/`](../../../quickshell/assets/planets/); those runtime files stay in place.

| Folder or file | Contents |
| --- | --- |
| [`source/`](source/) | Full-resolution transparent PNGs for the Nyvorel moon and eight planets, plus the original white moon SVG. |
| [`explorations/`](explorations/) | Earlier generated studies. These are retained for future design work and are not loaded by the shell. |
| [`concept-preview.html`](concept-preview.html) | Standalone HTML/CSS/JavaScript exploration. It reads the runtime planet PNGs through relative paths, so open it from this checkout. It predates the final QML refinements. |
| [`concept-preview.png`](concept-preview.png) | Still image of the early concept. |

## Source-to-runtime map

| High-resolution source | Shell asset |
| --- | --- |
| [`nyvorel-moon-3d.png`](source/nyvorel-moon-3d.png) | [`nyvorel-moon-3d.png`](../../../quickshell/assets/planets/nyvorel-moon-3d.png) |
| [`mercury.png`](source/mercury.png) | [`mercury.png`](../../../quickshell/assets/planets/mercury.png) |
| [`venus.png`](source/venus.png) | [`venus.png`](../../../quickshell/assets/planets/venus.png) |
| [`earth.png`](source/earth.png) | [`earth.png`](../../../quickshell/assets/planets/earth.png) |
| [`mars.png`](source/mars.png) | [`mars.png`](../../../quickshell/assets/planets/mars.png) |
| [`jupiter.png`](source/jupiter.png) | [`jupiter.png`](../../../quickshell/assets/planets/jupiter.png) |
| [`saturn.png`](source/saturn.png) | [`saturn.png`](../../../quickshell/assets/planets/saturn.png) |
| [`uranus.png`](source/uranus.png) | [`uranus.png`](../../../quickshell/assets/planets/uranus.png) |
| [`neptune.png`](source/neptune.png) | [`neptune.png`](../../../quickshell/assets/planets/neptune.png) |

The PNGs are generated artwork, not astronomy reference imagery. The source SVG is a copy of the supplied `moon_logo_white_transparent.svg`; the 3D moon was generated from its silhouette. The QML implementation lives in [`CheatsheetUniverse.qml`](../../../quickshell/modules/nyvorel/cheatsheet/CheatsheetUniverse.qml).
