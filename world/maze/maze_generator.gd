class_name MazeGenerator
extends RefCounted
## Seeded recursive-backtracker maze generation, with optional braiding.
##
## The carve pass produces a perfect maze (spanning tree — exactly one path
## between any two cells). `loop_chance` then braids it: each dead-end has that
## probability of gaining an extra connection, which removes dead-ends and adds
## loops / alternate routes. 0.0 = perfect maze, 1.0 = fully braided.
##
## Always fully connected (braiding only opens walls). Seeding the RNG makes it
## deterministic: same (cols, rows, seed, loop_chance) → identical MazeData.

## Fixed neighbour probe order — part of what makes generation deterministic.
const _DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


## Generate a cols x rows cell maze. The returned grid is
## (cols*2 + 1) x (rows*2 + 1) tiles. `loop_chance` in [0,1] braids dead-ends.
static func generate(cols: int, rows: int, seed_value: int, loop_chance: float = 0.0) -> MazeData:
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

	if loop_chance > 0.0:
		cells = _braid(cells, width, height, rng, loop_chance)

	return MazeData.new(cells, width, height)


## Braid the carved maze: give each dead-end cell a `loop_chance` probability of
## opening one more wall (preferring a neighbour that is itself a dead-end),
## turning single corridors into loops. Returns the modified grid.
static func _braid(cells: PackedByteArray, width: int, height: int,
		rng: RandomNumberGenerator, loop_chance: float) -> PackedByteArray:
	var out := cells
	for cy in range(1, height, 2):
		for cx in range(1, width, 2):
			var open_dirs: Array[Vector2i] = []
			var closed: Array[Vector2i] = []
			for d in _DIRS:
				var nx := cx + d.x * 2
				var ny := cy + d.y * 2
				if nx < 0 or nx >= width or ny < 0 or ny >= height:
					continue # no neighbour cell that way
				if out[(cy + d.y) * width + (cx + d.x)] == 1:
					open_dirs.append(d)
				else:
					closed.append(d)
			# Only braid actual dead-ends (exactly one existing passage).
			if open_dirs.size() != 1 or closed.is_empty():
				continue
			if rng.randf() >= loop_chance:
				continue
			# Prefer linking to another dead-end so braiding reduces them faster.
			var preferred: Array[Vector2i] = []
			for d in closed:
				if _is_dead_end(out, width, height, cx + d.x * 2, cy + d.y * 2):
					preferred.append(d)
			var pool := preferred if not preferred.is_empty() else closed
			var pick: Vector2i = pool[rng.randi_range(0, pool.size() - 1)]
			out[(cy + pick.y) * width + (cx + pick.x)] = 1
	return out


static func _is_dead_end(cells: PackedByteArray, width: int, height: int, cx: int, cy: int) -> bool:
	if cx < 0 or cx >= width or cy < 0 or cy >= height or cells[cy * width + cx] != 1:
		return false
	var passages := 0
	for d in _DIRS:
		var wx := cx + d.x
		var wy := cy + d.y
		if wx >= 0 and wx < width and wy >= 0 and wy < height and cells[wy * width + wx] == 1:
			passages += 1
	return passages == 1


static func _cell_to_tile(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * 2 + 1, cell.y * 2 + 1)
