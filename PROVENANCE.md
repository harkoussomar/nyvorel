# Nyvorel provenance

Nyvorel is a substantially modified derivative of
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland), whose root
license is GNU GPL version 3.

This file records provenance decisions for bundled source and assets. It is a
technical inventory, not legal advice.

## Cleared source/components

| Area | Provenance | License / treatment |
|---|---|---|
| Nyvorel shell source | Nyvorel modifications over end-4/dots-hyprland | GPL-3.0 |
| Waffle module tree | end-4/dots-hyprland | GPL-3.0 |
| common `widgetCanvas` | end-4/dots-hyprland | GPL-3.0 |
| translations | end-4/dots-hyprland translation tree, modified by Nyvorel where applicable | GPL-3.0 |
| terminal `scheme-base.json` | end-4/dots-hyprland | GPL-3.0 |
| rounded-polygon QML/JS shapes | end-4/rounded-polygon-qmljs | Apache-2.0; retain component license |
| Nyvorel logo | Nyvorel project-owned artwork | project asset distributed with Nyvorel |
| Default wallpaper (`quickshell/assets/images/default_wallpaper.png`) | Generated for Nyvorel on 2026-10-09 with the built-in image-generation tool; no third-party image input | Project default asset; replaces the inherited upstream wallpaper |

## Fluent icon family

The upstream Waffle README states that individual Fluent SVGs were downloaded
for the Waffle implementation and links Microsoft's Fluent iconography. The
authoritative Microsoft `fluentui-system-icons` repository is MIT licensed.

Nyvorel therefore preserves a copy of that MIT license in:
`LICENSES/MIT-Microsoft-Fluent-UI-System-Icons.txt`.

### Separate CC BY 4.0 Waffle icon family

The upstream icon README separately identifies the `start-here`,
`system-search`, and `task-view` families as modified assets originating from
the “Windows 11” Figma Community file by Joshua Oghenekaro Okwe, licensed
CC BY 4.0. See `LICENSES/CC-BY-4.0-NOTICE.txt`.

## Other explicit subcomponent licenses

- `quickshell/modules/common/widgets/shapes/`:
  Apache-2.0; central copy in
  `LICENSES/Apache-2.0-rounded-polygon-qmljs.txt`.
- `quickshell/assets/icons/fedora-symbolic.svg`:
  contains its own Font Awesome Free attribution; icon license CC BY 4.0.
- `quickshell/assets/icons/gentoo-symbolic.svg`:
  source metadata identifies Pictogrammers Material Design Icons. The
  Pictogrammers collection licenses icons under Apache-2.0; retain provenance
  and trademark context.

## Non-vendored references

The provenance scanner also detected names such as Material icons, Nerd Fonts,
and Tabler icons in code/documentation. Those detections do not establish that
a corresponding font or icon package is vendored as a separate binary
dependency in this staging tree.


## Inherited upstream assets

Nyvorel retains a set of brand/project SVGs inherited from
`end-4/dots-hyprland`.

These assets are not claimed as Nyvorel-owned material. Their upstream status,
project policy, and complete file list are documented in
`INHERITED_ASSETS.md`.

The brand/project SVGs are retained as inherited third-party interface assets
rather than being relicensed or represented as original Nyvorel artwork.
