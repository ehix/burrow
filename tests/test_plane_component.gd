extends GutTest
## PlaneComponent's shared static helpers (ceiling/plane mechanics rework):
## effective_plane()/same_plane() default anything without a PlaneComponent
## to GROUND, and apply_hit_fall() is the knockdown-plus-fall-damage penalty
## for getting hit while on the ceiling.

func _make_owner_with_plane(plane: Level.Layer = Level.Layer.GROUND) -> Node2D:
	var owner := Node2D.new()
	add_child_autofree(owner)
	var plane_comp := PlaneComponent.new()
	# A runtime-created node isn't auto-named after its class_name (that only
	# happens for nodes placed in a .tscn) — effective_plane() looks it up as
	# "PlaneComponent" by name, exactly like player.tscn/enemy.tscn wire it,
	# so the test double must match that name too.
	plane_comp.name = "PlaneComponent"
	owner.add_child(plane_comp)
	plane_comp.current_plane = plane
	return owner


func test_effective_plane_defaults_to_ground_without_a_plane_component() -> void:
	var owner := Node2D.new()
	add_child_autofree(owner)

	assert_eq(PlaneComponent.effective_plane(owner), Level.Layer.GROUND)


func test_effective_plane_defaults_to_ground_for_null() -> void:
	assert_eq(PlaneComponent.effective_plane(null), Level.Layer.GROUND)


func test_effective_plane_reads_the_plane_component_when_present() -> void:
	var owner := _make_owner_with_plane(Level.Layer.CEILING)

	assert_eq(PlaneComponent.effective_plane(owner), Level.Layer.CEILING)


func test_same_plane_true_when_both_ground_by_default() -> void:
	var a := Node2D.new()
	var b := Node2D.new()
	add_child_autofree(a)
	add_child_autofree(b)

	assert_true(PlaneComponent.same_plane(a, b))


func test_same_plane_false_when_planes_differ() -> void:
	var a := _make_owner_with_plane(Level.Layer.GROUND)
	var b := _make_owner_with_plane(Level.Layer.CEILING)

	assert_false(PlaneComponent.same_plane(a, b))


func test_apply_hit_fall_transitions_to_ground_and_deals_fall_damage_from_ceiling() -> void:
	var plane_comp := PlaneComponent.new()
	add_child_autofree(plane_comp)
	plane_comp.current_plane = Level.Layer.CEILING
	plane_comp.fall_damage = 8.0
	var health := HealthComponent.new()
	health.max_health = 100.0
	add_child_autofree(health)
	health.current_health = 50.0

	plane_comp.apply_hit_fall(health)

	assert_eq(plane_comp.current_plane, Level.Layer.GROUND, "knocked down to the ground")
	assert_almost_eq(health.current_health, 42.0, 0.001, "eats the bonus fall-damage tick")


func test_apply_hit_fall_is_a_noop_while_already_on_the_ground() -> void:
	var plane_comp := PlaneComponent.new()
	add_child_autofree(plane_comp)
	plane_comp.current_plane = Level.Layer.GROUND
	var health := HealthComponent.new()
	health.max_health = 100.0
	add_child_autofree(health)
	health.current_health = 50.0

	plane_comp.apply_hit_fall(health)

	assert_eq(plane_comp.current_plane, Level.Layer.GROUND)
	assert_almost_eq(health.current_health, 50.0, 0.001, "no extra damage from the ground")


## Playtest fix: a ground spider and a ceiling spider never contest a tile
## (GridMover.spider_tile_contested), but transition() swaps the owner's
## plane *in place* — landing it on a tile another spider already occupies
## on that same plane, an overlap nothing previously prevented. Reuses
## GridMover.knockback() (see Centipede.shove_spiders_out_of for the same
## primitive) rather than blocking the transition outright.
func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_transition_shoves_the_other_spider_off_the_landing_tile() -> void:
	var level := _make_level()
	var tile := level.tile_of(level.player.global_position)
	# Guarantee an open cardinal neighbor regardless of maze seed, so the
	# shove always has somewhere to land.
	level.maze.set_open(tile.x + 1, tile.y)

	level.enemy.global_position = level.player.global_position
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent
	enemy_plane.current_plane = Level.Layer.CEILING

	enemy_plane.transition() # CEILING -> GROUND, landing on the player's tile

	var player_mover := level.player.get_node("GridMover") as GridMover
	assert_ne(player_mover.committed_tile(), tile,
		"the player got shoved off the tile the enemy just landed on")


## Bare spider double (mirrors test_grid_mover.gd's own _make_spider): a
## plain Node2D + unblocked GridMover (no block_check, no PhysicsBody2D
## parent, so _is_blocked() always reports clear -- see GridMover._is_blocked)
## plus a PlaneComponent, so this exercises PlaneComponent.transition()'s
## shove logic without depending on a real Level's baked wall colliders
## (maze.set_open() only flips MazeData's own flag; it doesn't retroactively
## remove a StaticBody2D wall collider a real Level already built, which
## made test_move() block a real Player/Enemy at a tile the test itself
## just declared open).
func _make_plane_spider(pos: Vector2, level: Level, plane: Level.Layer = Level.Layer.GROUND) -> Array:
	var node := Node2D.new()
	node.add_to_group("spiders")
	node.global_position = pos
	var mover := GridMover.new()
	mover.name = "GridMover"
	mover.tile_size = 48
	node.add_child(mover)
	var plane_comp := PlaneComponent.new()
	plane_comp.name = "PlaneComponent"
	plane_comp.level = level
	plane_comp.current_plane = plane
	node.add_child(plane_comp)
	add_child_autofree(node)
	mover.set_process(false) # drive tick() manually, deterministic
	return [node, mover, plane_comp]


## Playtest regression: knockback() refuses to interrupt an in-flight step
## (by design), and the enemy is rarely standing still — it's almost always
## mid-step from its own AI the instant a transition lands on its tile,
## which silently dropped the shove every time this mattered in real play.
## The shove must instead wait for that in-flight step to land and retry.
func test_transition_retries_the_shove_once_an_in_flight_occupant_lands() -> void:
	var bare_level := Level.new() # tile_of() only needs TILE_SIZE, not a built maze
	autofree(bare_level)

	# "Player" is mid-step INTO tile (1,0) from tile (0,0) -- still is_moving()
	# the instant "enemy" transitions onto that same tile.
	var player := _make_plane_spider(Vector2(0, 0), bare_level)
	var player_mover: GridMover = player[1]
	assert_true(player_mover.try_step(Vector2i.RIGHT), "nothing set up to block this step")
	player_mover.tick(0.03) # partway through the step -- still is_moving()

	var enemy := _make_plane_spider(Vector2(48, 0), bare_level, Level.Layer.CEILING)
	var enemy_plane: PlaneComponent = enemy[2]

	enemy_plane.transition() # CEILING -> GROUND, landing on the contested tile (1,0)

	assert_true(player_mover.is_moving(), "the shove must not force-interrupt the in-flight step")
	assert_eq(player_mover.committed_tile(), Vector2i(1, 0), "still mid-step toward its own tile, untouched so far")

	player_mover.tick(1.0) # finishes the player's step -- fires step_finished, retrying the shove
	assert_ne(player_mover.committed_tile(), Vector2i(1, 0), "once landed, the deferred shove finally fires")


func test_transition_does_not_shove_a_spider_left_on_a_different_plane() -> void:
	var level := _make_level()
	var tile := level.tile_of(level.player.global_position)
	level.enemy.global_position = level.player.global_position
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent

	# enemy starts GROUND (default); transitioning it to CEILING leaves the
	# player alone on GROUND -- different planes never contest a tile.
	enemy_plane.transition()

	var player_mover := level.player.get_node("GridMover") as GridMover
	assert_eq(player_mover.committed_tile(), tile,
		"different planes never contest a tile -- no shove needed")
