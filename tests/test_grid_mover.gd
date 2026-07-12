extends GutTest
## GridMover step animation, blocking seam, buffering and slow.
## Pure: injects block_check and drives tick() manually (no physics frames).


func _make_mover(open := true) -> Array:
	# Returns [parent_node2d, mover]. Parent starts at origin.
	var parent := Node2D.new()
	parent.global_position = Vector2.ZERO
	var mover := GridMover.new()
	mover.tile_size = 48
	mover.step_time = 0.1
	mover.block_check = func(_d: Vector2i) -> bool: return not open
	parent.add_child(mover)
	add_child_autofree(parent)
	mover.set_process(false) # drive tick() manually
	return [parent, mover]


func test_step_moves_exactly_one_tile_over_step_time() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	assert_true(mover.try_step(Vector2i.RIGHT), "clear step starts")
	assert_true(mover.is_moving())
	mover.tick(0.05) # half of step_time
	assert_almost_eq(parent.global_position.x, 24.0, 0.5, "halfway across the tile")
	mover.tick(0.05) # finishes
	assert_almost_eq(parent.global_position.x, 48.0, 0.001, "lands on tile centre")
	assert_false(mover.is_moving())


func test_blocked_step_is_refused() -> void:
	var m := _make_mover(false) # block_check always true
	var mover: GridMover = m[1]
	assert_false(mover.try_step(Vector2i.RIGHT), "blocked step refused")
	assert_false(mover.is_moving())


func test_cannot_start_a_second_step_while_moving() -> void:
	var m := _make_mover()
	var mover: GridMover = m[1]
	mover.try_step(Vector2i.RIGHT)
	assert_false(mover.try_step(Vector2i.DOWN), "second step refused mid-step")


func test_buffered_direction_runs_after_finish() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	mover.try_step(Vector2i.RIGHT)
	mover.try_step(Vector2i.DOWN) # buffered
	mover.tick(0.1) # finish RIGHT -> auto-starts buffered DOWN
	assert_true(mover.is_moving(), "buffered step now running")
	mover.tick(0.1) # finish DOWN
	assert_almost_eq(parent.global_position, Vector2(48, 48), Vector2(0.001, 0.001))


func test_step_finished_signal_emits_once_per_step() -> void:
	var m := _make_mover()
	var mover: GridMover = m[1]
	watch_signals(mover)
	mover.try_step(Vector2i.RIGHT)
	mover.tick(0.1)
	assert_signal_emit_count(mover, "step_finished", 1)


func test_apply_slow_reduces_step_speed() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	mover.apply_slow(0.5, 999.0)
	assert_eq(mover.speed_scale, 0.5)
	mover.try_step(Vector2i.RIGHT)
	mover.tick(0.05) # at half speed this is only a quarter of the way
	assert_almost_eq(parent.global_position.x, 12.0, 0.5, "slowed step advances slower")


func test_a_later_slow_supersedes_an_earlier_timer() -> void:
	var m := _make_mover()
	var mover: GridMover = m[1]
	mover.apply_slow(0.5, 0.05) # short slow
	mover.apply_slow(0.3, 0.5)  # longer slow applied second
	assert_eq(mover.speed_scale, 0.3, "the later slow is active")
	await wait_seconds(0.15)     # the first (short) timer has now elapsed
	assert_eq(mover.speed_scale, 0.3, "stale timer must not reset the active slow")


func test_stun_blocks_stepping_until_it_elapses() -> void:
	var m := _make_mover()
	var mover: GridMover = m[1]
	mover.stun(0.2)
	assert_true(mover.is_stunned())
	assert_false(mover.try_step(Vector2i.RIGHT), "cannot step while stunned")
	mover.tick(0.25) # stun elapses (ticked in real time)
	assert_false(mover.is_stunned())
	assert_true(mover.try_step(Vector2i.RIGHT), "can step once the stun clears")


func test_knockback_shoves_even_while_stunned() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	mover.stun(1.0)
	assert_true(mover.knockback(Vector2i.RIGHT), "a hit shoves past the stun")
	mover.tick(0.1) # complete the shove
	assert_almost_eq(parent.global_position.x, 48.0, 0.001, "shoved one tile")


func test_knockback_into_a_wall_does_not_move() -> void:
	var m := _make_mover(false) # everything blocked
	var mover: GridMover = m[1]
	assert_false(mover.knockback(Vector2i.RIGHT), "no shove into a wall")
	assert_false(mover.is_moving())


func _make_spider(pos: Vector2) -> Array:
	# Returns [node, mover], in the "spiders" group for spider_tile_contested.
	# The mover is named "GridMover" to match how real Player/Enemy scenes name
	# it — spider_tile_contested looks it up by that exact node path, and an
	# anonymous node created via .new() otherwise gets an internal auto-name.
	var node := Node2D.new()
	node.add_to_group("spiders")
	node.global_position = pos
	var mover := GridMover.new()
	mover.name = "GridMover"
	mover.tile_size = 48
	mover.step_time = 0.1
	node.add_child(mover)
	add_child_autofree(node)
	mover.set_process(false) # drive tick() manually
	return [node, mover]


func test_committed_tile_is_the_landing_tile_while_moving() -> void:
	var pair := _make_spider(Vector2(240, 240)) # tile (5,5)
	var mover: GridMover = pair[1]
	mover.try_step(Vector2i.RIGHT)
	assert_eq(mover.committed_tile(), Vector2i(6, 5), "mid-step, committed tile is the destination")


func test_committed_tile_is_the_current_tile_when_stationary() -> void:
	var pair := _make_spider(Vector2(240, 240)) # tile (5,5)
	var mover: GridMover = pair[1]
	assert_eq(mover.committed_tile(), Vector2i(5, 5))


## Regression: the exact race that let two spiders land on the same tile. An
## enemy starts a step toward tile (5,5) while it's still empty; a player
## elsewhere then tries to step into that same tile before the enemy's step
## finishes landing. Must be blocked — a step's destination is "owned" the
## moment it's committed to, not just once something physically arrives.
func test_spider_tile_contested_blocks_a_step_into_an_in_flight_destination() -> void:
	var enemy_pair := _make_spider(Vector2(288, 240)) # tile (6,5)
	var enemy_mover: GridMover = enemy_pair[1]
	var player_pair := _make_spider(Vector2(192, 240)) # tile (4,5)
	var player_mover: GridMover = player_pair[1]

	assert_true(enemy_mover.try_step(Vector2i.LEFT), "starts clear, toward the empty tile (5,5)")
	enemy_mover.tick(0.03) # partway through the step, not yet landed

	assert_true(GridMover.spider_tile_contested(player_mover, player_pair[0], Vector2i.RIGHT),
		"the enemy already committed to (5,5) mid-step")


func test_spider_tile_contested_false_when_target_tile_is_unclaimed() -> void:
	_make_spider(Vector2(288, 240)) # tile (6,5), stationary — not tile (5,5)
	var player_pair := _make_spider(Vector2(192, 240)) # tile (4,5)
	var player_mover: GridMover = player_pair[1]
	assert_false(GridMover.spider_tile_contested(player_mover, player_pair[0], Vector2i.RIGHT),
		"tile (5,5) isn't owned by anyone")


func test_cancel_buffer_drops_a_queued_step() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	mover.try_step(Vector2i.RIGHT)
	mover.try_step(Vector2i.DOWN) # buffered
	mover.cancel_buffer() # e.g. the player released the key
	mover.tick(0.1) # finishes RIGHT; must NOT auto-start the cancelled DOWN
	assert_false(mover.is_moving(), "no buffered step should fire after cancel")
	assert_almost_eq(parent.global_position, Vector2(48, 0), Vector2(0.001, 0.001))


func test_spider_tile_contested_ignores_a_node_on_a_different_plane() -> void:
	var enemy_pair := _make_spider(Vector2(288, 240)) # tile (6,5)
	var enemy_mover: GridMover = enemy_pair[1]
	var enemy_node: Node2D = enemy_pair[0]
	var enemy_plane := PlaneComponent.new()
	enemy_plane.name = "PlaneComponent" # runtime nodes aren't auto-named after class_name
	enemy_node.add_child(enemy_plane)
	enemy_plane.current_plane = Level.Layer.CEILING # the "other" spider is on the ceiling
	var player_pair := _make_spider(Vector2(192, 240)) # tile (4,5), stays GROUND (no PlaneComponent)
	var player_mover: GridMover = player_pair[1]

	assert_true(enemy_mover.try_step(Vector2i.LEFT), "starts clear, toward the empty tile (5,5)")
	enemy_mover.tick(0.03) # partway through the step, not yet landed

	assert_false(GridMover.spider_tile_contested(player_mover, player_pair[0], Vector2i.RIGHT),
		"the enemy committed to (5,5), but it's on a different plane — never contests")
