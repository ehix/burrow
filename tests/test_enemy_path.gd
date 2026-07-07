extends GutTest
## The pure step-direction helper the enemy uses to follow a tile path.


func test_step_dir_is_a_unit_cardinal_toward_target() -> void:
	assert_eq(Enemy._step_dir(Vector2i(2, 2), Vector2i(5, 2)), Vector2i.RIGHT)
	assert_eq(Enemy._step_dir(Vector2i(2, 2), Vector2i(2, 0)), Vector2i.UP)
	assert_eq(Enemy._step_dir(Vector2i(2, 2), Vector2i(1, 2)), Vector2i.LEFT)


func test_step_dir_same_tile_is_zero() -> void:
	assert_eq(Enemy._step_dir(Vector2i(3, 3), Vector2i(3, 3)), Vector2i.ZERO)
