extends GutTest
## Enemy AI motivation pass: purposeful patrol (biased toward unexplored
## tiles), state stickiness between PATROL/SEEK_FOOD (FLEE/CHASE always
## override immediately), and fighting back when fully cornered in FLEE.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func after_each() -> void:
	GameState.freeze_enemy = false # don't leak into other tests


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(500, 500)
	return enemy


# --- purposeful patrol ---------------------------------------------------------

func test_tick_last_visited_defaults_to_minus_one_for_unvisited() -> void:
	var enemy := _make_enemy()
	assert_eq(enemy._tick_last_visited(Vector2i(3, 3)), -1)


func test_patrol_prefers_the_least_recently_visited_tile() -> void:
	var enemy := _make_enemy()
	var my_tile := enemy._tile_of(enemy.global_position)
	# Mark three directions as recently visited; leave RIGHT never-visited (-1),
	# which must sort as the most stale (most preferred) regardless of shuffle.
	enemy._patrol_tick = 10
	enemy._tile_last_visited[my_tile + Vector2i.UP] = 10
	enemy._tile_last_visited[my_tile + Vector2i.DOWN] = 9
	enemy._tile_last_visited[my_tile + Vector2i.LEFT] = 8
	enemy._do_patrol()
	assert_eq(enemy.facing, Vector2.RIGHT, "patrol steps toward the only unvisited tile")


func test_do_patrol_marks_its_own_tile_visited() -> void:
	var enemy := _make_enemy()
	var my_tile := enemy._tile_of(enemy.global_position)
	assert_eq(enemy._tick_last_visited(my_tile), -1)
	enemy._do_patrol()
	assert_ne(enemy._tick_last_visited(my_tile), -1, "patrolling through a tile marks it visited")


# --- state stickiness -----------------------------------------------------------

func test_idle_state_stays_locked_during_min_duration() -> void:
	var enemy := _make_enemy()
	enemy.hunger.current_hunger = 0.0 # well under hungry_fraction
	enemy._update_state()
	assert_eq(enemy.state, Enemy.State.PATROL)

	enemy.hunger.current_hunger = enemy.hunger.max_hunger # well over hungry_fraction
	enemy._update_state()
	assert_eq(enemy.state, Enemy.State.PATROL, "locked in for state_min_duration")


func test_idle_state_switches_once_the_lock_expires() -> void:
	var enemy := _make_enemy()
	enemy.hunger.current_hunger = 0.0
	enemy._update_state() # enters PATROL, starts the lock
	enemy.hunger.current_hunger = enemy.hunger.max_hunger
	enemy._state_lock_left = 0.0 # simulate the lock having elapsed
	enemy._update_state()
	assert_eq(enemy.state, Enemy.State.SEEK_FOOD)


func test_flee_overrides_the_idle_lock_immediately() -> void:
	var enemy := _make_enemy()
	enemy.hunger.current_hunger = 0.0
	enemy._update_state() # PATROL, locked
	enemy.health.current_health = enemy.health.max_health * 0.1 # below flee_health_fraction
	enemy._update_state()
	assert_eq(enemy.state, Enemy.State.FLEE, "an emergency flee is never delayed by the lock")


# --- fight back when cornered ---------------------------------------------------

func test_flee_fights_back_when_fully_cornered() -> void:
	var enemy := _make_enemy()
	var player := Node2D.new()
	player.add_to_group("player")
	player.global_position = enemy.global_position + Vector2(48, 0) # adjacent, in melee range
	add_child_autofree(player)
	enemy._player = player
	enemy._mover.block_check = func(_d: Vector2i) -> bool: return true # every direction blocked
	enemy.state = Enemy.State.FLEE
	enemy._do_flee()
	assert_gt(enemy._melee_left, 0.0, "a cornered enemy fights back instead of idling")


# --- Playtest Mode (dev tool 0) --------------------------------------------------

func test_freeze_enemy_halts_physics_process() -> void:
	var enemy := _make_enemy()
	GameState.freeze_enemy = true
	var repath_before := enemy._repath_left
	enemy._physics_process(1.0)
	assert_eq(enemy._repath_left, repath_before, "a demobilized enemy takes no physics step")


# --- Ceiling/plane mechanics rework -----------------------------------------------

func test_enemy_has_a_plane_component_defaulting_to_ground() -> void:
	var enemy := _make_enemy() # use this file's existing enemy-construction helper
	var plane := enemy.get_node_or_null("PlaneComponent") as PlaneComponent

	assert_not_null(plane, "Enemy gains a PlaneComponent (ceiling/plane mechanics rework)")
	assert_eq(plane.current_plane, Level.Layer.GROUND)


func test_enemy_climbs_to_match_a_target_on_the_ceiling_while_entering_chase() -> void:
	var enemy := _make_enemy()
	var target := Node2D.new()
	add_child_autofree(target)
	target.add_to_group("player")
	var target_plane := PlaneComponent.new()
	target_plane.name = "PlaneComponent" # runtime nodes aren't auto-named after class_name
	target.add_child(target_plane)
	target_plane.current_plane = Level.Layer.CEILING
	enemy._current_target = target

	enemy._match_plane_to(target)

	assert_eq(enemy._plane.current_plane, Level.Layer.CEILING)


func test_enemy_never_climbs_to_chase_a_plane_less_target() -> void:
	var enemy := _make_enemy()
	var decoy := Node2D.new() # no PlaneComponent -> always effective_plane() == GROUND
	add_child_autofree(decoy)

	enemy._match_plane_to(decoy)

	assert_eq(enemy._plane.current_plane, Level.Layer.GROUND)


func test_enemy_settles_back_to_ground_when_state_leaves_chase() -> void:
	var enemy := _make_enemy()
	enemy._plane.current_plane = Level.Layer.CEILING
	enemy.state = Enemy.State.PATROL
	enemy._current_target = null

	enemy._update_state()

	assert_eq(enemy._plane.current_plane, Level.Layer.GROUND, "not chasing anymore, so it climbs back down")


# --- pit crossing via the ceiling (patrol/food-seeking/flee can't otherwise
# reach anything past a pit with no ground-only detour, unlike the player) ---

func _make_bound_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_step_or_cross_pit_climbs_the_ceiling_and_settles_back_down_on_landing() -> void:
	var level := _make_bound_level()
	var enemy := _make_enemy()
	enemy.bind_level(level)
	var tile := enemy._tile_of(enemy.global_position)
	var target := tile + Vector2i.RIGHT
	level.dev_remove_wall_at(target) # guarantee it's open regardless of maze seed
	level.set_pit_at(target, true)

	assert_true(enemy._step_or_cross_pit(Vector2i.RIGHT), "climbs the ceiling to cross the pit")
	assert_eq(enemy._plane.current_plane, Level.Layer.CEILING, "mid-crossing, still up there")
	assert_true(enemy._crossing_pit)

	enemy._mover.tick(1.0) # finishes the crossing step -- fires step_finished
	assert_eq(enemy._plane.current_plane, Level.Layer.GROUND, "settles back down once landed")
	assert_false(enemy._crossing_pit)
	assert_eq(enemy._mover.committed_tile(), target, "actually ended up across the pit")


func test_step_or_cross_pit_never_climbs_for_a_plain_dead_end() -> void:
	var level := _make_bound_level()
	var enemy := _make_enemy()
	enemy.bind_level(level)
	var tile := enemy._tile_of(enemy.global_position)
	# A direction that's simply blocked (no pit at all) must never trigger a
	# climb -- only a pit specifically is crossable via the ceiling.
	enemy._mover.block_check = func(_d: Vector2i) -> bool: return true

	assert_false(enemy._step_or_cross_pit(Vector2i.RIGHT), "nothing to climb over here")
	assert_eq(enemy._plane.current_plane, Level.Layer.GROUND, "never climbed")
	assert_eq(enemy._tile_of(enemy.global_position), tile, "never moved")


func test_step_or_cross_pit_steps_normally_when_nothing_blocks_it() -> void:
	var enemy := _make_enemy()
	# Isolates _step_or_cross_pit()'s delegation behavior from real physics
	# entirely (unlike the pit/dead-end tests above, this one doesn't care
	# *why* a step succeeds) -- a freshly-added CharacterBody2D's test_move()
	# isn't reliable before the physics server has run a frame, which a
	# synchronous GUT test never does.
	enemy._mover.block_check = func(_d: Vector2i) -> bool: return false

	assert_true(enemy._step_or_cross_pit(Vector2i.RIGHT), "an ordinary open tile just steps normally")
	assert_eq(enemy._plane.current_plane, Level.Layer.GROUND, "no reason to ever leave the ground")
	assert_false(enemy._crossing_pit)
