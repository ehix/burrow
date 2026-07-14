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

**Revised scope (post-Phase-1 brainstorm, 2026-07-14):** `assets/tilesets/`
is still empty and no underside/belly sprite art exists — same "no real
art yet" state Phase 1 found. So Phase 2 stays code-only too: no
`TileMapLayer` migration (still hand-rolled `_draw()` on `MazeRenderer`,
same as Phase 1 actually shipped — Phase 1's own build deviated from this
doc's original Phase 1 text for the same reason), and the underside
sprite is deferred to a future pass once that art exists — not built in
this phase.

**Mirrored wall rendering.** No new node needed. `MazeRenderer` already
tracks `_active_plane`; `_draw_wall()` gets a per-plane variant instead of
a second tile layer — on `GROUND` the front face anchors to the tile's own
bottom edge with the top face poking up into the tile north of it (as
Phase 1 shipped); on `CEILING` this mirrors: front face anchors to the
tile's own top edge, hanging down into the tile south of it. Phase 1's
`wall_occludes_position()` fade check gets a matching mirrored variant for
the ceiling case (checking the southern overdraw band instead of the
northern one), wired the same way via `set_fade_focus()` — kept symmetric
with the ground-plane fade on the user's call, even though that fade's
real-world effect is still unconfirmed (see Phase 1's final review notes).

**Floor dim via `CanvasGroup` + shader, floor tiles only for the actual
color transform.** Floor-drawing moves out of `MazeRenderer._draw()`
(which keeps walls only) into a new sibling node, `FloorRenderer`, living
inside a new `GroundLayer` (`CanvasGroup`) node. `GroundLayer` carries a
small new shader (this project's second hand-written shader, after
`outline.gdshader`) doing the desaturate + brightness-reduction pass the
mockup demonstrated (`saturate(0.6) brightness(0.75)`, no blur — cheap,
no extra buffer/viewport, matching this doc's original recommendation to
start simple). The shader is active only when the *focus* plane (the
player's own plane, via `PlaneComponent.effective_plane()`) is `CEILING`;
on `GROUND` it's fully off, since the ground is the plane actually in
focus, not background. `Level._on_plane_changed()`/`_refresh_plane_focus()`
toggle it (same signal already driving the existing per-entity
`body_alpha` dimming — see below).

This retires `ceiling_floor_color` (shipped in sub-project F): with a
real background layer that dims independently, re-tinting the *same*
floor tiles to indicate "which plane you're on" is now redundant — the
dim effect is a strictly better version of the same cue. `FloorRenderer`
always draws the one true ground `floor_color`; "which plane am I on"
reads from wall orientation + whether the floor is dimmed, not a color
swap.

**Ground-layer scope covers everything ground-resident, not just
tiles — except the Centipedes.** `GroundLayer` gets the hazard markers
(pit/water `Polygon2D` nodes, currently `add_child()`'d directly onto
`Level`) and always-ground entities currently parented under `Entities`:
larvae and `WorldItemPickup`. Neither carries a `PlaneComponent` today
(confirmed by grep — only `Player`, `Enemy`, and the skills that can be
cast from either plane (`EggMineSkill`, `BlockadeSkill`, `CocoonMine`) do),
so moving them under `GroundLayer` doesn't change any plane-aware
behavior, only where they're parented for rendering purposes.

**Both Centipede types (the obstacle `Centipede` and
`CentipedeExpressRider`) are deliberately excluded** (correction, post-
Phase-1-brainstorm follow-up, 2026-07-14): a Centipede's body is the same
width as the tunnel itself, so it must read identically regardless of
which plane the player is viewing from — dimming it along with the actual
floor content would be wrong, since it's not "background" the way a loose
larva or item is. Both Centipede types stay parented under `Entities`
(undimmed), same as `Player`/`Enemy`. `Player`/`Enemy`/mines/blockades
also stay under the existing `Entities` node, unaffected — that's a
different question ("is this specific plane-aware entity on the
off-plane") from "is this static ground-only content in the background
right now" (which never applies to either Centipede type).

**Enemy's off-plane dimming switches from a flat alpha fade to the same
hazy/desaturate look** (second correction, same day): sub-project F's
`body_alpha`-only fade (`OFF_PLANE_ALPHA = 0.35`) is replaced by the same
desaturate+darken formula `GroundLayer` uses, for visual consistency
across the whole "off-plane/background" language — Enemy stays fully
opaque but reads hazy/darker instead of merely more transparent. Since
`Player`/`Enemy` sprites already share one `ShaderMaterial`
(`outline.gdshader`, via `OutlineFx`) for their outline/Camouflage
effects, and a `CanvasItem` can only ever hold one `material`, the
formula is merged directly into `outline.gdshader` as new uniforms
(`saturation`, `brightness`, `dim_enabled`) rather than given a second
material — `GroundLayer`'s own `ground_dim.gdshader` stays a separate,
dedicated shader, since a `CanvasGroup` has no outline/Camouflage
concerns to share a material with. `OFF_PLANE_ALPHA` is retired entirely;
`body_alpha` remains, now exclusively Camouflage's uniform.

**New scene tree order** (`world/level.tscn`): `GroundLayer` (floor +
hazards + larvae/items) draws first, then `Renderer` (`MazeRenderer`,
walls only) on top of it, then `Walls`/`Occluders` (collision/light
geometry, unchanged), then `Entities`
(player/enemy/mines/blockades/centipedes) on top of everything, then
`SenseLayer`. This preserves the existing "entities always draw on top"
guarantee while adding the new layer: crisp ceiling walls compositing
over the hazy ground-layer background when viewed from the ceiling.

**Underside sprite — deferred.** No belly/underside art exists for either
class yet (confirmed via `spritecook-assets.json`). Not built this phase;
revisit once that art is generated. `plane_changed`'s existing dispatch
(`_on_plane_changed()`) is already the right seam to hang a texture swap
on when that art exists — no structural change needed to add it later.

## Non-goals

- No change to `GridMover`, tile-stepping, collision, navigation, or any
  gameplay system — this is rendering-only, confirmed with the user.
- No real 3D camera or geometry — ruled out explicitly (see Decisions).
- No commitment yet to a true GPU blur pass for Phase 2's floor treatment
  — start with the cheaper desaturate/darken version; only escalate if it
  doesn't read as intended.
- Doesn't block or depend on the rest of the tileset (floor/pit/water
  tiles from `docs/art-bible.md` §8) beyond walls specifically.
- No `TileMapLayer`/`TileSet` migration in Phase 2 either (revised scope,
  see above) — `assets/tilesets/` is still empty, so this stays hand-drawn
  `_draw()` rects, same as Phase 1 actually shipped.
- No underside/belly sprite in Phase 2 (revised scope, see above) — no
  art exists yet; deferred to a future pass.

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
its own (shipped 2026-07-14, PR #15) — confirmed separable, as recommended.
Phase 2 depends on Phase 1's wall-rendering foundation (`_draw_wall()`,
`wall_occludes_position()`) but is otherwise separable and carries the one
open-ended technical risk (the floor dim pass and the `GroundLayer`
scene-tree restructure). Its own implementation plan, per this doc's
original recommendation to keep the two phases separate.
