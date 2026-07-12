# Ceiling/Plane Mechanics Rework — Design

## Context

Sub-project F of the playtest roadmap (see memory: burrow-playtest-roadmap).
Scope per the roadmap: "Floor re-colors (not spider), same-plane collision/
stacking rules, same-plane-only combat, fall-on-damage-while-ceiling."

**Autonomy note:** this spec was brainstormed with the user for ~15 minutes
before they stepped away for the night, delegating the rest of the pipeline
(spec detail, plan, implementation, review, merge) to be run unsupervised.
Three high-level calls were made together with the user (see "Decisions
confirmed with the user" below); everything past that — the concrete
mechanism for each — is a judgment call made solo and flagged inline,
following the standing autonomy agreement (memory:
burrow-user-delegates-full-autonomy).

Scope: `components/plane_component.gd`, `components/hurtbox.gd`,
`components/grid_mover.gd`, `components/health_component.gd` (untouched,
just called into), `entities/enemy/enemy.gd`/`.tscn`, `entities/player/
player.gd`, `world/level.gd`, `world/maze/maze_renderer.gd`, and their tests.

## Decisions confirmed with the user

1. **Enemies get real ceiling access** (not just "ceiling = safe from ground
   enemies") — bigger scope than the recommended minimal option, chosen
   deliberately by the user.
2. **Ceiling visuals**: floor/tiles re-color per plane instead of tinting the
   spider sprite (the roadmap's literal wording), plus the user's own framing
   that off-plane things should read as "less in focus."
3. **Fall-on-damage-while-ceiling**: a hit while on the ceiling knocks the
   victim down to the ground plane *and* deals bonus fall damage (not
   knockdown-only).

## Current state

- **Plane tracking already exists** and is more built-out than the roadmap's
  phrasing suggests: `Level.Layer` enum `{GROUND, CEILING}`
  (`world/level.gd:48`), `Level.is_blocked(tile, plane)` as the single
  blocking seam (`world/level.gd:441-448`), `CeilingData` as an inverted-floor
  overlay that ignores pits (`world/maze/ceiling_data.gd`), and
  `PlaneComponent` (`components/plane_component.gd`) holding `current_plane`
  + `transition()` + `blocked(tile, dir)`.
- **Only the Player has a `PlaneComponent`** (`entities/player/player.tscn`).
  `Enemy` has zero plane awareness — always effectively ground, with no
  concept of "the target might be on a different plane."
- **The only visual cue today is a sprite tint**: `Player._on_plane_changed()`
  → `_update_sprite_tint()` (`player.gd:292-306`) multiplies the active
  class's `display_color` by a cool tint on the ceiling. This directly
  clashes with the per-class identity colors from sub-project B (class
  colors are supposed to "survive" cosmetic effects) — exactly what the
  roadmap's "floor re-colors (not spider)" line is calling out.
- **Combat has zero plane-awareness.** `Hurtbox.receive_hit()`
  (`components/hurtbox.gd:27-32`) — the single choke point every attack
  already funnels through (melee, web shots, contact hits) — has no plane
  check. A ceiling player and a ground enemy can hit each other today.
- **Tile "stacking" is also plane-blind today.**
  `GridMover.spider_tile_contested()` (`components/grid_mover.gd:66-79`)
  checks every node in group `"spiders"` regardless of plane — a ceiling
  player and a ground enemy currently block each other out of the same tile,
  even though they're on physically different layers. This is a real, latent
  bug this rework fixes as a side effect of adding plane-awareness generally.
- **No fall/fall-damage mechanic exists anywhere.**
- **`MazeRenderer`** (`world/maze/maze_renderer.gd`) draws one flat
  `floor_color`/`wall_color` per tile from `MazeData.is_open()` — no
  per-plane distinction, no ceiling-specific rendering at all.

## Design

### 1. `PlaneComponent` becomes the shared plane authority

Two static helpers, mirroring the `OutlineFx`/`CombatFx` static-helper
pattern already used in this codebase:

```gdscript
## A node's plane if it has a PlaneComponent child, else GROUND — the
## default for every entity that never tracks planes at all (larvae,
## decoys, hatchlings, traps, Blockade).
static func effective_plane(node: Node) -> Level.Layer:
    if node == null:
        return Level.Layer.GROUND
    var plane := node.get_node_or_null("PlaneComponent") as PlaneComponent
    return plane.current_plane if plane != null else Level.Layer.GROUND

static func same_plane(a: Node, b: Node) -> bool:
    return effective_plane(a) == effective_plane(b)
```

New export + method for the fall-on-damage mechanic (kept on
`PlaneComponent` itself, not `Hurtbox`, so any future plane-aware entity gets
consistent fall behavior automatically without per-entity wiring):

```gdscript
## First-pass balance number — tune during playtest.
@export var fall_damage: float = 8.0

## Called by Hurtbox after a hit lands: knocks the owner down to the ground
## plane and applies bonus fall damage. No-op while already on the ground.
func apply_hit_fall(health: HealthComponent) -> void:
    if current_plane != Level.Layer.CEILING:
        return
    transition()
    if health != null:
        health.take_damage(fall_damage)
```

### 2. Same-plane-only combat

`Hurtbox.receive_hit()` gains a gate at the very top — an attack from a
different plane doesn't land at all (no damage, no Camouflage break, no
`took_hit` signal):

```gdscript
func receive_hit(amount: float, source: Node = null) -> void:
    if not PlaneComponent.same_plane(get_parent(), source):
        return
    took_hit.emit(amount, source)
    CamouflageSkill.break_if_present(get_parent())
    CamouflageSkill.break_if_present(source)
    if health != null:
        health.take_damage(amount)
        var plane := get_parent().get_node_or_null("PlaneComponent") as PlaneComponent
        if plane != null:
            plane.apply_hit_fall(health)
```

Since `effective_plane()` defaults to `GROUND` for anything without a
`PlaneComponent`, every existing entity (larvae, hatchlings, decoys, traps)
keeps behaving exactly as today — this only changes outcomes once *both*
sides could plausibly differ, i.e. Player vs. Enemy.

**Judgment call:** a melee swing that whiffs cross-plane still plays its
slash FX (`CombatFx.spawn_slash()` fires unconditionally in both
`Player._melee()` and `Enemy._melee_target()`, before/independent of whether
a `Hurtbox` is even present) — this already happens on an ordinary miss
today, so a cross-plane whiff looks the same as any other miss. Not treated
as a bug to fix in this round.

### 3. Same-plane tile stacking

`GridMover.spider_tile_contested()` skips any node on a different plane from
`self_node` — two spiders on different planes can now occupy/pass through
the same tile freely, only same-plane spiders still block each other:

```gdscript
static func spider_tile_contested(mover: GridMover, self_node: Node2D, dir: Vector2i) -> bool:
    ...
    for node in self_node.get_tree().get_nodes_in_group("spiders"):
        if node == self_node:
            continue
        var other := node as Node2D
        if other == null or not PlaneComponent.same_plane(self_node, other):
            continue
        ...
```

### 4. Enemy gains real ceiling access, gated to active pursuit

`entities/enemy/enemy.tscn` gains a `PlaneComponent` child (mirroring
`player.tscn`). `Enemy.bind_level()` wires `_plane.level = level`, same as
`Player.bind_level()`.

`Enemy._blocked()` gains the same plane-branch `Player._blocked()` already
has: on `CEILING`, blocking is decided entirely by
`_level.is_blocked(target, CEILING)`; on `GROUND`, the existing
`test_move`-based physics check plus `_level.is_blocked(target, GROUND)` for
pits.

**Judgment call — when the enemy climbs/descends:** kept to the minimum that
makes "same-plane combat" meaningful at all: the enemy only ever matches
plane to *actively chase* a real target, and always settles back to ground
the instant it isn't chasing. In `_update_state()`:

```gdscript
if next == State.CHASE and _current_target != null:
    _match_plane_to(_current_target)
elif _plane.current_plane == Level.Layer.CEILING:
    _plane.transition() # settle back to ground: not chasing anymore
```

```gdscript
func _match_plane_to(target: Node2D) -> void:
    if PlaneComponent.effective_plane(target) != _plane.current_plane:
        _plane.transition()
```

A target with no `PlaneComponent` (a Decoy) is always treated as `GROUND` —
the enemy never climbs to "chase" a decoy prop, which never moves planes
itself anyway. The transition is instant (no climb delay/animation), matching
the existing player `toggle_plane` precedent exactly — introducing a
climb-reaction delay is explicitly out of scope for this round (see below).

`_melee_nearby_hatchling()` needs no special-casing: hatchlings never get a
`PlaneComponent`, so if the enemy is currently on the ceiling chasing the
player there, `Hurtbox.receive_hit()`'s new plane gate (§2) already rejects
the opportunistic swing at a ground-plane hatchling automatically — one
mechanism, no per-call-site exceptions.

### 5. Ceiling visuals: floor re-color + entity dimming (not sprite tint)

**Floor re-color.** `MazeRenderer` gains a second floor color and an active
plane:

```gdscript
var ceiling_floor_color := Color(0.13, 0.17, 0.24) # cool-toned, distinct from wall_color
var _active_plane: Level.Layer = Level.Layer.GROUND

func set_active_plane(plane: Level.Layer) -> void:
    _active_plane = plane
    queue_redraw()
```

`_draw()`'s open-tile branch picks `floor_color` or `ceiling_floor_color`
based on `_active_plane`. Wall color is unchanged on both planes — walls
exist identically on both layers (`CeilingData` mirrors `MazeData`'s wall
geometry 1:1), so there's nothing distinct to show there.

`Level` connects to `EventBus.plane_changed` in `_ready()`. When the emitter
is the player specifically, it calls `_renderer.set_active_plane(plane)` —
the rendered floor always reflects *the player's own* plane (there's one
camera, one local viewer; the floor doesn't need to represent the enemy's
plane).

**Entity dimming ("less in focus").** Reuses the existing `body_alpha`
shader uniform (`OutlineFx.set_body_alpha()`, already built for Camouflage)
rather than inventing a new mechanism. On *any* `EventBus.plane_changed`
event (player's or enemy's — either one can change the relative
same/different-plane relationship), `Level` recomputes:

```gdscript
const OFF_PLANE_ALPHA := 0.35

func _refresh_plane_focus() -> void:
    var focus_plane := PlaneComponent.effective_plane(player)
    for node in [player, enemy]: # the only two plane-aware entities today
        if node == null or not is_instance_valid(node):
            continue
        var vis := node.get_node_or_null("Sprite") as CanvasItem
        if vis == null:
            continue
        var alpha := 1.0 if PlaneComponent.effective_plane(node) == focus_plane else OFF_PLANE_ALPHA
        OutlineFx.set_body_alpha(vis, alpha)
```

**Judgment call — dimming scope.** Deliberately limited to Player + Enemy
(the only two entities that track a plane at all after this round). Larvae,
hatchlings, decoys, and traps are always ground-bound and always rendered at
full brightness regardless of the player's plane — extending "less in focus"
to them is a plausible follow-up but adds surface area (each has its own ad
hoc sprite reference, none currently wired to the shared outline shader) for
an unsupervised overnight round. Called out explicitly as **out of scope**
below rather than silently skipped.

`Player._on_plane_changed()`/`_update_sprite_tint()` — the old tint hack —
is deleted outright. The class's own `display_color` is the sprite's
`modulate` on both planes now, full stop.

### 6. Fall-on-damage-while-ceiling

Fully covered by §1/§2 above: `PlaneComponent.apply_hit_fall()` is invoked
from `Hurtbox.receive_hit()` immediately after `health.take_damage(amount)`,
for whichever side has a `PlaneComponent` and is currently on `CEILING`.
Works symmetrically for both Player and Enemy — either one takes a hit while
on the ceiling, gets knocked down, and eats the bonus `fall_damage` tick.

## Testing

- `tests/test_plane_component.gd` (new): `effective_plane()`/`same_plane()`
  static helpers (with and without a `PlaneComponent` present);
  `apply_hit_fall()` transitions `CEILING → GROUND` and applies
  `fall_damage` only when starting on `CEILING`; no-ops (no transition, no
  damage) when already on `GROUND`.
- `tests/test_hurtbox.gd`: extend — `receive_hit()` no-ops entirely
  (no damage, no signal, no Camouflage break) when attacker/victim planes
  differ; existing same-plane/no-`PlaneComponent` cases stay green
  unmodified (default-GROUND fallback preserves current behavior).
- `tests/test_grid_mover.gd`: extend `spider_tile_contested` coverage — two
  movers on different planes committed to the same tile no longer contest;
  same-plane contest behavior (today's tests) stays green unmodified.
- `tests/test_enemy_ai.gd` (or a new `tests/test_enemy_plane.gd`): entering
  `CHASE` against a `CEILING`-plane target transitions the enemy to
  `CEILING`; leaving `CHASE` (target lost, health drops into `FLEE`, hunger
  into `SEEK_FOOD`/`PATROL`) transitions back to `GROUND` if it was on the
  ceiling; chasing a plane-less target (Decoy) never triggers a transition.
- New `tests/test_maze_renderer_plane.gd`: `set_active_plane()` switches
  which color open tiles draw in; wall tiles are unaffected.
- Extend whichever `Level` test file covers `Renderer`/`EventBus` wiring:
  `EventBus.plane_changed` from the player updates `_renderer`'s active
  plane; from the enemy does not; `_refresh_plane_focus()` sets `body_alpha`
  to `1.0`/`OFF_PLANE_ALPHA` correctly for both same- and different-plane
  Player/Enemy combinations.
- Headless validation per the existing workflow (memory:
  godot-validation-workflow): import check, then a throwaway scene run.
  Note from the Hatchlings/VFX round: shader-adjacent changes (`body_alpha`
  reuse here) compile-check via headless import but visual correctness
  (does dimming actually read right in real play) needs a manual/windowed
  pass too — this round doesn't touch the shader itself, only calls an
  already-shipped uniform, so risk is lower, but a quick visual pass is
  still worth doing before calling this done.

## Out of scope

- Extending plane-dimming to larvae/hatchlings/decoys/traps (see §5's
  judgment call) — always rendered at full brightness regardless of plane.
- A climb-reaction delay/animation for the enemy's plane transitions —
  instant, matching the existing player `toggle_plane` precedent.
- Giving any enemy *other* AI hooks around planes (e.g. deliberately luring
  the player up/down, using the ceiling defensively) — this round only wires
  "match the target's plane while chasing," nothing fancier.
- Retuning `melee_damage`/`vision_range`/etc. — only the plane mechanics
  described above are new; `fall_damage`'s default (8.0) is a first-pass
  number for playtest tuning, not a balance decision made here.
- Real map/tile art for the two floor colors — placeholder flat colors,
  same as the existing `MazeRenderer` approach generally (a real TileSet is
  separately planned future work, per the Hatchlings/VFX round's Sense
  design notes).
- Sub-project G (environment tiles) and H (Centipede) — separate
  sub-projects, next in the roadmap sequence.
