# Hatchlings / VFX / Generic Skill Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Hatchlings' escort tightness/lifecycle, make Sense/Camouflage's shared outline shader actually look right (thicker, opacity-independent), rework Sense into a radius-limited outline (no more light-through-walls), and collapse the 8 per-class skill keybinds down to two universal buttons.

**Architecture:** Eight small, mostly-independent fixes across the existing skill/entity/UI layers — no new systems, no new scenes beyond what already exists. `SkillComponent` gains a small cooldown-deferral extension point; `TinySpiderling` gains a real death path; `Enemy` gains one additive opportunistic-melee check; the shared `outline.gdshader`/`OutlineFx` gain an opacity-decoupling uniform; `Level`'s Sense handling becomes continuous and radius-limited instead of a one-shot blanket toggle; `Player`'s input polling collapses from 8 named actions to 2 generic ones, with `SkillBar`/`ui/control_indicators.gd` updated to match.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-12-hatchlings-vfx-input-fixes-design.md` — read once for full context.
- **This branch (`hatchlings-vfx-input-fixes`) is stacked on top of the not-yet-merged `ui-hud-overhaul` branch**, not `main` — `SkillBar` only exists there, and Task 8 needs to touch it.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1` (read the full output, not `tail`; drop `-gselect=` for the whole suite).
- Import check after any `.tscn`/`.gdshader` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- New `.gd`/`.tscn` files generate an untracked `.gd.uid`/`.tscn.uid` sidecar the first time Godot imports/runs them — after each task, run `git status` and stage any stray sidecar files. This project has had this gotcha slip through before.
- Hatchlings no longer despawn on a timer — they persist until killed. Any hit through the standard `Hurtbox` → `HealthComponent.take_damage()` pipeline kills a hatchling outright (1 max HP), matching the "one-hit kill" decision, not a multi-hit health bar.
- `EventBus.class_changed(spider_class: int)` is an existing, unmodified signal this plan consumes — exact signature, do not alter.
- Only touch the files each task's **Files** section lists. This slice touches: `components/skill_component.gd`, `entities/skills/hatchlings_skill.gd`, `entities/skills/scenes/tiny_spiderling.gd`/`.tscn`, `entities/enemy/enemy.gd`, `components/outline_fx.gd`, `assets/shaders/outline.gdshader`, `entities/skills/camouflage_skill.gd`, `world/level.gd`, `entities/skills/sense_skill.gd`, `entities/player/player.gd`, `ui/skill_bar.gd`, `ui/control_indicators.gd`, `project.godot`, and their tests. No other system.

---

### Task 1: `SkillComponent` cooldown-defer extension point

**Files:**
- Modify: `components/skill_component.gd`
- Test: `tests/test_skill_component.gd` (extend)

**Interfaces:**
- Produces: `SkillComponent._defer_cooldown() -> bool` (override point, default `false`), `SkillComponent._start_deferred_cooldown() -> void` — the two seams a subclass uses to delay its real cooldown past `activate()` (Task 4 consumes this).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_skill_component.gd`:

```gdscript
class DeferringSkill:
	extends SkillComponent

	func _defer_cooldown() -> bool:
		return true


func test_non_deferring_skill_arms_cooldown_immediately_on_activate() -> void:
	var skill := SkillComponent.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)

	skill.activate(caster)

	assert_eq(skill.remaining_cooldown(), 5.0)
	assert_false(skill.can_activate())


func test_deferring_skill_stays_non_reactivatable_even_after_cooldown_duration_elapses() -> void:
	var skill := DeferringSkill.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)

	skill._process(10.0) # well past `cooldown`, but _start_deferred_cooldown() was never called

	assert_false(skill.can_activate(), "stays busy until the subclass explicitly starts the real cooldown")
	assert_eq(skill.remaining_cooldown(), 5.0, "shows the frozen cooldown value, not a ticked-down one")


func test_deferring_skill_starts_the_real_cooldown_once_told_to() -> void:
	var skill := DeferringSkill.new()
	skill.cooldown = 5.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)

	skill._start_deferred_cooldown()

	assert_eq(skill.remaining_cooldown(), 5.0)
	skill._process(2.0)
	assert_almost_eq(skill.remaining_cooldown(), 3.0, 0.001, "counts down for real now")


func test_deferring_skill_can_activate_again_once_cooldown_elapses() -> void:
	var skill := DeferringSkill.new()
	skill.cooldown = 1.0
	add_child_autofree(skill)
	var caster := Node2D.new()
	add_child_autofree(caster)
	skill.activate(caster)
	skill._start_deferred_cooldown()

	skill._process(1.0)

	assert_true(skill.can_activate())
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_component.gd 2>&1`
Expected: FAIL — `test_deferring_skill_stays_non_reactivatable_even_after_cooldown_duration_elapses` fails both assertions (today's `_cooldown_left` ticks down normally regardless of `_defer_cooldown()`, since `activate()` never consults it); `test_deferring_skill_starts_the_real_cooldown_once_told_to` and `test_deferring_skill_can_activate_again_once_cooldown_elapses` fail with `Invalid call. Nonexistent function '_start_deferred_cooldown'`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `components/skill_component.gd` with:

```gdscript
class_name SkillComponent
extends Node
## Base for an activatable spider skill: cooldown + hunger cost, mirroring the
## WebEmitter/TrapPlacer pattern so every skill — class specialisations
## (NetHold, Hatchlings, Blockade, Camouflage, ...) and general utilities
## (Sense, Remove Walls) alike — plugs into the same metabolic-cost economy
## (HungerComponent.charge_all) as every other action a spider takes.
## Subclasses implement `_on_activate()`.

@export var cooldown: float = 8.0
@export var hunger_cost: float = 10.0
## Read-only HUD metadata (UI/HUD overhaul) — authored per skill instance in
## each class's .tscn, same pattern cooldown/hunger_cost already use.
@export var display_name: String = ""
@export var description: String = ""

var _cooldown_left: float = 0.0
## True while a subclass has deferred its real cooldown past activation (see
## _defer_cooldown()) — e.g. Hatchlings, whose cooldown shouldn't start
## counting down until every spawned minion has died. Gates can_activate()
## independently of _cooldown_left, which stays at 0 the whole time it's busy.
var _busy: bool = false


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func can_activate() -> bool:
	return not _busy and _cooldown_left <= 0.0


## How many seconds remain before can_activate() returns true again — the
## seam a HUD polls instead of reaching into the private _cooldown_left.
## While busy (see _defer_cooldown()), shows the frozen full `cooldown`
## value rather than a ticking-down one, since the real countdown hasn't
## started yet.
func remaining_cooldown() -> float:
	return cooldown if _busy else _cooldown_left


## Attempt to activate. Returns false on cooldown (no cost charged);
## otherwise starts the cooldown (or, for a skill that deferred it, marks it
## busy instead — see _defer_cooldown()), charges hunger, and calls
## `_on_activate()`.
func activate(source: Node) -> bool:
	if not can_activate():
		return false
	if _defer_cooldown():
		_busy = true
	else:
		_cooldown_left = cooldown
	HungerComponent.charge_all(source.get_tree(), hunger_cost)
	_on_activate(source)
	return true


## Override in a subclass that needs to start its real cooldown later than
## activation (e.g. once every spawned minion has died) instead of
## immediately. While deferred, the skill stays non-reactivatable
## (can_activate() stays false via the `_busy` gate above) until the
## subclass calls _start_deferred_cooldown().
func _defer_cooldown() -> bool:
	return false


## Called by a subclass that returned true from _defer_cooldown(), once
## ready to start the real cooldown countdown.
func _start_deferred_cooldown() -> void:
	_busy = false
	_cooldown_left = cooldown


## Override in subclasses.
func _on_activate(_source: Node) -> void:
	pass
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_component.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add components/skill_component.gd tests/test_skill_component.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Add SkillComponent cooldown-defer extension point"
```

---

### Task 2: `TinySpiderling` — leash/snap escort, real one-hit death, no more lifetime timer

**Files:**
- Modify: `entities/skills/scenes/tiny_spiderling.gd`
- Modify: `entities/skills/scenes/tiny_spiderling.tscn`
- Modify: `entities/skills/hatchlings_skill.gd` (drop the now-removed `lifetime` param from its `setup()` call and its own `lifetime` export)
- Test: `tests/test_tiny_spiderling.gd` (extend/fix)
- Test: `tests/test_hatchlings_skill.gd` (fix call sites)

**Interfaces:**
- Produces: `TinySpiderling.setup(owner_spider: Node, escort_offset: Vector2 = Vector2.ZERO) -> void` (was `setup(owner_spider, lifetime, escort_offset)` — the `lifetime` param is gone), `TinySpiderling.leash_distance: float` (`@export`, default `200.0`), a `Hurtbox` + `HealthComponent` (1 max HP) child pair.

- [ ] **Step 1: Write the failing tests**

In `tests/test_tiny_spiderling.gd`:

Delete `test_expires_after_its_lifetime` entirely (the concept it tests is being removed).

Replace every `spiderling.setup(owner_spider, 5.0)` call with `spiderling.setup(owner_spider)`, every `spiderling.setup(null, 5.0)` with `spiderling.setup(null)`, and `spiderling.setup(owner_spider, 5.0, Vector2(20, 0))` with `spiderling.setup(owner_spider, Vector2(20, 0))` — i.e. drop the second positional argument (the old `lifetime`) from all six remaining call sites (`test_attacks_the_nearest_non_owner_spider_on_contact`, `test_never_targets_its_own_owner`, `test_attack_respects_its_own_cooldown`, `test_escorts_toward_the_owner_plus_offset_when_no_enemy_is_near`, `test_switches_to_chase_when_an_enemy_enters_aggro_radius_and_los`, `test_never_targets_an_enemy_blocked_by_a_wall`, `test_reverts_to_escort_once_the_target_leaves_aggro_radius`).

Append these new tests at the end of the file:

```gdscript
func test_snaps_to_the_escort_point_once_it_falls_beyond_leash_distance() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(0, 0)
	spiderling.global_position = Vector2(1000, 0) # far beyond leash_distance (200)
	spiderling.setup(owner_spider, Vector2(20, 0))

	spiderling._physics_process(0.016)

	assert_eq(spiderling.global_position, Vector2(20, 0),
		"snaps directly to the escort point instead of continuing to path when the gap is too large")


func test_walks_normally_toward_escort_point_when_within_leash_distance() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(100, 0)
	spiderling.global_position = Vector2(0, 0) # 100px away, well under leash_distance (200)
	spiderling.setup(owner_spider)
	var target_point := owner_spider.global_position
	var before := spiderling.global_position.distance_to(target_point)

	for i in 10:
		spiderling._physics_process(0.05)

	var after := spiderling.global_position.distance_to(target_point)
	assert_lt(after, before, "steps toward the escort point rather than snapping when within leash_distance")
	assert_gt(after, 0.0, "hasn't teleported all the way there in one frame")


func test_dies_in_one_hit_via_its_hurtbox() -> void:
	var spiderling := _make_spiderling()
	var hurtbox := spiderling.get_node("Hurtbox") as Hurtbox

	hurtbox.receive_hit(1.0, null)

	assert_true(spiderling.is_queued_for_deletion(), "any hit through the standard Hurtbox pipeline kills it")
```

In `tests/test_hatchlings_skill.gd`, the existing `test_on_activate_passes_the_spawn_offset_into_setup` test doesn't call `setup()` directly (it's called internally by `_on_activate`) — no change needed there, it already passes `offset` as the third positional arg matching the *old* 3-arg `setup()`; after this task `_on_activate()` itself calls `setup(source, offset)` (2 args), so no test change is needed in this file for this task — leave it as-is for now.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_tiny_spiderling.gd 2>&1`
Expected: FAIL — `test_snaps_to_the_escort_point_once_it_falls_beyond_leash_distance` and `test_walks_normally_toward_escort_point_when_within_leash_distance` fail on `Invalid call. Nonexistent function 'setup'` (wrong arg count against the still-3-arg signature) or on the missing `leash_distance` behavior; `test_dies_in_one_hit_via_its_hurtbox` fails with `Invalid get index 'Hurtbox'` (no such child yet).

- [ ] **Step 3: Write the implementation**

Replace the whole of `entities/skills/scenes/tiny_spiderling.gd` with:

```gdscript
class_name TinySpiderling
extends CharacterBody2D
## A temporary attacking hatchling (Hatchlings/VFX/input round: leash+snap
## escort, real one-hit death, no more fixed lifetime). Spawned by
## HatchlingsSkill — escorts near its owner spider until an enemy spider
## comes within both aggro_radius and line-of-sight, then breaks off to
## chase/attack it, reverting to escort once the target dies, leaves
## aggro_radius, or line-of-sight breaks. Persists until killed in combat —
## any hit through the standard Hurtbox pipeline (1 max HP) kills it
## outright. Placeholder visual: a small drawn dot, no art asset yet.
## collision_layer = 0 (doesn't block anything itself); collision_mask =
## world(1) only, so move_and_slide() stops at walls but never physically
## collides with a real spider — damage dealt to a *target* is resolved via
## a direct Hurtbox lookup instead, same pattern Enemy/Player melee already
## use; damage taken by this entity itself goes through its own Hurtbox
## child below, the same as every other damageable entity.

@export var move_speed: float = 180.0
@export var attack_range: float = 20.0
@export var attack_damage: float = 4.0
@export var attack_cooldown: float = 0.6
@export var aggro_radius: float = 180.0
## Escort snaps directly to the desired position instead of continuing to
## path once it falls this far behind — bounds both "not tight enough" and
## "stuck on corner geometry while the owner keeps moving away".
@export var leash_distance: float = 200.0

@onready var _health: HealthComponent = $HealthComponent

var _owner_spider: Node
var _escort_offset: Vector2 = Vector2.ZERO
var _attack_left: float = 0.0
var _aggro_target: Node2D = null


## Called by HatchlingsSkill right after spawn. `escort_offset` is the same
## radial offset the caster spawned this hatchling at, relative to the
## owner — the hatchling escorts around owner.global_position + this offset
## when nothing's worth chasing.
func setup(owner_spider: Node, escort_offset: Vector2 = Vector2.ZERO) -> void:
	_owner_spider = owner_spider
	_escort_offset = escort_offset


func _ready() -> void:
	add_to_group("hatchlings")
	_health.died.connect(queue_free)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color(0.85, 0.3, 0.3, 0.9))


func _physics_process(delta: float) -> void:
	_attack_left = maxf(0.0, _attack_left - delta)
	_update_aggro_target()
	if _aggro_target != null:
		_chase(_aggro_target)
	else:
		_escort()


## Keeps the current target if it's still in range/LOS; otherwise looks for
## the nearest qualifying replacement (may be null).
func _update_aggro_target() -> void:
	if _aggro_target != null and is_instance_valid(_aggro_target):
		var still_in_range := global_position.distance_to(_aggro_target.global_position) <= aggro_radius
		if still_in_range and _has_line_of_sight(_aggro_target.global_position):
			return
	_aggro_target = _nearest_target()


func _nearest_target() -> Node2D:
	var best: Node2D = null
	var best_dist := aggro_radius
	for node in get_tree().get_nodes_in_group("spiders"):
		if node == _owner_spider:
			continue
		var spider := node as Node2D
		if spider == null:
			continue
		var d := global_position.distance_to(spider.global_position)
		if d <= best_dist and _has_line_of_sight(spider.global_position):
			best_dist = d
			best = spider
	return best


func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos, 1) # world layer
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _chase(target: Node2D) -> void:
	var to_target := target.global_position - global_position
	if to_target.length() <= attack_range:
		velocity = Vector2.ZERO
		_attack(target)
	else:
		velocity = to_target.normalized() * move_speed
		move_and_slide()


## Walks toward the owner's current position plus the fixed spawn-relative
## offset; holds still once within 1px (avoids jittering) or if the owner is
## gone. Snaps directly to that point instead of walking once the distance
## exceeds leash_distance — see the export's doc comment.
func _escort() -> void:
	# Check validity on the raw reference before casting — casting a freed
	# (but non-null) object throws, and the owner spider dying mid-escort is
	# a normal gameplay occurrence, not just a test-teardown artifact.
	if _owner_spider == null or not is_instance_valid(_owner_spider):
		velocity = Vector2.ZERO
		return
	var owner_2d := _owner_spider as Node2D
	if owner_2d == null:
		velocity = Vector2.ZERO
		return
	var desired := owner_2d.global_position + _escort_offset
	var to_desired := desired - global_position
	if to_desired.length() > leash_distance:
		global_position = desired
		velocity = Vector2.ZERO
	elif to_desired.length() <= 1.0:
		velocity = Vector2.ZERO
	else:
		velocity = to_desired.normalized() * move_speed
		move_and_slide()


func _attack(target: Node2D) -> void:
	if _attack_left > 0.0:
		return
	_attack_left = attack_cooldown
	var hurtbox := target.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(attack_damage, self)
```

Replace the whole of `entities/skills/scenes/tiny_spiderling.tscn` with:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://entities/skills/scenes/tiny_spiderling.gd" id="1_hatch"]
[ext_resource type="Script" path="res://components/health_component.gd" id="2_health"]
[ext_resource type="Script" path="res://components/hurtbox.gd" id="3_hurtbox"]

[sub_resource type="CircleShape2D" id="CircleShape2D_hatch"]
radius = 6.0

[node name="TinySpiderling" type="CharacterBody2D"]
collision_layer = 0
collision_mask = 1
script = ExtResource("1_hatch")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_hatch")

[node name="HealthComponent" type="Node" parent="."]
script = ExtResource("2_health")
max_health = 1.0

[node name="Hurtbox" type="Area2D" parent="."]
collision_layer = 16
collision_mask = 0
monitoring = false
script = ExtResource("3_hurtbox")
health_path = NodePath("../HealthComponent")

[node name="CollisionShape2D" type="CollisionShape2D" parent="Hurtbox"]
shape = SubResource("CircleShape2D_hatch")
```

In `entities/skills/hatchlings_skill.gd`, remove the `@export var lifetime: float = 8.0` line and change the `_on_activate()` call from `hatchling.setup(source, lifetime, offset)` to `hatchling.setup(source, offset)`. Also update the file's header doc comment, replacing:

```gdscript
## Wolf Spider (female): spawns `spawn_count` temporary hatchling scouts that
## hunt independently for `lifetime` seconds, then despawn. `hatchling_scene`
## is a small CharacterBody2D (own GridMover + a light Hitbox) — not yet
## authored as a `.tscn` (needs an editor pass for its collision/visual), but
## its script contract (`setup(owner, lifetime)`) is fixed here.
```

with:

```gdscript
## Wolf Spider (female): spawns `spawn_count` temporary hatchling scouts that
## hunt independently until killed — no fixed lifetime, they persist until
## a hit lands. `hatchling_scene`'s script contract is `setup(owner,
## escort_offset)`.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_tiny_spiderling.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hatchlings_skill.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add entities/skills/scenes/tiny_spiderling.gd entities/skills/scenes/tiny_spiderling.tscn entities/skills/hatchlings_skill.gd tests/test_tiny_spiderling.gd
git status # stage a stray .tscn.uid if one appears
git commit -m "TinySpiderling: leash/snap escort, one-hit death via Hurtbox, no more lifetime timer"
```

---

### Task 3: `Enemy` — opportunistic melee against adjacent hatchlings

**Files:**
- Modify: `entities/enemy/enemy.gd`
- Test: `tests/test_enemy_hatchling_melee.gd` (new)

**Interfaces:**
- Consumes: `TinySpiderling`'s `Hurtbox` (Task 2), `Enemy._melee_target(target: Node2D, to_target: Vector2) -> void` and `Enemy._nearest_in_group(group: String) -> Node2D` (existing, unmodified).
- Produces: `Enemy._melee_nearby_hatchling() -> void`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_enemy_hatchling_melee.gd`:

```gdscript
extends GutTest
## Enemy's opportunistic melee against hatchlings (Hatchlings/VFX/input
## round): a hatchling within melee_range gets swatted regardless of
## Enemy's CHASE state/pathing — Enemy never targets hatchlings for pursuit
## (_acquire_target() only ever returns the player or a decoy), so without
## this a hatchling could never take damage in real play even though it now
## has a Hurtbox (see TinySpiderling). Doesn't touch _acquire_target(),
## _current_target, or the state machine/pathing at all.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")
const SpiderlingScene := preload("res://entities/skills/scenes/tiny_spiderling.tscn")


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(500, 500)
	return enemy


func _make_hatchling(at: Vector2) -> TinySpiderling:
	var hatchling: TinySpiderling = SpiderlingScene.instantiate()
	add_child_autofree(hatchling)
	hatchling.global_position = at
	return hatchling


func test_melees_a_hatchling_within_range() -> void:
	var enemy := _make_enemy()
	var hatchling := _make_hatchling(enemy.global_position + Vector2(20, 0)) # within melee_range (56)

	enemy._melee_nearby_hatchling()

	assert_true(hatchling.is_queued_for_deletion(), "a hatchling within melee range gets swatted dead (1 HP)")


func test_ignores_a_hatchling_out_of_range() -> void:
	var enemy := _make_enemy()
	var hatchling := _make_hatchling(enemy.global_position + Vector2(500, 0)) # far beyond melee_range

	enemy._melee_nearby_hatchling()

	assert_false(hatchling.is_queued_for_deletion(), "a distant hatchling is never touched")


func test_respects_the_shared_melee_cooldown() -> void:
	var enemy := _make_enemy()
	var hatchling := _make_hatchling(enemy.global_position + Vector2(20, 0))
	enemy._melee_left = 1.0 # already on cooldown from another swing this frame

	enemy._melee_nearby_hatchling()

	assert_false(hatchling.is_queued_for_deletion(), "no swing while the shared melee cooldown is still active")


func test_does_not_touch_the_state_machine_or_current_target() -> void:
	var enemy := _make_enemy()
	_make_hatchling(enemy.global_position + Vector2(20, 0))
	var state_before := enemy.state
	var target_before := enemy._current_target

	enemy._melee_nearby_hatchling()

	assert_eq(enemy.state, state_before, "opportunistic hatchling melee never changes state")
	assert_eq(enemy._current_target, target_before, "opportunistic hatchling melee never sets _current_target")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_hatchling_melee.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_melee_nearby_hatchling'`.

- [ ] **Step 3: Write the implementation**

In `entities/enemy/enemy.gd`, find the `_physics_process()` body's `match state:` block (the one that dispatches `_do_chase()`/`_do_flee()`/`_do_seek_food()`/`_do_patrol()`) and add a call right after it:

```gdscript
	match state:
		State.CHASE:
			_do_chase()
		State.FLEE:
			_do_flee()
		State.SEEK_FOOD:
			_do_seek_food()
		State.PATROL:
			_do_patrol()
	_melee_nearby_hatchling()
```

Add the new method near `_nearest_in_group()`:

```gdscript
## Opportunistic strike (Hatchlings/VFX/input round): a hatchling that
## wanders within melee range gets swatted regardless of CHASE state/
## pathing — Enemy never targets hatchlings for pursuit (_acquire_target()
## only ever returns the player or a decoy), so without this a hatchling
## could never take damage in real play even though it now has a Hurtbox.
## Reuses the same shared melee cooldown/_melee_target() as normal combat —
## a real threat in range this same frame always wins the swing, since this
## runs after the state-machine match block above.
func _melee_nearby_hatchling() -> void:
	var hatchling := _nearest_in_group("hatchlings")
	if hatchling == null:
		return
	var to_hatchling: Vector2 = hatchling.global_position - global_position
	if to_hatchling.length() <= melee_range:
		_melee_target(hatchling, to_hatchling)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_hatchling_melee.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/enemy/enemy.gd tests/test_enemy_hatchling_melee.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Enemy: opportunistic melee against adjacent hatchlings"
```

---

### Task 4: `HatchlingsSkill` — death-triggered deferred cooldown

**Files:**
- Modify: `entities/skills/hatchlings_skill.gd`
- Test: `tests/test_hatchlings_skill.gd` (extend)

**Interfaces:**
- Consumes: `SkillComponent._defer_cooldown()`/`_start_deferred_cooldown()` (Task 1), `TinySpiderling`'s `tree_exited` signal firing on death (Task 2, standard `Node` signal).
- Produces: cooldown only starts counting down once every spawned hatchling has left the tree.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_hatchlings_skill.gd`:

```gdscript
func test_cooldown_does_not_start_until_all_hatchlings_have_died() -> void:
	var skill := _make_skill()
	skill.cooldown = 5.0
	var caster := _make_caster()

	skill.activate(caster)

	assert_false(skill.can_activate(), "stays busy while the batch is alive")
	assert_eq(skill.remaining_cooldown(), 5.0, "shows the frozen cooldown value")

	skill._process(10.0) # well past `cooldown`, but nothing has died yet
	assert_false(skill.can_activate(), "still busy — nothing has died")


func test_cooldown_starts_once_the_last_hatchling_dies() -> void:
	var skill := _make_skill()
	skill.cooldown = 5.0
	var caster := _make_caster()
	skill.activate(caster)
	var hatchlings := get_tree().get_nodes_in_group("hatchlings")
	assert_eq(hatchlings.size(), 1)
	var hatchling: TinySpiderling = hatchlings[0]

	hatchling.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(skill.remaining_cooldown(), 5.0, "the real cooldown has just started")
	skill._process(5.0)
	assert_true(skill.can_activate(), "reactivatable once the real cooldown elapses")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hatchlings_skill.gd 2>&1`
Expected: FAIL — `test_cooldown_does_not_start_until_all_hatchlings_have_died` fails (today's `activate()` arms the cooldown immediately, so `_process(10.0)` past a 5s cooldown makes `can_activate()` true); `test_cooldown_starts_once_the_last_hatchling_dies` fails the same way (nothing defers, so the cooldown is already ticking down from the moment of activation, independent of the hatchling's death).

- [ ] **Step 3: Write the implementation**

Replace the whole of `entities/skills/hatchlings_skill.gd` with:

```gdscript
class_name HatchlingsSkill
extends SkillComponent
## Wolf Spider (female): spawns `spawn_count` temporary hatchling scouts that
## hunt independently until killed — no fixed lifetime, they persist until
## a hit lands. `hatchling_scene`'s script contract is `setup(owner,
## escort_offset)`. The skill's own cooldown doesn't start counting down
## until every spawned hatchling has died — see
## SkillComponent._defer_cooldown()/_start_deferred_cooldown().

@export var hatchling_scene: PackedScene
@export var spawn_count: int = 3
@export var spawn_radius: float = 24.0

## The current batch's still-alive hatchlings — emptied as each one leaves
## the tree (dies), at which point the deferred cooldown finally starts.
var _alive: Array[Node] = []


func _defer_cooldown() -> bool:
	return true


func _on_activate(source: Node) -> void:
	_alive.clear()
	var origin := source as Node2D
	if hatchling_scene != null and origin != null:
		var holder := _spawn_parent(source)
		for i in spawn_count:
			var hatchling := hatchling_scene.instantiate()
			holder.add_child(hatchling)
			var offset := Vector2(spawn_radius, 0).rotated(TAU * float(i) / float(spawn_count))
			hatchling.global_position = origin.global_position + offset
			if hatchling.has_method("setup"):
				hatchling.setup(source, offset)
			_alive.append(hatchling)
			hatchling.tree_exited.connect(_on_hatchling_died.bind(hatchling))
	# Nothing actually spawned (bad config, or spawn_count <= 0) — don't get
	# stuck busy forever waiting for a death that will never come.
	if _alive.is_empty():
		_start_deferred_cooldown()


func _on_hatchling_died(hatchling: Node) -> void:
	_alive.erase(hatchling)
	if _alive.is_empty():
		_start_deferred_cooldown()


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hatchlings_skill.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/skills/hatchlings_skill.gd tests/test_hatchlings_skill.gd
git commit -m "HatchlingsSkill: cooldown starts once the last spawned hatchling dies"
```

---

### Task 5: Outline shader — 8-tap diagonal sampling, thicker default, `body_alpha` uniform

**Files:**
- Modify: `assets/shaders/outline.gdshader`
- Modify: `components/outline_fx.gd`
- Test: `tests/test_outline_fx.gd` (extend)

**Interfaces:**
- Produces: `OutlineFx.set_body_alpha(sprite: CanvasItem, alpha: float) -> void` — sets the shader's new `body_alpha` uniform, applied only to normal body pixels, independent of `outline_color`'s own alpha (Task 6 consumes this).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_outline_fx.gd`:

```gdscript
func test_set_body_alpha_sets_the_shader_uniform() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_body_alpha(sprite, 0.15)

	var mat := sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 0.15, 0.001)


func test_set_body_alpha_on_null_sprite_is_a_noop() -> void:
	OutlineFx.set_body_alpha(null, 0.5) # must not error
	assert_true(true, "reached this point without erroring")


func test_set_body_alpha_reuses_the_same_material_set_outline_uses() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED)
	var mat_after_outline := sprite.material
	OutlineFx.set_body_alpha(sprite, 0.5)
	var mat_after_alpha := sprite.material

	assert_eq(mat_after_outline, mat_after_alpha, "one shared material, not a second one stacked on")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_outline_fx.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'set_body_alpha'`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `assets/shaders/outline.gdshader` with:

```glsl
shader_type canvas_item;

// Standard alpha-edge outline: if this texel is (near-)transparent but a
// same-distance neighbour (8-tap: 4 cardinal + 4 diagonal, so corners get
// full coverage too) is opaque, paint outline_color instead. body_alpha
// dims normal body pixels only — kept independent of outline_color's own
// alpha so a caller (Camouflage) can fade the body to near-invisible while
// the outline stays fully visible, which node `modulate` can't do (it
// multiplies everything this shader outputs, outline included).
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 2.0;
uniform bool outline_enabled = true;
uniform float body_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (tex_color.a > 0.5) {
		COLOR = vec4(tex_color.rgb, tex_color.a * body_alpha);
		return;
	}
	if (!outline_enabled) {
		COLOR = vec4(tex_color.rgb, tex_color.a * body_alpha);
		return;
	}
	vec2 texel = outline_width / vec2(textureSize(TEXTURE, 0));
	float neighbor_alpha = 0.0;
	neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
	neighbor_alpha += texture(TEXTURE, UV - vec2(texel.x, 0.0)).a;
	neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
	neighbor_alpha += texture(TEXTURE, UV - vec2(0.0, texel.y)).a;
	neighbor_alpha += texture(TEXTURE, UV + texel).a;
	neighbor_alpha += texture(TEXTURE, UV - texel).a;
	neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, -texel.y)).a;
	neighbor_alpha += texture(TEXTURE, UV + vec2(-texel.x, texel.y)).a;
	COLOR = neighbor_alpha > 0.0 ? outline_color : vec4(tex_color.rgb, tex_color.a * body_alpha);
}
```

In `components/outline_fx.gd`, add a new method after `set_outline()`:

```gdscript
## Sets the shader's body_alpha uniform directly — no ref-counting (unlike
## set_outline()'s on/off toggle, there's only ever one "true" opacity value
## at a time; the last caller wins, same as the old `modulate.a` assignment
## this replaces in CamouflageSkill).
static func set_body_alpha(sprite: CanvasItem, alpha: float) -> void:
	if sprite == null:
		return
	var mat := _material_of(sprite)
	mat.set_shader_parameter("body_alpha", alpha)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_outline_fx.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check** (shader syntax is only validated at import/parse time, not by GUT)

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add assets/shaders/outline.gdshader components/outline_fx.gd tests/test_outline_fx.gd
git commit -m "Outline shader: 8-tap diagonal sampling, thicker default, body_alpha uniform"
```

---

### Task 6: `CamouflageSkill` — decouple body opacity from the outline

**Files:**
- Modify: `entities/skills/camouflage_skill.gd`
- Test: `tests/test_camouflage_wiring.gd` (fix + extend)

**Interfaces:**
- Consumes: `OutlineFx.set_body_alpha()` (Task 5).

- [ ] **Step 1: Write the failing tests**

In `tests/test_camouflage_wiring.gd`, replace `test_activate_makes_the_sprite_nearly_transparent`:

```gdscript
func test_activate_makes_the_sprite_nearly_transparent() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var entity: Node2D = setup["entity"]
	assert_true(camo.active)
	assert_almost_eq((entity.get_node("Sprite") as Sprite2D).modulate.a, camo.target_alpha, 0.001)
```

with:

```gdscript
func test_activate_sets_body_alpha_to_target_alpha() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var entity: Node2D = setup["entity"]
	assert_true(camo.active)
	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), camo.target_alpha, 0.001)
```

Append a new test after `test_break_camouflage_disables_the_outline_shader`:

```gdscript
func test_break_camouflage_resets_body_alpha_to_one() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var entity: Node2D = setup["entity"]

	camo.break_camouflage()

	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 1.0, 0.001)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_camouflage_wiring.gd 2>&1`
Expected: FAIL — `test_activate_sets_body_alpha_to_target_alpha` and `test_break_camouflage_resets_body_alpha_to_one` fail because `body_alpha` is still the shader default `1.0` (nothing sets it yet — `_on_activate()` still only touches `modulate.a`).

- [ ] **Step 3: Write the implementation**

In `entities/skills/camouflage_skill.gd`, replace `_on_activate()`:

```gdscript
func _on_activate(source: Node) -> void:
	_visual = _visual_of(source)
	if _visual == null:
		return
	active = true
	_time_left = duration
	_visual.modulate.a = target_alpha
	OutlineFx.set_outline(_visual, true, OUTLINE_COLOR)
```

with:

```gdscript
func _on_activate(source: Node) -> void:
	_visual = _visual_of(source)
	if _visual == null:
		return
	active = true
	_time_left = duration
	OutlineFx.set_body_alpha(_visual, target_alpha)
	OutlineFx.set_outline(_visual, true, OUTLINE_COLOR)
```

And replace `break_camouflage()`:

```gdscript
func break_camouflage() -> void:
	if not active:
		return
	active = false
	if _visual != null:
		_visual.modulate.a = 1.0
		OutlineFx.set_outline(_visual, false, OUTLINE_COLOR)
	broken.emit()
```

with:

```gdscript
func break_camouflage() -> void:
	if not active:
		return
	active = false
	if _visual != null:
		OutlineFx.set_body_alpha(_visual, 1.0)
		OutlineFx.set_outline(_visual, false, OUTLINE_COLOR)
	broken.emit()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_camouflage_wiring.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/skills/camouflage_skill.gd tests/test_camouflage_wiring.gd
git commit -m "Camouflage: decouple body opacity (shader body_alpha) from the outline"
```

---

### Task 7: Sense rework — no more light-through-walls, radius-limited outline for entities and walls

**Files:**
- Modify: `world/level.gd`
- Modify: `entities/skills/sense_skill.gd`
- Modify: `entities/player/player.gd`
- Test: `tests/test_level_sense_and_pits.gd` (rewrite the Sense-related tests)

**Interfaces:**
- Consumes: `OutlineFx.set_outline()` (existing, unmodified).
- Produces: `SenseSkill.radius: float` (`@export`, default `240.0`), `Level.set_sense_outline(active: bool, radius: float = 0.0) -> void` (signature gains `radius`; `Level.set_sense_active()` is removed entirely).

- [ ] **Step 1: Write the failing tests**

Replace `test_set_sense_active_hides_wall_occluders` and `test_set_sense_outline_toggles_the_shader_on_every_spider_and_larva` in `tests/test_level_sense_and_pits.gd` (delete both) with:

```gdscript
func test_set_sense_outline_outlines_entities_within_radius() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(100, 100)
	var player_sprite := level.player.get_node("Sprite") as CanvasItem

	level.set_sense_outline(true, 50.0)

	var player_mat := player_sprite.material as ShaderMaterial
	assert_not_null(player_mat)
	assert_true(player_mat.get_shader_parameter("outline_enabled"), "the player is always within its own sense radius")


func test_set_sense_outline_skips_entities_outside_radius() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(0, 0)
	level.enemy.global_position = Vector2(1000, 1000) # far outside any reasonable radius
	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem

	level.set_sense_outline(true, 50.0)

	var mat := enemy_sprite.material as ShaderMaterial
	assert_true(mat == null or not mat.get_shader_parameter("outline_enabled"),
		"an entity far outside the radius never gets outlined")


func test_set_sense_outline_updates_as_the_player_moves_closer() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(0, 0)
	level.enemy.global_position = Vector2(1000, 1000)
	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	level.set_sense_outline(true, 50.0)

	level.player.global_position = Vector2(990, 990) # now within radius of the enemy
	level._process(0.016)

	var mat := enemy_sprite.material as ShaderMaterial
	assert_true(mat.get_shader_parameter("outline_enabled"), "entering radius turns the outline on")


func test_set_sense_outline_false_clears_everything() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(0, 0)
	var player_sprite := level.player.get_node("Sprite") as CanvasItem
	level.set_sense_outline(true, 500.0)
	assert_true((player_sprite.material as ShaderMaterial).get_shader_parameter("outline_enabled"))

	level.set_sense_outline(false)

	assert_false((player_sprite.material as ShaderMaterial).get_shader_parameter("outline_enabled"))


func test_set_sense_outline_highlights_wall_tiles_within_radius() -> void:
	var level := _make_level()
	var wall_tile: Vector2i = level._wall_nodes.keys()[0]
	var wall_pos := level.centre_of(wall_tile)
	level.player.global_position = wall_pos # right on top of a wall tile's centre

	level.set_sense_outline(true, 10.0)

	assert_true(level._sense_wall_highlights.has(wall_tile))

	level.set_sense_outline(false)
	assert_false(level._sense_wall_highlights.has(wall_tile))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_sense_and_pits.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'set_sense_outline'` (wrong arg count against the still-1-arg signature) and `Invalid get index '_sense_wall_highlights'`.

- [ ] **Step 3: Write the implementation**

In `world/level.gd`:

Add a new constant after `const SENSE_OUTLINE_COLOR := Color(0.75, 0.9, 1.0, 0.9)`:

```gdscript
## Translucent fill for a wall tile within Sense's radius (design round 2):
## walls have no per-tile sprite to shader-outline the way spiders/larvae
## do (the whole maze is one batched MazeRenderer draw), and using an
## alpha-edge shader on that renderer would only work while floor tiles
## stay transparent — future map art will make floor opaque too. This
## overlay is art-agnostic instead: it only needs "is this tile coordinate
## a wall within radius", never anything about what's actually drawn there.
const SENSE_WALL_HIGHLIGHT_COLOR := Color(0.75, 0.9, 1.0, 0.25)
```

Add new instance vars after `var _pit_nodes: Dictionary = {}`:

```gdscript
var _sense_active: bool = false
var _sense_radius: float = 0.0
## Node currently outlined via Sense -> true, so entry/exit toggles the
## refcounted OutlineFx on/off exactly once each, not every frame.
var _sense_outlined: Dictionary = {}
## Wall tile currently highlighted via Sense -> its highlight node.
var _sense_wall_highlights: Dictionary = {}
```

Replace `_process()`:

```gdscript
## Keep the maze stocked: spawn a larva every interval while under the cap.
func _process(delta: float) -> void:
	if maze == null:
		return
	_spawn_accum += delta
	if _spawn_accum < LARVA_SPAWN_INTERVAL:
		return
	_spawn_accum = 0.0
	if get_tree().get_nodes_in_group("larvae").size() < _larva_cap:
		_spawn_larva_at_random()
```

with:

```gdscript
## Keep the maze stocked (larva spawns), and while Sense is active, keep its
## outline in sync with the player's live position every frame.
func _process(delta: float) -> void:
	if maze == null:
		return
	_spawn_accum += delta
	if _spawn_accum >= LARVA_SPAWN_INTERVAL:
		_spawn_accum = 0.0
		if get_tree().get_nodes_in_group("larvae").size() < _larva_cap:
			_spawn_larva_at_random()
	if _sense_active:
		_update_sense_outlines()
```

Delete `set_sense_active()` entirely (the whole method, including its doc comment).

Replace `set_sense_outline()`:

```gdscript
## SenseSkill's outline cue (skill fixes bundle): every living spider/larva
## gets the shared outline shader while sense is active, alongside the
## existing wall-occluder x-ray. A blanket effect, not per-entity occlusion —
## consistent with set_sense_active()'s own blanket wall treatment.
func set_sense_outline(active: bool) -> void:
	for group in ["spiders", "larvae"]:
		for node in get_tree().get_nodes_in_group(group):
			var sprite := (node as Node).get_node_or_null("Sprite") as CanvasItem
			if sprite != null:
				OutlineFx.set_outline(sprite, active, SENSE_OUTLINE_COLOR)
```

with:

```gdscript
## SenseSkill's outline cue (Hatchlings/VFX/input round): every living
## spider/larva within `radius` of the player gets the shared outline
## shader, and nearby wall tiles get a translucent highlight — no more
## light-through-walls (the old set_sense_active()). Continuous while
## active: _process() re-syncs every frame as the player moves, so entering/
## leaving the radius toggles the effect on/off in real time. `radius` is
## ignored when `active` is false.
func set_sense_outline(active: bool, radius: float = 0.0) -> void:
	_sense_active = active
	_sense_radius = radius
	if active:
		_update_sense_outlines()
		return
	for node in _sense_outlined.keys():
		if is_instance_valid(node):
			var sprite := (node as Node2D).get_node_or_null("Sprite") as CanvasItem
			if sprite != null:
				OutlineFx.set_outline(sprite, false, SENSE_OUTLINE_COLOR)
	_sense_outlined.clear()
	_clear_sense_wall_highlights()


## Re-scans which spiders/larvae and wall tiles are currently within
## _sense_radius of the player, toggling OutlineFx/highlights only on
## entry/exit (via the _sense_outlined/_sense_wall_highlights "currently on"
## sets) rather than redundantly every frame regardless of change.
func _update_sense_outlines() -> void:
	if player == null:
		return
	var still_in_range: Dictionary = {}
	for group in ["spiders", "larvae"]:
		for node in get_tree().get_nodes_in_group(group):
			var n2d := node as Node2D
			if n2d == null or not is_instance_valid(n2d):
				continue
			if n2d.global_position.distance_to(player.global_position) > _sense_radius:
				continue
			still_in_range[n2d] = true
			if not _sense_outlined.has(n2d):
				var sprite := n2d.get_node_or_null("Sprite") as CanvasItem
				if sprite != null:
					OutlineFx.set_outline(sprite, true, SENSE_OUTLINE_COLOR)
					_sense_outlined[n2d] = true
	for node in _sense_outlined.keys().duplicate():
		if not still_in_range.has(node):
			if is_instance_valid(node):
				var sprite := (node as Node2D).get_node_or_null("Sprite") as CanvasItem
				if sprite != null:
					OutlineFx.set_outline(sprite, false, SENSE_OUTLINE_COLOR)
			_sense_outlined.erase(node)
	_update_sense_wall_highlights()


func _update_sense_wall_highlights() -> void:
	if player == null:
		return
	var still_in_range: Dictionary = {}
	for tile in _wall_nodes.keys():
		var centre := _tile_centre(tile.x, tile.y)
		if centre.distance_to(player.global_position) > _sense_radius:
			continue
		still_in_range[tile] = true
		if not _sense_wall_highlights.has(tile):
			_sense_wall_highlights[tile] = _spawn_sense_wall_highlight(tile)
	for tile in _sense_wall_highlights.keys().duplicate():
		if not still_in_range.has(tile):
			var highlight = _sense_wall_highlights[tile]
			if highlight != null and is_instance_valid(highlight):
				highlight.queue_free()
			_sense_wall_highlights.erase(tile)


func _spawn_sense_wall_highlight(tile: Vector2i) -> Node2D:
	var half := TILE_SIZE * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	poly.color = SENSE_WALL_HIGHLIGHT_COLOR
	poly.position = _tile_centre(tile.x, tile.y)
	add_child(poly)
	return poly


func _clear_sense_wall_highlights() -> void:
	for highlight in _sense_wall_highlights.values():
		if highlight != null and is_instance_valid(highlight):
			highlight.queue_free()
	_sense_wall_highlights.clear()
```

In `entities/skills/sense_skill.gd`, add a new export after `@export var duration: float = 5.0`:

```gdscript
## How far from the player (in pixels) the outline reveal reaches — spiders/
## larvae and wall tiles beyond this are untouched.
@export var radius: float = 240.0
```

In `entities/player/player.gd`, replace `_on_effect_applied()`/`_on_effect_expired()`:

```gdscript
func _on_effect_applied(id: StringName, _magnitude: float, _duration: float) -> void:
	if id == &"sense" and _level != null:
		_level.set_sense_active(true)
		_level.set_sense_outline(true)


func _on_effect_expired(id: StringName) -> void:
	if id == &"sense" and _level != null:
		_level.set_sense_active(false)
		_level.set_sense_outline(false)
```

with:

```gdscript
func _on_effect_applied(id: StringName, _magnitude: float, _duration: float) -> void:
	if id == &"sense" and _level != null:
		_level.set_sense_outline(true, _sense.radius)


func _on_effect_expired(id: StringName) -> void:
	if id == &"sense" and _level != null:
		_level.set_sense_outline(false)
```

Also update the doc comment directly above `_on_effect_applied()` — replace:

```gdscript
## SenseSkill (and FungusSenseItem) both just apply a timed "sense" tag on
## this component — this is where that tag actually does something: the
## Level's wall occluders stop blocking the player's vision light, so nearby
## structure/critters/hostiles show through a wall within light range (a
## local x-ray, not a full-map reveal — that's the separate darkness toggle).
```

with:

```gdscript
## SenseSkill (and FungusSenseItem) both just apply a timed "sense" tag on
## this component — this is where that tag actually does something: nearby
## spiders/larvae and wall tiles within SenseSkill.radius get a shared
## outline/highlight treatment (Level.set_sense_outline()), continuously
## tracking the player's position while active. No more light-through-walls
## — that approach read as "illuminating the map" rather than a readable
## reveal.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_sense_and_pits.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add world/level.gd entities/skills/sense_skill.gd entities/player/player.gd tests/test_level_sense_and_pits.gd
git commit -m "Sense: radius-limited continuous outline for entities and walls, no more light-through-walls"
```

---

### Task 8: Generic two-button skill input (`skill_1`/`skill_2`)

**Files:**
- Modify: `project.godot`
- Modify: `entities/player/player.gd`
- Modify: `ui/skill_bar.gd`
- Modify: `ui/control_indicators.gd`
- Test: `tests/test_player_skill_input.gd` (new)
- Test: `tests/test_player_class_switching.gd` (remove the now-deleted `_is_active_skill()` coverage)
- Test: `tests/test_skill_bar.gd` (fix key-label assertions)
- Test: `tests/test_control_indicators.gd` (fix entry-count assertion)

**Interfaces:**
- Consumes: `Player.CLASS_SKILLS`/`_skill_by_action` (existing, unmodified).
- Produces: `Player._skill_for_slot(slot: int) -> SkillComponent` (0 = the current class's first skill, 1 = its second; the seam `_physics_process()` and tests both resolve through, instead of driving flaky single-frame `Input` simulation).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_player_skill_input.gd`:

```gdscript
extends GutTest
## Player's generic two-button skill input (Hatchlings/VFX/input round):
## skill_1/skill_2 resolve positionally through CLASS_SKILLS for whichever
## class is active, instead of each skill owning its own dedicated action.
## Driven through _skill_for_slot() directly rather than real Input events —
## Input.is_action_just_pressed() only clears on a real engine frame
## boundary, which synchronous test calls never cross (see
## test_control_indicators.gd's own note on this).

const PlayerScene := preload("res://entities/player/player.tscn")


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_skill_slot_0_resolves_to_the_current_classs_first_skill() -> void:
	var player := _make_player() # defaults to Wolf -> hatchlings, egg_mine
	assert_eq(player._skill_for_slot(0), player._hatchlings)
	assert_eq(player._skill_for_slot(1), player._egg_mine)


func test_skill_slots_update_after_switching_class() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	assert_eq(player._skill_for_slot(0), player._camouflage)
	assert_eq(player._skill_for_slot(1), player._decoy)


func test_skill_slot_0_resolves_to_net_hold_for_net_caster() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_eq(player._skill_for_slot(0), player._net_hold)
	assert_eq(player._skill_for_slot(1), player._net_shot)


func test_out_of_range_slot_returns_null() -> void:
	var player := _make_player()
	assert_null(player._skill_for_slot(2))
	assert_null(player._skill_for_slot(-1))
```

In `tests/test_player_class_switching.gd`, delete `test_is_active_skill_only_true_for_the_current_classs_own_skills` entirely (the method it tests is being removed).

In `tests/test_skill_bar.gd`, replace the two key-label assertions in `test_binds_the_default_classs_two_skills`:

```gdscript
	assert_eq(bar._key_label1.text, "Y")
	assert_eq(bar._key_label2.text, "U")
```

with:

```gdscript
	assert_eq(bar._key_label1.text, "V")
	assert_eq(bar._key_label2.text, "B")
```

In `tests/test_control_indicators.gd`, replace:

```gdscript
func test_builds_one_entry_per_tracked_action() -> void:
	var indicators := _make()
	assert_eq(indicators._entries.size(), 26 + UpgradeRegistry.ALL.size())
```

with:

```gdscript
func test_builds_one_entry_per_tracked_action() -> void:
	var indicators := _make()
	assert_eq(indicators._entries.size(), 20 + UpgradeRegistry.ALL.size())
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_skill_input.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_skill_for_slot'`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_bar.gd 2>&1`
Expected: FAIL — key labels still show `"Y"`/`"U"` (the old per-skill actions still exist and are still what `_bind_slot()` looks up).

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_control_indicators.gd 2>&1`
Expected: FAIL — entry count is still `26 + UpgradeRegistry.ALL.size()`.

- [ ] **Step 3: Write the implementation**

In `project.godot`, remove these 8 whole blocks (each is `<name>={ "deadzone": 0.5, "events": [Object(InputEventKey,...)] }`): `camouflage`, `net_hold`, `net_shot`, `hatchlings`, `egg_mine`, `blockade`, `silk_tunnel`, `decoy`.

Concretely, delete this block:

```
camouflage={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":86,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

and, right after it, replace it with the new `skill_1`/`skill_2` actions (reusing the same freed-up physical keycodes, V and B):

```
skill_1={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":86,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
skill_2={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":66,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Then delete the remaining 7 blocks entirely (`net_hold`, `net_shot`, `hatchlings`, `egg_mine`, `blockade`, `silk_tunnel`, `decoy` — each with the same `{"deadzone": 0.5, "events": [...]}` shape, at physical_keycode 66/84/89/85/79/73/90 respectively), leaving every other action (`dev_trigger_hazard`, `sense`, `remove_walls_skill`, `cycle_class`, `buy_upgrade_1..4`, `pause`, `use_item`, `toggle_shop`, and everything before `camouflage`) untouched.

In `entities/player/player.gd`, replace the class-gated skill block in `_physics_process()`:

```gdscript
	if Input.is_action_just_pressed("camouflage") and _is_active_skill("camouflage"):
		_camouflage.activate(self)
	# Held, not just-pressed: picking up a trap works either by walking onto
	# it while holding the button, or by pressing the button while already
	# stopped on it — both need this checked every frame the button is down,
	# not just on the press edge. NetHoldSkill.activate() itself gates out
	# the idle case so this never burns cooldown/hunger while nothing's in
	# reach.
	if Input.is_action_pressed("net_hold") and _is_active_skill("net_hold"):
		_net_hold.activate(self)
	if Input.is_action_just_pressed("net_shot") and _is_active_skill("net_shot"):
		_net_shot.activate(self)
	if Input.is_action_just_pressed("hatchlings") and _is_active_skill("hatchlings"):
		_hatchlings.activate(self)
	if Input.is_action_just_pressed("egg_mine") and _is_active_skill("egg_mine"):
		_egg_mine.activate(self)
	if Input.is_action_just_pressed("blockade") and _is_active_skill("blockade"):
		_blockade.activate(self)
	if Input.is_action_just_pressed("silk_tunnel") and _is_active_skill("silk_tunnel"):
		_silk_tunnel.activate(self)
	if Input.is_action_just_pressed("decoy") and _is_active_skill("decoy"):
		_decoy.activate(self)
```

with:

```gdscript
	# Two generic skill buttons (Hatchlings/VFX/input round) resolve
	# positionally through CLASS_SKILLS instead of each skill owning its own
	# dedicated action — see _skill_for_slot(). skill_1 polls with
	# is_action_pressed (not _just_pressed) so it works uniformly whether the
	# current class's first skill is held (NetHoldSkill, whose own
	# activate() override already no-ops harmlessly on repeat calls while
	# already holding or with nothing in reach) or one-shot (cooldown-gated,
	# so repeat calls while held are harmless). skill_2 never lands on a
	# held skill in the current CLASS_SKILLS layout, so it stays
	# _just_pressed for a clean single-trigger feel.
	if Input.is_action_pressed("skill_1"):
		var skill1 := _skill_for_slot(0)
		if skill1 != null:
			skill1.activate(self)
	if Input.is_action_just_pressed("skill_2"):
		var skill2 := _skill_for_slot(1)
		if skill2 != null:
			skill2.activate(self)
```

Delete `_is_active_skill()` entirely (the whole method, including its doc comment).

Add a new public method after `active_skills()`:

```gdscript
## The SkillComponent occupying input slot 0 (skill_1) or 1 (skill_2) for
## whichever class is currently active — the seam _physics_process() and
## tests both resolve through, instead of duplicating the CLASS_SKILLS/
## _skill_by_action lookup or needing to drive real Input events.
func _skill_for_slot(slot: int) -> SkillComponent:
	var actions: Array = CLASS_SKILLS.get(_active_class, [])
	if slot < 0 or slot >= actions.size():
		return null
	return _skill_by_action.get(actions[slot])
```

In `ui/skill_bar.gd`, replace `_rebind()`:

```gdscript
func _rebind() -> void:
	if _player == null:
		return
	var skills := _player.active_skills()
	var actions := skills.keys()
	var action1: String = actions[0] if actions.size() > 0 else ""
	var action2: String = actions[1] if actions.size() > 1 else ""
	_skill1 = skills.get(action1)
	_skill2 = skills.get(action2)
	_bind_slot(action1, _skill1, _key_label1, _name_label1)
	_bind_slot(action2, _skill2, _key_label2, _name_label2)


func _bind_slot(action: String, skill: SkillComponent, key_label: Label, name_label: Label) -> void:
	if skill == null:
		key_label.text = ""
		name_label.text = ""
		name_label.tooltip_text = ""
		return
	name_label.text = skill.display_name
	name_label.tooltip_text = skill.description
	var events := InputMap.action_get_events(action)
	key_label.text = events[0].as_text_physical_keycode() if events.size() > 0 else ""
```

with:

```gdscript
func _rebind() -> void:
	if _player == null:
		return
	var skills := _player.active_skills()
	var actions := skills.keys()
	_skill1 = skills.get(actions[0]) if actions.size() > 0 else null
	_skill2 = skills.get(actions[1]) if actions.size() > 1 else null
	_bind_slot(_skill1, "skill_1", _key_label1, _name_label1)
	_bind_slot(_skill2, "skill_2", _key_label2, _name_label2)


## `input_action` is always "skill_1"/"skill_2" now (the generic buttons),
## never the skill's own name — those per-skill actions no longer exist in
## the InputMap after the Hatchlings/VFX/input round's keybind collapse.
func _bind_slot(skill: SkillComponent, input_action: String, key_label: Label, name_label: Label) -> void:
	if skill == null:
		key_label.text = ""
		name_label.text = ""
		name_label.tooltip_text = ""
		return
	name_label.text = skill.display_name
	name_label.tooltip_text = skill.description
	var events := InputMap.action_get_events(input_action)
	key_label.text = events[0].as_text_physical_keycode() if events.size() > 0 else ""
```

In `ui/control_indicators.gd`, replace these 8 lines in `_ready()`:

```gdscript
	_add_one_shot(root, "Camouflage (V)", "camouflage")
	_add_one_shot(root, "Sense (N)", "sense")
	_add_one_shot(root, "Remove Walls Skill (M)", "remove_walls_skill")
	_add_one_shot(root, "Net Hold (B)", "net_hold")
	_add_one_shot(root, "Net Shot (T)", "net_shot")
	_add_one_shot(root, "Hatchlings (Y)", "hatchlings")
	_add_one_shot(root, "Egg Mine (U)", "egg_mine")
	_add_one_shot(root, "Blockade (O)", "blockade")
	_add_one_shot(root, "Silk Tunnel (I)", "silk_tunnel")
	_add_one_shot(root, "Decoy (Z)", "decoy")
```

with:

```gdscript
	_add_held(root, "Skill 1 (V)", func() -> bool: return Input.is_action_pressed("skill_1"))
	_add_one_shot(root, "Skill 2 (B)", "skill_2")
	_add_one_shot(root, "Sense (N)", "sense")
	_add_one_shot(root, "Remove Walls Skill (M)", "remove_walls_skill")
```

(This drops 8 rows and adds 2, net -6 — matches the updated `20 + UpgradeRegistry.ALL.size()` test assertion. `Skill 1` is tracked as a held indicator, matching how `Player._physics_process()` now actually polls it with `is_action_pressed`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_skill_input.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_skill_bar.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_control_indicators.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Run the full suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!` (there's a known pre-existing intermittent flake in `test_larva_hazards.gd::test_open_ground_does_not_block_a_spawned_larva`, unrelated to this branch — if only that one fails, re-run once to confirm it's the same pre-existing flake before treating it as a pass).

- [ ] **Step 7: Manual boot smoke check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no new errors.

- [ ] **Step 8: Commit**

```bash
git add project.godot entities/player/player.gd ui/skill_bar.gd ui/control_indicators.gd tests/test_player_skill_input.gd tests/test_player_class_switching.gd tests/test_skill_bar.gd tests/test_control_indicators.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Collapse per-class skill keybinds to two generic buttons (skill_1/skill_2 on V/B)"
```

---

### Final check

- [ ] Run the full suite once more end-to-end: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1` — expect `All tests passed!`.
- [ ] Run `git status` — stage any stray `.gd.uid`/`.tscn.uid` sidecars from new files before opening the PR.
- [ ] Manual playtest pass (headless tests verify wiring/state, not the rendered result): as Wolf, summon Hatchlings and confirm they hug the player tightly while moving through corners (no getting stuck), persist through combat instead of despawning on a timer, and confirm the skill bar shows the skill dimmed/frozen the whole time they're alive, only starting to count down once the last one dies; get an enemy to actually kill a hatchling and confirm it dies in one hit; press Sense (N) and confirm nearby spiders/larvae/walls within a few tiles get an outline (not a lit-up-through-walls effect), and it updates as you move; watch the outline shader up close and confirm it reads as a solid, even line on diagonal edges too, not thin/gappy; activate Camouflage and confirm the body visibly fades to near-invisible while the outline silhouette stays fully visible; press V and B and confirm they trigger the current class's two skills (cycle class with Q and confirm V/B always trigger whichever two skills that class has); confirm the debug indicator overlay's "Skill 1 (V)"/"Skill 2 (B)" rows light up correctly.
