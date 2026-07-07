extends GutTest
## Level's tile<->world conversions round-trip on tile centres.


func test_tile_of_and_centre_of_round_trip() -> void:
	var level := preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	# centre_of a tile, then tile_of that point, returns the same tile.
	for tile in [Vector2i(1, 1), Vector2i(3, 5), Vector2i(8, 8)]:
		var centre := level.centre_of(tile)
		assert_eq(level.tile_of(centre), tile, "round-trips tile %s" % tile)


func test_centre_is_tile_middle() -> void:
	var level := preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	assert_eq(level.centre_of(Vector2i(0, 0)), Vector2(24, 24))
