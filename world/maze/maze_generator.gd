class_name MazeGenerator
extends RefCounted
## Seeded recursive-backtracker maze generation.
##
## Produces a perfect maze (spanning tree — exactly one path between any two
## cells), so the result is always fully connected. Seeding the RNG makes it
## deterministic: the same (cols, rows, seed) yields an identical MazeData.

## Fixed neighbour probe order — part of what makes generation deterministic.
const _DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


## Generate a cols x rows cell maze. The returned grid is
## (cols*2 + 1) x (rows*2 + 1) tiles.
static func generate(cols: int, rows: int, seed_value: int) -> MazeData:
	cols = maxi(cols, 1)
	rows = maxi(rows, 1)
	var width := cols * 2 + 1
	var height := rows * 2 + 1
	var cells := PackedByteArray()
	cells.resize(width * height) # zero-filled: everything starts as wall

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var visited := {}
	var stack: Array[Vector2i] = []
	var start := Vector2i.ZERO
	visited[start] = true
	var start_tile := _cell_to_tile(start)
	cells[start_tile.y * width + start_tile.x] = 1
	stack.push_back(start)

	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var neighbours: Array[Vector2i] = []
		for d in _DIRS:
			var n: Vector2i = current + d
			if n.x >= 0 and n.x < cols and n.y >= 0 and n.y < rows and not visited.has(n):
				neighbours.append(n)
		if neighbours.is_empty():
			stack.pop_back()
			continue
		var chosen: Vector2i = neighbours[rng.randi_range(0, neighbours.size() - 1)]
		var current_tile := _cell_to_tile(current)
		var chosen_tile := _cell_to_tile(chosen)
		# Carve the chosen cell and the wall tile between the two cells. Mutate
		# `cells` directly here — passing a PackedByteArray to a helper to write
		# would copy-on-write and lose the changes.
		var wall_tile := (current_tile + chosen_tile) / 2
		cells[chosen_tile.y * width + chosen_tile.x] = 1
		cells[wall_tile.y * width + wall_tile.x] = 1
		visited[chosen] = true
		stack.push_back(chosen)

	return MazeData.new(cells, width, height)


static func _cell_to_tile(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * 2 + 1, cell.y * 2 + 1)
