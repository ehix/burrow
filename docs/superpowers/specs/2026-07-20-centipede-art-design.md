# Centipede Art (Design)

## 1. Goal

Replace the Centipede's placeholder visual (a flat 40×40 olive-green rect,
identical for every segment regardless of position or facing) with real
art: a head, a tail, and a body that visually connects through both
straight runs and turns, oriented correctly for whichever direction that
part of the body is actually facing — plus per-centipede color variation
so individual centipedes read as distinct within the game's earthy
palette, using one shared sprite set rather than separately-generated
color variants.

## 2. Non-goals

- No separate ground/ceiling art variants. Centipede has no
  `PlaneComponent` and isn't plane-aware (`Level.is_blocked()` blocks
  GROUND and CEILING identically for any Centipede tile) — "fills both
  planes" is a collision rule, not a vertical/depth visual, confirmed
  during design exploration.
- No animation. Segments stay static images, matching the current
  placeholder — movement is purely positional (`_sync_segments()`
  repositioning), never frame-animated.
- No baked directional art variants (no player/enemy-style 9-animation
  set). Facing is handled by rotating a small fixed set of sprites in
  engine, per this project's existing default convention (art-bible §2:
  "no directional/rotational asymmetry — sprites rotate in-engine").
- No wiring of the wall decals from the earlier tile-texturing work —
  unrelated, already tracked as its own separate follow-up.
- `CentipedeExpressRider` gets no special-cased fixed color — it joins
  the same per-instance random-color pool as regular Centipedes (a
  deliberate choice, not an oversight: the art-bible already establishes
  Express is distinguished by behavior/motion, not appearance).
- No change to `CentipedeSegment`'s collision shape (`RectangleShape2D`,
  40×40, in `centipede_segment.tscn`) — this is a visual-only change, so
  hit detection and physics stay exactly as they are today.

## 3. Assets

Four still-image pieces via SpriteCook (`generate_game_art`, pixel mode,
transparent background — the same tool/mode already used for
`wall_material.png`/`floor_material.png`, not the character-animation
pipeline, since these don't animate):

- `centipede_head.png`
- `centipede_tail.png`
- `centipede_body_straight.png`
- `centipede_body_corner.png` — one L-shaped bend, rotated in-engine to
  whichever of the 4 turn orientations a given body segment needs; not 4
  separately-authored corner pieces.

**Style:** blocky/cube-ish pixel art matching this project's faux-3D wall
aesthetic (per user direction) — imposing bulk, not menacing detail,
consistent with Centipede being a passive, non-combatant obstacle.

**Palette:** generated in a fairly neutral/desaturated base tone (light
grayish-tan, form/shading carried by value contrast rather than a strong
baked-in hue). This is a hard requirement, not a style preference: the
color-randomization mechanism (§6) works by multiplying this texture by a
per-centipede `Color` (`Sprite2D.modulate`, a straight multiply) — a
strongly-colored source (e.g. baked-in green) would mix/clash against a
target tint instead of reproducing it cleanly across the "wide earthy
range" the design calls for.

**Canvas size:** generated at a pixel-art-appropriate resolution (in the
same ballpark as the existing `player_wolf_spider.png` convention, ~64px)
rather than exactly 48px, matching this project's existing sprite-asset
sizing precedent.

## 4. Orientation & rendering wiring

`CentipedeSegment` currently has no `Sprite2D` — it's pure `_draw()`
(`entities/centipede/centipede_segment.gd:23-25`). This adds a `Sprite2D`
child (new node in `centipede_segment.tscn`) and a public setter,
`CentipedeSegment.set_visual(texture: Texture2D, rotation_deg: float, tint: Color) -> void`,
that assigns `Sprite2D.texture`/`.rotation_degrees`/`.modulate` — the
segment itself still holds no state, matching its existing "purely
physical/visual" contract (its own doc comment).

A new pure function computes which piece + rotation a segment needs,
purely from its neighbors in `Centipede._tiles` (head-first, per that
array's existing contract) — directly unit-testable without a scene
tree, matching this codebase's established pattern for this kind of
logic (e.g. `MazeRenderer.wall_occludes_extent()`,
`WallOverdrawMask._straddled_columns()`):

```
static func orientation_for(index: int, tiles: Array[Vector2i]) -> Dictionary
```

returning `{"role": "head"|"tail"|"straight"|"corner", "rotation_deg": float}`:

- **Head** (`index == 0`): direction = `tiles[0] - tiles[1]` (facing away
  from the body, i.e. its current direction of travel).
- **Tail** (`index == tiles.size() - 1`): direction = `tiles[last] - tiles[last-1]`
  (facing away from the body, i.e. which way it trails).
- **Body segment** (any other index): compare `tiles[index-1]` (toward
  the head) and `tiles[index+1]` (toward the tail). Same axis (both
  horizontal or both vertical, opposite signs) → `"straight"`, rotated to
  align with that axis. Perpendicular → `"corner"`, rotated to the one of
  4 orientations matching which two edges it's actually connecting.

Called from `Centipede._sync_segments()` (`entities/centipede/centipede.gd:426-430`)
right alongside the existing `global_position` update, so a segment's
look updates automatically every time the body moves or turns — no
separate tracking or event needed. `CentipedeExpressRider` has its own
segment array (`entities/centipede/centipede_express_rider.gd`, no
shared sync path with `Centipede`) and needs the equivalent call added
at whatever point it repositions its own segments.

**Sizing:** the `Sprite2D`'s own scale/texture fills more of the 48px
tile than the current 40×40 inset (per the "fill the tile more fully"
decision) — collision (§2) is untouched.

## 5. Color randomization

One shared pure function, colocated with `CentipedeSegment` (e.g.
`CentipedeSegment.random_body_color() -> Color`, since both spawn sites
below need the identical range and this avoids duplicating HSV-range
constants in two files):

```
const HUE_MIN := 0.05   # ~18°, brown/umber
const HUE_MAX := 0.40   # ~144°, olive-green
const SATURATION_MIN := 0.35
const SATURATION_MAX := 0.6
const VALUE_MIN := 0.35
const VALUE_MAX := 0.55

static func random_body_color() -> Color:
    return Color.from_hsv(
        randf_range(HUE_MIN, HUE_MAX),
        randf_range(SATURATION_MIN, SATURATION_MAX),
        randf_range(VALUE_MIN, VALUE_MAX)
    )
```

The hue band (~18°-144°) spans brown/umber through olive-green — the
"wider earthy range" the design calls for — while staying clear of
blue/purple/red, which wouldn't read as earthy. Saturation and value are
kept in a muted band (bracketing the current placeholder's own roughly
0.55 saturation / 0.45 value) rather than going neon, consistent with
the rest of this project's palette (art-bible §3). These are first-pass
numbers, not final balance — easy to retune during playtest, same
posture as this project's other placeholder tuning constants (e.g.
`WaterIngress.RING_STEP`).

Called **once per centipede at spawn time** — mirroring how
`body_length` is already randomized once per spawn
(`world/level.gd:958`/`:943`) — and applied identically to every segment
of that one body, so a whole centipede reads as one consistent
individual:

- `Centipede.spawn_at()` (`entities/centipede/centipede.gd:56-67`): compute
  one `Color` before the segment-spawn loop, pass it to each segment's
  `set_visual()` call.
- `CentipedeExpressRider.start_run()` (`entities/centipede/centipede_express_rider.gd:62`
  onward): same pattern, its own separate segment-spawn loop.

## 6. Testing

- `orientation_for()`: unit tests covering head, tail, a straight run
  (both axes), and a corner in each of the 4 turn shapes — pure function,
  no scene tree, matching `test_centipede_segment.gd`'s existing style.
- `random_body_color()`: a determinism-adjacent test isn't meaningful
  here (it's meant to be random) — instead, a test that repeated calls
  stay within the declared HSV bounds (same shape as
  `test_tile_texture_variant.gd`'s bounds-safety tests).
- `CentipedeSegment.set_visual()`: extend `test_centipede_segment.gd`
  with a test confirming it actually sets `Sprite2D.texture`/
  `.rotation_degrees`/`.modulate` on the child sprite.
- Manual: boot windowed, spawn a few centipedes of different lengths and
  shapes (straight runs and turns), visually confirm head/tail/corner
  pieces orient correctly and each centipede reads as its own distinct
  color.
