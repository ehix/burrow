class_name WaterIngress
extends HazardEvent
## Flash-floods a patch of open ground tiles: they become ground-blocked for
## `FLOOD_DURATION`, then naturally recede. Reuses MazeData's pit overlay (a
## flooded tile is ground-blocked exactly like a pit) rather than adding a
## third tile state — a flood and a pit both mean "ground movement blocked
## here, ceiling unaffected" (see CeilingData). Never touches boundary tiles
## (guardrail), so the border can't be "washed away".

const FLOOD_RADIUS := 2
const FLOOD_DURATION := 12.0


func trigger(level: Node) -> void:
	if level == null or level.maze == null:
		return
	var cells: Array = level.maze.open_cells()
	if cells.is_empty():
		return
	cells.shuffle()
	var origin: Vector2i = cells[0]
	var flooded: Array[Vector2i] = []
	for dx in range(-FLOOD_RADIUS, FLOOD_RADIUS + 1):
		for dy in range(-FLOOD_RADIUS, FLOOD_RADIUS + 1):
			var tile := origin + Vector2i(dx, dy)
			if level.maze.is_open(tile.x, tile.y) and not level.maze.is_boundary(tile.x, tile.y):
				level.maze.set_pit(tile.x, tile.y, true)
				flooded.append(tile)
	EventBus.hazard_triggered.emit("water_ingress")
	if level.get_tree() != null:
		level.get_tree().create_timer(FLOOD_DURATION).timeout.connect(
			func() -> void: _recede(level, flooded))


func _recede(level: Node, tiles: Array[Vector2i]) -> void:
	if level == null or not is_instance_valid(level) or level.maze == null:
		return
	for tile in tiles:
		level.maze.set_pit(tile.x, tile.y, false)
