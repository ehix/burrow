class_name SeismicCompaction
extends HazardEvent
## Earthquake: opens `OPEN_COUNT` random existing wall blocks into floor while
## collapsing `COLLAPSE_COUNT` random open, unoccupied tiles back into wall —
## a net redraw of some corridors. Never touches the outer boundary
## (guardrail): both passes explicitly skip MazeData.is_boundary() tiles.

const OPEN_COUNT := 3
const COLLAPSE_COUNT := 3


func trigger(level: Node) -> void:
	if level == null or level.maze == null:
		return
	_open_random_walls(level)
	_collapse_random_floors(level)
	EventBus.hazard_triggered.emit("seismic_compaction")


func _open_random_walls(level: Node) -> void:
	var maze: MazeData = level.maze
	var candidates: Array[Vector2i] = []
	for y in maze.height:
		for x in maze.width:
			if not maze.is_open(x, y) and not maze.is_boundary(x, y):
				candidates.append(Vector2i(x, y))
	candidates.shuffle()
	for i in mini(OPEN_COUNT, candidates.size()):
		level.dev_remove_wall_at(candidates[i])


func _collapse_random_floors(level: Node) -> void:
	var maze: MazeData = level.maze
	var candidates: Array[Vector2i] = []
	for cell in maze.open_cells():
		if not maze.is_boundary(cell.x, cell.y) and not _is_occupied(level, cell):
			candidates.append(cell)
	candidates.shuffle()
	for i in mini(COLLAPSE_COUNT, candidates.size()):
		level.collapse_tile_at(candidates[i])


func _is_occupied(level: Node, cell: Vector2i) -> bool:
	if level.get_tree() == null:
		return false
	for spider in level.get_tree().get_nodes_in_group("spiders"):
		if level.tile_of((spider as Node2D).global_position) == cell:
			return true
	return false
