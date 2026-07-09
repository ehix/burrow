# Grid Movement & Web-Combat Redesign — Design

Date: 2026-07-07
Status: Approved (design), pending implementation plan
Scope: Slice-1 iteration on `slice-1-rebuild`

## Motivation

First playtest surfaced three problems:

1. **Movement feel.** Free 8-way analog movement reads as loose in a tight,
   tile-based maze. Tile-stepping will make position, aiming, and trap/web
   placement crisp and readable.
2. **Webs are shallow.** A web shot is just a 20-damage bullet. It should behave
   like an actual spider web — entangling the enemy, killing (not feeding)
   larvae, and being destructible when placed.
3. **The enemy starves itself.** It can only eat through an unlikely trap
   sequence and hits max hunger in ~33s, so pacing around the map wins by
   default. The enemy must be able to feed itself, forcing the player to engage.

All three are addressed together because grid movement is the foundation the
other two build on (web lanes, contact eating, tile-aligned traps).

## Decisions (locked with the user)

- **Movement:** full tile-step, grid-locked. Player, enemy, and larvae all move
  cell-to-cell.
- **Web shot vs. enemy:** *both* light HP damage *and* a slow/entangle.
- **Larvae + webs:** a web shot kills a larva into an inedible remnant.
- **Placed webs:** destructible — three web-shot hits destroy one.
- **Enemy hunger:** let it eat larvae by contact *and* slow its hunger clock so
  it sustains itself; the player's hunger pressure is unchanged.

Every numeric value below is a **starting/tunable value**, exposed as an
`@export` or `const` so it can be felt out in playtest.

## 1. GridMover component

New `components/grid_mover.gd` — a reusable node added as a child of any
CharacterBody2D that should move on the maze grid. Follows the existing
composition-over-inheritance pattern (`HealthComponent`, `HungerComponent`).

Responsibilities:

- Holds `tile_size` (48) and `step_time` (**0.12s**, ≈400 px/s effective).
- `try_step(dir: Vector2i) -> bool` — begins a one-tile step in a cardinal
  direction **only if** currently idle and the destination tile is clear.
  Returns whether a step started.
- Animates the owner's `position` linearly from the current tile centre to the
  destination centre over `step_time`; the owner is never at rest between tiles.
- `is_moving() -> bool`, and a `step_finished` signal for chaining held movement
  or path-following.
- `speed_scale: float` (default 1.0) multiplies step speed; the web slow sets it
  below 1 for a duration (see §3). `apply_slow(factor, duration)` sets the scale
  then restores it after `duration` via a scene-tree timer.

Blocking check: the owner's own `test_move(transform, dir * tile_size)` against
the physics world. Walls (StaticBody, layer 1) and armed traps (layer 32) block;
open corridors do not. This keeps entities decoupled from `MazeData` — they
never need the grid handed to them, only their own collision setup.

Movement is **4-directional only** (no diagonals): corridors are one tile wide,
so a diagonal step would clip a wall. Diagonal input resolves to its dominant
axis.

## 2. Player, enemy, and larva movement

**Player** (`entities/player/player.gd`):
- Reads `Input.get_vector(...)`, reduces to the dominant cardinal direction, and
  calls `GridMover.try_step`. The last-pressed direction is buffered so holding a
  key produces continuous, responsive tile-stepping and clean turns.
- `facing` becomes the last stepped direction; web shots fire down that lane.
- Firing and trap placement are unchanged in trigger, but now land on tile
  centres because the player is always on one.

**Enemy** (`entities/enemy/enemy.gd`): pathing switches from navmesh to grid.
- The `NavigationAgent2D` node and `_advance_along_path` navmesh logic are
  replaced. The FSM (PATROL / SEEK_FOOD / CHASE / FLEE) and its transition rules
  stay; only the movement/pathing layer changes.
- On repath, the enemy asks the level for a tile path to its target
  (see §4 pathfinding), then walks it one `GridMover` step at a time, re-pathing
  on the existing `repath_interval` or when the path is exhausted.
- Line-of-sight / vision logic is unchanged (still a physics raycast on layer 1).

**Larva** (`entities/larva/larva.gd`): grid wander.
- Each time it is idle, it picks a random open cardinal neighbour and steps there,
  avoiding an immediate reversal **unless** it is a dead-end (only the reverse is
  open). Uses `GridMover` and `test_move` for the open check, so no `MazeData`
  dependency.
- `set_caught` (trap capture) and the webbed-corpse conversion (§3) both stop it.

## 3. Pathfinding — AStarGrid2D, navmesh removed

`world/level.gd`:

- Build an `AStarGrid2D` sized to the maze (`region`, `cell_size = TILE_SIZE`).
  Every wall tile is marked solid (`set_point_solid`), then `update()`.
- Expose `path_tiles(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]`
  and helpers to convert between tile coords and world centres
  (`tile_of(world)`, `centre_of(tile)`), which the enemy and larva use.
- **Delete** `_build_navigation()` and `_corner_index()` (the copy-on-write nav
  triangle builder) and the `NavRegion` node. The `AStarGrid2D` replaces them and
  removes the copy-on-write footgun that section carried.

Determinism: `AStarGrid2D` with a fixed diagonal mode and a fixed heuristic
returns a stable path for a given (from, to) on a given maze, preserving the
seed-reproducibility guarantee.

## 4. Web redesign

**`entities/web/web_shot.gd`** — detection widens and effects branch by target:

- Collision mask gains the **larva (8)** and **trap (32)** layers in addition to
  the existing world (1) and hurtbox (16).
- On hitting an **enemy/player hurtbox** (`area_entered`, not the source's):
  deal reduced **damage 8** (was 20) via the existing `Hurtbox.receive_hit`, and
  call the hit entity's `apply_web_slow(factor, duration)` — the entity forwards
  it to its `GridMover.apply_slow(**0.4**, **2.0s**)`. Then despawn (splat).
  Applies symmetrically: enemy webs slow the player too.
- On hitting a **larva** (`body_entered`, body in group `larvae`): call the
  larva's `web_kill()`, which converts it to an inedible **webbed-corpse decal**
  (a `WebDecal`-style sprite) and removes it from the `larvae` group so neither
  spider can eat it. Then despawn (splat).
- On hitting a **placed web trap** (`body_entered`, body is `WebTrap`): call
  `WebTrap.take_web_hit()` and despawn (splat).
- On hitting a **wall** (`body_entered`, world layer): unchanged — leave splat,
  despawn.

**`entities/web/web_trap.gd`** — destructible:

- New `hits_to_destroy: int = 3` and a hit counter. `take_web_hit()` increments;
  on the 3rd hit the trap is destroyed the same way consumption destroys it
  (leave the torn-web decal, `queue_free`, drop from `traps`). Fewer than 3 hits
  just accrue.
- The trap's body must be on a layer the web shot's mask includes (trap layer
  32) so `body_entered` fires. Traps already block spiders via that layer.

**Player/enemy** gain `apply_web_slow(factor, duration)` that forwards to their
`GridMover`. No-op if they have no `GridMover` (defensive).

Strategic tension (intended): webbing a larva denies the enemy a meal but also
destroys food you might have wanted; shooting a trap can reopen a blocked lane.

## 5. Enemy sustains itself

**Contact eating** (`entities/enemy/enemy.gd`, `SEEK_FOOD`):
- Path to the nearest larva's tile. When the enemy occupies the larva's tile (or
  overlaps it within an eat radius), it consumes the larva directly: satiate its
  `HungerComponent`, emit `larva_consumed`, remove the larva. No trap required.
- Traps remain available (it can still place them) but are no longer the only
  path to food, so the enemy reliably feeds when larvae exist and are reachable.

**Hunger retune:**
- Enemy `hunger_rate` **3.0 → 1.2** (in `rival_spider.tres` / enemy scene).
- Player hunger unchanged (rate 4.0) — the player's starvation pressure is the
  intended tension and stays.
- Net effect: the enemy starves only when food genuinely runs out or when the
  player keeps it too busy fighting to feed; passive pacing no longer wins.

## 6. Food economy

- `LARVA_COUNT` **4 → 6** in `world/level.gd`. Two spiders now eat larvae *and*
  web shots destroy them, so 4 empties the map in seconds. Six keeps a sustained
  but still-contested food supply. Tunable.
- No larva respawn in this slice (out of scope) — scarcity over a level is part
  of the pressure.

## 7. Camera / fog / HUD

Unchanged. The camera follows the player's (now tile-snapped) position; the
darkness toggle and whole-map framing still work. Grid movement does not touch
these systems.

## 8. Testing

GUT unit tests, run headless (per the Godot validation workflow):

- **GridMover:** `try_step` moves exactly one tile; refuses a blocked
  (wall/trap) tile and returns false; refuses a second step while mid-step;
  buffered direction is consumed on `step_finished`; `apply_slow` reduces then
  restores `speed_scale`.
- **Pathfinding:** `AStarGrid2D` path from A to B never enters a wall tile and is
  identical across two builds of the same seed (determinism).
- **Web trap:** destroyed on the 3rd `take_web_hit`, not the 2nd; consumption
  still destroys immediately.
- **Web kills larva:** a web-killed larva is no longer in the `larvae` group and
  cannot be consumed.
- **Enemy contact eating:** an enemy on a larva's tile consumes it (hunger drops,
  larva removed).
- **Enemy sustain:** at `hunger_rate 1.2`, an enemy that reaches food over a
  simulated window does not reach starvation (guards the retune).

In-engine validation: headless import, boot `world.tscn` for N frames, and a
short scripted scene exercising a tile-step, a web-vs-larva kill, and a
3-hit trap destruction.

## Out of scope (this slice)

- Larva respawn / spawning waves.
- Diagonal movement or variable movement speeds beyond the web slow.
- Map-size progression (still fixed 9×9).
- New art (webbed-corpse reuses the existing `WebDecal` sprite approach).
