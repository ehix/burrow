class_name MazeData
extends RefCounted
## Immutable-ish grid of a generated maze. `true`/1 = open floor, 0 = wall.
##
## The grid uses the "expanded" representation: for a cols x rows cell maze the
## grid is (cols*2 + 1) x (rows*2 + 1), so walls are one tile thick and odd/odd
## tiles are cell centres. This maps 1:1 onto a TileMapLayer of floor/wall tiles.

var width: int
var height: int
var _cells: PackedByteArray

## Fixed neighbour order — keep deterministic for reproducible traversal.
const _DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


func _init(cells: PackedByteArray, w: int, h: int) -> void:
	_cells = cells
	width = w
	height = h


func is_open(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height:
		return false
	return _cells[y * width + x] == 1


## Carve a wall tile into floor (dev "remove wall" tool). No-op out of bounds.
func set_open(x: int, y: int) -> void:
	if x < 0 or x >= width or y < 0 or y >= height:
		return
	_cells[y * width + x] = 1


## Every open tile coordinate, row-major.
func open_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			if _cells[y * width + x] == 1:
				result.append(Vector2i(x, y))
	return result


## Tile type of a cell from its open neighbours (BLOCKED_CELL if it's a wall).
func classify(x: int, y: int) -> TileTypes.Type:
	if not is_open(x, y):
		return TileTypes.Type.BLOCKED_CELL
	return TileTypes.classify(
		is_open(x, y - 1), is_open(x + 1, y), is_open(x, y + 1), is_open(x - 1, y))


## Count of open tiles reachable from `start` via 4-connected flood fill.
func reachable_count(start: Vector2i) -> int:
	if not is_open(start.x, start.y):
		return 0
	var seen := {}
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in _DIRS:
			var n: Vector2i = c + d
			if is_open(n.x, n.y) and not seen.has(n):
				seen[n] = true
				stack.push_back(n)
	return seen.size()


## True when every open tile is reachable from the first one (no islands).
## Number of open cells with exactly one open orthogonal neighbour (dead-ends).
## A perfect maze has many; braiding drives this down.
func dead_end_count() -> int:
	var count := 0
	for y in height:
		for x in width:
			if not is_open(x, y):
				continue
			var neighbours := int(is_open(x, y - 1)) + int(is_open(x + 1, y)) \
				+ int(is_open(x, y + 1)) + int(is_open(x - 1, y))
			if neighbours == 1:
				count += 1
	return count


func is_fully_connected() -> bool:
	var cells := open_cells()
	if cells.is_empty():
		return true
	return reachable_count(cells[0]) == cells.size()


func equals(other: MazeData) -> bool:
	return width == other.width and height == other.height and _cells == other._cells
