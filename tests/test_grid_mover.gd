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
