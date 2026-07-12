class_name Player
extends CharacterBody2D
## Player spider: free 8-way movement, fires web shots along its facing, lays
## traps, and carries HP + Hunger (via child components) between levels. Relays
## its component signals to the EventBus so the generic HUD can listen.

## Close-quarters strike (F): damage + shove the spider one tile ahead, or
## kills a larva outright (mirrors a web shot; harvesting stays trap-only).
@export var melee_range: float = 60.0
@export var melee_damage: float = 14.0
@export var melee_stun: float = 0.3
@export var melee_cooldown: float = 0.5
## Hunger added to every spider per swing (charge_all's max-hunger fail-safe
## drains health instead once a spider is already starving).
@export var melee_hunger_cost: float = 5.0

@onready var health: HealthComponent = $HealthComponent
@onready var hunger: HungerComponent = $HungerComponent
@onready var web_emitter: WebEmitter = $WebEmitter
@onready var trap_placer: TrapPlacer = $TrapPlacer
@onready var sprite: Sprite2D = $Sprite
@onready var _mover: GridMover = $GridMover
@onready var _plane: PlaneComponent = $PlaneComponent
@onready var _camouflage: CamouflageSkill = $CamouflageSkill
@onready var _status: StatusEffectComponent = $StatusEffectComponent
@onready var _sense: SenseSkill = $SenseSkill
@onready var _remove_walls: RemoveWallsSkill = $RemoveWallsSkill
## Every class-specific skill below is attached to the player for testing
## all seven at once — this is not final class balance (see SpiderClassData,
## not yet wired onto Player/Enemy for real class selection), just a kitchen
## -sink loadout so each skill can actually be exercised in a running game.
@onready var _net_hold: NetHoldSkill = $NetHoldSkill
@onready var _net_shot: NetShotSkill = $NetShotSkill
@onready var _hatchlings: HatchlingsSkill = $HatchlingsSkill
@onready var _egg_mine: EggMineSkill = $EggMineSkill
@onready var _blockade: BlockadeSkill = $BlockadeSkill
@onready var _silk_tunnel: SilkTunnelSkill = $SilkTunnelSkill
@onready var _decoy: DecoySkill = $DecoySkill
@onready var inventory: InventoryComponent = $InventoryComponent

## The four class archetypes (design §3), each authored as a .tres — the same
## "author a Resource, don't fork the scene" pattern EnemyType established.
## Dev tool (Q, in World) cycles GameState.selected_class through these live.
const NetCasterData: SpiderClassData = preload("res://resources/spiders/net_caster.tres")
const WolfData: SpiderClassData = preload("res://resources/spiders/wolf.tres")
const WeaverData: SpiderClassData = preload("res://resources/spiders/weaver.tres")
const DecoyData: SpiderClassData = preload("res://resources/spiders/decoy.tres")

## Which class-specific skills respond to input for each class — everything
## else in the kitchen-sink loadout stays attached but inert. Sense and
## Remove Walls are general utilities (design §4), not class-locked, so they
## aren't in this map at all and always respond regardless of active class.
const CLASS_SKILLS := {
	0: ["net_hold", "net_shot"],           # SpiderClassData.SpiderClass.NET_CASTER
	1: ["hatchlings", "egg_mine"],         # .WOLF
	2: ["blockade", "silk_tunnel"],        # .WEAVER
	3: ["camouflage", "decoy"],            # .DECOY
}

var facing := Vector2.RIGHT
var _dead := false
var _melee_left := 0.0
var _level: Level
var _class_data_by_id: Dictionary = {}
## action name -> the matching SkillComponent instance, built once in
## _ready() — the lookup active_skills() resolves CLASS_SKILLS' action-name
## lists through, instead of guessing node names from action strings.
var _skill_by_action: Dictionary = {}
var _active_class: int = SpiderClassData.SpiderClass.WOLF
var _active_class_data: SpiderClassData
var _base_melee_damage: float
var _base_web_cooldown: float
var _base_hunger_rate: float


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("player")
	# Route blocking through the player so the dev noclip toggle can bypass it.
	_mover.block_check = _blocked
	_mover.step_finished.connect(_on_step_finished)
	_plane.plane_changed.connect(_on_plane_changed)
	_status.effect_applied.connect(_on_effect_applied)
	_status.effect_expired.connect(_on_effect_expired)
	inventory.item_held_changed.connect(func(_item: ConsumableItem) -> void: queue_redraw())
	_net_shot.net_hold = _net_hold
	_class_data_by_id = {
		SpiderClassData.SpiderClass.NET_CASTER: NetCasterData,
		SpiderClassData.SpiderClass.WOLF: WolfData,
		SpiderClassData.SpiderClass.WEAVER: WeaverData,
		SpiderClassData.SpiderClass.DECOY: DecoyData,
	}
	_skill_by_action = {
		"net_hold": _net_hold, "net_shot": _net_shot,
		"hatchlings": _hatchlings, "egg_mine": _egg_mine,
		"blockade": _blockade, "silk_tunnel": _silk_tunnel,
		"camouflage": _camouflage, "decoy": _decoy,
	}
	_base_melee_damage = melee_damage
	_base_web_cooldown = web_emitter.cooldown
	_base_hunger_rate = hunger.hunger_rate
	apply_class(GameState.selected_class) # also applies purchased upgrades — see refresh_upgrades()
	_restore_vitals()
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(func(amount: float) -> void: EventBus.player_damaged.emit(amount))
	# Distress flash is reserved for actually being hurt — never for a status
	# effect like a web's slow, which deals no damage.
	health.damaged.connect(func(_amount: float) -> void: CombatFx.flash(sprite))
	health.died.connect(_on_died)
	hunger.hunger_changed.connect(_on_hunger_changed)
	hunger.overflowed.connect(func(amount: float) -> void: EventBus.excess_consumed.emit(self, amount))
	# Prime the HUD with current values.
	EventBus.health_changed.emit(self, health.current_health, health.max_health)
	EventBus.hunger_changed.emit(self, hunger.current_hunger, hunger.max_hunger)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _melee_left > 0.0:
		_melee_left = maxf(0.0, _melee_left - delta)
	var dir := _dominant_dir(Input.get_vector("move_left", "move_right", "move_up", "move_down"))
	if dir != Vector2i.ZERO:
		facing = Vector2(dir)
		sprite.rotation = facing.angle() # sprite drawn facing east (rotation 0)
		_mover.try_step(dir)
	else:
		# No input this frame: drop any queued step so a step finishing right
		# after release doesn't auto-continue into a stale buffered direction.
		_mover.cancel_buffer()

	if Input.is_action_pressed("fire") and _active_class_data != null and _active_class_data.web_enabled:
		var shot := web_emitter.fire(global_position, facing, self, _active_class_data.web_projectile_speed_mult)
		if shot != null and _active_class_data.web_fire_health_cost > 0.0:
			health.take_damage(_active_class_data.web_fire_health_cost)
	if Input.is_action_just_pressed("place_trap"):
		trap_placer.place(global_position, self)
	if Input.is_action_just_pressed("melee"):
		_melee()
	if Input.is_action_just_pressed("toggle_plane"):
		_plane.transition()
	# Sense, Remove Walls, and item use are general utilities — always
	# available, regardless of active class. Everything below is
	# class-gated: pressing a key for a skill that isn't part of the
	# current class silently no-ops.
	if Input.is_action_just_pressed("sense"):
		_sense.activate(self)
	if Input.is_action_just_pressed("remove_walls_skill"):
		_remove_walls.activate(self)
	if Input.is_action_just_pressed("use_item"):
		inventory.use(self)
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
	if Input.is_action_just_pressed("buy_upgrade_1"):
		_try_buy_upgrade(0)
	if Input.is_action_just_pressed("buy_upgrade_2"):
		_try_buy_upgrade(1)
	if Input.is_action_just_pressed("buy_upgrade_3"):
		_try_buy_upgrade(2)
	if Input.is_action_just_pressed("buy_upgrade_4"):
		_try_buy_upgrade(3)


## Called by Level right after instancing, mirroring Enemy.bind_level() — lets
## the player's PlaneComponent resolve ceiling-plane blocking without a
## NodePath wired in the .tscn.
func bind_level(level: Level) -> void:
	_level = level
	_plane.level = level


## Switches which class is active, live (dev tool Q — see World._cycle_class).
## Recomputes melee/web/hunger stats via refresh_upgrades() so repeated calls
## (cycling through all four) never compound — each call is relative to the
## untouched base, not the previous class's already-modified numbers. No-op
## (falls back to whatever was already active) if `spider_class` isn't a
## recognised id.
func apply_class(spider_class: int) -> void:
	var data: SpiderClassData = _class_data_by_id.get(spider_class)
	if data == null:
		return
	_active_class = spider_class
	_active_class_data = data
	refresh_upgrades()
	_update_sprite_tint()


## Whether `action`'s skill belongs to the currently active class. Sense and
## Remove Walls (general utilities) never go through this check at all.
func _is_active_skill(action: String) -> bool:
	var skills: Array = CLASS_SKILLS.get(_active_class, [])
	return action in skills


## The current class's two class-specific SkillComponents, keyed by their
## input action name in CLASS_SKILLS order — the seam ui/skill_bar.gd binds
## its two icons through.
func active_skills() -> Dictionary:
	var actions: Array = CLASS_SKILLS.get(_active_class, [])
	var result: Dictionary = {}
	for action in actions:
		var skill: SkillComponent = _skill_by_action.get(action)
		if skill != null:
			result[action] = skill
	return result


## Recomputes melee damage, web cooldown, hunger rate, and max health from
## their pristine _base_* values plus every purchased upgrade's effect
## (design §5), then the active class's multipliers on top — idempotent, so
## calling it again after a live purchase or a class switch never compounds
## on top of a previous call's result. GameState.purchased_upgrades is
## session-long, like the rest of GameState's dev-adjacent state.
func refresh_upgrades() -> void:
	var mult := _active_class_data.melee_damage_mult if _active_class_data != null else 1.0
	var fire_mult := _active_class_data.web_fire_rate_mult if _active_class_data != null else 1.0
	melee_damage = (_base_melee_damage + _upgrade_bonus("melee_damage")) * mult
	web_emitter.cooldown = maxf(0.05, (_base_web_cooldown + _upgrade_bonus("web_fire_rate")) / maxf(0.01, fire_mult))
	hunger.hunger_rate = maxf(0.1, _base_hunger_rate + _upgrade_bonus("hunger_rate"))
	health.set_max_health(GameState.DEFAULT_MAX_HEALTH + _upgrade_bonus("max_health"), false)


## `stat` is a plain String, matching UpgradeCatalog.effect_stat's own type
## exactly (an @export_enum String) — avoids any doubt about String vs.
## StringName comparison semantics.
func _upgrade_bonus(stat: String) -> float:
	var total := 0.0
	for id in GameState.purchased_upgrades:
		var upgrade := UpgradeRegistry.by_id(id)
		if upgrade != null and upgrade.effect_stat == stat:
			total += upgrade.effect_amount
	return total


## Attempts to buy the Nth authored upgrade (keys 1-4). Charges runes via
## GameState.buy_upgrade() (the only spend path); on success, refreshes this
## spider's stats immediately rather than waiting for the next level.
func _try_buy_upgrade(index: int) -> void:
	if index < 0 or index >= UpgradeRegistry.ALL.size():
		return
	var upgrade := UpgradeRegistry.ALL[index]
	if GameState.buy_upgrade(upgrade):
		refresh_upgrades()
		EventBus.upgrade_purchased.emit(upgrade.upgrade_id)


## Blocking seam for the GridMover: the noclip dev toggle passes through walls.
## On the ceiling plane, blocking is decided entirely by PlaneComponent (wall
## geometry only — pits/floods don't reach up there, design §1); there's no
## separate physical collider for the ceiling, so test_move against the
## ground's colliders would be the wrong check there. On the ground, a pit
## has no physical collider either (it's a MazeData-only overlay), so
## test_move alone can't see it — is_blocked(..., GROUND) is added as an
## *additional* blocking condition, on top of the original test_move check
## (unchanged), so ground movement's physics (traps, a stationary spider,
## dynamic obstacles) still behave exactly as before, now correctly blocked by
## a pit as well.
func _blocked(dir: Vector2i) -> bool:
	if GameState.noclip:
		return false
	if GridMover.spider_tile_contested(_mover, self, dir):
		return true
	if _level != null:
		var target := _level.tile_of(global_position) + dir
		if _plane.current_plane == Level.Layer.CEILING:
			return _level.is_blocked(target, Level.Layer.CEILING)
		if _level.is_blocked(target, Level.Layer.GROUND):
			return true
	return test_move(global_transform, Vector2(dir) * float(_mover.tile_size))


## Visual cue for which plane the player currently occupies — a dim,
## cool-toned tint on the ceiling, restored to normal on the ground.
func _on_plane_changed(_plane_arg: Level.Layer) -> void:
	_update_sprite_tint()


## The sprite's tint is the active class's color, dimmed/cooled by the
## ceiling tint on top when on the ceiling plane — the two effects compose
## instead of one clobbering the other.
func _update_sprite_tint() -> void:
	var base := _active_class_data.display_color if _active_class_data != null else Color.WHITE
	if _plane.current_plane == Level.Layer.CEILING:
		sprite.modulate = base * Color(0.55, 0.65, 0.85, 0.85)
	else:
		sprite.modulate = base


## Placeholder held-item indicator — a colored dot above the sprite, keyed
## by item_id via ConsumableItem.ITEM_COLORS. Sub-project I replaces this
## with real inventory UI.
func _draw() -> void:
	if inventory.held_item == null:
		return
	var color: Color = ConsumableItem.ITEM_COLORS.get(inventory.held_item.item_id, Color.WHITE)
	draw_circle(Vector2(0, -22), 5.0, color)


## SenseSkill (and FungusSenseItem) both just apply a timed "sense" tag on
## this component — this is where that tag actually does something: the
## Level's wall occluders stop blocking the player's vision light, so nearby
## structure/critters/hostiles show through a wall within light range (a
## local x-ray, not a full-map reveal — that's the separate darkness toggle).
func _on_effect_applied(id: StringName, _magnitude: float, _duration: float) -> void:
	if id == &"sense" and _level != null:
		_level.set_sense_active(true)
		_level.set_sense_outline(true)


func _on_effect_expired(id: StringName) -> void:
	if id == &"sense" and _level != null:
		_level.set_sense_active(false)
		_level.set_sense_outline(false)


## Strike one tile ahead: light damage + shove + stun on a spider, or an
## outright kill on a larva. The slash VFX always plays on a swing, even a
## whiff; hunger is only spent on a landed hit (the max-hunger fail-safe in
## charge_all drains health once starving).
func _melee() -> void:
	if _melee_left > 0.0:
		return
	_melee_left = melee_cooldown
	var push := _dominant_dir(facing)
	var target := global_position + facing * float(_mover.tile_size)
	CombatFx.spawn_slash(get_parent(), target, facing) # always shows, hit or miss
	for node in get_tree().get_nodes_in_group("spiders"):
		if node == self:
			continue
		var spider := node as Node2D
		if spider == null or spider.global_position.distance_to(target) > melee_range:
			continue
		var hurtbox := spider.get_node_or_null("Hurtbox") as Hurtbox
		if hurtbox != null:
			hurtbox.receive_hit(melee_damage, self)
		if spider.has_method("apply_web_hit"):
			spider.apply_web_hit(push, 1.0, 0.0, melee_stun) # shove + stun, no slow
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return
	for node in get_tree().get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva == null or larva.global_position.distance_to(target) > melee_range:
			continue
		if larva.has_method("web_kill"):
			larva.web_kill()
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return
	# Exact-tile lookup, not a distance threshold: melee_range (60px) also
	# reaches an orthogonally-adjacent tile (48px away), so with two
	# blockades placed side by side the old distance check matched both and
	# hit whichever the group happened to enumerate first — not necessarily
	# the one actually being swung at.
	var target_tile := _mover.committed_tile() + Vector2i(int(facing.x), int(facing.y))
	var blockade := Blockade.at_tile(get_tree(), target_tile, _mover.tile_size)
	if blockade != null:
		blockade.take_hit(facing)
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return
	for node in get_tree().get_nodes_in_group("earthworms"):
		var worm := node as Node2D
		if worm == null or worm.global_position.distance_to(target) > melee_range:
			continue
		if worm.has_method("take_hit"):
			worm.take_hit()
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return


## A step landed on a larva's tile — give a tiny visual shunt (juice only).
## Exact tile comparison rather than a pixel-distance threshold, so it can't
## be missed by any small position drift (e.g. right after a knockback/stun).
func _on_step_finished() -> void:
	var my_tile := _mover_tile_of(global_position)
	for node in get_tree().get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva != null and _mover_tile_of(larva.global_position) == my_tile:
			CombatFx.shunt(sprite, facing * 5.0)
			return


func _mover_tile_of(world: Vector2) -> Vector2i:
	var ts := float(_mover.tile_size)
	return Vector2i(int(floorf(world.x / ts)), int(floorf(world.y / ts)))


## Reduce analog movement input to one cardinal grid direction (ties -> x).
static func _dominant_dir(input: Vector2) -> Vector2i:
	if input.length_squared() < 0.04:
		return Vector2i.ZERO
	if absf(input.x) >= absf(input.y):
		return Vector2i(int(signf(input.x)), 0)
	return Vector2i(0, int(signf(input.y)))


## Take a landed web/melee hit: get shoved one tile along `push_dir`
## (Vector2i.ZERO = no shove), slowed, and stunned. Called by web shots, web
## traps, and melee strikes; symmetric across both spiders. No flash here —
## that's reserved for actual damage (see the HealthComponent.damaged hookup
## in _ready), since a pure web-crossing slow deals none.
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


## Snapshot vitals and the held item into GameState before the level is
## freed on descent.
func store_vitals() -> void:
	GameState.store_player_vitals(health.current_health, hunger.current_hunger)
	GameState.store_carried_item(inventory.held_item)


## health.max_health is already set by refresh_upgrades() (called via
## apply_class() earlier in _ready()) — this only restores current
## health/hunger against that already-upgrade-aware ceiling. The held item
## restores unconditionally (null is a valid, harmless "nothing held" value
## on a first spawn, unlike vitals' NAN-gated has_carried_vitals() check).
func _restore_vitals() -> void:
	if GameState.has_carried_vitals():
		health.current_health = clampf(GameState.carried_health, 0.0, health.max_health)
		hunger.current_hunger = clampf(GameState.carried_hunger, 0.0, hunger.max_hunger)
	else:
		health.current_health = health.max_health
		hunger.current_hunger = 0.0
	inventory.held_item = GameState.carried_item
	inventory.item_held_changed.emit(inventory.held_item)


func _on_health_changed(value: float, max_value: float) -> void:
	EventBus.health_changed.emit(self, value, max_value)


func _on_hunger_changed(value: float, max_value: float) -> void:
	EventBus.hunger_changed.emit(self, value, max_value)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	EventBus.player_died.emit()
