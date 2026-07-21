class_name Enemy
extends CharacterBody2D
## The rival spider. A data-driven EnemyType sets base stats; depth scales them.
## An enum FSM drives behaviour — patrol / seek_food / chase / flee — stepping
## on the maze grid via GridMover. Chase and food-seeking path with the level's
## AStarGrid2D; patrol and flee step greedily. It hungers like the player, eats
## larvae by contact, and can be starved out as well as killed.

enum State { PATROL, SEEK_FOOD, CHASE, FLEE }

@export var enemy_type: EnemyType

## Behaviour tuning (design §10 — feel these out in playtest).
@export var vision_range: float = 240.0
@export var attack_range: float = 200.0
@export var flee_health_fraction: float = 0.3
@export var hungry_fraction: float = 0.6
@export var repath_interval: float = 0.35
## Minimum time to stay in PATROL or SEEK_FOOD before switching between them,
## so hunger hovering right at hungry_fraction doesn't flicker every frame.
## FLEE and CHASE always override immediately regardless — an emergency flee
## or spotting the player should never be delayed by "stickiness".
@export var state_min_duration: float = 1.5
## Distance at which the enemy eats a larva by contact.
@export var eat_range: float = 30.0
## Hunger removed by eating one larva.
@export var eat_satiation: float = 40.0
## Close-quarters strike when it catches the player: damage + shove + stun.
@export var melee_range: float = 56.0
@export var melee_damage: float = 12.0
@export var melee_stun: float = 0.3
@export var melee_cooldown: float = 0.6
## Hunger added to every spider per swing (charge_all's max-hunger fail-safe
## drains health instead once a spider is already starving).
@export var melee_hunger_cost: float = 5.0
## Seconds between the enemy laying web traps while hunting food.
@export var trap_interval: float = 5.0

## Class kit (design §2/§3): each enemy rolls one of the four classes at
## spawn — independent per spawn, not persisted across depths like
## GameState.selected_class is for the player — and scales melee/web stats
## the same way Player.apply_class() does.
const NetCasterData: SpiderClassData = preload("res://resources/spiders/net_caster.tres")
const WolfData: SpiderClassData = preload("res://resources/spiders/wolf.tres")
const WeaverData: SpiderClassData = preload("res://resources/spiders/weaver.tres")
const DecoyClassData: SpiderClassData = preload("res://resources/spiders/decoy.tres")

const NetShotScene := preload("res://entities/skills/scenes/net_shot.tscn")
const TinySpiderlingScene := preload("res://entities/skills/scenes/tiny_spiderling.tscn")
const CocoonMineScene := preload("res://entities/skills/scenes/cocoon_mine.tscn")
const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")
const DecoyPropScene := preload("res://entities/skills/scenes/decoy.tscn")
const WebTrapScene := preload("res://entities/web/web_trap.tscn")

## How often the enemy reconsiders using a skill (design §2/§3) — a skill's
## own cooldown already prevents spamming once chosen; this only paces the
## *decision* itself so it isn't re-evaluated every single physics frame.
const SKILL_DECISION_INTERVAL := 0.75

@onready var health: HealthComponent = $HealthComponent
@onready var hunger: HungerComponent = $HungerComponent
@onready var web_emitter: WebEmitter = $WebEmitter
@onready var trap_placer: TrapPlacer = $TrapPlacer
@onready var _mover: GridMover = $GridMover
@onready var _plane: PlaneComponent = $PlaneComponent
@onready var facing_visual: Node2D = get_node_or_null("Sprite")

var state: State = State.PATROL

var _player: Node2D
## Whichever spider CHASE is actually pursuing right now — the real player,
## or a closer visible Decoy (design §3: Decoy diverts aggro). Re-picked by
## _acquire_target() every _update_state() tick; only meaningful in CHASE —
## FLEE/_fight_back() always react to the real player specifically, since
## fleeing from (or striking back at) a harmless decoy prop makes no sense.
var _current_target: Node2D
var _level: Node
var _repath_left := 0.0
var facing := Vector2.RIGHT
var _dead := false
var _path: Array[Vector2i] = []
var _path_i := 0
var _melee_left := 0.0
var _trap_left := 0.0
var _state_lock_left := 0.0
## Tile -> the _patrol_tick it was last patrolled through, so patrol can bias
## toward unexplored ground instead of a pure random walk. A monotonic step
## counter rather than wall-clock time, so it's deterministic and testable.
var _tile_last_visited: Dictionary = {}
var _patrol_tick := 0
## True while the enemy has deliberately climbed to the ceiling for exactly
## one step to bypass a pit blocking its ground path (see
## _step_or_cross_pit()) -- suppresses _update_state()'s own "always settle
## back to ground unless chasing" rule until that one step actually lands,
## so the climb isn't undone before it's used.
var _crossing_pit := false
var active_class: int = SpiderClassData.SpiderClass.WOLF
var _class_data_by_id: Dictionary = {}
var _active_class_data: SpiderClassData
var _skills: Array[SkillComponent] = []
var _skill_decision_left := 0.0
var _base_melee_damage: float
var _base_web_cooldown: float


## Level calls this right after instancing so the enemy can path on the grid.
func bind_level(level: Node) -> void:
	_level = level
	_plane.level = level


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("enemy")
	_apply_type()
	_mover.block_check = _blocked
	# The enemy starts in PATROL without ever "transitioning" into it, so the
	# idle-state lock (normally armed by _update_state on a state change) needs
	# arming here too, or the very first hunger check would ignore it.
	_state_lock_left = state_min_duration
	health.died.connect(_on_died)
	# Distress flash is reserved for actually being hurt — never for a status
	# effect like a web's slow, which deals no damage.
	health.damaged.connect(func(_amount: float) -> void: CombatFx.flash(facing_visual))
	health.health_changed.connect(_on_health_changed)
	hunger.hunger_changed.connect(_on_hunger_changed)
	# Prime the HUD with this instance's depth-scaled starting vitals (a fresh
	# enemy is spawned each depth, so the HUD needs a fresh snapshot every time).
	EventBus.health_changed.emit(self, health.current_health, health.max_health)
	EventBus.hunger_changed.emit(self, hunger.current_hunger, hunger.max_hunger)
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_class_data_by_id = {
		SpiderClassData.SpiderClass.NET_CASTER: NetCasterData,
		SpiderClassData.SpiderClass.WOLF: WolfData,
		SpiderClassData.SpiderClass.WEAVER: WeaverData,
		SpiderClassData.SpiderClass.DECOY: DecoyClassData,
	}
	_base_melee_damage = melee_damage
	_base_web_cooldown = web_emitter.cooldown
	_apply_class(randi() % 4)


func _on_health_changed(value: float, max_value: float) -> void:
	EventBus.health_changed.emit(self, value, max_value)


func _on_hunger_changed(value: float, max_value: float) -> void:
	EventBus.hunger_changed.emit(self, value, max_value)


## Blocking seam for the GridMover: checks a tile the player has already
## committed to (mid-step, not just physically standing on) before falling
## back to the body's own physics (walls, traps, a stationary spider).
## Ceiling/plane mechanics rework: mirrors Player._blocked()'s plane branch —
## on the ceiling, blocking is decided entirely by Level.is_blocked (no
## separate physical collider up there); on the ground, is_blocked() adds
## the pit check on top of the existing test_move physics check.
func _blocked(dir: Vector2i) -> bool:
	if GridMover.spider_tile_contested(_mover, self, dir):
		return true
	if _level != null:
		# _level is typed loosely as Node (unlike Player._level: Level), so an
		# explicit Vector2i annotation is needed here — `:=` can't infer a type
		# through Node's dynamically-resolved tile_of() call.
		var target: Vector2i = _level.tile_of(global_position) + dir
		if _plane.current_plane == Level.Layer.CEILING:
			return _level.is_blocked(target, Level.Layer.CEILING)
		if _level.is_blocked(target, Level.Layer.GROUND):
			return true
	if GridMover.tile_shared_with_another(_mover, self):
		return false # already overlapping someone here -- always escapable on foot
	return test_move(global_transform, Vector2(dir) * float(_mover.tile_size))


func _apply_type() -> void:
	var depth_mult := GameState.depth_scale()
	if enemy_type != null:
		health.max_health = enemy_type.max_health * depth_mult
		hunger.hunger_rate = enemy_type.hunger_rate * depth_mult
	else:
		health.max_health *= depth_mult
	health.current_health = health.max_health


## Rolls this enemy's class: scales melee/web stats from the base values
## snapshotted at _ready() and attaches its two skills. Mirrors
## Player.apply_class() so class differentiation feels consistent across
## both spiders, but this is a fresh roll every spawn — not a persisted dev
## preference like GameState.selected_class.
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
	_update_sprite_frame()
	for skill in _skills:
		skill.queue_free()
	_skills = _make_skills(spider_class)
	for skill in _skills:
		add_child(skill)
	EventBus.enemy_class_changed.emit(spider_class)


## The two skill instances for `spider_class`, with their scene dependencies
## wired the same way player.tscn wires each one's.
func _make_skills(spider_class: int) -> Array[SkillComponent]:
	match spider_class:
		SpiderClassData.SpiderClass.NET_CASTER:
			var hold := NetHoldSkill.new()
			var shot := NetShotSkill.new()
			shot.net_shot_scene = NetShotScene
			shot.net_hold = hold
			# Free to fire, same as Player's NetShotSkill (player.tscn): Net
			# Hold already charges the real engagement fee to arm a trap;
			# discharging it costs nothing extra.
			shot.cooldown = 0.0
			shot.hunger_cost = 0.0
			return [hold, shot]
		SpiderClassData.SpiderClass.WEAVER:
			var blockade := BlockadeSkill.new()
			blockade.blockade_scene = BlockadeScene
			var silk := SilkTunnelSkill.new()
			silk.trap_scene = WebTrapScene
			return [blockade, silk]
		SpiderClassData.SpiderClass.DECOY:
			var decoy := DecoySkill.new()
			decoy.decoy_scene = DecoyPropScene
			return [CamouflageSkill.new(), decoy]
		_: # WOLF
			var hatch := HatchlingsSkill.new()
			hatch.hatchling_scene = TinySpiderlingScene
			var mine := EggMineSkill.new()
			mine.mine_scene = CocoonMineScene
			return [hatch, mine]


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if GameState.freeze_others or GameState.freeze_enemy: # dev freeze (J) or playtest mode (0)
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D

	_update_state()

	_repath_left -= delta
	_melee_left = maxf(0.0, _melee_left - delta)
	_trap_left = maxf(0.0, _trap_left - delta)
	_state_lock_left = maxf(0.0, _state_lock_left - delta)
	_skill_decision_left -= delta
	if _skill_decision_left <= 0.0:
		_skill_decision_left = SKILL_DECISION_INTERVAL
		_consider_using_a_skill()
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
	_melee_nearby_centipede()


func _update_state() -> void:
	var next := state
	var target := _acquire_target()
	if health.fraction() <= flee_health_fraction:
		next = State.FLEE
	elif target != null:
		_current_target = target
		next = State.CHASE
	elif state == State.PATROL or state == State.SEEK_FOOD:
		# Only these two idle states are sticky against each other — a low-health
		# flee or spotting a target (above) always overrides immediately.
		if _state_lock_left > 0.0:
			next = state
		else:
			next = State.SEEK_FOOD if hunger.fraction() >= hungry_fraction else State.PATROL
	else:
		next = State.SEEK_FOOD if hunger.fraction() >= hungry_fraction else State.PATROL

	if next != state:
		state = next
		_repath_left = 0.0
		_path = []
		if next == State.PATROL or next == State.SEEK_FOOD:
			_state_lock_left = state_min_duration

	if next == State.CHASE and _current_target != null:
		_match_plane_to(_current_target)
	elif _plane.current_plane == Level.Layer.CEILING and not _crossing_pit:
		_plane.transition() # settle back to ground: not actively chasing anymore


# --- per-state behaviour ------------------------------------------------------

## Fires along `direction` with the active class's projectile-speed
## multiplier, then charges its fire-health-cost (Decoy) if any — shared by
## both _do_chase() and _fight_back() so the class-multiplier/health-cost
## logic lives in exactly one place.
func _fire_web(direction: Vector2) -> void:
	var speed_mult := _active_class_data.web_projectile_speed_mult if _active_class_data != null else 1.0
	var shot := web_emitter.fire(global_position, direction, self, speed_mult)
	if shot != null and _active_class_data != null and _active_class_data.web_fire_health_cost > 0.0:
		health.take_damage(_active_class_data.web_fire_health_cost)


## Ceiling/plane mechanics rework: the enemy only ever climbs to match a
## target's plane while actively chasing it (called from _update_state()),
## and always settles back to ground the instant it isn't chasing (see the
## call site above) — the minimum that makes same-plane combat meaningful.
## A target with no PlaneComponent (a Decoy) is always effective_plane()
## GROUND, so the enemy never climbs to "chase" a decoy prop. Instant
## transition, matching the existing Player.toggle_plane precedent exactly —
## no climb-reaction delay (design's explicit out-of-scope call).
func _match_plane_to(target: Node2D) -> void:
	if PlaneComponent.effective_plane(target) != _plane.current_plane:
		_plane.transition()


## Steps `dir` normally; if that's blocked specifically by a pit (not a
## wall) while the enemy is on the ground, climbs to the ceiling for exactly
## this one step instead — pits don't reach up there at all (design §1), so
## the same tile is always open from above — then settles back to the
## ground the instant that step lands. Without this, patrol/food-seeking/
## fleeing could never cross a pit with no ground-only detour, leaving
## whatever's past it permanently unreachable even though the player can
## just climb over the same pit. CHASE benefits too via _follow_path(), but
## never conflicts with _match_plane_to()'s own ceiling use: that already
## puts the enemy on whichever plane the target occupies, so this helper's
## GROUND-only guard below simply never triggers while already up there.
func _step_or_cross_pit(dir: Vector2i) -> bool:
	if _mover.try_step(dir):
		return true
	if _plane.current_plane != Level.Layer.GROUND or _level == null:
		return false
	var target: Vector2i = _tile_of(global_position) + dir
	if not _level.maze.is_pit(target.x, target.y):
		return false
	_crossing_pit = true
	_plane.transition()
	if not _mover.try_step(dir):
		# Something else (e.g. a ceiling-side obstacle) still blocks it --
		# bail back to the ground immediately rather than getting stuck up
		# there for no reason.
		_plane.transition()
		_crossing_pit = false
		return false
	_mover.step_finished.connect(func() -> void:
		_plane.transition()
		_crossing_pit = false
	, CONNECT_ONE_SHOT)
	return true


func _do_chase() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		return
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(_current_target.global_position))
		_repath_left = repath_interval
	_follow_path()
	var to_target := _current_target.global_position - global_position
	if to_target.length() <= melee_range:
		_melee_target(_current_target, to_target)
	elif to_target.length() <= attack_range and _web_enabled() and _has_line_of_sight(_current_target.global_position):
		_fire_web(to_target)


func _do_seek_food() -> void:
	var larva := _nearest_in_group("larvae")
	if larva == null:
		_do_patrol()
		return
	if global_position.distance_to(larva.global_position) <= eat_range:
		_eat_larva(larva)
		return
	# Lay a web across its own tile now and then — a placed web catches wandering
	# larvae on the enemy's behalf (feeding it) even when it can't chase them all.
	if _trap_left <= 0.0 and not _mover.is_moving() and trap_placer.can_place():
		trap_placer.place(global_position, self, _plane.current_plane)
		_trap_left = trap_interval
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(larva.global_position))
		_repath_left = repath_interval
	_follow_path()


## Strike `target` (the real player, or a Decoy that diverted CHASE) in close
## quarters: damage, a shove away, a stun, a flash. Costs hunger to swing
## (charge_all's max-hunger fail-safe drains health once the enemy is already
## starving). Works unmodified against a Decoy: it carries the same
## Hurtbox/apply_web_hit contract every real spider does.
func _melee_target(target: Node2D, to_target: Vector2) -> void:
	if _melee_left > 0.0 or target == null:
		return
	_melee_left = melee_cooldown
	HungerComponent.charge_all(get_tree(), melee_hunger_cost)
	var hurtbox := target.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.receive_hit(melee_damage, self)
	if target.has_method("apply_web_hit"):
		target.apply_web_hit(_dominant(to_target), 1.0, 0.0, melee_stun)
	CombatFx.spawn_slash(get_parent(), target.global_position, to_target)


## Run from the player; if truly cornered (no escape tile at all) turn and
## fight instead of standing there uselessly — the moment you actually corner
## a fleeing enemy should be a decisive one, not an anticlimax.
func _do_flee() -> void:
	if _mover.is_moving():
		return
	var away := (global_position - _player.global_position) if _player != null else Vector2.RIGHT
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var dir := _dominant(away)
	if _step_or_cross_pit(dir):
		_face(dir)
		return
	var perpendicular := _dominant(Vector2(away.y, -away.x))
	if _step_or_cross_pit(perpendicular):
		_face(perpendicular)
		return
	_fight_back()


## No escape route this frame: attack like CHASE would, instead of idling.
## Always the real player specifically — FLEE is triggered by low health
## against a genuine threat, so cornered-and-fighting-back never targets a
## harmless Decoy prop even if CHASE had been diverted to one beforehand.
func _fight_back() -> void:
	if _player == null:
		return
	var to_player := _player.global_position - global_position
	if to_player.length() <= melee_range:
		_melee_target(_player, to_player)
	elif to_player.length() <= attack_range and _web_enabled() and _has_line_of_sight(_player.global_position):
		_fire_web(to_player)


func _web_enabled() -> bool:
	return _active_class_data == null or _active_class_data.web_enabled


# --- class skills (AI) --------------------------------------------------------

## Utility-scores each owned skill against a "do nothing extra" baseline
## (design §2/§3): EnemyUtilityAI.best() picks the highest scorer.
## depth_intel biases willingness upward at deeper levels — never a
## stat/damage change, just how eagerly the enemy reaches for its kit
## (guardrail: intelligence scaling alone can't compound into an unfair
## fight — health/damage stay solely on EnemyType/depth_scale()).
func _consider_using_a_skill() -> void:
	if _skills.is_empty():
		return
	var intel := EnemyUtilityAI.depth_intel(GameState.depth)
	var candidates: Array[EnemyUtilityAI.Candidate] = [
		EnemyUtilityAI.Candidate.new(EnemyUtilityAI.Action.PATROL, 0.35), # baseline: nothing extra
	]
	for skill in _skills:
		if not skill.can_activate():
			continue
		var base_score := _score_skill(skill)
		if base_score <= 0.0:
			continue
		candidates.append(EnemyUtilityAI.Candidate.new(
			EnemyUtilityAI.Action.USE_SKILL, base_score * (0.5 + 0.5 * intel), {"skill": skill}))
	var winner := EnemyUtilityAI.best(candidates)
	if winner != null and winner.action == EnemyUtilityAI.Action.USE_SKILL:
		(winner.context["skill"] as SkillComponent).activate(self)


## Simple, class-agnostic heuristics for whether each owned skill is worth
## using right now, grouped by the state it makes sense in — combat skills
## during an active CHASE, defensive/escape skills while FLEEing, and
## NetHold (harvesting) during SEEK_FOOD. Deliberately kept on Enemy, not
## SkillComponent, so skill scripts stay usable by any spider — player or
## enemy — without carrying AI-specific concerns.
func _score_skill(skill: SkillComponent) -> float:
	if skill is NetHoldSkill:
		return 0.7 if state == State.SEEK_FOOD and _nearest_pickupable_trap() != null else 0.0
	if skill is NetShotSkill:
		return 0.6 if state == State.CHASE and _current_target != null \
				and (skill as NetShotSkill).net_hold.is_holding() else 0.0
	if skill is HatchlingsSkill or skill is EggMineSkill or skill is SilkTunnelSkill:
		return 0.6 if state == State.CHASE and _current_target != null else 0.0
	if skill is BlockadeSkill or skill is CamouflageSkill or skill is DecoySkill:
		return 0.6 if state == State.FLEE else 0.0
	return 0.0


## An unspent trap within easy reach — laid by anyone, ownership doesn't
## gate pickup — worth a Net Hold pickup whether or not it's already caught a
## larva (a pre-loaded trap is auto-eaten on pickup, so there's no special
## case for that here).
func _nearest_pickupable_trap() -> WebTrap:
	for node in get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap != null and not trap.spent \
				and global_position.distance_to(trap.global_position) <= eat_range * 2.0:
			return trap
	return null


## Sweeps toward unexplored ground instead of a pure random walk: candidate
## tiles are tried least-recently-visited first (never-visited sorts first of
## all), falling back down the list if the preferred direction is blocked.
func _do_patrol() -> void:
	if _mover.is_moving():
		return
	var my_tile := _tile_of(global_position)
	_patrol_tick += 1
	_tile_last_visited[my_tile] = _patrol_tick
	var options: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	options.shuffle() # random tie-break among equally-stale (e.g. never-visited) candidates
	options.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _tick_last_visited(my_tile + a) < _tick_last_visited(my_tile + b))
	for d in options:
		if _step_or_cross_pit(d):
			_face(d)
			return


func _tick_last_visited(tile: Vector2i) -> int:
	return _tile_last_visited.get(tile, -1)


# --- grid path following ------------------------------------------------------

func _set_path_to(target_tile: Vector2i) -> void:
	if _level == null:
		_path = []
		return
	_path = _level.path_tiles(_tile_of(global_position), target_tile)
	_path_i = 0


## _step_or_cross_pit() here is mostly defensive, not a full fix for CHASE/
## SEEK_FOOD: the AStarGrid2D this path was computed from already marks
## every pit tile solid (GridNav.build()), so a normal path never routes
## across one in the first place — a target genuinely reachable only via a
## ceiling crossing still needs a dual-plane-aware pathfinder, which is a
## bigger job than this fix. This only helps a tile that turned into a pit
## *after* the path was computed (e.g. mid-chase flooding/collapse).
func _follow_path() -> void:
	if _mover.is_moving() or _path.is_empty() or _path_i >= _path.size():
		return
	var my_tile := _tile_of(global_position)
	var dir := _step_dir(my_tile, _path[_path_i])
	if dir == Vector2i.ZERO:
		_path_i += 1
		return
	if _step_or_cross_pit(dir):
		_face(dir)
		_path_i += 1
	else:
		_path = [] # blocked (e.g. a trap dropped in the lane) — repath next tick


## Clamped unit step from `from` toward `to` (cardinal; ties favour x).
static func _step_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


func _dominant(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


func _face(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	facing = Vector2(dir)
	_update_sprite_frame()


## Swaps in the active class's baked directional frame matching `facing`
## instead of rotating a single sprite (docs/art-bible.md §2's 2026-07-21
## revision) -- mirrors Player._update_sprite_frame(). Called whenever
## `facing` changes and whenever the active class changes, so the two never
## fall out of sync with each other.
func _update_sprite_frame() -> void:
	if facing_visual == null or not (facing_visual is Sprite2D) or _active_class_data == null:
		return
	var sprite := facing_visual as Sprite2D
	var frame := _active_class_data.frame_for_facing(facing)
	if frame != null:
		sprite.texture = frame
	sprite.rotation = 0.0


func _tile_of(world: Vector2) -> Vector2i:
	if _level != null:
		return _level.tile_of(world)
	return Vector2i(int(world.x / 48.0), int(world.y / 48.0))


# --- eating -------------------------------------------------------------------

## Uses the larva's own growth-scaled heal_value() (design §2) when it has
## one — falls back to the flat eat_satiation for a bare test double.
func _eat_larva(larva: Node) -> void:
	if not larva.is_in_group("larvae"):
		return
	var heal_amount: float = larva.heal_value() if larva.has_method("heal_value") else eat_satiation
	var overflow := hunger.satiate(heal_amount)
	EventBus.larva_consumed.emit(self, overflow)
	larva.queue_free()


# --- perception ---------------------------------------------------------------

## Whichever of {the real player, any visible Decoy} is nearest right now —
## the actual "divert aggro" mechanic (design §3): a Decoy placed closer than
## the player wins the contest even while the player is also visible, not
## just as a fallback once the player is hidden/camouflaged. Returns null if
## neither is currently visible. _update_state() stores the result in
## _current_target for CHASE to act on.
func _acquire_target() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	if _can_see_player():
		best = _player
		best_dist = global_position.distance_to(_player.global_position)
	var decoy := _nearest_visible_decoy(best_dist)
	if decoy != null:
		best = decoy
	return best


## Nearest node in the "decoys" group within vision_range and line-of-sight,
## strictly closer than `closer_than` (so a farther decoy never displaces an
## already-closer player). Returns null if none qualify.
func _nearest_visible_decoy(closer_than: float = INF) -> Node2D:
	var best: Node2D = null
	var best_dist := closer_than
	for node in get_tree().get_nodes_in_group("decoys"):
		var decoy := node as Node2D
		if decoy == null or not is_instance_valid(decoy):
			continue
		var d := global_position.distance_to(decoy.global_position)
		if d >= best_dist or d > vision_range:
			continue
		if not _has_line_of_sight(decoy.global_position):
			continue
		best = decoy
		best_dist = d
	return best


## Vision alone decides whether the real player is a CHASE candidate (design
## §3 guardrail: Camouflage breaks on any attack, but while it holds, it
## should actually work — a camouflaged player is invisible to this check
## regardless of range/line-of-sight). A patrolling enemy never enters CHASE
## against a hidden player in the first place, and an active CHASE drops back
## to SEEK_FOOD/PATROL the moment camouflage goes up, *unless* a visible
## Decoy is still around to hold its attention instead (see _acquire_target).
func _can_see_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player_is_camouflaged():
		return false
	if global_position.distance_to(_player.global_position) > vision_range:
		return false
	return _has_line_of_sight(_player.global_position)


func _player_is_camouflaged() -> bool:
	if _player == null:
		return false
	var camo := _player.get_node_or_null("CamouflageSkill") as CamouflageSkill
	return camo != null and camo.active


func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos, 1) # world layer
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _nearest_in_group(group: String) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(group):
		var n := node as Node2D
		if n == null:
			continue
		var d := global_position.distance_squared_to(n.global_position)
		if d < best_dist:
			best_dist = d
			best = n
	return best


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


## Opportunistic strike, mirroring _melee_nearby_hatchling() but for a
## Centipede: Player._melee() already hits a Centipede via an exact-tile
## lookup (the tile directly ahead, same as its existing Blockade check)
## because neither carries a Hurtbox _melee_target() could reach -- Enemy
## needs the identical tile-based check, not the distance-based one
## _melee_nearby_hatchling() uses.
func _melee_nearby_centipede() -> void:
	if _melee_left > 0.0:
		return
	var target_tile := _mover.committed_tile() + Vector2i(int(facing.x), int(facing.y))
	var centipede := Centipede.segment_at_tile(get_tree(), target_tile)
	if centipede == null:
		return
	_melee_left = melee_cooldown
	centipede.hit_segment_at(target_tile, facing)
	HungerComponent.charge_all(get_tree(), melee_hunger_cost)


## Take a landed web/melee hit: get shoved one tile along `push_dir`
## (Vector2i.ZERO = no shove), slowed, and stunned. Mirrors the player's
## reaction so combat is symmetric. No flash here — that's reserved for actual
## damage (see the HealthComponent.damaged hookup in _ready), since a pure
## web-crossing slow deals none.
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


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	var cause := "starved" if hunger.is_starving() else "killed"
	EventBus.enemy_defeated.emit(cause)
	queue_free()
