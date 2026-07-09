extends GutTest
## HazardDirector is instanced by Level.build() (design §7); trigger_random_now()
## fires immediately regardless of its 50-120s base intervals, and each
## concrete hazard announces itself via EventBus.hazard_triggered.


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _count_pits(level: Level) -> int:
	var count := 0
	for cell in level.maze.open_cells():
		if level.maze.is_pit(cell.x, cell.y):
			count += 1
	return count


func test_level_build_instances_a_bound_hazard_director() -> void:
	var level := _make_level()
	assert_not_null(level._hazard_director)


func test_trigger_random_now_fires_a_hazard() -> void:
	var level := _make_level()
	var fired: Array = []
	EventBus.hazard_triggered.connect(func(name: String) -> void: fired.append(name))
	level.trigger_random_hazard_now()
	assert_eq(fired.size(), 1)
	assert_has(["water_ingress", "seismic_compaction", "centipede_express"], fired[0])


func test_water_ingress_floods_at_least_the_origin_tile() -> void:
	var level := _make_level()
	var before := _count_pits(level)
	WaterIngress.new().trigger(level)
	assert_gt(_count_pits(level), before)


func test_water_ingress_emits_hazard_triggered() -> void:
	var level := _make_level()
	var fired: Array = []
	EventBus.hazard_triggered.connect(func(name: String) -> void: fired.append(name))
	WaterIngress.new().trigger(level)
	assert_has(fired, "water_ingress")


func test_seismic_compaction_emits_hazard_triggered() -> void:
	var level := _make_level()
	var fired: Array = []
	EventBus.hazard_triggered.connect(func(name: String) -> void: fired.append(name))
	SeismicCompaction.new().trigger(level)
	assert_has(fired, "seismic_compaction")


func test_centipede_express_opens_a_full_row_or_column() -> void:
	var level := _make_level()
	CentipedeExpress.new().trigger(level)
	assert_true(_has_full_open_line(level), "one full interior row or column should be open")


func test_centipede_express_emits_hazard_triggered() -> void:
	var level := _make_level()
	var fired: Array = []
	EventBus.hazard_triggered.connect(func(name: String) -> void: fired.append(name))
	CentipedeExpress.new().trigger(level)
	assert_has(fired, "centipede_express")


func _has_full_open_line(level: Level) -> bool:
	var maze := level.maze
	for y in range(1, maze.height - 1):
		var row_open := true
		for x in range(1, maze.width - 1):
			if not maze.is_open(x, y):
				row_open = false
				break
		if row_open:
			return true
	for x in range(1, maze.width - 1):
		var col_open := true
		for y in range(1, maze.height - 1):
			if not maze.is_open(x, y):
				col_open = false
				break
		if col_open:
			return true
	return false
