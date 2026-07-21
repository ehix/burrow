extends GutTest
## SpiderClassData.frame_for_facing() (NSWE directional sprite work): picks
## the right baked directional texture purely from a cardinal `facing`
## Vector2 -- Player._dominant_dir()/Enemy._dominant() both already reduce
## all movement input to exactly one of the 4 cardinal unit vectors before
## `facing` is ever set, so this never needs to handle a diagonal.

func _make_data() -> SpiderClassData:
	var data := SpiderClassData.new()
	data.sprite_south = load("res://assets/sprites/nswe/wolf_south.png")
	data.sprite_north = load("res://assets/sprites/nswe/wolf_north.png")
	data.sprite_west = load("res://assets/sprites/nswe/wolf_west.png")
	data.sprite_east = load("res://assets/sprites/nswe/wolf_east.png")
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


func test_frame_for_facing_right_is_east() -> void:
	var data := _make_data()
	assert_eq(data.frame_for_facing(Vector2.RIGHT), data.sprite_east)


func test_frame_for_facing_falls_back_to_south_for_zero_vector() -> void:
	# facing is never actually zero once movement has started (both
	# Player._dominant_dir() and Enemy._dominant() only ever produce a
	# cardinal or leave facing untouched), but a safe default matters for
	# the very first frame before any input has happened.
	var data := _make_data()
	assert_eq(data.frame_for_facing(Vector2.ZERO), data.sprite_south)
