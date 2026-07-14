# Tunnel Visual Rework: Faux-3D Walls + Occlusion Fade — Design

## Context

Brainstormed with the user over a visual-companion session (mockup
screenshots relayed via Playwright, since the companion server's port
wasn't reachable from the user's own browser in this environment).

The maze currently renders as flat top-down rectangles
(`world/maze/maze_renderer.gd`) with no tileset at all yet (see
`docs/art-bible.md`'s asset inventory — this was already the #1 flagged
gap). Two problems surfaced in playtest feedback:

1. The player's point-light (`VisionLight`, a `PointLight2D` with
   `shadow_enabled = true`) casts long shadows off every `LightOccluder2D`
   wall occluder — a classic 2D top-down lighting artifact that makes flat
   walls read as tall vertical blocks, which fights the fiction (you're
   *at* the same underground level as the walls, not looking at raised
   obstacles).
2. Pure top-down orthographic framing reads flat/uninteresting on its own.

The user explicitly wants to stay close to the current architecture (2D,
`Node2D`-based, no engine/rendering pivot to 3D) rather than chase the
"most impressive" option (a real tilted 3D camera), which would be a much
bigger, riskier lift (new geometry pipeline, new art pipeline — SpriteCook
only generates 2D sprites — redone lighting from scratch) for a problem
that a well-established 2D convention already solves.

## Decisions confirmed with the user

1. **2D faux-3D, not a real 3D camera.** Camera stays flat/top-down;
   wall sprites are drawn taller than their grid footprint (the classic
   Zelda/RPG-Maker/Hyper Light Drifter convention) to imply a shallow pitch.
2. **A subtler amount of wall height**, not a more dramatic pitch — shown a
   direct comparison (wall front-face at ~22px vs. ~48px against a 48px
   footprint) and the user picked the shorter one: enough to read as a real
   wall, not so much it eats into forward sightlines or needs a wide
   occlusion-fade zone.
3. **Occlusion fade is wanted** — any wall geometry that would otherwise
   visually overlap the player fades toward transparent, the same idiom
   Stardew Valley uses for house roofs and Diablo/Hades use for pillars.
4. **The ceiling plane gets an inverse treatment, not just a recolor**:
   - Wall front-faces flip to hang *downward* out of their footprint
     (mirroring the ground plane's *upward* rise) — walls are the same
     physical geometry, but which surface reads as "near" flips with the
     plane.
   - The floor plane (and anyone standing on it) renders through a
     blur/desaturate pass while the player is on the ceiling, replacing the
     current flat alpha-dim (`Level.OFF_PLANE_ALPHA`) for the floor itself
     (the alpha-dim on other *spiders* can stay layered underneath, but the
     floor needs to look genuinely "below/behind," not just tinted).
   - The player (and enemy) sprite swaps to a distinct **underside** pose
     while on the ceiling, since a fixed top-down camera looking at an
     upside-down spider would actually see its belly, not its back.

## Current state

- `MazeRenderer extends Node2D` draws the whole maze in one `_draw()` call:
  flat `floor_color`/`ceiling_floor_color`/`wall_color` rects, no tileset,
  no per-tile texture (`maze_renderer.gd:35-48`).
- `Level._build_collision_and_occluders()` (`world/level.gd:405+`) builds one
  `LightOccluder2D` + `CollisionShape2D` per wall tile. The player's
  `VisionLight` (`entities/player/player.tscn`, `PointLight2D`,
  `shadow_enabled = true`) casts real-time shadows off these.
- `Level._refresh_plane_focus()` (`world/level.gd:741-754`) applies a flat
  alpha (`OutlineFx.set_body_alpha`) to whichever of Player/Enemy is off the
  viewer's current plane — `OFF_PLANE_ALPHA = 0.35`. Nothing dims/blurs the
  *floor* itself today; only the floor *color* changes
  (`floor_color` vs. `ceiling_floor_color`).
- No wall tileset or wall sprite exists yet (`assets/tilesets/` is empty).
- Sprites are single static top-down poses, rotated in-engine to face travel
  direction (`Player._process`, `player.gd:123-124`) — there is currently no
  concept of a sprite variant swap based on state (only a color tint swap
  based on class, `_update_sprite_tint()`).

## Design

### Phase 1 — Ground-plane faux-3D walls + occlusion fade

**Wall art & tile geometry.** This is also the trigger to finally do the
TileMapLayer migration the README already anticipated ("swap in a
TileMapLayer once the tileset exists") — there's no reason to keep hand-
rolling `_draw()` rects once real tile art exists. A wall tile's authored
art is taller than its 48×48 footprint: a **top face** (the visible top
surface) plus a **front face** (the visible "cliff" facing the camera,
noticeably shorter than the top face) — matching the subtler of the two
pitches shown to the user, anchored so its *bottom* edge sits on the
tile's own southern grid line, with the extra height poking up into the
tile north of it on screen. (The exact pixel proportions shown during
brainstorming — a front face roughly half the top face's height — were
rough mockup CSS, not validated art dimensions; treat them as a rough
starting ratio for the actual tileset authoring pass, not a spec'd number.)
`TileMapLayer` supports a texture region
larger than the cell size directly (tile size vs. texture size in the
`TileSet`), so this doesn't need any custom draw-order hacking beyond
what Godot's own `y_sort_enabled` already provides on the layer/parent —
a wall's overdrawn top portion needs to composite correctly against
whatever's standing in the tile north of it, which Y-sorting by each
node's own foot/base position already handles for entities today (worth
confirming Level's entity container has `y_sort_enabled = true`; if not,
turning it on is part of this phase).

**Occlusion fade.** Rather than tracking "which individual wall tile's
bounds overlap the player" as discrete state, this reuses the same
proximity-around-the-player idiom already established for Sense's reveal
outline: a shader on the wall `TileMapLayer` reduces alpha for wall pixels
near the player's current screen position, biased toward the direction a
wall could actually overdraw into (north of the player, given the chosen
"walls rise up" convention) rather than a full omnidirectional radius —
a wall two tiles to the side or south of the player can never visually
overlap them under this convention, so it shouldn't fade for no reason.
Exact falloff shape/radius is an implementation-level tuning detail, not
fixed by this spec. The pure "should tile X be faded given player position
P" decision (if extracted as a plain function rather than left entirely
inside the shader) is unit-testable the same way this codebase already
tests other pure-logic seams (`WaterIngress._compute_rings()`, etc.);
the shader's actual visual output is not — per this project's own
established gotcha (memory: shader compile errors slip past GUT), any
`.gdshader` touched here needs a real headless boot check that actually
triggers rendering, not just a parameter-get/set unit test.

**Shadow retuning.** With wall height now intentional (via art, not a
lighting accident), the existing `LightOccluder2D` shadow-casting needs
retuning so it complements rather than re-exaggerates the effect — most
likely a shorter/softer shadow (reduce how far the player's `VisionLight`
projects occluder shadows) rather than removing shadows outright, since
some shadow is part of what makes the new wall height read as real. Exact
tuning is a playtest-and-adjust task, not a fixed number this spec commits
to.

### Phase 2 — Ceiling-plane inverse treatment

**Mirrored wall rendering.** The ceiling plane needs its own wall
tile-source with the overdraw flipped to hang *downward* (front-face below
the footprint's own northern edge, extending into the tile south of it) —
the same asset pair (top face + front face) as the ground variant, just
composited the other way. Cleanest implementation: a second `TileMapLayer`
(ceiling walls) stacked with the existing one, visibility toggled by
`MazeRenderer.set_active_plane()` exactly like the floor color swap
already works — not a runtime flip of the same layer, since Y-sort
direction and overdraw direction both need to invert together and a
single shared layer would fight itself if both variants were ever visible
at once (which currently never happens — only one plane is "active" for
rendering purposes at a time).

**Floor blur/desaturate.** The biggest genuinely new technical piece in
this whole rework. While the player is on the ceiling, the floor plane
(and anyone/anything standing on it) needs to read as a soft, out-of-focus
background layer rather than just a recolored tile. Godot doesn't have a
trivial built-in real-time blur for arbitrary `CanvasItem` content without
an extra pass — the practical route is a `BackBufferCopy` + blur shader on
a dedicated "floor plane" `CanvasLayer`/`SubViewport`, or (simpler, if
sufficient) a strong desaturate + brightness-reduction shader without a
true blur convolution, matching what the mockup actually demonstrated
(`saturate(0.6) brightness(0.75)` plus a small blur). Recommend starting
with the desaturate/darken pass alone (cheap, no extra buffer/viewport) and
only reaching for a true blur pass if playtesting shows it's needed to
read as "out of focus" rather than just "dimmer" — this keeps the
guardrail from the original ceiling-plane design (design decision: "the
floor re-color... off-plane things read as less in focus") intact without
necessarily paying for a full blur pipeline up front.

**Underside sprite.** Player (and Enemy, since it shares the same class
kit and can also use the ceiling) gets one additional sprite variant per
class — a belly/underside pose — swapped in on `plane_changed` alongside
the existing color-tint logic, the same event `_on_plane_changed()`
already fires on. This is purely an art + one texture-swap addition, no
new mechanic.

## Non-goals

- No change to `GridMover`, tile-stepping, collision, navigation, or any
  gameplay system — this is rendering-only, confirmed with the user.
- No real 3D camera or geometry — ruled out explicitly (see Decisions).
- No commitment yet to a true GPU blur pass for Phase 2's floor treatment
  — start with the cheaper desaturate/darken version; only escalate if it
  doesn't read as intended.
- Doesn't block or depend on the rest of the tileset (floor/pit/water
  tiles from `docs/art-bible.md` §8) beyond walls specifically, though it's
  the natural moment to build the wall tileset since none exists yet.

## Testing approach

Given this is a rendering-heavy feature, the split is the same one this
project already uses elsewhere: pure logic (occlusion-fade trigger
math, plane-based sprite/texture selection) gets GUT coverage the normal
way; anything shader/visual (the actual wall art compositing, the blur/
desaturate pass, the occlusion fade's on-screen look) is verified by a
real headless boot + manual playtest, never asserted on via a unit test
alone.

## Art requirements (ties into `docs/art-bible.md`)

- Ground-plane wall tile: top face + front face, footprint 48×48 with a
  shorter front face extending below it, anchored bottom-aligned to its
  footprint (15-piece autotile set per `world/maze/tile_types.gd`'s
  existing shape classification).
- Ceiling-plane wall tile: the mirrored variant (front face hangs below
  instead of above), same 15-piece shape set.
- One underside/belly sprite per spider class (Net-Caster, Wolf Spider,
  Weaver, Decoy) plus the rival — 5 new sprites total, matching the
  existing class-color-tinting convention.

## Suggested plan structure

Phase 1 is independently shippable and resolves the original complaint on
its own; Phase 2 depends on Phase 1's wall-art foundation but is otherwise
separable and carries the one open-ended technical risk (the floor blur/
desaturate pass). Recommend two separate implementation plans rather than
one combined one, so Phase 1 can land and be played with before committing
to Phase 2's specifics.
