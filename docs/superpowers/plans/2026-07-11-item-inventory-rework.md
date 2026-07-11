# Item/Inventory Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace walk-over-instant-consume with a single-slot hold-then-use-button inventory; fold Lure into the same pickup flow with a 60s deploy timer; stop items from spawning on unreachable pit tiles; per playtest feedback (sub-project D).

**Architecture:** A new `InventoryComponent` (single-slot, sibling to `HealthComponent`/`HungerComponent`) owns the held item and the use/deploy logic. `WorldItemPickup` routes pickups through it instead of calling `ConsumableItem.apply()` directly. Player gets a real "use item" button; Enemy gets the same component with `auto_use = true`, reproducing today's instant-consume with zero new AI code. Held item persists across depth transitions the same way vitals already do (`GameState`).

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-11-item-inventory-rework-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1 | tail -30`
  (drop `-gselect=` for the whole suite). Expect `All tests passed!`.
- Import check after any `.tscn`/`.tres` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- New `.gd` files generate an untracked `.gd.uid` sidecar the first time Godot imports/runs them — after the final task, run `git status` and stage any stray `.gd.uid` files before considering the branch done.
- This slice touches: `components/inventory_component.gd` (new), `resources/consumable_item.gd`, `resources/items/lure_item.gd`, `entities/items/world_item_pickup.gd`, `autoloads/game_state.gd`, `entities/player/player.tscn`, `entities/player/player.gd`, `entities/enemy/enemy.tscn`, `world/level.gd`, `project.godot`, and their tests. No other system.
- Both `held_item` on `InventoryComponent` and `carried_item` on `GameState` are typed `ConsumableItem` (the base `Resource` class already used by `WorldItemPickup.item`) — every task below must match this exact type, not a subtype.

---

### Task 1: Shared item colors + Lure's 60s timer

**Files:**
- Modify: `resources/consumable_item.gd`
- Modify: `resources/items/lure_item.gd`
- Modify: `entities/items/world_item_pickup.gd`
- Test: `tests/test_world_item_pickup.gd` (existing — verify its color-independent assertions still pass; no new test needed for the const move itself, it's exercised by Task 3's rewritten pickup tests)

**Interfaces:**
- Produces: `ConsumableItem.ITEM_COLORS: Dictionary` (StringName item_id -> Color), `LureItem.duration` default now `60.0`.

- [ ] **Step 1: Move `ITEM_COLORS` onto `ConsumableItem` and add the Lure entry**

In `resources/consumable_item.gd`, add after the class doc comment (before `@export var item_id: StringName`):

```gdscript
## Placeholder color-per-item_id, shared by WorldItemPickup's world dot and
## Player's held-item indicator — no art assets yet (design: item/inventory
## rework).
const ITEM_COLORS := {
	&"fungus_poison": Color(0.55, 0.25, 0.65, 0.9),
	&"fungus_sense": Color(0.3, 0.75, 0.55, 0.9),
	&"seed_pod": Color(0.85, 0.7, 0.25, 0.9),
	&"lure": Color(0.6, 0.85, 1.0, 0.9),
}
```

In `entities/items/world_item_pickup.gd`, delete the local `const ITEM_COLORS := {...}` block (lines 15-19) and change `_draw()`'s lookup from `ITEM_COLORS.get(id, Color.WHITE)` to `ConsumableItem.ITEM_COLORS.get(id, Color.WHITE)`.

- [ ] **Step 2: Bump Lure's default duration**

In `resources/items/lure_item.gd`, change:

```gdscript
@export var duration: float = 8.0
```

to:

```gdscript
@export var duration: float = 60.0
```

- [ ] **Step 3: Run the existing suites to confirm nothing broke**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_world_item_pickup.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_lure_pulse.gd 2>&1 | tail -30`
Expected: both `All tests passed!` — `test_lure_pulse.gd`'s tests all pass an explicit `duration` into `_make_lure()`, so the new 60.0 default doesn't affect them.

- [ ] **Step 4: Commit**

```bash
git add resources/consumable_item.gd resources/items/lure_item.gd entities/items/world_item_pickup.gd
git commit -m "Hoist item colors onto ConsumableItem, bump Lure to a 60s timer"
```

---

### Task 2: `InventoryComponent`

**Files:**
- Create: `components/inventory_component.gd`
- Test: `tests/test_inventory_component.gd` (new)

**Interfaces:**
- Consumes: `ConsumableItem.apply(consumer: Node) -> void` (existing), `LureItem` (existing, `class_name`), `entities/items/lure_pulse.tscn` (existing `PackedScene`, root node has `@export var item: LureItem` and adds itself to group `"world_items"` in `_ready()`).
- Produces: `InventoryComponent.held_item: ConsumableItem`, `InventoryComponent.auto_use: bool` (`@export`, default `false`), `InventoryComponent.try_pickup(item: ConsumableItem, consumer: Node) -> bool`, `InventoryComponent.use(consumer: Node) -> void`, `InventoryComponent.item_held_changed(item: ConsumableItem)` signal (emitted with the new item on pickup, or `null` on clear).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_inventory_component.gd`:

```gdscript
extends GutTest
## InventoryComponent (item/inventory rework): single-slot carry. `use()`
## applies a consumable or, for a held Lure, deploys a LurePulse instead.
## `auto_use = true` (Enemy) makes try_pickup() call use() immediately,
## reproducing the old walk-over-instant-consume behavior through the same
## component Player uses.


func _make_inventory(auto_use: bool = false) -> InventoryComponent:
	var spider := Node2D.new()
	add_child_autofree(spider)
	var inventory := InventoryComponent.new()
	inventory.auto_use = auto_use
	spider.add_child(inventory)
	return inventory


func _make_consumer_with_status() -> Node2D:
	var consumer := Node2D.new()
	add_child_autofree(consumer)
	var status := StatusEffectComponent.new()
	consumer.add_child(status)
	return consumer


func test_try_pickup_fills_an_empty_slot() -> void:
	var inventory := _make_inventory()
	var item := FungusSenseItem.new()

	var picked_up := inventory.try_pickup(item, Node2D.new())

	assert_true(picked_up)
	assert_eq(inventory.held_item, item)


func test_try_pickup_refuses_when_the_slot_is_occupied() -> void:
	var inventory := _make_inventory()
	var first := FungusSenseItem.new()
	inventory.try_pickup(first, Node2D.new())

	var picked_up := inventory.try_pickup(SeedPodItem.new(), Node2D.new())

	assert_false(picked_up)
	assert_eq(inventory.held_item, first, "the second item is refused, first stays held")


func test_try_pickup_emits_item_held_changed() -> void:
	var inventory := _make_inventory()
	var item := SeedPodItem.new()
	var received: Array = []
	inventory.item_held_changed.connect(func(held: ConsumableItem) -> void: received.append(held))

	inventory.try_pickup(item, Node2D.new())

	assert_eq(received, [item])


func test_use_applies_a_consumable_and_clears_the_slot() -> void:
	var inventory := _make_inventory()
	var consumer := _make_consumer_with_status()
	inventory.try_pickup(FungusSenseItem.new(), consumer)

	inventory.use(consumer)

	var status := consumer.get_child(0) as StatusEffectComponent
	assert_true(status.has(&"sense"))
	assert_null(inventory.held_item)


func test_use_emits_item_held_changed_with_null() -> void:
	var inventory := _make_inventory()
	var consumer := _make_consumer_with_status()
	inventory.try_pickup(FungusSenseItem.new(), consumer)
	var received: Array = []
	inventory.item_held_changed.connect(func(held: ConsumableItem) -> void: received.append(held))

	inventory.use(consumer)

	assert_eq(received, [null])


func test_use_on_an_empty_slot_is_a_noop() -> void:
	var inventory := _make_inventory()
	var consumer := _make_consumer_with_status()

	inventory.use(consumer) # must not error

	assert_null(inventory.held_item)


func test_use_on_a_held_lure_spawns_a_lure_pulse_with_its_duration() -> void:
	var inventory := _make_inventory()
	var consumer := Node2D.new()
	add_child_autofree(consumer)
	consumer.global_position = Vector2(300, 300)
	inventory.try_pickup(LureItem.new(), consumer)

	inventory.use(consumer)

	assert_null(inventory.held_item)
	var pulses := get_tree().get_nodes_in_group("world_items")
	assert_eq(pulses.size(), 1)
	var pulse := pulses[0] as LurePulse
	assert_eq(pulse.item.duration, 60.0)
	assert_eq(pulse.global_position, consumer.global_position)


func test_auto_use_consumes_immediately_on_pickup() -> void:
	var inventory := _make_inventory(true)
	var consumer := _make_consumer_with_status()

	inventory.try_pickup(FungusSenseItem.new(), consumer)

	var status := consumer.get_child(0) as StatusEffectComponent
	assert_true(status.has(&"sense"))
	assert_null(inventory.held_item, "auto_use clears the slot the same frame it fills")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_inventory_component.gd 2>&1 | tail -30`
Expected: FAIL — `Cannot find class "InventoryComponent"`.

- [ ] **Step 3: Write the implementation**

Create `components/inventory_component.gd`:

```gdscript
class_name InventoryComponent
extends Node
## Single-slot item carry for a spider (item/inventory rework). Player holds
## a picked-up item until use() is called on button-press; auto_use makes
## Enemy consume/deploy the instant it picks something up, reproducing the
## old walk-over-instant-consume behavior through this same component
## rather than a second code path.

const LurePulseScene := preload("res://entities/items/lure_pulse.tscn")

## Enemy sets this true (it has no button-press input to hook a "use"
## decision into); Player leaves it false.
@export var auto_use: bool = false

var held_item: ConsumableItem = null

## Emitted with the newly-held item, or null when the slot empties (used,
## deployed, or restored empty on a fresh descent).
signal item_held_changed(item: ConsumableItem)


## Fills the slot with `item` if empty. Returns false (no-op — the item
## stays wherever it was) if already holding something. `consumer` is only
## used if auto_use immediately triggers use().
func try_pickup(item: ConsumableItem, consumer: Node) -> bool:
	if held_item != null:
		return false
	held_item = item
	item_held_changed.emit(held_item)
	if auto_use:
		use(consumer)
	return true


## Consumes or deploys the held item. No-op if the slot is empty.
func use(consumer: Node) -> void:
	if held_item == null:
		return
	if held_item is LureItem:
		var lure := LurePulseScene.instantiate()
		lure.item = held_item as LureItem
		_spawn_parent().add_child(lure)
		if consumer is Node2D:
			lure.global_position = (consumer as Node2D).global_position
	else:
		held_item.apply(consumer)
	held_item = null
	item_held_changed.emit(null)


## A deployed Lure should live alongside the spider in the level's entity
## tree, not as this component's own child (which would free it the instant
## the spider dies/the level tears down its children individually) — mirrors
## TrapPlacer._spawn_parent()'s grandparent-walk.
func _spawn_parent() -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return get_tree().current_scene
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_inventory_component.gd 2>&1 | tail -30`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add components/inventory_component.gd tests/test_inventory_component.gd
git status # check for a stray test_inventory_component.gd.uid and add it too if present
git add tests/test_inventory_component.gd.uid 2>/dev/null
git commit -m "Add InventoryComponent: single-slot carry with use()/auto_use"
```

---

### Task 3: `WorldItemPickup` routes through `InventoryComponent`

**Files:**
- Modify: `entities/items/world_item_pickup.gd`
- Test: `tests/test_world_item_pickup.gd` (rewritten)

**Interfaces:**
- Consumes: `InventoryComponent.try_pickup(item, consumer) -> bool` (Task 2).
- Produces: no change to `WorldItemPickup`'s public shape (`item: ConsumableItem` export, `_on_body_entered(body: Node2D) -> void` still called directly by tests, matching the existing pattern).

- [ ] **Step 1: Rewrite the failing/changed tests**

Replace the full contents of `tests/test_world_item_pickup.gd`:

```gdscript
extends GutTest
## WorldItemPickup (item/inventory rework): a spider entering fills its
## InventoryComponent's single slot and consumes the pickup; a larva (or
## anything else) passes through untouched. Application/deployment now
## happens on InventoryComponent.use(), not on pickup — except for a spider
## whose InventoryComponent has auto_use = true (Enemy), which still applies
## immediately, matching the old walk-over-instant-consume behavior.

const PickupScene := preload("res://entities/items/world_item_pickup.tscn")


func _make_pickup(item: ConsumableItem = null) -> WorldItemPickup:
	var pickup: WorldItemPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	pickup.item = item
	return pickup


func _make_spider(auto_use: bool = false) -> Node2D:
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	add_child_autofree(spider)
	var status := StatusEffectComponent.new()
	spider.add_child(status)
	var inventory := InventoryComponent.new()
	inventory.auto_use = auto_use
	spider.add_child(inventory)
	return spider


func test_spider_entering_fills_its_inventory_and_frees_the_pickup() -> void:
	var item := FungusSenseItem.new()
	var pickup := _make_pickup(item)
	var spider := _make_spider()

	pickup._on_body_entered(spider)

	var inventory := spider.get_child(1) as InventoryComponent
	assert_eq(inventory.held_item, item)
	var status := spider.get_child(0) as StatusEffectComponent
	assert_false(status.has(&"sense"), "not applied yet -- only picked up")
	assert_true(pickup.is_queued_for_deletion())


func test_auto_use_spider_applies_the_item_immediately_on_pickup() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	var spider := _make_spider(true)

	pickup._on_body_entered(spider)

	var status := spider.get_child(0) as StatusEffectComponent
	assert_true(status.has(&"sense"))
	assert_true(pickup.is_queued_for_deletion())


func test_refuses_pickup_when_the_spiders_slot_is_already_full() -> void:
	var spider := _make_spider()
	var inventory := spider.get_child(1) as InventoryComponent
	var first := SeedPodItem.new()
	inventory.try_pickup(first, spider)
	var pickup := _make_pickup(FungusSenseItem.new())

	pickup._on_body_entered(spider)

	assert_false(pickup.is_queued_for_deletion(), "second item stays in the world")
	assert_eq(inventory.held_item, first, "the first held item is untouched")


func test_ignores_bodies_that_are_not_spiders() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)

	pickup._on_body_entered(larva)

	assert_false(pickup.is_queued_for_deletion())


func test_without_an_item_assigned_is_a_noop() -> void:
	var pickup := _make_pickup(null)
	var spider := _make_spider()

	pickup._on_body_entered(spider) # must not error

	assert_false(pickup.is_queued_for_deletion())
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_world_item_pickup.gd 2>&1 | tail -30`
Expected: FAIL — `_on_body_entered` still calls `item.apply(body)` directly, so `test_spider_entering_fills_its_inventory_and_frees_the_pickup`'s "not applied yet" assertion fails.

- [ ] **Step 3: Write the implementation**

In `entities/items/world_item_pickup.gd`, replace `_on_body_entered`:

```gdscript
func _on_body_entered(body: Node2D) -> void:
	if _spent or item == null or not body.is_in_group("spiders"):
		return
	var inventory := _inventory_of(body)
	if inventory == null or not inventory.try_pickup(item, body):
		return
	_spent = true
	queue_free()


func _inventory_of(entity: Node) -> InventoryComponent:
	for child in entity.get_children():
		if child is InventoryComponent:
			return child
	return null
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_world_item_pickup.gd 2>&1 | tail -30`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/items/world_item_pickup.gd tests/test_world_item_pickup.gd
git commit -m "Route WorldItemPickup through InventoryComponent instead of instant-apply"
```

---

### Task 4: `GameState.carried_item`

**Files:**
- Modify: `autoloads/game_state.gd`
- Test: `tests/test_game_state.gd`

**Interfaces:**
- Produces: `GameState.carried_item: ConsumableItem` (default `null`), `GameState.store_carried_item(item: ConsumableItem) -> void`. `GameState.clear_carried_vitals()` now also resets `carried_item` to `null`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_game_state.gd` (after `test_start_new_run_clears_carried_vitals`):

```gdscript
func test_clear_carried_vitals_also_clears_the_carried_item() -> void:
	GameState.carried_item = FungusSenseItem.new()
	GameState.clear_carried_vitals()
	assert_null(GameState.carried_item)


func test_store_carried_item_sets_it() -> void:
	var item := SeedPodItem.new()
	GameState.store_carried_item(item)
	assert_eq(GameState.carried_item, item)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_game_state.gd 2>&1 | tail -30`
Expected: FAIL — `Invalid get index 'carried_item'` / `store_carried_item` not found.

- [ ] **Step 3: Write the implementation**

In `autoloads/game_state.gd`, add after `var carried_hunger: float = NAN`:

```gdscript
## Player's held item (item/inventory rework), carried between levels the
## same way vitals are. null = nothing held (also the reset state).
var carried_item: ConsumableItem = null
```

Change `clear_carried_vitals()`:

```gdscript
## Drop any carried vitals/held item so the next spawn uses the component
## defaults (full health, no hunger, empty inventory) instead of continuing
## a previous run's state.
func clear_carried_vitals() -> void:
	carried_health = NAN
	carried_hunger = NAN
	carried_item = null
```

Add after `store_player_vitals()`:

```gdscript
## Snapshot the player's held item before freeing a level on descent —
## called alongside store_player_vitals() from Player.store_vitals().
func store_carried_item(item: ConsumableItem) -> void:
	carried_item = item
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_game_state.gd 2>&1 | tail -30`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add autoloads/game_state.gd tests/test_game_state.gd
git commit -m "Add GameState.carried_item for cross-depth held-item persistence"
```

---

### Task 5: Player wiring — component, use button, visual indicator, persistence

**Files:**
- Modify: `entities/player/player.tscn`
- Modify: `entities/player/player.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `InventoryComponent` (Task 2), `GameState.carried_item`/`store_carried_item()` (Task 4), `ConsumableItem.ITEM_COLORS` (Task 1).
- Produces: `Player.inventory: InventoryComponent` (new `@onready` field — later sub-project I's HUD will read `player.inventory.held_item`/listen to `player.inventory.item_held_changed`), new input action `use_item`.

- [ ] **Step 1: Add the input action**

In `project.godot`, add after the `pause={...}` block (before `[layer_names]`):

```
use_item={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194306,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

(physical_keycode `4194306` is Tab — the one keyboard key not already bound in this file.)

- [ ] **Step 2: Add the `InventoryComponent` node to `player.tscn`**

Add a new `ext_resource` line after the `id="27_decoy"` line:

```
[ext_resource type="Script" path="res://components/inventory_component.gd" id="28_inventory"]
```

Add a new node block at the end of the file (after the `DecoySkill` node):

```
[node name="InventoryComponent" type="Node" parent="."]
script = ExtResource("28_inventory")
```

- [ ] **Step 3: Wire the component, use-button, visual indicator, and persistence into `player.gd`**

Add the onready var after `@onready var _decoy: DecoySkill = $DecoySkill`:

```gdscript
@onready var inventory: InventoryComponent = $InventoryComponent
```

In `_ready()`, add after `_status.effect_expired.connect(_on_effect_expired)`:

```gdscript
	inventory.item_held_changed.connect(func(_item: ConsumableItem) -> void: queue_redraw())
```

In `_physics_process()`, add after the `remove_walls_skill` check (it's a general utility like Sense/Remove Walls, not class-gated):

```gdscript
	if Input.is_action_just_pressed("use_item"):
		inventory.use(self)
```

Add a `_draw()` override (place it near `_update_sprite_tint()`, e.g. right after it):

```gdscript
## Placeholder held-item indicator — a colored dot above the sprite, keyed
## by item_id via ConsumableItem.ITEM_COLORS. Sub-project I replaces this
## with real inventory UI.
func _draw() -> void:
	if inventory.held_item == null:
		return
	var color: Color = ConsumableItem.ITEM_COLORS.get(inventory.held_item.item_id, Color.WHITE)
	draw_circle(Vector2(0, -22), 5.0, color)
```

Change `store_vitals()`:

```gdscript
## Snapshot vitals and the held item into GameState before the level is
## freed on descent.
func store_vitals() -> void:
	GameState.store_player_vitals(health.current_health, hunger.current_hunger)
	GameState.store_carried_item(inventory.held_item)
```

Change `_restore_vitals()`:

```gdscript
## health.max_health is already set by refresh_upgrades() (called via
## apply_class() earlier in _ready()) — this only restores current
## health/hunger against that already-upgrade-aware ceiling. The held item
## restores unconditionally (null is a valid, harmless "nothing held" value
## on a first spawn, unlike vitals' NAN-gated has_carried_vitals() check).
func _restore_vitals() -> void:
	if GameState.has_carried_vitals():
		health.current_health = clampf(GameState.carried_health, 0.0, health.max_health)
		hunger.current_hunger = clampf(GameState.carried_hunger, 0.0, hunger.max_hunger)
	inventory.held_item = GameState.carried_item
```

- [ ] **Step 4: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 5: Run the full suite to confirm nothing broke**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -40`
Expected: `All tests passed!`

- [ ] **Step 6: Manual smoke check (no automated test for input/rendering)**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no new errors (pre-existing warnings, if any, are unrelated to this change — compare against a run before this task if unsure).

- [ ] **Step 7: Commit**

```bash
git add entities/player/player.tscn entities/player/player.gd project.godot
git status # check for a stray .uid on any newly-touched file
git commit -m "Wire InventoryComponent, use-item button, and held-item indicator into Player"
```

---

### Task 6: Enemy gets the same component with `auto_use`

**Files:**
- Modify: `entities/enemy/enemy.tscn`

**Interfaces:**
- Consumes: `InventoryComponent` (Task 2). No `enemy.gd` script changes — `WorldItemPickup._inventory_of()` finds the component by type, and `auto_use = true` handles the "consume immediately" behavior with zero AI code.

- [ ] **Step 1: Add the `InventoryComponent` node to `enemy.tscn`**

Add a new `ext_resource` line after the `id="11_mover"` line:

```
[ext_resource type="Script" path="res://components/inventory_component.gd" id="12_inventory"]
```

Add a new node block at the end of the file (after the `Hurtbox`'s `CollisionShape2D`):

```
[node name="InventoryComponent" type="Node" parent="."]
script = ExtResource("12_inventory")
auto_use = true
```

- [ ] **Step 2: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 3: Run the full suite to confirm nothing broke**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -40`
Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add entities/enemy/enemy.tscn
git commit -m "Give Enemy an auto-use InventoryComponent (matches old instant-consume)"
```

---

### Task 7: Lure joins the pickup flow + spawn-time pit avoidance

**Files:**
- Modify: `world/level.gd`
- Test: `tests/test_level_world_seeding.gd`

**Interfaces:**
- Consumes: `_spawn_pickup_at(world_pos: Vector2, item: ConsumableItem) -> void` (existing, unchanged), `MazeData.is_pit(x: int, y: int) -> bool` (existing), `Level.set_pit_at(tile: Vector2i, value: bool) -> void` (existing, public).
- Produces: no public API change — `_spawn_random_item_at()` and `_seed_world_items()` stay private, behavior changes only.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_level_world_seeding.gd` (after `test_world_items_are_away_from_both_spawns`):

```gdscript
func test_world_items_never_land_on_a_pit_tile() -> void:
	var level := _make_level()
	for item in level.get_tree().get_nodes_in_group("world_items"):
		(item as Node2D).free()

	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	var safe_cell: Vector2i = level.maze.open_cells()[0]
	for cell in level.maze.open_cells():
		if cell != player_tile and cell != enemy_tile:
			safe_cell = cell
			break
	for cell in level.maze.open_cells():
		if cell == player_tile or cell == enemy_tile or cell == safe_cell:
			continue
		level.set_pit_at(cell, true)

	level._seed_world_items()

	for item in level.get_tree().get_nodes_in_group("world_items"):
		var tile: Vector2i = level.tile_of((item as Node2D).global_position)
		assert_eq(tile, safe_cell, "every open, non-spawn tile except one was blocked off as a pit")


func test_seeded_items_are_always_pickups_not_bare_lure_pulses() -> void:
	var level := _make_level()
	for item in level.get_tree().get_nodes_in_group("world_items"):
		assert_true(item is WorldItemPickup,
			"Lure is now picked up like every other item, never spawned pre-active as a bare LurePulse")
```

- [ ] **Step 2: Run the tests to verify the pit-avoidance test fails**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_world_seeding.gd 2>&1 | tail -30`
Expected: `test_world_items_never_land_on_a_pit_tile` FAILs (items still land on pit tiles); `test_seeded_items_are_always_pickups_not_bare_lure_pulses` FAILs whenever that particular seed's 3 rolls include a Lure (branch 0 still spawns a bare `LurePulse`, which is not a `WorldItemPickup`) — since it's random per run, re-run once or twice if it happens to pass this time; the fix below makes it pass unconditionally.

- [ ] **Step 3: Write the implementation**

In `world/level.gd`, delete the `const LurePulseScene := preload("res://entities/items/lure_pulse.tscn")` line.

Replace `_seed_world_items()`:

```gdscript
## Scatter a mix of Fungus Poison/Sense, Seed Pod, and Lure pickups (design
## §5) across random open, non-spawn, non-pit tiles — a pit-tile spawn would
## be permanently unreachable, since pits block all ground-plane movement.
func _seed_world_items() -> void:
	var reserved := {tile_of(player.global_position): true, tile_of(enemy.global_position): true}
	var cells := maze.open_cells()
	cells.shuffle()
	var placed := 0
	for cell in cells:
		if placed >= ITEM_SPAWN_COUNT:
			break
		if reserved.has(cell) or maze.is_pit(cell.x, cell.y):
			continue
		_spawn_random_item_at(cell)
		reserved[cell] = true
		placed += 1
```

Replace `_spawn_random_item_at()`:

```gdscript
## One of four roughly-equal outcomes — Lure, Fungus Poison, Fungus Sense,
## or Seed Pod — all picked up the same way now (item/inventory rework).
## Deployment/consumption happens on InventoryComponent.use(), not on
## pickup; a picked-up Lure deploys a LurePulse wherever it's used.
func _spawn_random_item_at(cell: Vector2i) -> void:
	var world_pos := _tile_centre(cell.x, cell.y)
	match randi() % 4:
		0:
			_spawn_pickup_at(world_pos, LureItem.new())
		1:
			_spawn_pickup_at(world_pos, FungusPoisonItem.new())
		2:
			_spawn_pickup_at(world_pos, FungusSenseItem.new())
		_:
			_spawn_pickup_at(world_pos, SeedPodItem.new())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_world_seeding.gd 2>&1 | tail -30`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -40`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add world/level.gd tests/test_level_world_seeding.gd
git commit -m "Lure joins the pickup flow; items never seed onto pit tiles"
```

---

### Final check

- [ ] Run the full suite once more end-to-end: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -40` — expect `All tests passed!`.
- [ ] Run `git status` — stage any stray `.gd.uid`/`.import` sidecars from new test files before opening the PR.
- [ ] Manual playtest pass (per `docs/superpowers/specs/2026-07-11-item-inventory-rework-design.md`'s testing section and this repo's usual "start the game, exercise the golden path" check): walk over a Fungus/Seed Pod item, confirm it's held not applied; press Tab, confirm it applies and the dot disappears; walk over a Lure, press Tab, confirm a pulse appears and pulls nearby larvae; win a round and confirm a still-held item survives into the next depth.
