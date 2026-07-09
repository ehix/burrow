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

var facing := Vector2.RIGHT
var _dead := false
var _melee_left := 0.0
var _level: Level


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("player")
	# Route blocking through the player so the dev noclip toggle can bypass it.
	_mover.block_check = _blocked
	_mover.step_finished.connect(_on_step_finished)
	_plane.plane_changed.connect(_on_plane_changed)
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

	if Input.is_action_pressed("fire"):
		web_emitter.fire(global_position, facing, self)
	if Input.is_action_just_pressed("place_trap"):
		trap_placer.place(global_position, self)
	if Input.is_action_just_pressed("melee"):
		_melee()
	if Input.is_action_just_pressed("toggle_plane"):
		_plane.transition()
	if Input.is_action_just_pressed("camouflage"):
		_camouflage.activate(self)


## Called by Level right after instancing, mirroring Enemy.bind_level() — lets
## the player's PlaneComponent resolve ceiling-plane blocking without a
## NodePath wired in the .tscn.
func bind_level(level: Level) -> void:
	_level = level
	_plane.level = level


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
func _on_plane_changed(plane: Level.Layer) -> void:
	sprite.modulate = Color(0.55, 0.65, 0.85, 0.85) if plane == Level.Layer.CEILING else Color.WHITE


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
	if factor < 1.0:
		_mover.apply_slow(factor, slow_duration)
	if stun_duration > 0.0:
		_mover.stun(stun_duration)


## Snapshot vitals into GameState before the level is freed on descent.
func store_vitals() -> void:
	GameState.store_player_vitals(health.current_health, hunger.current_hunger)


func _restore_vitals() -> void:
	health.max_health = GameState.DEFAULT_MAX_HEALTH
	if GameState.has_carried_vitals():
		health.current_health = clampf(GameState.carried_health, 0.0, health.max_health)
		hunger.current_hunger = clampf(GameState.carried_hunger, 0.0, hunger.max_hunger)
	else:
		health.current_health = health.max_health
		hunger.current_hunger = 0.0


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
