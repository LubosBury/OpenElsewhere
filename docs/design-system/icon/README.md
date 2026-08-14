# OpenElsewhere — Fork icon package

Source of truth: `fork-master.svg` (1024, glow, sheen) and `fork-master-small.svg`
(heavier stroke, no glow — used for the 16/32/64 px renders). Glyph-only files:
`fork-glyph-accent.svg` (#73AEFF) and `fork-glyph-template.svg` (black, for template rendering).

## Where the rasters live

The rendered sets are installed in the catalog; only the vectors above are kept here, as the
source to re-render from.

- `OpenElsewhere/Resources/Assets.xcassets/AppIcon.appiconset` — every mac idiom slot
  (16/32/128/256/512 at 1x and 2x). `ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml` is
  what makes `actool` emit it as the app icon.
- `OpenElsewhere/Resources/Assets.xcassets/MenuBarIconTemplate.imageset` — 18 pt at 1x, carrying
  `template-rendering-intent: template`, so the menu bar tints it for light/dark and for the
  highlighted state. Used by `OpenElsewhereApp` as
  `Image("MenuBarIconTemplate").renderingMode(.template)`.

Assets.xcassets is listed under `sources:` in `project.yml`, so files added inside it need no
`xcodegen generate`.

## Geometry

512 grid, 38 stroke (46 for the small master), round caps and joins. One source node at the
bottom, two branches: the routed branch and its node are full accent, the unused branch sits at
42% — that pair is the one glowing element in the mark, per the design system's glow ceiling.
Tile: 824×824 inside a 1024 canvas, radius 185, navy gradient #1A2757 → #080E24, 4px white
hairline at 16%, top sheen at 16%.

Filenames use `-2x` rather than `@2x`, and `Contents.json` matches — which is all Xcode requires.
Rename both together if you prefer Apple's convention.
