# Scachs design system

Tokens: `brand/tokens.json`. Implementation: `Scachs/Design/Theme.swift` and `Scachs/Design/Components.swift`. Brand rules: `brand/BRAND.md`. The 1.2 direction and its mock: Dev-Brain ADR 280.

- **Direction (1.2):** Chess.com's structure with Scachs' identity and one small dose of the medieval: compact dark bars, flat panels, the board framed, one gold action per screen, engraved capitals for titles, gold wire and lozenges as the only ornament.
- **Colour strategy:** restrained. Flat field `#13201D`, bars `#0E1816`, panels `#1B2A27`, raised `#24372F` and `#2F463F`. Gold `#E7B96C` is for what you press and for the wire; good `#6DBE7E`, warn `#EF7D6C`. No gradients on surfaces, no grain, no lamp.
- **Scene:** someone on a sofa at 11 pm with ten minutes, holding the phone low in lamplight. That forces a deep, low-luminance field with bright objects on it.
- **Type:** `Theme.title` (Marcellus SC) for screen, card and section titles, never numbers or notation. `Theme.text` (Ysabeau Office) for everything else, tabular digits. Grenze Gotisch only lives in the wordmark (and the widgets).
- **Bars:** `TopBar` / `.topBar(_:leading:trailing:)`: 46 pt, title centred, a gold wire with a lozenge at its centre underneath. Sheets keep the system bar, styled the same through `UINavigationBarAppearance`. The tab bar is ours (`ScachsTabBar`, the system one is glass and can't go flat); a pushed screen with its own tools hides it with `TabBarHidden`.
- **Sections:** `SectionTitle` is a fleuron rule: fading wire, lozenge, name in gold capitals, lozenge, wire, with an optional count.
- **Surfaces:** `.panel()`: solid fill, 6 pt corners, a gold wire at 13 %. Rows are panels with a `Medallion` (icon on a square tinted with its colour), title, detail and chevron.
- **Buttons:** the one primary action per screen is a gold plaque (`.buttonStyle(.plaque)`): bevelled corners, flat, a 4 pt darker edge that it sinks into when pressed; `.plaque(secondary: true)` is the dark plate. Tools under a board are icon over label (`.buttonStyle(.tool)`) in a `Dock` with the plaque on the right. Text actions are tin with a gold underline. Labels in sentence case. Hit areas 44 pt minimum.
- **Board:** full width inside `.boardFrame()`: a dark bezel, a gold wire just outside the squares and a lozenge at each corner. Only pieces cast shadows.
- **The coach's page:** `.manuscript()`: cream with a brown rule inside the edge; move, class and evaluation chip on top, the note below, in ink.
- **Move-class badge:** an enamel disc in a gold wire, like the pieces (`MoveClassBadge`). Classes are told apart by glyph, then colour.
- **Numbers:** accuracy and rating read like instruments: the eval graph sits in a gold wire (`.wireFrame()`), a review's classes are bars facing each other, empty ones hidden until asked.
- **Energy:** the streak and the puzzle rating sit in Avui's bar; a set shows as a row of segments; solved is a green panel. Nothing about what wasn't done.
- **Motion:** 150-250 ms, ease-out, no bounce. The reflex wave is the single signature. `Reduce Motion` freezes tilt and shrinks the wave to a flash.
- **Heraldry and wax:** the profile's crest is an enamelled shield in a gold wire beside the temperament's name and blazon. A finished lesson is a red wax seal with its Roman numeral; the next one is a gold disc; ahead are dashed circles, joined by a gold thread as far as you've come.
- **The ink map:** Avui shows La carta as a small gold-ink map (coast, wood, hills, a range, a river, a dotted road to a tower), lit as far as you've explored (`InkChart`).
- **The Atlas:** the one exception to the field: a vellum portolan sheet, full-bleed like the board, painted per pixel (`AtlasPainter`). Its washes are pigments, not accents: green where you do well, ochre where it's even, vermilion where it costs you.
- **La carta** (`Scachs/Puzzles/Chart/`): the second sheet of vellum, sister to the Atlas. Every puzzle theme is a land in one of five realms; a land is fog until three puzzles chart it, and gets a gold flag once a dozen blind puzzles there go better than your rating expects. Flags never come down (`chartHeld`), and navigator ranks climb with the flags held. The beasts are enamel in gold wire like the pieces; `Reduce Motion` stills them.
