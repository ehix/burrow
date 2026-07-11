# Skill Fixes Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six playtest-driven skill fixes — a shared outline shader for Sense/Camouflage, Hatchlings' escort/aggro AI + speed, Egg Mine's redesign (direct damage + cosmetic burst + larvae immunity + ceiling placement), Silk Tunnel's longer reach, and Decoy's collision fix.

**Architecture:** One new shared static helper (`OutlineFx`, mirroring `CombatFx`'s pattern) plus one new shader back two of the six fixes (Sense, Camouflage). The other four are independent, self-contained edits to their own skill/entity scripts, following each file's existing patterns (`SkillComponent._on_activate()`, the `_spawn_parent()`/`_plane_of()` idioms `BlockadeSkill` already established).

**Tech Stack:** Godot 4.7 (GDScript + GDShader), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-11-skill-fixes-bundle-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1` (read the full output, not `tail` — this project has had prior orphan-node/warning findings from truncated output; drop `-gselect=` for the whole suite).
- Import check after any `.tscn`/`.gdshader` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- New `.gd` files generate an untracked `.gd.uid` sidecar the first time Godot imports/runs them — after the final task, run `git status` and stage any stray `.gd.uid` files before considering the branch done.
- This slice touches: `components/outline_fx.gd` (new), `assets/shaders/outline.gdshader` (new), `entities/skills/camouflage_skill.gd`, `world/level.gd`, `entities/player/player.gd`, `entities/skills/hatchlings_skill.gd`, `entities/skills/scenes/tiny_spiderling.gd`, `entities/skills/scenes/mine_spiderling.gd`/`.tscn` (new), `entities/skills/scenes/cocoon_mine.gd`, `entities/skills/egg_mine_skill.gd`, `entities/skills/silk_tunnel_skill.gd`, `entities/skills/scenes/decoy.gd`/`.tscn`, and their tests. No other system.
- Two originally-scoped items are already built and are NOT part of this plan: Camouflage's attack-break wiring, Decoy's AI retargeting (`Enemy._acquire_target()`).

---

### Task 1: Outline shader + `OutlineFx` helper

**Files:**
- Create: `assets/shaders/outline.gdshader`
- Create: `components/outline_fx.gd`
- Test: `tests/test_outline_fx.gd` (new)

**Interfaces:**
- Produces: `OutlineFx.set_outline(sprite: CanvasItem, enabled: bool, color: Color = Color.WHITE) -> void`, `OutlineFx.OutlineShader` (a `Shader` const, `res://assets/shaders/outline.gdshader`). Shader parameters: `outline_enabled: bool`, `outline_color: vec4`, `outline_width: float` (default `1.0`).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_outline_fx.gd`:

```gdscript
extends GutTest
## OutlineFx (skill fixes bundle): shared static helper for toggling the
## outline shader on a sprite, used by Sense and Camouflage alike. Lazily
## creates and caches one ShaderMaterial per sprite rather than stacking a
## new one on every call.


func _make_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	return sprite


func test_set_outline_true_attaches_the_shader_material() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED)

	var mat := sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_eq(mat.shader, OutlineFx.OutlineShader)
	assert_true(mat.get_shader_parameter("outline_enabled"))
	assert_eq(mat.get_shader_parameter("outline_color"), Color.RED)


func test_set_outline_false_disables_without_erroring() -> void:
	var sprite := _make_sprite()
	OutlineFx.set_outline(sprite, true, Color.RED)

	OutlineFx.set_outline(sprite, false)

	var mat := sprite.material as ShaderMaterial
	assert_false(mat.get_shader_parameter("outline_enabled"))


func test_repeated_calls_reuse_the_same_material_instead_of_stacking() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED)
	var first_mat := sprite.material
	OutlineFx.set_outline(sprite, true, Color.BLUE)
	var second_mat := sprite.material

	assert_eq(first_mat, second_mat, "the same ShaderMaterial instance is reused, not replaced")


func test_set_outline_on_null_sprite_is_a_noop() -> void:
	OutlineFx.set_outline(null, true, Color.RED) # must not error
	assert_true(true, "reached this point without erroring")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_outline_fx.gd 2>&1`
Expected: FAIL — `Cannot find class "OutlineFx"` (script doesn't exist yet).

- [ ] **Step 3: Write the shader**

Create `assets/shaders/outline.gdshader`:

```glsl
shader_type canvas_item;

// Standard alpha-edge outline: if this texel is (near-)transparent but a
// neighbour is opaque, paint outline_color instead. No-op when disabled.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 1.0;
uniform bool outline_enabled = true;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (!outline_enabled || tex_color.a > 0.5) {
		COLOR = tex_color;
		return;
	}
	vec2 texel = outline_width / vec2(textureSize(TEXTURE, 0));
	float neighbor_alpha = 0.0;
	neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
	neighbor_alpha += texture(TEXTURE, UV - vec2(texel.x, 0.0)).a;
	neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
	neighbor_alpha += texture(TEXTURE, UV - vec2(0.0, texel.y)).a;
	COLOR = neighbor_alpha > 0.0 ? outline_color : tex_color;
}
```

- [ ] **Step 4: Write `OutlineFx`**

Create `components/outline_fx.gd`:

```gdscript
class_name OutlineFx
extends RefCounted
## Static-only helper (mirrors CombatFx's pattern) for toggling the shared
## outline shader on a sprite — used by Sense (blanket reveal cue) and
## Camouflage (silhouette-while-hidden). Lazily creates and caches a
## ShaderMaterial on the sprite itself on first use, so repeated calls never
## stack a new material.

const OutlineShader := preload("res://assets/shaders/outline.gdshader")


## Toggle the outline effect on `sprite`. No-op if `sprite` is null.
static func set_outline(sprite: CanvasItem, enabled: bool, color: Color = Color.WHITE) -> void:
	if sprite == null:
		return
	var mat := _material_of(sprite)
	mat.set_shader_parameter("outline_enabled", enabled)
	mat.set_shader_parameter("outline_color", color)


static func _material_of(sprite: CanvasItem) -> ShaderMaterial:
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != OutlineShader:
		mat = ShaderMaterial.new()
		mat.shader = OutlineShader
		sprite.material = mat
	return mat
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_outline_fx.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add assets/shaders/outline.gdshader components/outline_fx.gd tests/test_outline_fx.gd
git status # stage any stray .gd.uid too
git commit -m "Add shared outline shader + OutlineFx helper"
```

---

### Task 2: Camouflage outline integration

**Files:**
- Modify: `entities/skills/camouflage_skill.gd`
- Test: `tests/test_camouflage_wiring.gd`

**Interfaces:**
- Consumes: `OutlineFx.set_outline(sprite, enabled, color)` (Task 1).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_camouflage_wiring.gd` (after `test_activate_makes_the_sprite_nearly_transparent`):

```gdscript
func test_activate_applies_the_outline_shader() -> void:
	var setup := _make_camouflaged()
	var entity: Node2D = setup["entity"]

	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("outline_enabled"))


func test_break_camouflage_disables_the_outline_shader() -> void:
	var setup := _make_camouflaged()
	var camo: CamouflageSkill = setup["camo"]
	var entity: Node2D = setup["entity"]

	camo.break_camouflage()

	var mat := (entity.get_node("Sprite") as CanvasItem).material as ShaderMaterial
	assert_false(mat.get_shader_parameter("outline_enabled"))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_camouflage_wiring.gd 2>&1`
Expected: FAIL — `material` is null on the sprite (no ShaderMaterial attached yet).

- [ ] **Step 3: Write the implementation**

In `entities/skills/camouflage_skill.gd`, add a const near the top (after the existing `@export var duration`):

```gdscript
const OUTLINE_COLOR := Color(0.6, 0.75, 1.0, 0.9)
```

Change `_on_activate`:

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

Change `break_camouflage`:

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_camouflage_wiring.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/skills/camouflage_skill.gd tests/test_camouflage_wiring.gd
git commit -m "Apply the outline shader while Camouflage is active"
```

---

### Task 3: Sense outline integration

**Files:**
- Modify: `world/level.gd`
- Modify: `entities/player/player.gd`
- Test: `tests/test_level_sense_and_pits.gd`

**Interfaces:**
- Consumes: `OutlineFx.set_outline(sprite, enabled, color)` (Task 1).
- Produces: `Level.set_sense_outline(active: bool) -> void`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_level_sense_and_pits.gd` (after `test_set_sense_active_hides_wall_occluders`):

```gdscript
func test_set_sense_outline_toggles_the_shader_on_every_spider_and_larva() -> void:
	var level := _make_level()
	var player_sprite := level.player.get_node("Sprite") as CanvasItem
	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem

	level.set_sense_outline(true)
	var player_mat := player_sprite.material as ShaderMaterial
	var enemy_mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(player_mat)
	assert_true(player_mat.get_shader_parameter("outline_enabled"))
	assert_not_null(enemy_mat)
	assert_true(enemy_mat.get_shader_parameter("outline_enabled"))

	level.set_sense_outline(false)
	assert_false(player_mat.get_shader_parameter("outline_enabled"))
	assert_false(enemy_mat.get_shader_parameter("outline_enabled"))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_sense_and_pits.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'set_sense_outline'`.

- [ ] **Step 3: Write the implementation**

In `world/level.gd`, add a const near `DARK_MODULATE`:

```gdscript
const SENSE_OUTLINE_COLOR := Color(0.75, 0.9, 1.0, 0.9)
```

Add a new method after `set_sense_active`:

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

In `entities/player/player.gd`, change `_on_effect_applied`/`_on_effect_expired`:

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

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_sense_and_pits.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add world/level.gd entities/player/player.gd tests/test_level_sense_and_pits.gd
git commit -m "Add an outline cue to every spider/larva while Sense is active"
```

---

### Task 4: Hatchlings escort/aggro AI + speed

**Files:**
- Modify: `entities/skills/scenes/tiny_spiderling.gd`
- Modify: `entities/skills/hatchlings_skill.gd`
- Test: `tests/test_tiny_spiderling.gd`
- Test: `tests/test_hatchlings_skill.gd` (new)

**Interfaces:**
- Produces: `TinySpiderling.setup(owner_spider: Node, lifetime: float, escort_offset: Vector2 = Vector2.ZERO) -> void`, `TinySpiderling.aggro_radius: float = 180.0`, `TinySpiderling.move_speed: float = 180.0`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_tiny_spiderling.gd` (after `test_attack_respects_its_own_cooldown`):

```gdscript
func _make_wall(at: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 48)
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = at
	return wall


func test_default_move_speed_is_180() -> void:
	var spiderling := _make_spiderling()
	assert_eq(spiderling.move_speed, 180.0)


func test_escorts_toward_the_owner_plus_offset_when_no_enemy_is_near() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(600, 600)
	spiderling.global_position = Vector2(0, 0)
	spiderling.setup(owner_spider, 5.0, Vector2(20, 0))
	var target_point := owner_spider.global_position + Vector2(20, 0)
	var before := spiderling.global_position.distance_to(target_point)

	for i in 10:
		spiderling._physics_process(0.05)

	var after := spiderling.global_position.distance_to(target_point)
	assert_lt(after, before, "the hatchling steps toward its owner's escort point")


func test_switches_to_chase_when_an_enemy_enters_aggro_radius_and_los() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(2000, 2000) # far away, irrelevant
	var enemy := _make_target()
	spiderling.global_position = Vector2(0, 0)
	enemy.global_position = Vector2(50, 0) # within aggro_radius(180), beyond attack_range(20)
	spiderling.setup(owner_spider, 5.0)

	spiderling._physics_process(0.016)

	assert_gt(spiderling.velocity.length(), 0.0, "the hatchling moves toward the visible enemy instead of escorting")


func test_never_targets_an_enemy_blocked_by_a_wall() -> void:
	var spiderling := _make_spiderling()
	var enemy := _make_target()
	spiderling.global_position = Vector2(0, 0)
	enemy.global_position = Vector2(100, 0)
	_make_wall(Vector2(50, 0))
	spiderling.setup(null, 5.0) # no owner -> escort() with no owner holds still

	spiderling._physics_process(0.016)

	assert_eq(spiderling.velocity, Vector2.ZERO, "a wall-blocked enemy is never targeted")


func test_reverts_to_escort_once_the_target_leaves_aggro_radius() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(0, 0)
	var enemy := _make_target()
	spiderling.global_position = Vector2(0, 0)
	enemy.global_position = Vector2(50, 0)
	spiderling.setup(owner_spider, 5.0)
	spiderling._physics_process(0.016)
	assert_gt(spiderling.velocity.length(), 0.0, "starts chasing")

	enemy.global_position = Vector2(5000, 5000) # far outside aggro_radius
	# Converge over several ticks rather than asserting on one exact instant
	# right after the switch — move_and_slide() uses the engine's own
	# physics delta, not the value passed here, so a single-tick distance
	# check would be too tightly coupled to that exact timing.
	for i in 20:
		spiderling._physics_process(0.05)

	assert_lt(spiderling.global_position.distance_to(owner_spider.global_position), 1.0,
		"settles back at the owner's position once escort resumes (no target, escort_offset defaults to zero)")
```

Add new `tests/test_hatchlings_skill.gd`:

```gdscript
extends GutTest
## HatchlingsSkill (skill fixes bundle): each spawned TinySpiderling escorts
## around the same offset it was spawned at, so activation and the
## hatchling's own escort target agree without a second source of truth.

const HatchlingScene := preload("res://entities/skills/scenes/tiny_spiderling.tscn")


func _make_skill() -> HatchlingsSkill:
	var skill := HatchlingsSkill.new()
	skill.hatchling_scene = HatchlingScene
	skill.spawn_count = 1
	skill.spawn_radius = 24.0
	add_child_autofree(skill)
	return skill


func _make_caster() -> Node2D:
	var caster := Node2D.new()
	add_child_autofree(caster)
	caster.global_position = Vector2(400, 400)
	return caster


func test_on_activate_passes_the_spawn_offset_into_setup() -> void:
	var skill := _make_skill()
	var caster := _make_caster()

	skill._on_activate(caster)

	var hatchlings := get_tree().get_nodes_in_group("hatchlings")
	assert_eq(hatchlings.size(), 1)
	var hatchling: TinySpiderling = hatchlings[0]
	var expected_offset := Vector2(skill.spawn_radius, 0) # spawn_count=1, i=0 -> rotation 0
	assert_eq(hatchling.global_position, caster.global_position + expected_offset)

	var before := hatchling.global_position.distance_to(caster.global_position + expected_offset)
	caster.global_position += Vector2(100, 0)
	for i in 10:
		hatchling._physics_process(0.05)
	var after := hatchling.global_position.distance_to(caster.global_position + expected_offset)
	assert_lt(after, before, "the hatchling escorts toward the owner's new position at the same relative offset")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_tiny_spiderling.gd 2>&1`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hatchlings_skill.gd 2>&1`
Expected: FAIL — `move_speed` is `90` not `180`; `setup()` doesn't accept a third argument; no escort/aggro behavior exists yet.

- [ ] **Step 3: Write the implementation**

Replace `entities/skills/scenes/tiny_spiderling.gd` in full:

```gdscript
class_name TinySpiderling
extends CharacterBody2D
## A temporary attacking hatchling (skill fixes bundle: escort/aggro AI +
## line-of-sight). Spawned by HatchlingsSkill (scouting mode) — escorts near
## its owner spider until an enemy spider comes within both aggro_radius and
## line-of-sight, then breaks off to chase/attack it, reverting to escort
## once the target dies, leaves aggro_radius, or line-of-sight breaks.
## Placeholder visual: a small drawn dot, no art asset yet.
## collision_layer = 0 (doesn't block anything itself); collision_mask =
## world(1) only, so move_and_slide() stops at walls but never physically
## collides with a real spider — damage is resolved via a direct Hurtbox
## lookup instead, same pattern Enemy/Player melee already use.

@export var move_speed: float = 180.0
@export var attack_range: float = 20.0
@export var attack_damage: float = 4.0
@export var attack_cooldown: float = 0.6
@export var aggro_radius: float = 180.0

var _owner_spider: Node
var _escort_offset: Vector2 = Vector2.ZERO
var _lifetime_left: float = 0.0
var _attack_left: float = 0.0
var _aggro_target: Node2D = null


## Called by HatchlingsSkill right after spawn. `escort_offset` is the same
## radial offset the caster spawned this hatchling at, relative to the
## owner — the hatchling escorts around owner.global_position + this offset
## when nothing's worth chasing.
func setup(owner_spider: Node, lifetime: float, escort_offset: Vector2 = Vector2.ZERO) -> void:
	_owner_spider = owner_spider
	_lifetime_left = lifetime
	_escort_offset = escort_offset


func _ready() -> void:
	add_to_group("hatchlings")


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color(0.85, 0.3, 0.3, 0.9))


func _physics_process(delta: float) -> void:
	_lifetime_left -= delta
	_attack_left = maxf(0.0, _attack_left - delta)
	if _lifetime_left <= 0.0:
		queue_free()
		return
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
## offset; holds still once within 4px (avoids jittering) or if the owner is
## gone.
func _escort() -> void:
	var owner_2d := _owner_spider as Node2D
	if owner_2d == null or not is_instance_valid(owner_2d):
		velocity = Vector2.ZERO
		return
	var desired := owner_2d.global_position + _escort_offset
	var to_desired := desired - global_position
	if to_desired.length() <= 4.0:
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

In `entities/skills/hatchlings_skill.gd`, change the spawn loop in `_on_activate`:

```gdscript
func _on_activate(source: Node) -> void:
	if hatchling_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var holder := _spawn_parent(source)
	for i in spawn_count:
		var hatchling := hatchling_scene.instantiate()
		holder.add_child(hatchling)
		var offset := Vector2(spawn_radius, 0).rotated(TAU * float(i) / float(spawn_count))
		hatchling.global_position = origin.global_position + offset
		if hatchling.has_method("setup"):
			hatchling.setup(source, lifetime, offset)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_tiny_spiderling.gd 2>&1`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hatchlings_skill.gd 2>&1`
Expected: `All tests passed!` for both.

- [ ] **Step 5: Commit**

```bash
git add entities/skills/scenes/tiny_spiderling.gd entities/skills/hatchlings_skill.gd tests/test_tiny_spiderling.gd tests/test_hatchlings_skill.gd
git status # stage tests/test_hatchlings_skill.gd.uid if it appears
git commit -m "Give Hatchlings an escort/aggro AI, line-of-sight, and a speed bump"
```

---

### Task 5: `MineSpiderling` cosmetic burst entity

**Files:**
- Create: `entities/skills/scenes/mine_spiderling.gd`
- Create: `entities/skills/scenes/mine_spiderling.tscn`
- Test: `tests/test_mine_spiderling.gd` (new)

**Interfaces:**
- Produces: `MineSpiderling.damage: float = 1.0`, `MineSpiderling.damage_radius: float = 24.0`, `MineSpiderling.explode_after: float = 0.3`, joins group `"mine_spiderlings"`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_mine_spiderling.gd`:

```gdscript
extends GutTest
## MineSpiderling (skill fixes bundle): Egg Mine's cosmetic burst flourish —
## appears, waits briefly, deals one tiny damage tick to whatever's still
## nearby, then frees. No movement, no chase, no persistent AI.

const MineSpiderlingScene := preload("res://entities/skills/scenes/mine_spiderling.tscn")


func _make_spiderling() -> MineSpiderling:
	var spiderling: MineSpiderling = MineSpiderlingScene.instantiate()
	add_child_autofree(spiderling)
	return spiderling


func _make_target(group: String, at: Vector2) -> Node2D:
	var target := Node2D.new()
	target.add_to_group(group)
	add_child_autofree(target)
	target.global_position = at
	var health := HealthComponent.new()
	health.current_health = health.max_health
	autofree(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	hurtbox.name = "Hurtbox"
	target.add_child(hurtbox)
	return target


func test_joins_the_mine_spiderlings_group() -> void:
	var spiderling := _make_spiderling()
	assert_true(spiderling.is_in_group("mine_spiderlings"))


func test_does_not_explode_before_explode_after_elapses() -> void:
	var spiderling := _make_spiderling()
	spiderling.explode_after = 1.0

	spiderling._physics_process(0.6)

	assert_false(spiderling.is_queued_for_deletion())


func test_explodes_and_deals_damage_to_a_nearby_target_after_explode_after() -> void:
	var spiderling := _make_spiderling()
	spiderling.explode_after = 0.3
	spiderling.damage = 1.0
	spiderling.damage_radius = 24.0
	var target := _make_target("spiders", spiderling.global_position + Vector2(5, 0))

	spiderling._physics_process(0.35)

	var hurtbox := target.get_node("Hurtbox") as Hurtbox
	assert_lt(hurtbox.health.current_health, hurtbox.health.max_health)
	assert_true(spiderling.is_queued_for_deletion())


func test_ignores_a_target_outside_damage_radius() -> void:
	var spiderling := _make_spiderling()
	spiderling.explode_after = 0.1
	spiderling.damage_radius = 24.0
	var target := _make_target("spiders", spiderling.global_position + Vector2(500, 0))

	spiderling._physics_process(0.2)

	var hurtbox := target.get_node("Hurtbox") as Hurtbox
	assert_eq(hurtbox.health.current_health, hurtbox.health.max_health)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_mine_spiderling.gd 2>&1`
Expected: FAIL — `Cannot find class "MineSpiderling"` / scene doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `entities/skills/scenes/mine_spiderling.gd`:

```gdscript
class_name MineSpiderling
extends Node2D
## Egg Mine's cosmetic burst flourish (skill fixes bundle) — appears at a
## radial offset when a mine detonates, waits `explode_after`, deals one
## tiny damage tick to whatever's still nearby, then frees. Not an attacker:
## no movement, no chase, no persistent AI — CocoonMine's real damage
## already landed via its own direct burst_damage on the trigger.
## Placeholder visual: a small drawn dot, no art asset yet.

@export var damage: float = 1.0
@export var damage_radius: float = 24.0
@export var explode_after: float = 0.3

var _time_left: float = 0.0


func _ready() -> void:
	add_to_group("mine_spiderlings")
	_time_left = explode_after


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(0.85, 0.3, 0.3, 0.9))


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_explode()


func _explode() -> void:
	for group in ["spiders", "larvae"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or body.global_position.distance_to(global_position) > damage_radius:
				continue
			var hurtbox := body.get_node_or_null("Hurtbox") as Hurtbox
			if hurtbox != null:
				hurtbox.receive_hit(damage, self)
	queue_free()
```

Create `entities/skills/scenes/mine_spiderling.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://entities/skills/scenes/mine_spiderling.gd" id="1_minespider"]

[node name="MineSpiderling" type="Node2D"]
script = ExtResource("1_minespider")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_mine_spiderling.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add entities/skills/scenes/mine_spiderling.gd entities/skills/scenes/mine_spiderling.tscn tests/test_mine_spiderling.gd
git status # stage stray .gd.uid/.tscn.uid files
git commit -m "Add MineSpiderling, Egg Mine's cosmetic burst flourish"
```

---

### Task 6: Egg Mine redesign — `CocoonMine` + `EggMineSkill`

**Files:**
- Modify: `entities/skills/scenes/cocoon_mine.gd`
- Modify: `entities/skills/egg_mine_skill.gd`
- Test: `tests/test_cocoon_mine.gd` (rewritten)
- Test: `tests/test_egg_mine_skill.gd` (new)

**Interfaces:**
- Consumes: `MineSpiderling` scene (Task 5), `PlaneComponent.current_plane: Level.Layer` (existing), the `_plane_of(source)` idiom `BlockadeSkill._plane_of()` already established.
- Produces: `CocoonMine.arm(owner_spider: Node, burst_count: int, plane: Level.Layer = Level.Layer.GROUND) -> void`, `CocoonMine.burst_damage: float = 30.0`. `CocoonMine` joins group `"traps"` (matching `WebTrap`'s convention).

- [ ] **Step 1: Write the failing tests**

Replace `tests/test_cocoon_mine.gd` in full:

```gdscript
extends GutTest
## CocoonMine (skill fixes bundle): a hidden proximity trap. Deals direct
## burst_damage to whatever spider crosses it, then spawns a cosmetic burst
## of MineSpiderlings — larvae are immune, and it only triggers for a body
## on the same plane it was armed on.

const MineScene := preload("res://entities/skills/scenes/cocoon_mine.tscn")
const PlayerScene := preload("res://entities/player/player.tscn")


func _make_mine() -> CocoonMine:
	var mine: CocoonMine = MineScene.instantiate()
	add_child_autofree(mine)
	return mine


func _make_body(group: String) -> Node2D:
	var body := Node2D.new()
	body.add_to_group(group)
	add_child_autofree(body)
	var health := HealthComponent.new()
	health.current_health = health.max_health
	autofree(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	hurtbox.name = "Hurtbox"
	body.add_child(hurtbox)
	return body


func test_body_entered_by_a_spider_deals_direct_damage_and_bursts_cosmetically() -> void:
	# Counts the delta, not an absolute total: another test in this file
	# (test_detonates_for_a_body_on_the_same_plane_it_was_armed_on) also
	# detonates and leaves its own MineSpiderling in the tree (spawned
	# inside CocoonMine._detonate(), not registered for autofree by either
	# test) — an absolute count would be order-dependent and flaky.
	var before_count := get_tree().get_nodes_in_group("mine_spiderlings").size()
	var mine := _make_mine()
	mine.arm(null, 3)
	var intruder := _make_body("spiders")

	mine._on_body_entered(intruder)

	var hurtbox := intruder.get_node("Hurtbox") as Hurtbox
	assert_eq(hurtbox.health.current_health, hurtbox.health.max_health - mine.burst_damage)
	assert_true(mine.is_queued_for_deletion(), "the mine consumes itself on detonation")
	assert_eq(get_tree().get_nodes_in_group("mine_spiderlings").size(), before_count + 3)


func test_ignores_a_larva_crossing_it() -> void:
	var mine := _make_mine()
	mine.arm(null, 2)
	var larva := _make_body("larvae")

	mine._on_body_entered(larva)

	assert_false(mine.is_queued_for_deletion(), "larvae are immune to Egg Mine")
	var hurtbox := larva.get_node("Hurtbox") as Hurtbox
	assert_eq(hurtbox.health.current_health, hurtbox.health.max_health)


func test_ignores_its_own_owner() -> void:
	var mine := _make_mine()
	var owner_spider := _make_body("spiders")
	mine.arm(owner_spider, 3)

	mine._on_body_entered(owner_spider)

	assert_false(mine.is_queued_for_deletion(), "the placer walking over their own mine doesn't trigger it")


func test_ignores_bodies_that_are_neither_a_spider_nor_a_larva() -> void:
	var mine := _make_mine()
	mine.arm(null, 3)
	var wall := StaticBody2D.new()
	add_child_autofree(wall)

	mine._on_body_entered(wall)

	assert_false(mine.is_queued_for_deletion())


func test_unarmed_mine_does_not_detonate() -> void:
	var mine := _make_mine()
	var intruder := _make_body("spiders")

	mine._on_body_entered(intruder) # never armed

	assert_false(mine.is_queued_for_deletion())


func test_ignores_a_body_on_a_different_plane_than_it_was_armed_on() -> void:
	var mine := _make_mine()
	mine.arm(null, 3, Level.Layer.CEILING)
	var ground_intruder := _make_body("spiders") # plain Node2D -> defaults to GROUND

	mine._on_body_entered(ground_intruder)

	assert_false(mine.is_queued_for_deletion(), "a ground-plane body doesn't trigger a ceiling-armed mine")


func test_detonates_for_a_body_on_the_same_plane_it_was_armed_on() -> void:
	var mine := _make_mine()
	mine.arm(null, 1, Level.Layer.CEILING)
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	player._plane.transition() # -> CEILING

	mine._on_body_entered(player)

	assert_true(mine.is_queued_for_deletion())


func test_joins_the_traps_group() -> void:
	var mine := _make_mine()
	assert_true(mine.is_in_group("traps"))
```

Create `tests/test_egg_mine_skill.gd`:

```gdscript
extends GutTest
## EggMineSkill (skill fixes bundle): arms the mine on whichever plane the
## caster currently occupies.

const MineScene := preload("res://entities/skills/scenes/cocoon_mine.tscn")
const PlayerScene := preload("res://entities/player/player.tscn")


func _make_skill() -> EggMineSkill:
	var skill := EggMineSkill.new()
	skill.mine_scene = MineScene
	skill.burst_count = 2
	add_child_autofree(skill)
	return skill


func test_on_activate_arms_the_mine_on_the_callers_current_plane() -> void:
	var skill := _make_skill()
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	player._plane.transition() # -> CEILING

	skill._on_activate(player)

	var mine: CocoonMine = null
	for node in get_tree().get_nodes_in_group("traps"):
		if node is CocoonMine:
			mine = node
	assert_not_null(mine)
	assert_eq(mine._plane, Level.Layer.CEILING)


func test_on_activate_defaults_to_ground_plane_for_a_caster_without_one() -> void:
	var skill := _make_skill()
	var caster := Node2D.new()
	add_child_autofree(caster)

	skill._on_activate(caster)

	var mine: CocoonMine = null
	for node in get_tree().get_nodes_in_group("traps"):
		if node is CocoonMine:
			mine = node
	assert_not_null(mine)
	assert_eq(mine._plane, Level.Layer.GROUND)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_cocoon_mine.gd 2>&1`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_egg_mine_skill.gd 2>&1`
Expected: FAIL — `arm()` doesn't accept a third argument; `burst_damage` doesn't exist; `mine_spiderlings`/`traps` groups are empty; `TinySpiderling`-based burst count assertion no longer matches old behavior.

- [ ] **Step 3: Write the implementation**

Replace `entities/skills/scenes/cocoon_mine.gd` in full:

```gdscript
class_name CocoonMine
extends Area2D
## Wolf Spider's Egg/Cocoon Mine (skill fixes bundle): a hidden proximity
## trap. On detonation it deals burst_damage directly to the triggering
## spider, then spawns a cosmetic burst of MineSpiderlings around itself,
## then frees. Larvae are immune. Only triggers for a body on the same
## plane it was armed on (mirrors Level.is_blocked()'s same-plane rule).
## Placeholder visual: a small drawn cocoon, no art asset yet. collision_mask
## = player(2) | enemy(4) = 6, mirroring WebTrap.CatchArea's own proximity
## mask minus larvae, since larvae no longer trigger it.

const MineSpiderlingScene := preload("res://entities/skills/scenes/mine_spiderling.tscn")

@export var trigger_radius: float = 24.0
@export var burst_damage: float = 30.0

var _owner_spider: Node
var _burst_count: int = 4
var _plane: Level.Layer = Level.Layer.GROUND
var _armed := false


## Called by EggMineSkill right after placement. `plane` is the plane the
## caster occupied when placing it.
func arm(owner_spider: Node, burst_count: int, plane: Level.Layer = Level.Layer.GROUND) -> void:
	_owner_spider = owner_spider
	_burst_count = burst_count
	_plane = plane
	_armed = true


func _ready() -> void:
	add_to_group("traps")
	body_entered.connect(_on_body_entered)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color(0.5, 0.35, 0.2, 0.85))


func _on_body_entered(body: Node2D) -> void:
	if not _armed or body == _owner_spider:
		return
	if not body.is_in_group("spiders"):
		return
	if _plane_of(body) != _plane:
		return
	_detonate(body)


func _detonate(trigger: Node2D) -> void:
	_armed = false
	var hurtbox := trigger.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(burst_damage, _owner_spider)
	var holder := get_parent()
	if holder != null:
		for i in _burst_count:
			var spiderling := MineSpiderlingScene.instantiate()
			holder.add_child(spiderling)
			var offset := Vector2(trigger_radius, 0).rotated(TAU * float(i) / float(_burst_count))
			spiderling.global_position = global_position + offset
	queue_free()


## Mirrors BlockadeSkill._plane_of(): PlaneComponent-tracked plane, or
## GROUND for anything without one (e.g. a plain test double).
func _plane_of(body: Node) -> Level.Layer:
	var plane_component: PlaneComponent = body.get("_plane") if "_plane" in body else null
	if plane_component != null:
		return plane_component.current_plane
	return Level.Layer.GROUND
```

In `entities/skills/egg_mine_skill.gd`, change `_on_activate` and add `_plane_of`:

```gdscript
func _on_activate(source: Node) -> void:
	if mine_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var mine := mine_scene.instantiate()
	_spawn_parent(source).add_child(mine)
	mine.global_position = origin.global_position
	if mine.has_method("arm"):
		mine.arm(source, burst_count, _plane_of(source))


## Mirrors BlockadeSkill._plane_of(): the plane `source` currently occupies.
func _plane_of(source: Node) -> Level.Layer:
	var plane_component: PlaneComponent = source.get("_plane") if "_plane" in source else null
	if plane_component != null:
		return plane_component.current_plane
	return Level.Layer.GROUND
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_cocoon_mine.gd 2>&1`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_egg_mine_skill.gd 2>&1`
Expected: `All tests passed!` for both.

- [ ] **Step 5: Commit**

```bash
git add entities/skills/scenes/cocoon_mine.gd entities/skills/egg_mine_skill.gd tests/test_cocoon_mine.gd tests/test_egg_mine_skill.gd
git status # stage tests/test_egg_mine_skill.gd.uid if it appears
git commit -m "Redesign Egg Mine: direct damage, cosmetic burst, larvae immunity, ceiling placement"
```

---

### Task 7: Silk Tunnel length

**Files:**
- Modify: `entities/skills/silk_tunnel_skill.gd`
- Test: `tests/test_silk_tunnel_skill.gd` (new)

**Interfaces:**
- Produces: `SilkTunnelSkill.tile_count: int = 6` (was `4`). No other signature changes.

- [ ] **Step 1: Write the failing test**

Create `tests/test_silk_tunnel_skill.gd`:

```gdscript
extends GutTest
## SilkTunnelSkill (skill fixes bundle): lays web across tile_count tiles
## ahead of the caster — bumped from 4 to 6 per playtest feedback.

const TrapScene := preload("res://entities/web/web_trap.tscn")


func _make_skill() -> SilkTunnelSkill:
	var skill := SilkTunnelSkill.new()
	skill.trap_scene = TrapScene
	add_child_autofree(skill)
	return skill


func test_default_tile_count_is_6() -> void:
	var skill := _make_skill()
	assert_eq(skill.tile_count, 6)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_silk_tunnel_skill.gd 2>&1`
Expected: FAIL — `tile_count` is `4`, not `6`.

- [ ] **Step 3: Write the implementation**

In `entities/skills/silk_tunnel_skill.gd`, change:

```gdscript
@export var tile_count: int = 4
```

to:

```gdscript
@export var tile_count: int = 6
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_silk_tunnel_skill.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/skills/silk_tunnel_skill.gd tests/test_silk_tunnel_skill.gd
git status # stage tests/test_silk_tunnel_skill.gd.uid if it appears
git commit -m "Lengthen Silk Tunnel from 4 to 6 tiles"
```

---

### Task 8: Decoy collision fix

**Files:**
- Modify: `entities/skills/scenes/decoy.tscn`
- Modify: `entities/skills/scenes/decoy.gd`
- Test: `tests/test_decoy.gd`

**Interfaces:**
- Produces: no signature change — `Decoy` is no longer a physical `StaticBody2D` obstacle (`collision_layer = 0`), still fully functional as a `Hurtbox`/`HealthComponent`-bearing target in the `"spiders"`/`"decoys"` groups.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_decoy.gd` (after `test_joins_the_spiders_and_decoys_groups`):

```gdscript
func test_has_no_physical_collision() -> void:
	var decoy := _make_decoy()
	assert_eq(decoy.collision_layer, 0, "a decoy never traps its own caster on placement")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_decoy.gd 2>&1`
Expected: FAIL — `collision_layer` is `4`, not `0`.

- [ ] **Step 3: Write the implementation**

In `entities/skills/scenes/decoy.tscn`, change:

```
[node name="Decoy" type="StaticBody2D"]
collision_layer = 4
collision_mask = 0
```

to:

```
[node name="Decoy" type="StaticBody2D"]
collision_layer = 0
collision_mask = 0
```

In `entities/skills/scenes/decoy.gd`, replace the class doc comment's stale note (the paragraph starting `## NOTE: joining "spiders" doesn't yet actually redirect...`) with:

```gdscript
## Retargeting is already wired: Enemy._acquire_target() prefers a nearer
## visible decoy over the real player (see tests/test_enemy_decoy_diversion.gd).
## No physical collision (skill fixes bundle) — a decoy is dropped on the
## caster's own tile, and being a solid obstacle there trapped the caster
## against its own decoy the instant it was placed.
```

Also update the doc comment line describing the collision layer choice (currently
`## On the enemy(4) collision layer so it's a physical obstacle like a real spider,
## not a walk-through prop.`) — delete that sentence since it's no longer true.

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_decoy.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add entities/skills/scenes/decoy.tscn entities/skills/scenes/decoy.gd tests/test_decoy.gd
git commit -m "Drop Decoy's physical collision so it never traps its own caster"
```

---

### Final check

- [ ] Run the full suite once more end-to-end: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1` — expect `All tests passed!`.
- [ ] Import check: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- [ ] Run `git status` — stage any stray `.gd.uid`/`.tscn` sidecars from new files before opening the PR.
- [ ] Manual playtest pass: activate Sense and Camouflage, confirm the outline is visible on-screen (headless checks can't verify this — the shader logic and material-attachment are tested, but the actual visual only shows in a windowed run); drop Hatchlings and confirm they orbit the caster until an enemy gets close; place Egg Mine, walk into it, confirm a real damage hit lands plus a brief cosmetic burst with tiny pokes; lay Silk Tunnel and confirm the longer reach; drop Decoy on yourself and confirm you're not stuck.
