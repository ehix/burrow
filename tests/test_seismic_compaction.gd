extends GutTest
## Seismic Compaction's collapse pass (environment tiles rework): a
## spider-occupied tile is still never a collapse candidate (unchanged
## eligibility check) -- Level.collapse_tile_at() itself is what now
## destroys any larva/web/item on an eligible tile, covered directly in
## tests/test_level_hazard_helpers.gd.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_collapse_candidates_exclude_a_spider_occupied_tile() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	level.add_child(spider)
	spider.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	var compaction := SeismicCompaction.new()
	assert_true(compaction._is_occupied(level, interior_cell),
		"a spider-occupied tile is still excluded from collapse candidates")


func test_collapse_candidates_exclude_a_centipede_occupied_tile() -> void:
	var level := _make_level()
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	var interior_cell := Vector2i(3, 3)
	var centipede := Centipede.new()
	level.add_child(centipede)
	centipede.bind_level(level)
	centipede.spawn_at([interior_cell])

	var compaction := SeismicCompaction.new()
	assert_true(compaction._is_occupied(level, interior_cell),
		"a Centipede-occupied tile must never collapse into a wall out from under it")
