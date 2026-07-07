extends GutTest
## Player analog input reduces to a single cardinal grid direction.


func test_pure_axes_map_straight_through() -> void:
	assert_eq(Player._dominant_dir(Vector2(1, 0)), Vector2i.RIGHT)
	assert_eq(Player._dominant_dir(Vector2(-1, 0)), Vector2i.LEFT)
	assert_eq(Player._dominant_dir(Vector2(0, 1)), Vector2i.DOWN)
	assert_eq(Player._dominant_dir(Vector2(0, -1)), Vector2i.UP)


func test_zero_input_is_no_direction() -> void:
	assert_eq(Player._dominant_dir(Vector2.ZERO), Vector2i.ZERO)


func test_diagonal_resolves_to_dominant_axis() -> void:
	assert_eq(Player._dominant_dir(Vector2(0.9, 0.3)), Vector2i.RIGHT)
	assert_eq(Player._dominant_dir(Vector2(0.2, -0.8)), Vector2i.UP)


func test_tie_favours_horizontal() -> void:
	assert_eq(Player._dominant_dir(Vector2(0.5, 0.5)), Vector2i.RIGHT)
