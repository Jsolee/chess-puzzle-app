# Scachs design system

Tokens: `brand/tokens.json`. Implementation: `Scachs/Design/Theme.swift`. Brand rules: `brand/BRAND.md`.

- **Colour strategy:** committed. The verd field `#0f3a33` carries every screen; gold `#e7b96c` is the one accent for interactive things.
- **Scene:** someone on a sofa at 11 pm with ten minutes, holding the phone low in lamplight. That forces a deep, low-luminance field with bright objects on it.
- **Type:** `Theme.display` (Grenze Gotisch, 28 pt and up, titles only). `Theme.text` (Ysabeau Office) for everything else, with a 1.25 step between levels. Screen titles are big and left-aligned.
- **Layout:** the board is full-bleed edge to edge. Content sits on the field with hairlines and space; no cards, no nested surfaces. Rows, not tiles.
- **Elevation:** none on the field. Only pieces cast shadows.
- **Motion:** 150-250 ms, ease-out quart, no bounce. The reflex wave is the single signature. `Reduce Motion` freezes tilt and shrinks the wave to a flash.
- **Glass:** system tab bar and toolbars only (iOS 26+ gives it free).
- **Components:** primary action is tin text with weight on the field, or gold for the current one. Buttons have no fill unless they're the screen's single primary action, then a tin capsule with ink text. Hit areas 44 pt minimum.
- **Move-class badge:** a small enamel disc with a dark glyph; `MoveClassBadge`. Classes are told apart by glyph, then colour.
- **Numbers:** always Ysabeau Office, tabular by default. Accuracy and rating read like instruments.
- **The Atlas:** the one exception to the field: a vellum portolan sheet, full-bleed like the board, painted per pixel (`AtlasPainter`). Its washes are pigments, not accents: green where you do well, ochre where it's even, vermilion where it costs you.
