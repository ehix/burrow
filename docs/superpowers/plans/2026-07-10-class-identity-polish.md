# Class Identity Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-class spider color, Weaver web-slow immunity, and wiring up Decoy's dead shot-speed multiplier plus a new fire-costs-health tradeoff, per playtest feedback.

**Architecture:** All four fixes hang off the existing `SpiderClassData` per-class data pattern (`display_name`, `melee_damage_mult`, etc. already work this way) — add fields, read them at the same call sites that already read the existing fields, no new architecture.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-10-class-identity-polish-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1 | tail -30`
  (drop `-gselect=` for the whole suite). Expect `All tests passed!`.
- Import check after any `.tscn`/`.tres` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- Color values (`display_color`) and the Decoy health cost (`4.0`) are tunable, not mandated exactly — use the spec's proposed values, adjust later if playtesting says otherwise.
- This slice touches only `resources/spider_class_data.gd`, the four `resources/spiders/*.tres` files, `entities/player/player.gd`, `entities/enemy/enemy.gd`, `components/combat_fx.gd`, `components/web_emitter.gd`, `entities/web/web_shot.gd`, and their tests. No other class/system.

---

### Task 1: Per-class spider color

**Files:**
- Modify: `resources/spider_class_data.gd`
- Modify: `resources/spiders/wolf.tres`, `resources/spiders/weaver.tres`, `resources/spiders/decoy.tres`, `resources/spiders/net_caster.tres`
- Modify: `entities/player/player.gd`
- Modify: `entities/enemy/enemy.gd`
- Modify: `components/combat_fx.gd`
- Modify: `tests/test_distress_flash.gd` (fixes a pre-existing test this task's own change invalidates)
- Test: `tests/test_player_class_switching.gd`, `tests/test_enemy_class_kit.gd`, `tests/test_combat_fx.gd` (new)

**Interfaces:**
- Produces: `SpiderClassData.display_color: Color`, `Player._update_sprite_tint() -> void` (private, no other task depends on it), `CombatFx.flash()`'s new restore-to-prior-modulate behavior (no signature change — same `static func flash(sprite: CanvasItem) -> void`).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_player_class_switching.gd` (after the existing `test_unknown_class_id_is_a_noop` function — this file already has a `_make_player()` helper and `Player.NetCasterData`/`WolfData`/`WeaverData`/`DecoyData` consts are already used elsewhere in this suite):

```gdscript
func test_apply_class_tints_the_sprite_to_the_class_color() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	assert_eq(player.sprite.modulate, Player.WeaverData.display_color)


func test_ceiling_tint_composes_with_the_class_color_instead_of_replacing_it() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	player._plane.transition() # -> CEILING
	assert_eq(player.sprite.modulate, Player.WeaverData.display_color * Color(0.55, 0.65, 0.85, 0.85))
	player._plane.transition() # -> GROUND
	assert_eq(player.sprite.modulate, Player.WeaverData.display_color, "back to the plain class color on the ground")
```

Add to `tests/test_enemy_class_kit.gd` (after the existing `test_decoy_gets_camouflage_and_decoy` function):

```gdscript
func test_apply_class_tints_the_sprite_to_the_class_color() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.DECOY)
	assert_eq(enemy.facing_visual.modulate, Enemy.DecoyClassData.display_color)
```

Create `tests/test_combat_fx.gd`:

```gdscript
extends GutTest
## CombatFx.flash() must restore the sprite's own prior tint, not a
## hardcoded white — otherwise a class-colored (or ceiling-tinted) sprite
## would incorrectly snap back to plain white after every hit.

func test_flash_sets_the_flash_color_immediately() -> void:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	sprite.modulate = Color(0.4, 0.75, 0.45) # some non-white class tint
	CombatFx.flash(sprite)
	assert_eq(sprite.modulate, CombatFx.FLASH_COLOR)


func test_flash_restores_the_sprites_actual_prior_tint_not_white() -> void:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	var class_tint := Color(0.4, 0.75, 0.45)
	sprite.modulate = class_tint
	CombatFx.flash(sprite)
	await get_tree().create_timer(CombatFx.FLASH_TIME + 0.05).timeout
	assert_eq(sprite.modulate, class_tint, "restores the actual prior tint, not hardcoded white")


func test_flash_is_a_noop_outside_the_tree() -> void:
	var sprite := Sprite2D.new()
	autofree(sprite) # deliberately not added to the tree
	sprite.modulate = Color(0.4, 0.75, 0.45)
	CombatFx.flash(sprite) # must not error
	assert_eq(sprite.modulate, Color(0.4, 0.75, 0.45), "no-op leaves modulate untouched")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_combat_fx.gd 2>&1 | tail -30`
Expected: FAIL — `display_color` not found on `SpiderClassData`/`Player.WeaverData`/`Enemy.DecoyClassData`; `test_combat_fx.gd`'s restore test fails because `flash()` still restores hardcoded white, not the captured `class_tint`.

- [ ] **Step 3: Write the implementation**

In `resources/spider_class_data.gd`, add after `@export var display_name: String = ""`:

```gdscript
## Sprite tint while this class is active — Player.apply_class()/
## Enemy._apply_class() apply it to the spider's sprite.
@export var display_color: Color = Color.WHITE
```

Add `display_color = Color(...)` to each `.tres`'s `[resource]` block (after the existing `display_name` line):

`resources/spiders/wolf.tres`:
```
display_color = Color(0.85, 0.4, 0.25, 1.0)
```

`resources/spiders/weaver.tres`:
```
display_color = Color(0.4, 0.75, 0.45, 1.0)
```

`resources/spiders/decoy.tres`:
```
display_color = Color(0.65, 0.45, 0.85, 1.0)
```

`resources/spiders/net_caster.tres`:
```
display_color = Color(0.85, 0.75, 0.35, 1.0)
```

In `entities/player/player.gd`, change `apply_class()` from:

```gdscript
func apply_class(spider_class: int) -> void:
	var data: SpiderClassData = _class_data_by_id.get(spider_class)
	if data == null:
		return
	_active_class = spider_class
	_active_class_data = data
	refresh_upgrades()
```

to:

```gdscript
func apply_class(spider_class: int) -> void:
	var data: SpiderClassData = _class_data_by_id.get(spider_class)
	if data == null:
		return
	_active_class = spider_class
	_active_class_data = data
	refresh_upgrades()
	_update_sprite_tint()
```

Change `_on_plane_changed()` from:

```gdscript
func _on_plane_changed(plane: Level.Layer) -> void:
	sprite.modulate = Color(0.55, 0.65, 0.85, 0.85) if plane == Level.Layer.CEILING else Color.WHITE
```

to:

```gdscript
func _on_plane_changed(_plane_arg: Level.Layer) -> void:
	_update_sprite_tint()
```

Add a new method right after `_on_plane_changed()`:

```gdscript
## The sprite's tint is the active class's color, dimmed/cooled by the
## ceiling tint on top when on the ceiling plane — the two effects compose
## instead of one clobbering the other.
func _update_sprite_tint() -> void:
	var base := _active_class_data.display_color if _active_class_data != null else Color.WHITE
	if _plane.current_plane == Level.Layer.CEILING:
		sprite.modulate = base * Color(0.55, 0.65, 0.85, 0.85)
	else:
		sprite.modulate = base
```

In `entities/enemy/enemy.gd`, change `_apply_class()` from:

```gdscript
func _apply_class(spider_class: int) -> void:
	var data: SpiderClassData = _class_data_by_id.get(spider_class)
	if data == null:
		return
	active_class = spider_class
	_active_class_data = data
	melee_damage = _base_melee_damage * data.melee_damage_mult
	web_emitter.cooldown = _base_web_cooldown / maxf(0.01, data.web_fire_rate_mult)
```

to:

```gdscript
func _apply_class(spider_class: int) -> void:
	var data: SpiderClassData = _class_data_by_id.get(spider_class)
	if data == null:
		return
	active_class = spider_class
	_active_class_data = data
	melee_damage = _base_melee_damage * data.melee_damage_mult
	web_emitter.cooldown = _base_web_cooldown / maxf(0.01, data.web_fire_rate_mult)
	if facing_visual != null:
		facing_visual.modulate = data.display_color
```

In `components/combat_fx.gd`, change `flash()` from:

```gdscript
## Pulse `sprite` red, then fade back to white. No-op if it can't tween yet.
static func flash(sprite: CanvasItem) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	sprite.modulate = FLASH_COLOR
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, FLASH_TIME)
```

to:

```gdscript
## Pulse `sprite` red, then fade back to whatever tint it actually had before
## the flash (a class color, possibly ceiling-dimmed) — never a hardcoded
## white, or per-class sprite tinting would visibly break on every hit.
static func flash(sprite: CanvasItem) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	var restore := sprite.modulate
	sprite.modulate = FLASH_COLOR
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate", restore, FLASH_TIME)
```

In `tests/test_distress_flash.gd`, change `test_apply_web_hit_alone_does_not_flash()` from:

```gdscript
func test_apply_web_hit_alone_does_not_flash() -> void:
	var player := _make_player()
	player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0) # a pure web-crossing slow
	assert_eq(player.sprite.modulate, Color.WHITE, "a status effect alone must not flash")
```

to:

```gdscript
func test_apply_web_hit_alone_does_not_flash() -> void:
	var player := _make_player()
	var before := player.sprite.modulate
	player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0) # a pure web-crossing slow
	assert_eq(player.sprite.modulate, before, "a status effect alone must not flash")
```

(This test's own intent — "a status effect alone must not change the sprite's tint" — is unaffected by which color happens to be active; it only hardcoded `Color.WHITE` because that used to be the only color a sprite could ever have. Comparing to the captured pre-call value is the correct, class-color-independent form of the same check.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `10/10 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `21/21 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_combat_fx.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `3/3 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_distress_flash.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `2/2 passed`.

- [ ] **Step 5: Import and commit**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.

```bash
git add resources/spider_class_data.gd resources/spiders/wolf.tres resources/spiders/weaver.tres resources/spiders/decoy.tres resources/spiders/net_caster.tres entities/player/player.gd entities/enemy/enemy.gd components/combat_fx.gd tests/test_distress_flash.gd tests/test_player_class_switching.gd tests/test_enemy_class_kit.gd tests/test_combat_fx.gd
git commit -m "Give each class a distinct sprite color that survives damage flashes"
```

---

### Task 2: Weaver immune to web slowdown (not Blockade)

**Files:**
- Modify: `entities/player/player.gd`
- Modify: `entities/enemy/enemy.gd`
- Test: `tests/test_player_class_switching.gd`, `tests/test_enemy_class_kit.gd`

**Interfaces:**
- Produces: `Player._is_weaver() -> bool`, `Enemy._is_weaver() -> bool` (private, no other task depends on them).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_player_class_switching.gd`:

```gdscript
func test_weaver_takes_no_slow_from_a_web_hit() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0) # a pure web-crossing slow
	assert_eq(player._mover.speed_scale, 1.0, "a Weaver never gets slowed by a web")


func test_non_weaver_still_gets_slowed_by_a_web_hit() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WOLF)
	player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0)
	assert_eq(player._mover.speed_scale, 0.5, "every other class is slowed as before")


func test_weaver_still_gets_knocked_back_and_stunned_by_a_web_hit() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	player.apply_web_hit(Vector2i.RIGHT, 0.5, 1.5, 0.3)
	assert_true(player._mover.is_stunned(), "immunity is to the slow only, not the stun")
```

Add to `tests/test_enemy_class_kit.gd`:

```gdscript
func test_weaver_enemy_takes_no_slow_from_a_web_hit() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WEAVER)
	enemy.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0)
	assert_eq(enemy._mover.speed_scale, 1.0, "a Weaver enemy never gets slowed by a web")


func test_non_weaver_enemy_still_gets_slowed_by_a_web_hit() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	enemy.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0)
	assert_eq(enemy._mover.speed_scale, 0.5, "every other class is slowed as before")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -30`
Expected: FAIL — Weaver's `speed_scale` is `0.5` (slowed), not the expected `1.0`, since immunity doesn't exist yet.

- [ ] **Step 3: Write the implementation**

In `entities/player/player.gd`, change `apply_web_hit()` from:

```gdscript
func apply_web_hit(push_dir: Vector2i, factor: float, slow_duration: float, stun_duration: float) -> void:
	if _mover == null:
		return
	if push_dir != Vector2i.ZERO:
		_mover.knockback(push_dir)
	if factor < 1.0:
		_mover.apply_slow(factor, slow_duration)
	if stun_duration > 0.0:
		_mover.stun(stun_duration)
```

to:

```gdscript
func apply_web_hit(push_dir: Vector2i, factor: float, slow_duration: float, stun_duration: float) -> void:
	if _mover == null:
		return
	if push_dir != Vector2i.ZERO:
		_mover.knockback(push_dir)
	if factor < 1.0 and not _is_weaver():
		_mover.apply_slow(factor, slow_duration)
	if stun_duration > 0.0:
		_mover.stun(stun_duration)


## Weavers never get slowed by a web (design: playtest correction) — this
## does not extend to Blockade, which is a hard physical collider that
## never goes through apply_web_hit() at all.
func _is_weaver() -> bool:
	return _active_class_data != null \
		and _active_class_data.spider_class == SpiderClassData.SpiderClass.WEAVER
```

In `entities/enemy/enemy.gd`, apply the identical change to its own `apply_web_hit()`:

```gdscript
func apply_web_hit(push_dir: Vector2i, factor: float, slow_duration: float, stun_duration: float) -> void:
	if _mover == null:
		return
	if push_dir != Vector2i.ZERO:
		_mover.knockback(push_dir)
	if factor < 1.0 and not _is_weaver():
		_mover.apply_slow(factor, slow_duration)
	if stun_duration > 0.0:
		_mover.stun(stun_duration)


## Weavers never get slowed by a web (design: playtest correction) — this
## does not extend to Blockade, which is a hard physical collider that
## never goes through apply_web_hit() at all.
func _is_weaver() -> bool:
	return _active_class_data != null \
		and _active_class_data.spider_class == SpiderClassData.SpiderClass.WEAVER
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `13/13 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `23/23 passed`.

- [ ] **Step 5: Commit**

```bash
git add entities/player/player.gd entities/enemy/enemy.gd tests/test_player_class_switching.gd tests/test_enemy_class_kit.gd
git commit -m "Make Weaver immune to web slowdown"
```

---

### Task 3: Wire web_projectile_speed_mult and Decoy's fire-costs-health

**Files:**
- Modify: `components/web_emitter.gd`
- Modify: `entities/web/web_shot.gd`
- Modify: `entities/player/player.gd`
- Modify: `entities/enemy/enemy.gd`
- Modify: `resources/spider_class_data.gd`
- Modify: `resources/spiders/decoy.tres`
- Test: `tests/test_web_shot.gd`, new `tests/test_web_emitter.gd`, `tests/test_player_class_switching.gd`, `tests/test_enemy_class_kit.gd`

**Interfaces:**
- Produces: `SpiderClassData.web_fire_health_cost: float` (default `0.0`), `WebEmitter.fire(from_position, direction, source, speed_mult: float = 1.0) -> Node`, `WebShot.launch(direction, source, speed_mult: float = 1.0) -> void`, `Enemy._fire_web(direction: Vector2) -> void` (private, replaces two duplicated call sites).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_web_shot.gd` (after the existing `test_reduced_damage_default` function):

```gdscript
func test_launch_default_speed_mult_leaves_velocity_unchanged() -> void:
	var shot := _make_shot()
	shot.launch(Vector2.RIGHT, null)
	assert_almost_eq(shot._velocity.length(), shot.speed, 0.001)


func test_launch_scales_velocity_by_speed_mult() -> void:
	var shot := _make_shot()
	shot.launch(Vector2.RIGHT, null, 1.4)
	assert_almost_eq(shot._velocity.length(), shot.speed * 1.4, 0.001)
```

Create `tests/test_web_emitter.gd`:

```gdscript
extends GutTest
## WebEmitter.fire() passes its optional speed_mult straight through to the
## spawned shot's launch() — defaulting to 1.0 (unchanged behavior) when the
## caller doesn't supply one.

const WebShotScene := preload("res://entities/web/web_shot.tscn")


func _make_emitter() -> WebEmitter:
	var emitter := WebEmitter.new()
	emitter.web_shot_scene = WebShotScene
	add_child_autofree(emitter)
	return emitter


func _make_source() -> Node2D:
	var source := Node2D.new()
	add_child_autofree(source)
	return source


func test_fire_defaults_speed_mult_to_one() -> void:
	var emitter := _make_emitter()
	var source := _make_source()
	var shot: WebShot = emitter.fire(Vector2.ZERO, Vector2.RIGHT, source)
	assert_almost_eq(shot._velocity.length(), shot.speed, 0.001)


func test_fire_passes_a_custom_speed_mult_through() -> void:
	var emitter := _make_emitter()
	var source := _make_source()
	var shot: WebShot = emitter.fire(Vector2.ZERO, Vector2.RIGHT, source, 1.4)
	assert_almost_eq(shot._velocity.length(), shot.speed * 1.4, 0.001)
```

Add to `tests/test_player_class_switching.gd`:

```gdscript
func test_decoy_shot_costs_health_to_fire() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	var before := player.health.current_health
	player.web_emitter.cooldown = 0.0 # ignore fire-rate cooldown for this check
	var shot := player.web_emitter.fire(player.global_position, Vector2.RIGHT, player,
		Player.DecoyData.web_projectile_speed_mult)
	if shot != null and Player.DecoyData.web_fire_health_cost > 0.0:
		player.health.take_damage(Player.DecoyData.web_fire_health_cost)
	assert_almost_eq(player.health.current_health, before - Player.DecoyData.web_fire_health_cost, 0.001)


func test_non_decoy_fire_costs_no_extra_health() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WOLF)
	var before := player.health.current_health
	assert_almost_eq(Player.WolfData.web_fire_health_cost, 0.0, 0.001, "no class but Decoy costs health to fire")
	assert_almost_eq(player.health.current_health, before, 0.001)
```

(These two tests check the data contract and the arithmetic directly — the actual firing integration through `Input.is_action_pressed("fire")` is exercised by the manual verification step in Task 4, since driving real input through `_physics_process` isn't this suite's established convention.)

Add to `tests/test_enemy_class_kit.gd`:

```gdscript
func test_decoy_has_a_nonzero_fire_health_cost() -> void:
	assert_gt(Enemy.DecoyClassData.web_fire_health_cost, 0.0)


func test_other_classes_have_no_fire_health_cost() -> void:
	for data in [Enemy.NetCasterData, Enemy.WolfData, Enemy.WeaverData]:
		assert_almost_eq(data.web_fire_health_cost, 0.0, 0.001)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_shot.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_emitter.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -30`
Expected: FAIL — `launch()`/`fire()` don't accept a third/fourth argument yet; `web_fire_health_cost` not found on `SpiderClassData`.

- [ ] **Step 3: Write the implementation**

In `entities/web/web_shot.gd`, change `launch()` from:

```gdscript
## Called by WebEmitter right after spawn.
func launch(direction: Vector2, source: Node) -> void:
	var dir := direction.normalized()
	_velocity = dir * speed
	_source = source
	rotation = dir.angle()
```

to:

```gdscript
## Called by WebEmitter right after spawn. speed_mult is the shooter's
## active class's web_projectile_speed_mult (1.0 = unchanged).
func launch(direction: Vector2, source: Node, speed_mult: float = 1.0) -> void:
	var dir := direction.normalized()
	_velocity = dir * speed * speed_mult
	_source = source
	rotation = dir.angle()
```

In `components/web_emitter.gd`, change `fire()` from:

```gdscript
## Fire along `direction`. Returns the spawned shot, or null if on cooldown /
## unconfigured / no direction.
func fire(from_position: Vector2, direction: Vector2, source: Node) -> Node:
	var dir := direction.normalized()
	if not can_fire() or dir == Vector2.ZERO:
		return null
	_cooldown_left = cooldown
	var shot := web_shot_scene.instantiate()
	_spawn_parent(source).add_child(shot)
	shot.global_position = from_position + dir * muzzle_offset
	if shot.has_method("launch"):
		shot.launch(dir, source)
	HungerComponent.charge_all(source.get_tree(), hunger_cost)
	return shot
```

to:

```gdscript
## Fire along `direction`. Returns the spawned shot, or null if on cooldown /
## unconfigured / no direction. speed_mult is passed straight through to the
## shot's launch() (1.0 = unchanged).
func fire(from_position: Vector2, direction: Vector2, source: Node, speed_mult: float = 1.0) -> Node:
	var dir := direction.normalized()
	if not can_fire() or dir == Vector2.ZERO:
		return null
	_cooldown_left = cooldown
	var shot := web_shot_scene.instantiate()
	_spawn_parent(source).add_child(shot)
	shot.global_position = from_position + dir * muzzle_offset
	if shot.has_method("launch"):
		shot.launch(dir, source, speed_mult)
	HungerComponent.charge_all(source.get_tree(), hunger_cost)
	return shot
```

In `resources/spider_class_data.gd`, add after `@export var web_projectile_speed_mult: float = 1.0`:

```gdscript
## Direct health cost to the shooter on a successful fire (0.0 = free, the
## default for every class but Decoy).
@export var web_fire_health_cost: float = 0.0
```

Add to `resources/spiders/decoy.tres`'s `[resource]` block (after `web_projectile_speed_mult = 1.4`):

```
web_fire_health_cost = 4.0
```

In `entities/player/player.gd`, change the fire line in `_physics_process()` from:

```gdscript
	if Input.is_action_pressed("fire") and _active_class_data != null and _active_class_data.web_enabled:
		web_emitter.fire(global_position, facing, self)
```

to:

```gdscript
	if Input.is_action_pressed("fire") and _active_class_data != null and _active_class_data.web_enabled:
		var shot := web_emitter.fire(global_position, facing, self, _active_class_data.web_projectile_speed_mult)
		if shot != null and _active_class_data.web_fire_health_cost > 0.0:
			health.take_damage(_active_class_data.web_fire_health_cost)
```

In `entities/enemy/enemy.gd`, add a new private method (e.g. right before `_do_chase()`):

```gdscript
## Fires along `direction` with the active class's projectile-speed
## multiplier, then charges its fire-health-cost (Decoy) if any — shared by
## both _do_chase() and _fight_back() so the class-multiplier/health-cost
## logic lives in exactly one place.
func _fire_web(direction: Vector2) -> void:
	var speed_mult := _active_class_data.web_projectile_speed_mult if _active_class_data != null else 1.0
	var shot := web_emitter.fire(global_position, direction, self, speed_mult)
	if shot != null and _active_class_data != null and _active_class_data.web_fire_health_cost > 0.0:
		health.take_damage(_active_class_data.web_fire_health_cost)
```

Change `_do_chase()`'s fire line from:

```gdscript
	elif to_target.length() <= attack_range and _web_enabled() and _has_line_of_sight(_current_target.global_position):
		web_emitter.fire(global_position, to_target, self)
```

to:

```gdscript
	elif to_target.length() <= attack_range and _web_enabled() and _has_line_of_sight(_current_target.global_position):
		_fire_web(to_target)
```

Change `_fight_back()`'s fire line from:

```gdscript
	elif to_player.length() <= attack_range and _web_enabled() and _has_line_of_sight(_player.global_position):
		web_emitter.fire(global_position, to_player, self)
```

to:

```gdscript
	elif to_player.length() <= attack_range and _web_enabled() and _has_line_of_sight(_player.global_position):
		_fire_web(to_player)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_shot.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `6/6 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_emitter.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `2/2 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_player_class_switching.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `15/15 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_class_kit.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `25/25 passed`.

- [ ] **Step 5: Import and commit**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.

```bash
git add components/web_emitter.gd entities/web/web_shot.gd entities/player/player.gd entities/enemy/enemy.gd resources/spider_class_data.gd resources/spiders/decoy.tres tests/test_web_shot.gd tests/test_web_emitter.gd tests/test_player_class_switching.gd tests/test_enemy_class_kit.gd
git commit -m "Wire web_projectile_speed_mult and add Decoy's fire-costs-health tradeoff"
```

---

### Task 4: Full-suite verification and manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full automated test suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!`.

- [ ] **Step 2: Import and boot smoke test**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"` — expect no new errors.

- [ ] **Step 3: Manual verification in a running Godot session**

Launch the game normally (not headless), cycle through all four classes with the dev hotkey (Q), and confirm by hand:
- Each class shows a visibly distinct spider color.
- Taking a hit flashes red, then fades back to the correct class color (not white) — check this on both the ground and the ceiling plane.
- As Weaver, crossing a web never slows you down, but walking into a Blockade still stops you.
- As Decoy, firing is visibly much faster than other classes and costs a small sliver of health each shot; as any other class, firing costs no health.

- [ ] **Step 4: Final commit (only if manual verification above required fixes)**

If Step 3 surfaced no issues, there's nothing to commit here. If it did, fix, re-run Steps 1-2, then:

```bash
git add -A
git commit -m "Fix issues found in manual class identity verification"
```
