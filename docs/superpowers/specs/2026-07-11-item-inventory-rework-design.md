# Item/Inventory Rework — Design

## Context

Playtest feedback flagged that world items are too disposable: walking over
a Fungus Poison/Sense or Seed Pod instantly consumes it (no choice in
timing), and Lure spawns pre-active in the world with an 8s timer that's too
short to matter. This is sub-project D of the larger feedback packet
decomposition (see the Net-caster rework spec for the full breakdown) —
foundational for sub-project I (UI/HUD overhaul), which needs something to
actually display an inventory slot for.

Scope: `entities/player/player.gd`, a new `InventoryComponent`,
`entities/items/world_item_pickup.gd`, `resources/items/lure_item.gd`,
`entities/items/lure_pulse.gd`, `world/level.gd`'s item-seeding, and
`autoloads/game_state.gd` for cross-depth persistence.

## Current state

- `WorldItemPickup` (`entities/items/world_item_pickup.gd`): an `Area2D`
  wrapping a `ConsumableItem` resource. `_on_body_entered` calls
  `item.apply(body)` immediately and frees itself — no inventory of any kind
  exists on `Player` today.
- Lure (`resources/items/lure_item.gd`, `entities/items/lure_pulse.gd`):
  never picked up at all. `Level._spawn_random_item_at()` instantiates an
  already-active `LurePulse` directly into the world at level-build time;
  `LureItem.apply()` is a no-op — a placed Lure pulses larvae toward itself
  every 0.5s for `LureItem.duration` (currently 8.0s), then frees itself.
- `Level._seed_world_items()` reserves only the player/enemy spawn tiles
  before scattering items across `maze.open_cells()` — it does not check
  `maze.is_pit()`, so an item can land on a pit tile. Pits block *all*
  ground-plane movement (`MazeData.is_ground_blocked(x,y) = not is_open(x,y)
  or is_pit(x,y)`), so a pit-spawned item is permanently unreachable by any
  spider on the ground plane — effectively lost.
- `GameState` (`autoloads/game_state.gd`) already snapshots player vitals
  across depth transitions (`store_player_vitals()` /
  `carried_health`/`carried_hunger`), called before `world.gd` frees the
  current `Level` (which frees `Player` along with it) and rebuilds a fresh
  one.
- Every letter key A–Z is already bound in `project.godot`'s `[input]`
  section; a new action needs an unused key.

## Design

### Components & data model

**New: `components/inventory_component.gd`**, `class_name
InventoryComponent extends Node`, added as a child node on `player.tscn`
and `enemy.tscn` (mirrors the existing `HealthComponent`/`HungerComponent`
sibling-component pattern):

```gdscript
@export var auto_use: bool = false  # Enemy sets true; Player leaves false

var held_item: ConsumableItem = null

signal item_held_changed(item: ConsumableItem)  # emitted with null on clear

func try_pickup(item: ConsumableItem) -> bool:
    # false (no-op) if held_item != null — walking over a second item while
    # the slot is full leaves it untouched in the world.
    ...

func use(consumer: Node) -> void:
    # no-op if held_item == null.
    # Lure: instantiate LurePulse into the level's entities container
    #   (reuses TrapPlacer._spawn_parent()'s grandparent-walk pattern) at
    #   consumer's own tile.
    # Everything else: held_item.apply(consumer), same as today's apply().
    # Either branch clears held_item and emits item_held_changed.
    ...
```

`try_pickup` internally calls `use(consumer)` immediately when `auto_use` is
true — this is how Enemy gets old-style instant-consume-on-walkover without
any AI decision code, while sharing the exact same component as Player.

**`entities/items/world_item_pickup.gd`**: `_on_body_entered` changes from
calling `item.apply(body)` directly to locating the body's
`InventoryComponent` (same duck-typed child search
`ConsumableItem._status_of()` already uses for `StatusEffectComponent`) and
calling `try_pickup(item)`. The pickup node only frees itself if the pickup
succeeded (slot was free). A body with no `InventoryComponent` at all is not
expected in practice — collision mask is player|enemy only and both will
carry the component — so no fallback path is needed.

**`resources/items/lure_item.gd`**: `duration` default `8.0` → `60.0`.

**`world/level.gd`**: `_spawn_random_item_at()`'s Lure branch changes from
instantiating an active `LurePulse` to instantiating a `WorldItemPickup`
wrapping a `LureItem`, exactly like the other three items — Lure is now
pickup-then-deploy, not spawn-active. `LurePulse` itself is unchanged; it's
now instantiated from `InventoryComponent.use()` instead of at level-seed
time.

### Data flow

**Pickup:** spider walks over a `WorldItemPickup` → `try_pickup(item)` →
slot free: `held_item = item`, emit `item_held_changed`, pickup frees
itself; slot occupied: no-op, item stays in the world.

**Use** (new `use_item` input action, `Input.is_action_just_pressed` check
added to `player.gd`'s `_physics_process` alongside the other skill checks;
Enemy's AI loop doesn't need this since `auto_use` handles it at pickup
time):
- Fungus Poison / Fungus Sense / Seed Pod: `held_item.apply(self)` —
  unchanged `apply()` bodies, just deferred from walk-over to button-press.
- Lure: spawn `LurePulse` at the player's own tile (no facing/ahead-of-caster
  placement logic — Lure isn't a solid obstacle like Blockade), pulsing for
  60s.
- Either branch clears the slot and emits `item_held_changed`.

**Depth persistence:** `GameState` gains `carried_item: ConsumableItem =
null`, parallel to `carried_health`/`carried_hunger`. The snapshot is taken
at the same call site `store_player_vitals()` already runs from in
`world.gd`, before the current `Level` (and its `Player`) is freed. On
rebuild, `Player._restore_vitals()` (or a sibling method called from the
same place) also restores `held_item` into the new `InventoryComponent`.
`ConsumableItem` is a plain `Resource`, not a `Node` — it survives the
level's `queue_free()` naturally, no special teardown handling required.

**Visual indicator:** a small colored dot above the player sprite, shown
only while `held_item != null`, reusing `WorldItemPickup.ITEM_COLORS`'
color-per-`item_id` mapping (hoisted to a shared location — e.g. a const on
`ConsumableItem` itself — since both `WorldItemPickup` and the new indicator
need it). Listens to `InventoryComponent.item_held_changed`. This is a
placeholder only; sub-project I replaces it with real UI.

### Spawn-time hole avoidance

`Level._seed_world_items()` additionally skips any cell where
`maze.is_pit(cell.x, cell.y)` is true, so no item (including Lure pickups,
now spawned the same way as the other three) can land somewhere no spider
can ever reach. Dynamic hazards that could strand an already-spawned item
post-seed (Water Ingress flooding, Seismic Compaction collapsing a tile into
a wall) are out of scope for D — spawn-time avoidance matches the roadmap's
literal "no spawn ... in holes" wording, and defending against hazards
created after spawn belongs to sub-project G (environment tiles rework),
which already owns water/compaction behavior.

### Input binding

New `use_item` action in `project.godot`'s `[input]` section, bound to `Tab`
(physical keycode `4194306`) — the one keyboard action left unbound.

## Testing

- `tests/test_inventory_component.gd` (new): `try_pickup` fills an empty
  slot and returns true; `try_pickup` on an occupied slot returns false and
  leaves `held_item` unchanged; `use()` on Fungus/Seed Pod calls `apply()`
  and clears the slot; `use()` on a held Lure spawns a `LurePulse` with the
  60s duration and clears the slot; `auto_use = true` triggers `use()`
  synchronously inside `try_pickup`; `item_held_changed` fires on both fill
  and clear.
- `tests/test_world_item_pickup.gd` (extend existing): pickup now fills the
  body's `InventoryComponent` instead of calling `apply()` directly, and
  does not free itself when the body's slot is already full.
- New/extended `Level` test: `_seed_world_items()` never places an item on a
  pit tile.
- Headless validation per the existing Godot workflow: import check, then a
  throwaway scene run (autoloads — `GameState`, `EventBus` — are required
  for the persistence and signal-relay paths).

## Out of scope

- Multi-slot inventory (explicitly "hold-one-slot" per the roadmap).
- Defending item placement against post-spawn hazards (Water Ingress,
  Seismic Compaction) — deferred to sub-project G.
- Real inventory UI/icons — sub-project I, which this work is foundational
  for.
- Lure facing/ahead-of-caster placement (stays same-tile deploy).
