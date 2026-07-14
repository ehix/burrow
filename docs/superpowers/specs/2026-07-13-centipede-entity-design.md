# Centipede Entity — Design Spec

Sub-project H of the Burrow playtest-feedback roadmap: "Brand new enemy — segmented body, AI,
combat, escape-through-tunnels destruction, ceiling-blocking, water-avoidance pathing." Brainstormed
2026-07-13, following sub-project G (Environment Tiles Rework).

## 1. Overview & Scope

`Centipede` is a multi-tile, segmented obstacle creature that blocks a corridor on **both** ground
and ceiling planes simultaneously. It is stationary and non-combatant while intact — it never
initiates an attack, it only reacts to being hit or to its tile flooding.

Two triggers make it move, both driving the same crawl/pathing system:

- **Combat-provoked flee**: enough hits (any combative strike — melee or web-shot, from Player or
  Enemy) land anywhere on its body → it crawls toward the nearest map boundary and despawns there
  ("burrows out"), tunneling through a wall if genuinely boxed in with no open path.
- **Flood-provoked relocate**: `WaterIngress` floods a tile its body occupies → it crawls to a new
  valid, dry, open corridor elsewhere in the maze and resumes blocking there (it does not despawn).

In both cases, every tile the head newly moves onto has its occupants (larvae, web traps, items)
permanently destroyed via the existing `Level._destroy_occupants_at()` helper (built in sub-project
G for Seismic Compaction) — the Centipede crawling over ground is destructive, not just an obstacle.

**`Centipede` replaces `Earthworm` entirely.** `Earthworm` (`entities/earthworm/`) is retired:
`Level._seed_earthworms()`/`EARTHWORM_COUNT` are replaced by `_seed_centipedes()`/
`CENTIPEDE_COUNT` (still 1 per level), and `entities/earthworm/` + `tests/test_earthworm.gd` are
deleted.

## 2. Why `Blockade` is the base pattern, not `Earthworm`

`Blockade` (`entities/skills/scenes/blockade.gd`) already has almost everything this design needs
that `Earthworm` doesn't:

- It's hit by **both** melee (`Player._melee`) and web-shots (`WebShot._on_body_entered`) through a
  plain `_hits` counter — no `HealthComponent`, no death, just a threshold.
- It blocks **both planes for free**: `Level.is_blocked()` checks `Blockade.at_tile(...)` *before*
  branching on ground vs. ceiling (`world/level.gd:459-466`), so a Blockade tile is impassable
  regardless of which plane you're on.

The one gap: today only `Player._melee` and `WebShot` call `Blockade.take_hit()` — Enemy's melee
never does (Enemy has no "check the tile ahead" sweep the way `Player._melee` does). This design
adds that sweep to Enemy, scoped narrowly to hitting a Centipede segment the same way Player already
hits a Blockade.

`Earthworm`'s only contribution to this design is its *retreat-and-despawn* flavor (`_begin_retreat`,
"burrows out" at the map edge) — but even that gets rebuilt properly here: Earthworm's retreat is a
naive straight-line `global_position +=` that ignores maze geometry entirely (it can visually clip
through walls). The Centipede's retreat is a real tile-by-tile crawl that respects walls and water.

## 3. Components & Scene Structure

### `Centipede` (`entities/centipede/centipede.gd`, `extends Node2D`)

The root/owner, one instance per spawn. Not a `CharacterBody2D` and does not use `GridMover` — its
movement (a multi-tile body shifting like a snake) doesn't fit GridMover's single-tile-stepper
model, so it gets its own small crawl stepper (§5).

- `_tiles: Array[Vector2i]` — single source of truth for occupied tiles, head first (`_tiles[0]`).
  Segment visuals are pure mirrors of this array; nothing else holds authoritative position state.
- `_hits: int` — shared hit counter across the *entire* body. Any segment being hit increments this
  one counter (confirmed: hitting any part of the body counts toward the same shared threshold).
- `@export var hits_to_flee: int = 4` (matches `Earthworm.hits_to_flee`'s existing default).
- `@export var body_length: int = 4` — number of segments/tiles.
- `@export var crawl_step_time: float = 0.35` — seconds between each tile-step while crawling. Named
  constant, no magic numbers.
- `enum State { BLOCKING, FLEEING, RELOCATING }`, starts `BLOCKING`.
- `add_to_group("centipedes")` — its own dedicated group, matching this codebase's established
  per-type convention (`"spiders"`, `"larvae"`, `"traps"`, etc. — there is no generic "hostile"
  supergroup to join instead).
- `bind_level(level: Node)` — same pattern as `Earthworm.bind_level()`.

### `CentipedeSegment` (`entities/centipede/centipede_segment.gd`, `extends StaticBody2D`)

`body_length` children, physical/visual only — they hold no independent state:

- `collision_layer = 1`, `collision_mask = 0` — identical to `Blockade`/`Earthworm`'s existing
  world-blocking layer. This means `WebShot._on_body_entered`'s existing physics-overlap detection
  picks up a `CentipedeSegment` with **zero changes to WebShot's collision setup** — only a new
  `elif body is CentipedeSegment:` branch calling `take_hit()`, mirroring the existing `Blockade`
  branch exactly.
- `take_hit()` forwards straight to the parent `Centipede.take_hit()` — no local counter.
- Placeholder `_draw()` — a segmented worm-silhouette rectangle, matching Earthworm's
  "no art asset yet" precedent.

### Melee hits (tile-lookup, not physics)

`Player._melee` and Enemy's new melee tile-check are not physics-collision-based — they compute a
target tile (the tile in front of the caster, via facing) and query directly, the same way
`Player._melee` already calls `Blockade.at_tile(get_tree(), target_tile, size)`
(`entities/player/player.gd:364`).

New static helper, `Centipede.segment_at_tile(tree: SceneTree, tile: Vector2i, tile_size: int) ->
Centipede`: scans the `"centipedes"` group, returns the first instance whose `_tiles` contains
`tile`, or `null`. Mirrors `Blockade.at_tile()`'s signature and implementation shape exactly.

- `Player._melee` gets one more check alongside its existing `Blockade.at_tile()`/`Earthworm` check:
  if `Centipede.segment_at_tile(...)` returns non-null, call `take_hit()` on it.
- Enemy gains an equivalent tile-check in its own melee resolution — the scoped addition mentioned
  above. Enemy's melee currently targets a specific tracked node (the player); this adds a
  Player-style "check the tile ahead" step for the Centipede/Blockade case specifically, without
  otherwise changing Enemy's target-tracking combat.

### Dual-plane blocking

`Level.is_blocked()` (`world/level.gd:459-466`) gets one more line alongside the existing
`Blockade.at_tile(...)` check, before the plane branch:

```gdscript
func is_blocked(tile: Vector2i, plane: Layer) -> bool:
	if maze == null:
		return true
	if Blockade.at_tile(get_tree(), tile, TILE_SIZE) != null:
		return true
	if Centipede.segment_at_tile(get_tree(), tile, TILE_SIZE) != null:
		return true
	if plane == Layer.CEILING:
		return ceiling.is_blocked(tile.x, tile.y)
	return maze.is_ground_blocked(tile.x, tile.y)
```

This blocks both planes on every occupied tile, for free, the same way Blockade already does.

## 4. Spawn Placement

`Level._seed_centipedes()` replaces `_seed_earthworms()`. Because the body can bend around corners,
placement needs a connected chain of `body_length` open, non-boundary tiles, not just one random
cell:

1. Reserve player/enemy spawn tiles (same guard `_seed_earthworms()` already uses).
2. Shuffle open cells; for each candidate starting cell not reserved, attempt a randomized walk over
   open, non-boundary, not-already-in-chain neighbors for `body_length - 1` further steps
   (backtrack/abandon and try the next candidate on a dead end).
3. First successful chain becomes the initial `_tiles` array (in walk order, so `_tiles[0]` — the
   head — is an arbitrary end of the chain, not distinguished from the tail at spawn time).
4. If no candidate produces a valid chain (very cramped maze), skip spawning for this level —
   graceful degradation, matching `WaterIngress`'s no-op-on-empty-maze precedent. `CENTIPEDE_COUNT
   := 1`.

## 5. State Machine & Movement

```
BLOCKING --(hits >= hits_to_flee)--> FLEEING --(reach boundary)--> despawn (queue_free)
BLOCKING --(a _tiles entry floods)--> RELOCATING --(reach new spot)--> BLOCKING
```

`Centipede.take_hit()` increments `_hits`; while `BLOCKING`, at `hits_to_flee` it computes a target
(nearest map-boundary tile, mirroring `Earthworm._direction_to_nearest_boundary()`'s "closest of the
four edges" logic but as a real tile coordinate, not a raw direction) and transitions to `FLEEING`.
It's a no-op once already `FLEEING`/`RELOCATING` (mirrors `Earthworm.take_hit()`'s
`if state == State.RETREATING: return` guard).

Water hook: `Level.set_water_at()`'s flood branch (`value == true`) gets one more sweep alongside the
existing `_drown_traps_at`/`_submerge_items_at` calls — `_flood_centipedes_at(tile)`, which finds any
`"centipedes"` group member whose `_tiles` contains `tile` and calls `notify_flooded()` on it.
`notify_flooded()` is a no-op unless the Centipede is currently `BLOCKING`; otherwise it picks a new
relocate destination (§6) and transitions to `RELOCATING`.

Both `FLEEING` and `RELOCATING` are driven by the same crawl stepper, on a `Timer`
(`crawl_step_time` interval — real timer pacing, same category as `WaterIngress`'s `RING_STEP`, not
per-`_physics_process` movement):

1. Compute the next head tile toward the current target via the local BFS (§6).
2. Call `level._destroy_occupants_at(next_tile)` — permanently destroys any larva/trap/item there
   (reused as-is from sub-project G; both `FLEEING` and `RELOCATING` destroy occupants, confirmed).
3. Prepend `next_tile` to `_tiles`, pop the last entry — the body shifts by one tile, snake-style.
4. Reposition each `CentipedeSegment` child to match its corresponding `_tiles` entry.
5. If the new head tile *is* the target: `FLEEING` → `queue_free()` the whole Centipede;
   `RELOCATING` → transition back to `BLOCKING` (stop the timer, resume being a static obstacle).

## 6. Pathing: Centipede-local BFS, not the shared AStar

Enemy's chase/seek-food pathing (`Level.path_tiles()` → `GridNav.path()` against the shared
`_astar`) is not reused. Two reasons: (a) that AStar grid does not treat pits/water as solid at all
today — only walls are (`_astar.set_point_solid()` is only ever called from wall-carving/collapsing
code) — so it would need new plumbing to support water-avoidance without affecting Enemy's own
pathing; (b) the Centipede's pathing needs are much simpler than "chase a moving target" — always
either "reach the nearest boundary tile" or "reach a specific new open-and-dry spot" — so a small,
isolated BFS local to `Centipede` is lower-risk than modifying shared infrastructure Enemy's AI
depends on.

`Centipede._find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]`: a plain grid BFS from the
current head tile to the target, where a tile is passable if `maze.is_open(x, y)` and not
`level.is_water_at(tile)` and not already occupied by *this* Centipede's own trailing body tiles
(so it doesn't path through itself). Returns `[]` if no path exists.

`Level.is_water_at(tile: Vector2i) -> bool` is a new tiny public accessor (`return
_water_tiles.has(tile)`) added alongside `set_water_at()` — every other external consumer of water
state goes through a named public method (`set_water_at`, `is_blocked`, `patch_pit_at`); this is the
first time production code outside `Level` needs to *query* water state, so it gets the same
one-entry-point treatment rather than reaching into the underscore-prefixed `_water_tiles` dict
directly.

**Boxed-in fallback** (the "escape-through-tunnels... unless blocked in" case): if `_find_path`
returns empty, find the single adjacent (4-directional from the current head) wall tile that
minimizes remaining Manhattan distance to the target, **excluding any boundary tile**
(`level.is_boundary(tile)`) from candidacy — the same caller-side guardrail check
`RemoveWallsSkill`/`SeismicCompaction` both perform before touching wall geometry, since
`Level.dev_remove_wall_at()` itself enforces no such restriction (it's the unrestricted dev cheat;
every production wall-editing call site is responsible for filtering boundary tiles out first). Once
a valid non-boundary candidate is chosen, carve it open via `level.dev_remove_wall_at()` and retry
`_find_path` from the head including the newly-opened tile. This is a permanent maze mutation,
consistent with "destruction" in the roadmap's original phrasing.

**Relocate destination selection**: on `notify_flooded()`, pick a new `body_length`-tile chain using
the same randomized-walk algorithm as spawn placement (§4), but additionally excluding any tile
where `level.is_water_at(tile)` is true (the new spot must be dry) and any tile currently occupied
by the Centipede's
own existing `_tiles` (no self-overlap during the transition). If no valid new chain can be found
(extreme edge case — e.g. the entire reachable maze is flooded), stay `BLOCKING` in place rather than
getting stuck mid-transition; `notify_flooded()` will simply be called again if a later flood event
finds it still there.

## 7. Scope-Limiting Assumptions

Stated explicitly so they're easy to correct if wrong, rather than silently decided:

- Occupant destruction (§1, §5) only happens on tiles the head newly *moves onto* while crawling —
  not a radius, not the whole body, not while stationary `BLOCKING`.
- No interaction with `Blockade`s or other `Centipede`s while pathing (BFS simply treats them as
  passable — cross-obstacle interaction is out of scope for this pass; a future pass could make the
  BFS avoid other Centipedes/Blockades the way it avoids water).
- The crawl stepper is real-timer-paced (`crawl_step_time`), not per-frame — consistent with this
  codebase's other timer-scheduled hazard behavior (`WaterIngress`'s `RING_STEP`), and, like that
  system, not practically unit-testable for pacing/feel — same manual-playtest caveat applies.

## 8. Testing Strategy

GUT coverage, one test file per new script (`tests/test_centipede.gd`,
`tests/test_centipede_segment.gd`), plus targeted extensions to existing shared-file tests:

- Shared hit-counter across segments: hitting any segment increments one counter; threshold triggers
  `FLEEING` (mirrors existing `test_blockade`/`test_earthworm`-style hit-counter tests).
- `Centipede.segment_at_tile()` lookup — hit and miss cases, multiple instances.
- `Level.is_blocked()` blocks both `Layer.GROUND` and `Layer.CEILING` on an occupied tile (extend
  `tests/test_level_hazard_helpers.gd` or the relevant existing blockade-blocking test file).
- Chain-placement algorithm: produces a connected, in-bounds, non-boundary chain of `body_length`
  tiles; degrades gracefully (no spawn) when no valid chain exists.
- BFS pathing: avoids walls and water tiles; returns `[]` when genuinely unreachable.
- Boxed-in tunnel fallback: carves exactly one wall tile, never the boundary, and the retried path
  succeeds afterward.
- Flood → `RELOCATING` transition: `notify_flooded()` no-ops unless `BLOCKING`; picks a dry
  destination excluding `_water_tiles`.
- Occupant destruction while crawling: a larva/trap/item on a newly-entered tile is destroyed
  (reusing the already-tested `_destroy_occupants_at`, so this test just confirms the crawl stepper
  calls it, not re-testing `_destroy_occupants_at` itself).
- Enemy's new melee tile-check hits a Centipede segment the same way `Player._melee` does.
- `WebShot._on_body_entered` hits a `CentipedeSegment` via physics overlap (mirrors the existing
  `Blockade` web-shot test).

## 9. Earthworm Removal

Delete `entities/earthworm/` (`.gd`, `.tscn`, `.gd.uid`) and `tests/test_earthworm.gd`
(`.gd.uid`). Remove `EARTHWORM_COUNT`, `_seed_earthworms()`, and the `EarthwormScene` preload from
`world/level.gd`. Grep the repo for any other `Earthworm`/`"earthworms"` references (e.g.
`Level._update_sense_sprite_outlines()`'s group lists, if it includes `"earthworms"`) before
considering the swap complete — this is a real deletion, not a deprecation, so every reference must
be found and updated or removed, not left dangling.
