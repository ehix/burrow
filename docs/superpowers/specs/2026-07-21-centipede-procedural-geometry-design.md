# Centipede Procedural Geometry (Design)

## 1. Goal

Replace the Centipede's placeholder visual (a flat 40×40 olive-green rect,
identical for every segment) with a chain of shaded spheres drawn purely
in Godot (`_draw()`), no sprite art — plus per-centipede random color
variation, so individual centipedes read as distinct within the game's
earthy palette. This directly follows from [[burrow-art-pipeline-status]]:
3 rounds of SpriteCook generation (see the superseded
`2026-07-20-centipede-art-design.md`) got every individual problem fixed
(cross-piece consistency, single-unit-per-tile, millipede anatomy, a
corner piece that fills its tile as a volume) but the user judged
generative AI wasn't going to converge on this asset and asked for pure
geometry instead — reusing the same faux-3D two-tone top/front-face
technique `MazeRenderer` already uses for walls was explored first (see
git history on this doc's superseded predecessor and the live mockup
iteration in this session), but the user's final preference, after
comparing rendered candidates, was a simpler "organic sphere" look: a
glossy shaded ball per segment, no legs, no antennae, no wall-style
two-tone shading.

## 2. Non-goals — this is a visual-only change

This is the hard constraint the user gave explicitly: **everything about
Centipede's behavior stays exactly as it is today.** Concretely, none of
the following change:

- Movement, AI (flee/relocate/tunnel-fallback/reverse), pathing, or the
  Centipede Express mechanic.
- Collision: `CentipedeSegment`'s `RectangleShape2D` (40×40,
  `centipede_segment.tscn`) is untouched — hit detection and physics stay
  exactly as they are.
- `take_hit()`'s signature/behavior, the shared-hit-counter forwarding to
  the parent `Centipede`, or the `CombatFx.shunt()` hit-bump.
- `WallOverdrawMask` occlusion: it already treats Centipede segments as
  occludable purely by `global_position`/`ENTITY_VISUAL_HALF_EXTENT`, with
  zero dependency on how a segment draws itself — nothing to change here,
  confirmed during design exploration.
- Any test that exercises movement/AI/combat/collision — only the small
  set of tests asserting on the old placeholder's visual state (if any)
  or adding new visual-setter tests are in scope.

No new node is added to `centipede_segment.tscn` either (no `Sprite2D`,
unlike the abandoned sprite-based design) — `CentipedeSegment` keeps
drawing itself via `_draw()`, exactly the mechanism the current
placeholder already uses, just with a richer shape.

Also out of scope, matching the abandoned design's own non-goals (still
true, unrelated to the art-source change):
- No separate ground/ceiling visual variants (Centipede isn't plane-aware).
- No animation — segments are static per-frame, only repositioned.
- `CentipedeExpressRider` gets no special-cased color — same random-color
  pool as regular Centipedes.

## 3. Segment geometry

A "sphere" is 3 layered `draw_circle()` calls, centered on the segment's
local origin (`_draw()` draws in local space, segment already positioned
via `global_position` exactly as today):

```gdscript
func _draw_sphere(radius: float, tint: Color) -> void:
    draw_circle(Vector2(2, 3), radius, tint.darkened(0.4))       # shadow/base
    draw_circle(Vector2.ZERO, radius - 2.0, tint)                 # main fill
    draw_circle(Vector2(-radius * 0.22, -radius * 0.25), radius * 0.45, tint.lightened(0.18))  # highlight
```

No legs, no antennae, no per-role rotation, no separate corner/straight/
head/tail *shapes* — confirmed via live-rendered mockups during design
that a same-radius sphere placed at each segment's own tile position
reads as connected to its neighbors whether the body runs straight or
turns 90°, since a circle looks identical from every angle. The only
per-segment variable is **radius**, by position in the body:

```gdscript
const HEAD_RADIUS := 24.0
const BODY_RADIUS := 22.0
const TAIL_RADIUS := 17.0

static func radius_for_index(index: int, count: int) -> float:
    if count <= 1 or index == 0:
        return HEAD_RADIUS
    if index == count - 1:
        return TAIL_RADIUS
    return BODY_RADIUS
```

(`count <= 1` mirrors the old design's same edge-case handling: a
single-segment body counts as HEAD, matching `Level.CENTIPEDE_BODY_
LENGTH_MIN`'s existing guarantee this is essentially unreachable in
practice.)

This eliminates the entire `Role` enum / `orientation_for()` / per-piece
texture / rotation-degrees system the sprite-based design needed —  a
direct consequence of spheres having no facing direction, not a
simplification applied on top of an equivalent design.

## 4. Color randomization

Unchanged from the abandoned sprite-based design — this logic was always
about the *color*, never the art source, so it transfers as-is:

```gdscript
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

User reviewed 4 rendered sample colors across this range (umber, olive,
moss, ochre) and approved as-is — no retuning needed, unlike the wall
material's earlier banding fix.

Called **once per centipede at spawn time**, applied identically to every
segment of that body (same pattern as `body_length`'s own existing
per-spawn randomization):
- `Centipede.spawn_at()`: compute one `Color` before the segment-spawn
  loop.
- `CentipedeExpressRider.start_run()`: same pattern, its own loop.

## 5. Wiring

`CentipedeSegment` gains two instance vars and a setter (replacing
`_draw()`'s current hardcoded rect):

```gdscript
var _radius: float = BODY_RADIUS
var _tint: Color = Color(0.3, 0.45, 0.2)  # old placeholder's color, as a safe default

func set_visual(radius: float, tint: Color) -> void:
    _radius = radius
    _tint = tint
    queue_redraw()

func _draw() -> void:
    draw_circle(Vector2(2, 3), _radius, _tint.darkened(0.4))
    draw_circle(Vector2.ZERO, _radius - 2.0, _tint)
    draw_circle(Vector2(-_radius * 0.22, -_radius * 0.25), _radius * 0.45, _tint.lightened(0.18))
```

`Centipede._sync_segments()` and `CentipedeExpressRider._sync_segments()`
(both already called every time the body moves) call
`segment.set_visual(CentipedeSegment.radius_for_index(i, _tiles.size()), _body_color)`
alongside their existing `global_position` update — same call-site shape
the abandoned design used, just a simpler payload (two scalars/a color
instead of a texture + rotation).

## 6. Testing

- `radius_for_index()`: unit tests for head (index 0), tail (last index),
  body (middle), and the single-segment edge case — pure function, no
  scene tree.
- `random_body_color()`: bounds-safety test, unchanged from before.
- `CentipedeSegment.set_visual()`: test it sets `_radius`/`_tint` (exposed
  via getters or by checking `_draw()`'s effect isn't feasible without a
  render — assert on the stored state, matching this codebase's existing
  "setter tests assert state, not pixels" convention).
- `Centipede`/`CentipedeExpressRider` spawn tests: same shape as before —
  every segment gets a real radius assigned and all segments of one body
  share the same tint.
- Manual: boot windowed, spawn a few centipedes of different lengths/
  shapes, confirm turns read as connected and different centipedes show
  visibly different earthy colors — same check as the abandoned design's
  own Task 5, minus the "head/tail pieces read as distinct art" bullet
  (no longer applicable — head/tail are now just bigger/smaller spheres).
