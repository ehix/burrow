class_name GridNav
extends RefCounted
## Builds an AStarGrid2D from a MazeData (walls = solid) and returns tile paths.
## 4-directional to match grid movement; deterministic for a fixed maze.


static func build(maze: MazeData, cell_size: int) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, maze.width, maze.height)
	astar.cell_size = Vector2(cell_size, cell_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for y in maze.height:
		for x in maze.width:
			if not maze.is_open(x, y):
				astar.set_point_solid(Vector2i(x, y), true)
	return astar


## Tile path from `from` to `to`, endpoints inclusive. Empty if either endpoint
## is out of bounds or solid.
static func path(astar: AStarGrid2D, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not astar.is_in_boundsv(from) or not astar.is_in_boundsv(to):
		return []
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return []
	return astar.get_id_path(from, to)
