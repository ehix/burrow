extends GutTest
## SpiderClassData.frame_for_facing()/should_flip_h() (NSWE directional
## sprite work): picks the right baked directional texture purely from a
## cardinal `facing` Vector2 -- Player._dominant_dir()/Enemy._dominant()
## both already reduce all movement input to exactly one of the 4 cardinal
## unit vectors before `facing` is ever set, so this never needs to handle
## a diagonal. There is no separate EAST texture: generating two
## independently-consistent mirror poses proved unreliable (west/east often
## read as "walking backwards" regardless of which file played which
## direction) for every class but Warden -- EAST always reuses sprite_west,
## mirrored via should_flip_h(), guaranteeing a true mirror by construction.

func _make_data() -> SpiderClassData:
	var data := SpiderClassData.new()
	data.sprite_south = load("res://assets/sprites/nswe/wolf_south.png")
	data.sprite_north = load("res://assets/sprites/nswe/wolf_north.png")
	data.sprite_west = load("res://assets/sprites/nswe/wolf_west.png")
	return data


func test_frame_for_facing_down_is_south() -> void:
	var data := _make_data()
	assert_eq(data.frame_for_facing(Vector2.DOWN), data.sprite_south)


func test_frame_for_facing_up_is_north() -> void:
	var data := _make_data()
	assert_eq(data.frame_for_facing(Vector2.UP), data.sprite_north)


func test_frame_for_facing_left_is_west() -> void:
	var data := _make_data()
	assert_eq(data.frame_for_facing(Vector2.LEFT), data.sprite_west)


func test_frame_for_facing_right_reuses_the_west_texture() -> void:
	var data := _make_data()
	assert_eq(data.frame_for_facing(Vector2.RIGHT), data.sprite_west)


func test_frame_for_facing_falls_back_to_south_for_zero_vector() -> void:
	# facing is never actually zero once movement has started (both
	# Player._dominant_dir() and Enemy._dominant() only ever produce a
	# cardinal or leave facing untouched), but a safe default matters for
	# the very first frame before any input has happened.
	var data := _make_data()
	assert_eq(data.frame_for_facing(Vector2.ZERO), data.sprite_south)


func test_should_flip_h_is_true_only_for_facing_right() -> void:
	var data := _make_data()
	assert_true(data.should_flip_h(Vector2.RIGHT))
	assert_false(data.should_flip_h(Vector2.LEFT))
	assert_false(data.should_flip_h(Vector2.UP))
	assert_false(data.should_flip_h(Vector2.DOWN))
