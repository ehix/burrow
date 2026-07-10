# Net-caster Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Net-caster's two class skills (remote-harvest Net Hold + blind immobilize-net Net Shot) with a pick-up-and-carry trap mechanic: place a trap, pick it up to hold it out ahead of you (eating any larva that touches it), and optionally fire it as a fast capture projectile.

**Architecture:** Two `SkillComponent` subclasses (`NetHoldSkill`, `NetShotSkill`) coordinate via a direct object reference (`NetShotSkill.net_hold`) rather than signals, matching this codebase's existing skill-to-skill wiring style. The projectile becomes a fast variant of `WebShot`'s dispatch-by-collision-type pattern, reusing `WebTrap.catch_larva()` for the "capture" resolution so a shot-caught larva is indistinguishable from a walked-into one.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-10-net-caster-rework-design.md` — every task below implements a piece of it; read it once for full context before starting.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1 | tail -20`
  (drop `-gselect=` to run the whole suite). Expect `All tests passed!` in the output.
- Import + parse-error check after any `.tscn`/`.godot` edit: `~/.local/bin/godot --headless --path . --import` (grep output for `error`/`ERROR`).
- Explicit decisions locked in during design review — do not relitigate:
  1. Net Shot vs. a spider keeps the current hard 2.5s immobilize + status-effect copy (not downgraded to a plain entangle).
  2. No manual drop of a held trap.
  3. A pre-loaded trap's larva is auto-eaten on pickup, not carried loaded.
- This slice touches only Net-caster code (`entities/skills/net_hold_skill.gd`, `entities/skills/net_projectile_skill.gd` → renamed, `entities/skills/scenes/net_shot.gd`/`.tscn`, `entities/player/player.gd`/`.tscn`, `entities/enemy/enemy.gd`, `project.godot`'s input map, and the corresponding tests). No other class, UI, or system changes.

---

### Task 1: Rewrite NetHoldSkill (pick up, auto-eat, forward-tile catch)

**Files:**
- Modify: `entities/skills/net_hold_skill.gd` (full rewrite)
- Test: `tests/test_net_hold_skill.gd` (new)

**Interfaces:**
- Consumes: `WebTrap` (`entities/web/web_trap.gd`) — reads `.owner_spider`, `.spent`, `.caught_larva`, `.global_position`; calls `.queue_free()`. `HungerComponent` (`components/hunger_component.gd`) — `.satiate(amount: float) -> float`. `GridMover` (`components/grid_mover.gd`) — reads `.tile_size: int`. `EventBus` autoload signals `larva_consumed(by: Node, overflow: float)`, `excess_consumed(by: Node, amount: float)`.
- Produces: `NetHoldSkill.holding: bool`, `NetHoldSkill.is_holding() -> bool`, `NetHoldSkill.spend() -> void` (ends holding without eating anything — called by `NetShotSkill` in Task 2). `reach: float` export (unchanged name from the old script, default 48.0).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_net_hold_skill.gd`:

```gdscript
extends GutTest
## NetHoldSkill's contract (Net-caster rework, design doc §"Net Hold"): pick
## up an owned, unspent trap within reach and hold it out ahead of your
## facing tile; a larva that touches that forward tile is eaten and the trap
## is spent; a trap that already held a larva is auto-eaten on pickup
## instead. No manual drop.

class FakeSpider:
	extends Node2D
	var facing := Vector2.RIGHT


func _make_spider(hunger_value: float = 50.0) -> Array:
	var spider := FakeSpider.new()
	add_child_autofree(spider)
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.current_hunger = hunger_value
	spider.add_child(hunger)
	return [spider, hunger]


func _make_trap(owner_spider: Node) -> WebTrap:
	var trap := WebTrap.new()
	trap.setup(owner_spider)
	add_child_autofree(trap)
	return trap


func _make_larva() -> Node2D:
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	autofree(larva)
	return larva


func test_pickup_requires_an_owned_trap_within_reach() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var other := Node2D.new()
	autofree(other)
	var trap := _make_trap(other) # owned by someone else
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_false(skill.holding, "can't pick up a trap you didn't place")


func test_pickup_an_own_trap_within_reach() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_true(skill.holding)
	assert_true(trap.is_queued_for_deletion(), "the placed trap is picked up, not left standing")


func test_pickup_ignores_a_trap_out_of_reach() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position + Vector2(500, 0)

	var skill := NetHoldSkill.new()
	skill.reach = 48.0
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_false(skill.holding)


func test_picking_up_a_preloaded_trap_eats_the_larva_immediately() -> void:
	var pair := _make_spider(50.0)
	var spider: Node2D = pair[0]
	var hunger: HungerComponent = pair[1]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position
	trap.catch_larva(_make_larva())

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_true(skill.holding, "you're still holding the now-empty trap")
	assert_almost_eq(hunger.current_hunger, 10.0, 0.001, "the preloaded larva is eaten on pickup")


func test_a_larva_touching_the_held_forward_tile_is_eaten_and_the_trap_is_spent() -> void:
	var pair := _make_spider(50.0)
	var spider: Node2D = pair[0]
	var hunger: HungerComponent = pair[1]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)
	assert_true(skill.holding)

	var larva := _make_larva()
	larva.global_position = spider.global_position + Vector2.RIGHT * 48.0 # one tile ahead, facing RIGHT

	skill._physics_process(0.016)

	assert_false(skill.holding, "the trap is spent once it catches a larva")
	assert_almost_eq(hunger.current_hunger, 10.0, 0.001)


func test_a_larva_far_from_the_forward_tile_is_left_alone() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	var larva := _make_larva()
	larva.global_position = spider.global_position + Vector2(500, 500)

	skill._physics_process(0.016)

	assert_true(skill.holding, "a distant larva doesn't trigger the catch")


func test_spend_ends_holding_without_eating_anything() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)
	assert_true(skill.holding)

	skill.spend()

	assert_false(skill.holding)


func test_cannot_pick_up_a_second_trap_while_already_holding() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var first_trap := _make_trap(spider)
	first_trap.global_position = spider.global_position
	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)
	assert_true(skill.holding)

	var second_trap := _make_trap(spider)
	second_trap.global_position = spider.global_position
	skill._on_activate(spider)

	assert_false(second_trap.is_queued_for_deletion(), "already holding — the second trap stays on the ground")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_net_hold_skill.gd 2>&1 | tail -30`
Expected: FAIL — `holding` not found on `NetHoldSkill` (the old script has no such property), or similar missing-member errors.

- [ ] **Step 3: Rewrite the implementation**

Replace the full contents of `entities/skills/net_hold_skill.gd`:

```gdscript
class_name NetHoldSkill
extends SkillComponent
## Net-Casting Spider: pick up a placed trap you own and hold it out ahead of
## you as a mobile hazard (design doc, Net-caster rework). Any larva that
## steps onto the held trap's forward tile is eaten immediately and the trap
## is spent. A pre-loaded trap (one that already caught a larva before being
## picked up) is eaten immediately on pickup instead. No manual drop —
## holding only ever resolves by eating (here) or by NetShotSkill firing it
## (spend()).

@export var reach: float = 48.0

var holding: bool = false

var _visual: Node2D = null
var _holder: Node2D = null


## Placeholder held-trap graphic, matching NetShot's own draw-a-diamond
## convention — swap for real art later.
class HeldTrapVisual:
	extends Node2D

	func _draw() -> void:
		var half := 8.0
		var pts := PackedVector2Array([Vector2(half, 0), Vector2(0, half), Vector2(-half, 0), Vector2(0, -half)])
		draw_colored_polygon(pts, Color(0.75, 0.75, 0.7, 0.85))
		draw_line(pts[0], pts[2], Color(0.4, 0.4, 0.35), 1.0)
		draw_line(pts[1], pts[3], Color(0.4, 0.4, 0.35), 1.0)


func _on_activate(source: Node) -> void:
	if holding:
		return
	var trap := _nearest_ready_trap(source as Node2D)
	if trap == null:
		return
	_holder = source as Node2D
	if trap.caught_larva != null:
		_eat(trap.caught_larva, source)
	trap.queue_free()
	holding = true
	_spawn_visual()


func is_holding() -> bool:
	return holding


## Called by NetShotSkill when it fires — ends holding without eating
## anything (the trap becomes the projectile instead).
func spend() -> void:
	holding = false
	_teardown_visual()


func _physics_process(_delta: float) -> void:
	if not holding or _holder == null or not is_instance_valid(_holder):
		return
	var forward := _forward_tile_position(_holder)
	if _visual != null and is_instance_valid(_visual):
		_visual.global_position = forward
	var catch_radius := _tile_size(_holder) * 0.5
	for node in _holder.get_tree().get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva == null:
			continue
		if larva.global_position.distance_to(forward) <= catch_radius:
			_eat(larva, _holder)
			holding = false
			_teardown_visual()
			return


func _eat(larva: Node, spider: Node) -> void:
	var hunger := _find_hunger(spider)
	var heal_amount: float = larva.heal_value() if larva.has_method("heal_value") else 40.0
	var overflow := 0.0
	if hunger != null:
		overflow = hunger.satiate(heal_amount)
	EventBus.larva_consumed.emit(spider, overflow)
	if overflow > 0.0:
		EventBus.excess_consumed.emit(spider, overflow)
	if is_instance_valid(larva):
		larva.queue_free()


func _nearest_ready_trap(source: Node2D) -> WebTrap:
	if source == null:
		return null
	var best: WebTrap = null
	var best_dist := reach
	for node in source.get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap == null or trap.spent or trap.owner_spider != source:
			continue
		var d := source.global_position.distance_to(trap.global_position)
		if d <= best_dist:
			best_dist = d
			best = trap
	return best


func _forward_tile_position(source: Node2D) -> Vector2:
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	return source.global_position + facing * _tile_size(source)


func _tile_size(source: Node2D) -> float:
	var mover := source.get_node_or_null("GridMover") as GridMover
	return float(mover.tile_size) if mover != null else 48.0


func _find_hunger(spider: Node) -> HungerComponent:
	for child in spider.get_children():
		if child is HungerComponent:
			return child
	return null


func _spawn_visual() -> void:
	_visual = HeldTrapVisual.new()
	_spawn_parent(_holder).add_child(_visual)
	_visual.global_position = _forward_tile_position(_holder)
	_visual.queue_redraw()


func _teardown_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_net_hold_skill.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `8/8 passed`.

- [ ] **Step 5: Commit**

```bash
git add entities/skills/net_hold_skill.gd tests/test_net_hold_skill.gd
git commit -m "Rework Net Hold into a pick-up-and-carry trap mechanic"
```

---

### Task 2: Rename NetProjectileSkill to NetShotSkill and gate it on holding

**Files:**
- Modify: `entities/skills/net_projectile_skill.gd` → renamed to `entities/skills/net_shot_skill.gd` (rewrite)
- Delete: `entities/skills/net_projectile_skill.gd`, `entities/skills/net_projectile_skill.gd.uid`
- Test: `tests/test_net_projectile_skill.gd` → renamed to `tests/test_net_shot_skill.gd` (rewrite)

**Interfaces:**
- Consumes: `NetHoldSkill.is_holding() -> bool` and `NetHoldSkill.spend() -> void` (Task 1). `WebTrap` (`entities/web/web_trap.gd`) — `.setup(placer: Node)`, `.catch_larva(larva: Node)`. `StatusEffectComponent` — unchanged from the old script's `_copy_status_effects`.
- Produces: `class_name NetShotSkill` with `net_hold: NetHoldSkill` (plain property, set externally — not `@export`, since `Enemy._make_skills()` constructs skills dynamically via `.new()` and can't wire a `NodePath`), `net_shot_scene: PackedScene` (unchanged export name from the old script), `muzzle_offset`, `immobilize_duration` (unchanged), `resolve_hit(shooter: Node, victim: Node) -> void` (unchanged behavior), new `resolve_larva_hit(shooter: Node, larva: Node, at_position: Vector2) -> void`.

- [ ] **Step 1: Write the failing tests**

First, remove the old test and script (they're being renamed, not kept side-by-side):

```bash
git rm entities/skills/net_projectile_skill.gd entities/skills/net_projectile_skill.gd.uid tests/test_net_projectile_skill.gd tests/test_net_projectile_skill.gd.uid
```

Create `tests/test_net_shot_skill.gd`:

```gdscript
extends GutTest
## NetShotSkill's contract (Net-caster rework): only fires while holding a
## trap (spends it on activation, via NetHoldSkill.spend()); on a spider hit,
## resolve_hit() keeps the pre-rework hard immobilize + status-copy
## unchanged; on a larva hit, resolve_larva_hit() captures it alive (spawns
## a live, consumable WebTrap) instead of killing it outright.

class RecordingVictim:
	extends Node2D
	var calls: Array = []
	func apply_web_hit(push_dir: Vector2i, factor: float, slow_duration: float, stun_duration: float) -> void:
		calls.append([push_dir, factor, slow_duration, stun_duration])


func _make_spider_with_status() -> Node2D:
	var spider := Node2D.new()
	autofree(spider)
	var status := StatusEffectComponent.new()
	spider.add_child(status)
	return spider


func test_resolve_hit_fully_immobilizes_with_no_slow() -> void:
	var skill := NetShotSkill.new()
	autofree(skill)
	skill.immobilize_duration = 2.5
	var shooter := _make_spider_with_status()
	var victim := RecordingVictim.new()
	autofree(victim)

	skill.resolve_hit(shooter, victim)

	assert_eq(victim.calls.size(), 1)
	var call: Array = victim.calls[0]
	assert_eq(call[0], Vector2i.ZERO, "no shove")
	assert_eq(call[1], 1.0, "no slow — factor 1.0")
	assert_eq(call[2], 0.0, "no slow duration")
	assert_eq(call[3], 2.5, "full stun duration")


func test_resolve_hit_copies_the_shooters_active_status_effects() -> void:
	var skill := NetShotSkill.new()
	autofree(skill)
	var shooter := _make_spider_with_status()
	var shooter_status := shooter.get_child(0) as StatusEffectComponent
	shooter_status.apply(&"venomous", 3.0, 10.0)

	var victim := RecordingVictim.new()
	autofree(victim)
	var victim_status := StatusEffectComponent.new()
	victim.add_child(victim_status)

	skill.resolve_hit(shooter, victim)

	assert_true(victim_status.has(&"venomous"))
	assert_eq(victim_status.magnitude(&"venomous"), 3.0)


func test_resolve_hit_without_a_victim_status_component_is_a_noop() -> void:
	var skill := NetShotSkill.new()
	autofree(skill)
	var shooter := _make_spider_with_status()
	var victim := RecordingVictim.new()
	autofree(victim)

	skill.resolve_hit(shooter, victim)

	assert_eq(victim.calls.size(), 1, "the immobilize itself still lands")


func test_activate_is_a_noop_when_not_holding() -> void:
	var skill := NetShotSkill.new()
	add_child_autofree(skill)
	var hold := NetHoldSkill.new()
	add_child_autofree(hold)
	skill.net_hold = hold
	var shooter := Node2D.new()
	autofree(shooter)

	var fired := skill.activate(shooter)

	assert_false(fired, "nothing to fire — no trap held")


func test_activate_spends_the_held_trap() -> void:
	var skill := NetShotSkill.new()
	add_child_autofree(skill)
	var hold := NetHoldSkill.new()
	add_child_autofree(hold)
	skill.net_hold = hold
	hold.holding = true # simulate an already-held trap without a full pickup
	var shooter := Node2D.new()
	autofree(shooter)

	skill.activate(shooter)

	assert_false(hold.holding, "firing spends the held trap")


func test_resolve_larva_hit_captures_instead_of_killing() -> void:
	var skill := NetShotSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	add_child_autofree(shooter)
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)

	skill.resolve_larva_hit(shooter, larva, Vector2(100, 100))

	assert_false(larva.is_queued_for_deletion(), "captured, not killed")
	assert_true(WebTrap.tile_has_caught_web(get_tree(), Vector2i(2, 2), 48),
		"a live trap now holds the larva at the impact tile")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_net_shot_skill.gd 2>&1 | tail -30`
Expected: FAIL — `NetShotSkill` not found (class doesn't exist yet under that name).

- [ ] **Step 3: Write the implementation**

Create `entities/skills/net_shot_skill.gd`:

```gdscript
class_name NetShotSkill
extends SkillComponent
## Net-Casting Spider: fires the currently-held trap as a fast capture shot
## (Net-caster rework). Only activates while `net_hold.is_holding()` is true
## — firing empty-handed is a no-op, no cooldown/hunger spent. On a landed
## hit it dispatches by victim type: a spider gets the unchanged pre-rework
## hard immobilize (2.5s hard stun, no slow) plus a copy of the shooter's own
## active status effects (e.g. Poison picked up from Fungal Larva); a larva
## is captured alive — see resolve_larva_hit().
##
## `net_shot_scene` is the fast projectile scene (entities/skills/scenes/
## net_shot.gd/.tscn) whose own script calls back into resolve_hit()/
## resolve_larva_hit() below on landing.

@export var net_shot_scene: PackedScene
@export var muzzle_offset: float = 18.0
@export var immobilize_duration: float = 2.5

## Set externally by whichever caller wires this skill's sibling NetHoldSkill
## — Player._ready() for the player, Enemy._make_skills() for the enemy. Not
## an @export/NodePath since Enemy constructs skills dynamically via .new().
var net_hold: NetHoldSkill = null

const WebTrapScene := preload("res://entities/web/web_trap.tscn")


func activate(source: Node) -> bool:
	if net_hold == null or not net_hold.is_holding():
		return false
	return super.activate(source)


func _on_activate(source: Node) -> void:
	net_hold.spend()
	if net_shot_scene == null:
		return
	var mover := source as Node2D
	if mover == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var shot := net_shot_scene.instantiate()
	_spawn_parent(source).add_child(shot)
	shot.global_position = mover.global_position + facing * muzzle_offset
	if shot.has_method("launch"):
		shot.launch(facing, source, self)


## Called by the net shot's own script when it lands a hit on a spider.
## Unchanged from the pre-rework NetProjectileSkill: a hard, full stun with
## no slow, plus a copy of the shooter's active status effects.
func resolve_hit(shooter: Node, victim: Node) -> void:
	if victim.has_method("apply_web_hit"):
		victim.apply_web_hit(Vector2i.ZERO, 1.0, 0.0, immobilize_duration)
	_copy_status_effects(shooter, victim)


## Called by the net shot's own script when it lands on a larva: captures it
## alive at the impact point using the same WebTrap machinery a normally
## -placed trap uses (including its own auto-consume-if-a-spider-is-standing
## -there path), instead of killing it outright.
func resolve_larva_hit(shooter: Node, larva: Node, at_position: Vector2) -> void:
	var trap: WebTrap = WebTrapScene.instantiate()
	_spawn_parent(shooter).add_child(trap)
	trap.global_position = at_position
	trap.setup(shooter)
	trap.catch_larva(larva)


func _copy_status_effects(shooter: Node, victim: Node) -> void:
	var from := _status_of(shooter)
	var to := _status_of(victim)
	if from != null and to != null:
		from.copy_active_into(to)


func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_net_shot_skill.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `6/6 passed`.

- [ ] **Step 5: Commit**

```bash
git add entities/skills/net_shot_skill.gd tests/test_net_shot_skill.gd entities/skills/net_projectile_skill.gd entities/skills/net_projectile_skill.gd.uid tests/test_net_projectile_skill.gd tests/test_net_projectile_skill.gd.uid
git commit -m "Rename NetProjectileSkill to NetShotSkill, gate firing on holding a trap"
```

---

### Task 3: Rewrite the net_shot projectile scene (fast, larva-aware capture shot)

**Files:**
- Modify: `entities/skills/scenes/net_shot.gd` (rewrite)
- Modify: `entities/skills/scenes/net_shot.tscn` (collision mask)
- Test: `tests/test_net_shot_projectile.gd` (new)

**Interfaces:**
- Consumes: `NetShotSkill.resolve_hit(shooter, victim)`, `NetShotSkill.resolve_larva_hit(shooter, larva, at_position)` (Task 2). `WebTrap.take_web_hit()`, `Blockade.take_hit()` (unchanged, existing).
- Produces: `class_name NetShot` (unchanged name) with `speed: float` (default raised), `launch(direction: Vector2, source: Node, skill: NetShotSkill) -> void` (same signature shape as before, but typed to the renamed `NetShotSkill`), `_on_body_entered(body: Node2D) -> void`, `_on_area_entered(area: Area2D) -> void` (both called directly by tests, matching this repo's `WebShot` test convention — no physics frames needed).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_net_shot_projectile.gd`:

```gdscript
extends GutTest
## The Net-caster's fast capture projectile (rework): a much wider collision
## mask than the old net (matches WebShot's world|larva|hurtbox|trap), and
## dispatches by what it strikes — a larva hands off to the firing skill's
## resolve_larva_hit() (capture, not kill); a spider hurtbox hands off to
## resolve_hit() (unchanged hard immobilize); traps and blockades take a
## destructive hit like a normal web shot. Drives the collision callbacks
## directly (no physics frames), mirroring test_web_shot.gd's convention.

const NetShotScene := preload("res://entities/skills/scenes/net_shot.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")


class RecordingSkill:
	extends NetShotSkill
	var larva_hits: Array = []
	var spider_hits: Array = []
	func resolve_larva_hit(shooter: Node, larva: Node, at_position: Vector2) -> void:
		larva_hits.append([shooter, larva, at_position])
	func resolve_hit(shooter: Node, victim: Node) -> void:
		spider_hits.append([shooter, victim])


func _make_shot() -> NetShot:
	var shot: NetShot = NetShotScene.instantiate()
	add_child_autofree(shot)
	return shot


func _make_larva() -> Larva:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	return larva


func test_default_speed_is_much_faster_than_a_web_shot() -> void:
	assert_gt(_make_shot().speed, 340.0 * 2.0, "far faster than WebShot's 340")


func test_hitting_a_larva_hands_off_to_the_firing_skills_capture() -> void:
	var shot := _make_shot()
	var skill := RecordingSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	autofree(shooter)
	shot.launch(Vector2.RIGHT, shooter, skill)
	var larva := _make_larva()

	shot._on_body_entered(larva)

	assert_eq(skill.larva_hits.size(), 1)
	assert_eq(skill.larva_hits[0][1], larva)
	assert_false(larva.is_queued_for_deletion(), "captured, not killed outright")


func test_hitting_a_trap_registers_a_destructive_hit() -> void:
	var shot := _make_shot()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	shot._on_body_entered(trap)
	assert_eq(trap.web_hits, 1)


func test_hitting_a_blockade_registers_a_hit() -> void:
	var blockade := Blockade.new()
	add_child_autofree(blockade)
	blockade.setup(3)
	_make_shot()._on_body_entered(blockade)
	assert_false(blockade.is_queued_for_deletion())
	_make_shot()._on_body_entered(blockade)
	_make_shot()._on_body_entered(blockade)
	assert_true(blockade.is_queued_for_deletion())


func test_hitting_a_spider_hurtbox_hands_off_to_resolve_hit() -> void:
	var shot := _make_shot()
	var skill := RecordingSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	autofree(shooter)
	shot.launch(Vector2.RIGHT, shooter, skill)

	var victim := Node2D.new()
	add_child_autofree(victim)
	var hurtbox := Hurtbox.new()
	victim.add_child(hurtbox)

	shot._on_area_entered(hurtbox)

	assert_eq(skill.spider_hits.size(), 1)
	assert_eq(skill.spider_hits[0][1], victim)


func test_ignores_its_own_shooters_hurtbox() -> void:
	var shot := _make_shot()
	var skill := RecordingSkill.new()
	add_child_autofree(skill)
	var shooter := Node2D.new()
	add_child_autofree(shooter)
	var hurtbox := Hurtbox.new()
	shooter.add_child(hurtbox)
	shot.launch(Vector2.RIGHT, shooter, skill)

	shot._on_area_entered(hurtbox)

	assert_eq(skill.spider_hits.size(), 0, "a shot never resolves against its own shooter")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_net_shot_projectile.gd 2>&1 | tail -30`
Expected: FAIL — `speed` default is 300 (not `> 680`), `_on_body_entered` on a larva doesn't call into any skill (old script ignores larvae entirely since the old mask excludes them and the old body_entered handler is a no-op stop).

- [ ] **Step 3: Rewrite the implementation**

Replace the full contents of `entities/skills/scenes/net_shot.gd`:

```gdscript
class_name NetShot
extends Area2D
## Net-Caster's fast capture projectile (rework). Travels far faster than a
## normal WebShot; on a landed hit it dispatches by what it struck: a larva
## hands off to the firing NetShotSkill's resolve_larva_hit() (captured
## alive, not killed); a spider hurtbox hands off to resolve_hit() (hard
## immobilize + status-copy, unchanged from the pre-rework net); a placed
## trap/blockade takes a destructive hit like a normal WebShot; a wall just
## stops it. Collision mask = world(1) | larva(8) | hurtbox(16) | trap(32) =
## 57 — matches WebShot's, unlike the old hurtbox-only net (mask 17).
## Placeholder visual: a small drawn diamond (no art asset yet), matching
## CombatFx.SlashVisual's own placeholder-graphic convention.

@export var speed: float = 900.0
@export var max_lifetime: float = 1.2

var _velocity := Vector2.ZERO
var _source: Node = null
var _skill: NetShotSkill = null
var _spent := false
var _life := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## Called by NetShotSkill right after spawn.
func launch(direction: Vector2, source: Node, skill: NetShotSkill) -> void:
	var dir := direction.normalized()
	_velocity = dir * speed
	_source = source
	_skill = skill
	rotation = dir.angle()


func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_life += delta
	if _life >= max_lifetime:
		_despawn()


func _draw() -> void:
	var half := 6.0
	var pts := PackedVector2Array([Vector2(half, 0), Vector2(0, half), Vector2(-half, 0), Vector2(0, -half)])
	draw_colored_polygon(pts, Color(0.75, 0.75, 0.7, 0.85))
	draw_line(pts[0], pts[2], Color(0.4, 0.4, 0.35), 1.0)
	draw_line(pts[1], pts[3], Color(0.4, 0.4, 0.35), 1.0)


func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body is WebTrap:
		(body as WebTrap).take_web_hit()
	elif body is Blockade:
		(body as Blockade).take_hit()
	elif body.is_in_group("larvae"):
		if _skill != null:
			_skill.resolve_larva_hit(_source, body, global_position)
	# else: a wall — nothing to do but stop.
	_despawn()


func _on_area_entered(area: Area2D) -> void:
	if _spent or not (area is Hurtbox):
		return
	var hurtbox := area as Hurtbox
	var victim: Node = hurtbox.owner if hurtbox.owner != null else hurtbox.get_parent()
	if victim == _source:
		return
	if _skill != null and victim != null:
		_skill.resolve_hit(_source, victim)
	_despawn()


func _despawn() -> void:
	if _spent:
		return
	_spent = true
	queue_free()
```

Update `entities/skills/scenes/net_shot.tscn`'s collision mask from 17 to 57 — change the `[node name="NetShot" type="Area2D"]` block's `collision_mask = 17` line to `collision_mask = 57`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_net_shot_projectile.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `6/6 passed`.

- [ ] **Step 5: Import and commit**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.

```bash
git add entities/skills/scenes/net_shot.gd entities/skills/scenes/net_shot.tscn tests/test_net_shot_projectile.gd
git commit -m "Widen the net shot's collision mask and add fast larva-capture dispatch"
```

---

### Task 4: Wire Player to the renamed skill and rename the input action

**Files:**
- Modify: `entities/player/player.gd`
- Modify: `entities/player/player.tscn`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `NetHoldSkill` (Task 1), `NetShotSkill` (Task 2) — `@onready` node references resolved from the scene tree.
- Produces: nothing new consumed by later tasks; this task is a leaf wiring point.

- [ ] **Step 1: Rename the input action in project.godot**

In `project.godot`'s `[input]` section, rename the `net_projectile` key to `net_shot`, keeping its event body byte-for-byte identical (same keycode). Find:

```
net_projectile={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":84,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Replace the key only:

```
net_shot={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":84,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Update player.tscn's node and script reference**

In `entities/player/player.tscn`, change the ext_resource declaration (currently around line 19):

```
[ext_resource type="Script" path="res://entities/skills/net_projectile_skill.gd" id="17_netproj"]
```

to:

```
[ext_resource type="Script" path="res://entities/skills/net_shot_skill.gd" id="17_netshot"]
```

And change the node block (currently around lines 124-126):

```
[node name="NetProjectileSkill" type="Node" parent="."]
script = ExtResource("17_netproj")
net_shot_scene = ExtResource("18_netshot")
```

to:

```
[node name="NetShotSkill" type="Node" parent="."]
script = ExtResource("17_netshot")
net_shot_scene = ExtResource("18_netshot")
```

- [ ] **Step 3: Update player.gd**

Change the `@onready` declaration (currently at line 33):

```gdscript
@onready var _net_projectile: NetProjectileSkill = $NetProjectileSkill
```

to:

```gdscript
@onready var _net_shot: NetShotSkill = $NetShotSkill
```

In `_ready()`, right after the line `_status.effect_expired.connect(_on_effect_expired)` (line 79), add the sibling wiring:

```gdscript
	_net_shot.net_hold = _net_hold
```

In the `CLASS_SKILLS` dictionary (line 53), change:

```gdscript
	0: ["net_hold", "net_projectile"],     # SpiderClassData.SpiderClass.NET_CASTER
```

to:

```gdscript
	0: ["net_hold", "net_shot"],           # SpiderClassData.SpiderClass.NET_CASTER
```

In `_physics_process()`, change (currently lines 138-139):

```gdscript
	if Input.is_action_just_pressed("net_projectile") and _is_active_skill("net_projectile"):
		_net_projectile.activate(self)
```

to:

```gdscript
	if Input.is_action_just_pressed("net_shot") and _is_active_skill("net_shot"):
		_net_shot.activate(self)
```

- [ ] **Step 4: Import and boot smoke test**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output (confirms `player.tscn` still parses with the renamed node/script).

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"` — expect no new errors (the game still boots and the player still spawns/moves).

- [ ] **Step 5: Run the full test suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!` (no regressions from the rename — nothing in the current suite references `_net_projectile` directly on `Player`).

- [ ] **Step 6: Commit**

```bash
git add project.godot entities/player/player.tscn entities/player/player.gd
git commit -m "Wire Player to NetShotSkill and rename the net_projectile action to net_shot"
```

---

### Task 5: Wire Enemy AI to the new Net Hold / Net Shot behavior

**Files:**
- Modify: `entities/enemy/enemy.gd`
- Modify: `tests/test_enemy_class_kit.gd`

**Interfaces:**
- Consumes: `NetHoldSkill`, `NetShotSkill` (Tasks 1-2).
- Produces: `Enemy._nearest_own_ready_trap() -> WebTrap` (replaces the removed `_nearest_caught_trap()`), updated `_score_skill()` conditions.

- [ ] **Step 1: Write the failing tests**

In `tests/test_enemy_class_kit.gd`, replace the test at lines 49-55:

```gdscript
func test_net_caster_gets_net_hold_and_net_projectile() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_eq(enemy._skills.size(), 2)
	assert_true(enemy._skills[0] is NetHoldSkill)
	assert_true(enemy._skills[1] is NetProjectileSkill)
```

with:

```gdscript
func test_net_caster_gets_net_hold_and_net_shot() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_eq(enemy._skills.size(), 2)
	assert_true(enemy._skills[0] is NetHoldSkill)
	assert_true(enemy._skills[1] is NetShotSkill)


func test_net_shot_is_wired_to_its_sibling_net_hold() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	var shot: NetShotSkill = enemy._skills[1]
	assert_eq(shot.net_hold, enemy._skills[0])
```

Replace the two tests at lines 121-138:

```gdscript
func test_nearest_caught_trap_finds_a_trap_within_range() -> void:
	var enemy := _make_enemy()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.global_position = enemy.global_position
	trap.caught_larva = Node2D.new()
	add_child_autofree(trap.caught_larva)

	assert_eq(enemy._nearest_caught_trap(), trap)


func test_nearest_caught_trap_ignores_an_empty_trap() -> void:
	var enemy := _make_enemy()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.global_position = enemy.global_position

	assert_null(enemy._nearest_caught_trap())
```

with:

```gdscript
func test_nearest_own_ready_trap_finds_an_owned_trap_within_range() -> void:
	var enemy := _make_enemy()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.setup(enemy)
	trap.global_position = enemy.global_position

	assert_eq(enemy._nearest_own_ready_trap(), trap, "found even though nothing's caught in it yet")


func test_nearest_own_ready_trap_ignores_a_trap_owned_by_someone_else() -> void:
	var enemy := _make_enemy()
	var other := Node2D.new()
	add_child_autofree(other)
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.setup(other)
	trap.global_position = enemy.global_position

	assert_null(enemy._nearest_own_ready_trap())
```

Add a new test (anywhere after `test_score_skill_favors_defensive_skills_while_fleeing`, e.g. right after it):

```gdscript
func test_score_skill_net_shot_only_scores_while_holding_a_trap() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	enemy.state = Enemy.State.CHASE
	enemy._current_target = Node2D.new()
	add_child_autofree(enemy._current_target)
	var shot: NetShotSkill = enemy._skills[1]

	assert_eq(enemy._score_skill(shot), 0.0, "not holding — nothing to fire")

	shot.net_hold.holding = true
	assert_gt(enemy._score_skill(shot), 0.0, "holding — worth firing")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -40`
Expected: FAIL — `NetShotSkill` isn't what `_make_skills()` attaches yet (still `NetProjectileSkill`), `_nearest_own_ready_trap` not found.

- [ ] **Step 3: Update the implementation**

In `entities/enemy/enemy.gd`, change the `NET_CASTER` branch of `_make_skills()` (currently lines 187-190):

```gdscript
		SpiderClassData.SpiderClass.NET_CASTER:
			var proj := NetProjectileSkill.new()
			proj.net_shot_scene = NetShotScene
			return [NetHoldSkill.new(), proj]
```

to:

```gdscript
		SpiderClassData.SpiderClass.NET_CASTER:
			var hold := NetHoldSkill.new()
			var shot := NetShotSkill.new()
			shot.net_shot_scene = NetShotScene
			shot.net_hold = hold
			return [hold, shot]
```

Change `_score_skill()` (currently lines 389-397):

```gdscript
func _score_skill(skill: SkillComponent) -> float:
	if skill is NetHoldSkill:
		return 0.7 if state == State.SEEK_FOOD and _nearest_caught_trap() != null else 0.0
	if skill is NetProjectileSkill or skill is HatchlingsSkill \
			or skill is EggMineSkill or skill is SilkTunnelSkill:
		return 0.6 if state == State.CHASE and _current_target != null else 0.0
	if skill is BlockadeSkill or skill is CamouflageSkill or skill is DecoySkill:
		return 0.6 if state == State.FLEE else 0.0
	return 0.0
```

to:

```gdscript
func _score_skill(skill: SkillComponent) -> float:
	if skill is NetHoldSkill:
		return 0.7 if state == State.SEEK_FOOD and _nearest_own_ready_trap() != null else 0.0
	if skill is NetShotSkill:
		return 0.6 if state == State.CHASE and _current_target != null \
				and (skill as NetShotSkill).net_hold.is_holding() else 0.0
	if skill is HatchlingsSkill or skill is EggMineSkill or skill is SilkTunnelSkill:
		return 0.6 if state == State.CHASE and _current_target != null else 0.0
	if skill is BlockadeSkill or skill is CamouflageSkill or skill is DecoySkill:
		return 0.6 if state == State.FLEE else 0.0
	return 0.0
```

Change `_nearest_caught_trap()` (currently lines 400-408):

```gdscript
## A caught larva within easy reach — worth a Net Hold instead of walking
## all the way up to the trap and eating normally.
func _nearest_caught_trap() -> Node:
	for node in get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap != null and trap.caught_larva != null \
				and global_position.distance_to(trap.global_position) <= eat_range * 2.0:
			return trap
	return null
```

to:

```gdscript
## An unspent trap this enemy placed, within easy reach — worth a Net Hold
## pickup whether or not it's already caught a larva (a pre-loaded trap is
## auto-eaten on pickup, so there's no special case for that here).
func _nearest_own_ready_trap() -> WebTrap:
	for node in get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap != null and not trap.spent and trap.owner_spider == self \
				and global_position.distance_to(trap.global_position) <= eat_range * 2.0:
			return trap
	return null
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -40`
Expected: `All tests passed!`, `19/19 passed`.

- [ ] **Step 5: Commit**

```bash
git add entities/enemy/enemy.gd tests/test_enemy_class_kit.gd
git commit -m "Wire Enemy AI to the reworked Net Hold / Net Shot mechanic"
```

---

### Task 6: Full-suite verification and manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full automated test suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!`, with the suite total grown by the new test files added in Tasks 1-3 (8 + 6 + 6 = 20 new tests, plus 2 renamed/replaced in Task 5's file) over the pre-existing baseline.

- [ ] **Step 2: Confirm no stale references remain**

Run: `grep -rn "NetProjectileSkill\|net_projectile" --include="*.gd" --include="*.tscn" --include="project.godot" .`
Expected: no output (every reference was renamed in Tasks 2 and 4).

- [ ] **Step 3: Import and boot smoke test**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"` — expect no new errors.

- [ ] **Step 4: Manual verification in a running Godot session**

Launch the game normally (not headless), cycle to Net-caster with the dev hotkey (Q), and confirm by hand:
- Placing a trap (`place_trap`) then pressing Net Hold picks it up (the placed trap disappears, a small diamond marker appears one tile ahead of you and tracks your facing).
- Walking a larva into that forward tile eats it and the marker disappears.
- Placing another trap, picking it up, then firing Net Shot at a larva captures it (it's caught, not killed — walk up to it afterward and it's consumable like a normal trapped larva).
- Firing Net Shot at the rival spider hard-immobilizes it (it can't move for ~2.5s).
- Pressing Net Shot while not holding anything does nothing (no cooldown/hunger spent — check the HUD hunger bar doesn't move).

- [ ] **Step 5: Final commit (only if manual verification above required fixes)**

If Step 4 surfaced no issues, there's nothing to commit here — the branch is done as of Task 5's commit. If it did, fix, re-run Steps 1-3, then:

```bash
git add -A
git commit -m "Fix issues found in manual Net-caster verification"
```
