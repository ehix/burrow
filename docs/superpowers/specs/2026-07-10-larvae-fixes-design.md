# Larvae Fixes — Design

## Context

Raw playtest feedback flagged three larvae issues: they're still too fast,
they should slow down as they grow ("the fatter they get the slower they
get"), and they shouldn't be able to cross floor holes or water. This is
sub-project C of the larger feedback packet decomposition (see the
Net-caster rework spec/plan for the full breakdown) — an independent,
small/medium slice touching only `entities/larva/` and the one `Level` call
site that spawns larvae.

## Current state

- `entities/larva/larva.tscn`: `GridMover.step_time = 0.34` (seconds per
  tile-step), fixed regardless of the larva's size — already the slowest of
  the three moving entities (`Player` 0.12, `Enemy` 0.16 — grep-verified
  against `entities/player/player.tscn` / `entities/enemy/enemy.tscn`), but
  still reported as too fast.
- `entities/larva/larva_growth.gd`: `LarvaGrowth.tick()` grows `size_scale`
  from `1.0` up to a cap of `2.5` over time (`GROWTH_RATE = 0.02`/sec),
  independent of `caught` state. Currently only read for sprite scale
  (`Larva._physics_process`) and `heal_value()` — never for movement speed.
- `GridMover` (`components/grid_mover.gd`) exposes two independent speed
  levers: `step_time` (seconds per tile, a plain `@export var`) and
  `speed_scale` (a multiplier consumed in `tick()`'s
  `_elapsed += delta * speed_scale`, currently owned exclusively by the
  temporary web-entangle slow via `apply_slow()`/a restore-to-`1.0` timer).
  A permanent growth-driven slowdown must use `step_time`, not
  `speed_scale`, or an expiring web-slow's restore-to-`1.0` would silently
  erase it.
- `Larva` has no `GridMover.block_check` set at all (`entities/larva/
  larva.gd` — contrast with `Player`/`Enemy`, which both do
  `_mover.block_check = _blocked` in `_ready()`). Blocking therefore falls
  back to `GridMover._is_blocked`'s default path, `body.test_move(...)` —
  physical wall colliders only. `Larva`'s collision mask is `1` (world/
  walls) with no collider on pits/water, since those are a `MazeData`-only
  overlay (`MazeData.is_ground_blocked(x,y) = not is_open(x,y) or
  is_pit(x,y)` — note today's "water" hazard, `world/hazards/
  water_ingress.gd`, is implemented via this exact same pit overlay, so
  blocking on `is_ground_blocked` covers both holes and water as they exist
  today). A larva currently walks over a pit/flood tile exactly as if it
  weren't there.
- `Player._blocked()` (`entities/player/player.gd`) already demonstrates the
  pattern this fix follows for the ground plane: `_level.is_blocked(tile,
  Level.Layer.GROUND)` in addition to `test_move`.
- `Level._spawn_larva_at()` (`world/level.gd`) instantiates a larva and
  calls `set_facing()` if present, but never calls `bind_level()` — unlike
  `Player`/`Enemy`/`Earthworm`, which all get `bind_level(self)` called
  right after instancing.
- `Larva._wander_step()` already has a reject-and-retry pattern: it builds a
  shuffled list of candidate directions, and `_mover.try_step(d)` silently
  rejects any blocked direction, falling through to the next candidate (this
  is how a larva already routes around walls without any explicit
  wall-avoidance logic). `Larva.nudge_toward()` (used by `LureItem`'s pulse)
  goes through the same `_mover.try_step()`.

## Fix

### 1. Baseline slowdown

Raise `entities/larva/larva.tscn`'s `GridMover.step_time` from `0.34` to
`0.5`. A tunable number, not mandated by the raw feedback — adjust after
playtesting if it still feels off.

### 2. Weight-based slowdown

`Larva` captures its base step time once, at `_ready()`, from whatever
`larva.tscn` sets:

```gdscript
var _base_step_time: float = 0.0

func _ready() -> void:
	_base_step_time = _mover.step_time
	...
```

A new private helper applies the growth scaling to `_mover.step_time`
(never to `speed_scale`, which the temporary web-slow owns):

```gdscript
func _apply_growth_speed() -> void:
	_mover.step_time = _base_step_time * growth.size_scale
```

Called at the top of both `_wander_step()` and `nudge_toward()` (both are
only reachable when the mover isn't already mid-step, per their existing
guards) — so a freshly-spawned larva (`size_scale == 1.0`) moves at the new
`0.5`s/tile baseline, and a fully-grown one (`size_scale` capped at `2.5`)
moves at `1.25`s/tile — 2.5× slower. Recomputing this only between steps
(never mid-lerp) avoids a visible position snap: changing `step_time` while
a step is in flight would instantly change the `t := _elapsed / step_time`
fraction `GridMover.tick()` uses to interpolate.

This composes cleanly with the temporary web-entangle slow: `step_time` sets
the *base* rate for growth, `speed_scale` still multiplies the *effective*
rate for a temporary entanglement, and an expiring entanglement's
restore-to-`1.0` only ever touches `speed_scale`, never disturbing the
growth-driven `step_time`.

### 3. Hole/water blocking

`Larva` gains a level reference and a blocking check, mirroring `Player`'s
ground-only branch (no plane/noclip/spider-contest concerns apply to a
larva):

```gdscript
var _level: Level

func bind_level(level: Level) -> void:
	_level = level

func _blocked(dir: Vector2i) -> bool:
	if _level != null:
		var target := _level.tile_of(global_position) + dir
		if _level.is_blocked(target, Level.Layer.GROUND):
			return true
	return test_move(global_transform, Vector2(dir) * float(_mover.tile_size))
```

`_ready()` wires `_mover.block_check = _blocked`, matching `Player`/
`Enemy`'s existing convention.

`world/level.gd`'s `_spawn_larva_at()` calls `larva.bind_level(self)` right
after instancing (alongside the existing `set_facing()` call), matching how
`Player`/`Enemy`/`Earthworm` are already bound.

No changes are needed to `_wander_step()`'s direction-selection logic or to
`nudge_toward()`'s call site: both already go through `_mover.try_step()`,
which will now reject a hole/water tile exactly the way it already rejects
a wall — the existing shuffle-and-retry loop naturally routes around the
newly-blocked tiles. If every candidate direction (including reversal) is
blocked, the larva simply doesn't move that tick, the same as being
cornered by walls today.

## Out of scope for this slice

- A distinct, visually-blue water tile type (today's "water" is the same
  pit overlay as a floor hole) — that's sub-project G (environment tiles
  rework). This fix blocks on `is_ground_blocked`, so it will keep working
  unchanged once a real water tile type exists, as long as that rework also
  routes through `is_ground_blocked`/`Level.is_blocked`.
- Centipedes, Enemy's own hole-blocking (Enemy currently doesn't check
  `is_blocked` for pits either, but that wasn't in the raw feedback and
  isn't touched here), or any other class/system.

## Testing

Existing `tests/test_larva.gd` already instantiates the real `larva.tscn`
scene (`LarvaScene.instantiate()` + `add_child_autofree`) and calls private
methods/fields directly (`_wander_step()`, `_mover`, `_last_dir`,
`_is_occupied_web()`) — this fix's new tests extend that same file and
convention:

- Weight-based `step_time` scaling: after `larva.growth.size_scale` is set
  directly (e.g. to `1.0`, `1.75`, and the `2.5` cap) and `_wander_step()`
  is called, `larva._mover.step_time` reflects `_base_step_time *
  size_scale`.
- `_blocked()` and the `bind_level()` spawn wiring, together: `tests/
  test_player_ceiling_traversal.gd` already establishes the pattern for
  exactly this — a `_make_level()` helper that instantiates the real
  `world/level.tscn`, calls `.build()`, and then inspects a live, fully
  -wired entity (there, `level.player`). This fix's tests do the same,
  grabbing a spawned larva via `get_tree().get_nodes_in_group("larvae")`
  after building a real level, then using `level.maze.set_open()`/
  `set_pit_at()` to force a pit ahead of it and asserting
  `larva._blocked(dir)`. Because this goes through a real, fully-built
  `Level`, it also proves `_spawn_larva_at()` actually calls
  `bind_level()` — if that wiring were missing, `larva._level` would be
  null and the assertion would fail (falls through to open ground).
- A bare `Larva` never bound to a level (as today's `test_larva.gd` tests
  already construct it, via `LarvaScene.instantiate()` with no `Level`
  around) must not error when `_blocked()` is called — `_level == null`
  falls through to the existing `test_move` check.
- Manual verification in a running Godot session (headless boot/scene
  smoke test per the project's Godot validation workflow): watch larvae
  visibly slow down as they grow, and confirm one refuses to cross a pit/
  flood tile, routing around it instead.
