extends GutTest
## Unit tests for TileTypes.classify / default_facing (design §9:
## "tile-type classification — corner/T/crossroad detection").

const T := TileTypes.Type


func test_isolated_cell_is_blocked() -> void:
	assert_eq(TileTypes.classify(false, false, false, false), T.BLOCKED_CELL)


func test_dead_ends_read_as_axis_tunnels() -> void:
	assert_eq(TileTypes.classify(true, false, false, false), T.TUNNEL_VERTICAL, "up-only")
	assert_eq(TileTypes.classify(false, false, true, false), T.TUNNEL_VERTICAL, "down-only")
	assert_eq(TileTypes.classify(false, true, false, false), T.TUNNEL_HORIZONTAL, "right-only")
	assert_eq(TileTypes.classify(false, false, false, true), T.TUNNEL_HORIZONTAL, "left-only")


func test_straight_tunnels() -> void:
	assert_eq(TileTypes.classify(true, false, true, false), T.TUNNEL_VERTICAL)
	assert_eq(TileTypes.classify(false, true, false, true), T.TUNNEL_HORIZONTAL)


func test_corners() -> void:
	# openings up+right -> walls bottom+left -> CORNER_BOTTOM_LEFT
	assert_eq(TileTypes.classify(true, true, false, false), T.CORNER_BOTTOM_LEFT)
	assert_eq(TileTypes.classify(true, false, false, true), T.CORNER_BOTTOM_RIGHT)
	assert_eq(TileTypes.classify(false, true, true, false), T.CORNER_TOP_LEFT)
	assert_eq(TileTypes.classify(false, false, true, true), T.CORNER_TOP_RIGHT)


func test_t_junctions_named_by_wall_side() -> void:
	assert_eq(TileTypes.classify(false, true, true, true), T.T_NORMAL, "bar on top")
	assert_eq(TileTypes.classify(true, true, false, true), T.T_UPSIDE_DOWN, "bar on bottom")
	assert_eq(TileTypes.classify(true, true, true, false), T.T_LEFT, "bar on left")
	assert_eq(TileTypes.classify(true, false, true, true), T.T_RIGHT, "bar on right")


func test_crossroad() -> void:
	assert_eq(TileTypes.classify(true, true, true, true), T.CROSSROAD)


func test_default_facing_heads_into_the_tunnel() -> void:
	assert_eq(TileTypes.default_facing(T.TUNNEL_VERTICAL), Vector2i.UP)
	assert_eq(TileTypes.default_facing(T.TUNNEL_HORIZONTAL), Vector2i.RIGHT)
	assert_eq(TileTypes.default_facing(T.T_NORMAL), Vector2i.DOWN, "faces away from top wall")
	assert_eq(TileTypes.default_facing(T.T_LEFT), Vector2i.RIGHT, "faces away from left wall")
	assert_eq(TileTypes.default_facing(T.CORNER_TOP_LEFT), Vector2i.DOWN)
	assert_eq(TileTypes.default_facing(T.CROSSROAD), Vector2i.UP)
