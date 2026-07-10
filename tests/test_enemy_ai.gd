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
