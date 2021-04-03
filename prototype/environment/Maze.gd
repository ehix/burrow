extends TileMap

const N = 1
const E = 2
const S = 4
const W = 8
const block_tile = N|E|S|W # 15 because tile index 15 is the 'block' tile (only collision)
const TileTypes = preload("res://src/TileTypes.gd").Tile_Type

var cell_walls = {Vector2(0, -2): N, Vector2(2, 0): E, 
				  Vector2(0, 2): S, Vector2(-2, 0): W}
var tile_size = 64  # tile size (in pixels)
var width = 17  # width of map (in tiles)
var height = 10  # height of map (in tiles)

var map_seed
# fraction of walls to remove
var erase_fraction = 0.1

func _ready():
#	$Camera2D.zoom = Vector2(3, 3)
#	$Camera2D.position = Map.map_to_world(Vector2(width/2, height/2))
	randomize()
	if !map_seed:
		map_seed = randi()
	seed(map_seed)
	print("Seed: ", map_seed)
	tile_size = self.cell_size
	# Make maze, and get starting positions for players
	var starting_positions = make_maze()
#	make_maze()
	get_parent().get_node("Player").set_position(starting_positions[0] + tile_size/2)
	get_parent().get_node("Enemy").set_position(starting_positions[1] + tile_size/2)
	erase_walls()
	
	
func check_neighbors(cell, unvisited):
	# returns an array of cell's unvisited neighbors
	var list = []
	for n in cell_walls.keys():
		if cell + n in unvisited:
			list.append(cell + n)
	return list
	
func make_maze():
	var unvisited = []  # array of unvisited tiles
	var stack = []
	# fill the map with solid tiles
	self.clear()
	for x in range(width):
		for y in range(height):
			self.set_cellv(Vector2(x, y), N|E|S|W)
	for x in range(0, width, 2):
		for y in range(0, height, 2):
			unvisited.append(Vector2(x, y))
	
	var current = Vector2(0, 0)
	unvisited.erase(current)
	
	# Start positions for each spider
	var player_start = current * tile_size
	var enemy_start = unvisited[-1] * tile_size

	# execute recursive backtracker algorithm
	while unvisited:
		var neighbors = check_neighbors(current, unvisited)
		if neighbors.size() > 0:
			var next = neighbors[randi() % neighbors.size()]
			stack.append(current)
			# remove walls from *both* cells
			var dir = next - current
			var current_walls = self.get_cellv(current) - cell_walls[dir]
			var next_walls = self.get_cellv(next) - cell_walls[-dir]
			self.set_cellv(current, current_walls)
			self.set_cellv(next, next_walls)
			# insert intermediate cell
			if dir.x != 0:
				self.set_cellv(current + dir/2, 5)
			else:
				self.set_cellv(current + dir/2, 10)
			current = next
			unvisited.erase(current)
		elif stack:
			current = stack.pop_back()
		#yield(get_tree(), 'idle_frame')
	return [player_start, enemy_start]

func erase_walls():
	# randomly remove a number of the map's walls
	for i in range(int((width * height) * erase_fraction)):
		var x = int(rand_range(2, width/2 - 2)) * 2
		var y = int(rand_range(2, height/2 - 2)) * 2
		var cell = Vector2(x, y)
		# pick random neighbor
		var neighbor = cell_walls.keys()[randi() % cell_walls.size()]
		# if there's a wall between them, remove it
		if self.get_cellv(cell) & cell_walls[neighbor]:
			var walls = self.get_cellv(cell) - cell_walls[neighbor]
			var n_walls = self.get_cellv(cell+neighbor) - cell_walls[-neighbor]
			self.set_cellv(cell, walls)
			self.set_cellv(cell+neighbor, n_walls)
			# insert intermediate cell
			if neighbor.x != 0:
				self.set_cellv(cell+neighbor/2, 5)
			else:
				self.set_cellv(cell+neighbor/2, 10)
		#yield(get_tree(), 'idle_frame')
		
func get_grid_id_from_worldpos(worldpos: Vector2):
	var cell_num = self.world_to_map(worldpos)
	print("Maze, get grid index from worldpos - ", cell_num)
	return cell_num
	
func get_tiletype_from_worldpos(worldpos: Vector2):
	var cell_num = self.world_to_map(worldpos)
	print("Maze, get grid index from worldpos - ", cell_num)
	return get_tiletype(cell_num)
	
func get_tiletype(grid_id: Vector2):
	var up_tile = self.get_cellv(grid_id + Vector2.UP)
	var up_blocked = up_tile == block_tile || up_tile == -1
	print("Up Blocked? - ", up_blocked)
	var right_tile = self.get_cellv(grid_id + Vector2.RIGHT)
	var right_blocked = right_tile == block_tile || right_tile == -1
	print("Right Blocked? - ", right_blocked)
	var down_tile = self.get_cellv(grid_id + Vector2.DOWN)
	var down_blocked = down_tile == block_tile || down_tile == -1
	print("Down Blocked? - ", down_blocked)
	var left_tile = self.get_cellv(grid_id + Vector2.LEFT)
	var left_blocked = left_tile == block_tile || left_tile == -1
	print("Left Blocked? - ", left_blocked)
	
	# Horizontal Tunnel Variants
	if up_blocked && down_blocked && !left_blocked && !right_blocked:
		print("FOUND HORIZONTAL TUNNEL")
		return TileTypes.TUNNEL_HORIZONTAL
	elif up_blocked && down_blocked && !left_blocked && right_blocked:
		print("FOUND HORIZONTAL TUNNEL w Dead Right End")
		return TileTypes.TUNNEL_HORIZONTAL
	elif up_blocked && down_blocked && left_blocked && !right_blocked:
		print("FOUND HORIZONTAL TUNNEL w Dead Left End")
		return TileTypes.TUNNEL_HORIZONTAL
	# Vertical Tunnel Variants
	elif !up_blocked && !down_blocked && left_blocked && right_blocked:
		print("FOUND VERTICAL TUNNEL")
		return TileTypes.TUNNEL_VERTICAL
	elif up_blocked && !down_blocked && left_blocked && right_blocked:
		print("FOUND VERTICAL TUNNEL w Dead End above")
		return TileTypes.TUNNEL_VERTICAL
	elif !up_blocked && down_blocked && left_blocked && right_blocked:
		print("FOUND VERTICAL TUNNEL w Dead End below")
		return TileTypes.TUNNEL_VERTICAL
	# Corner Variants
	elif left_blocked && up_blocked && !right_blocked && !down_blocked:
		print("FOUND TOP LEFT CORNER ")
		return TileTypes.CORNER_TOP_LEFT
	elif !left_blocked && up_blocked && right_blocked && !down_blocked:
		print("FOUND TOP RIGHT CORNER ")
		return TileTypes.CORNER_TOP_RIGHT
	elif !left_blocked && !up_blocked && right_blocked && down_blocked:
		print("FOUND BOTTOM RIGHT CORNER ")
		return TileTypes.CORNER_BOTTOM_RIGHT
	elif left_blocked && !up_blocked && !right_blocked && down_blocked:
		print("FOUND BOTTOM LEFT CORNER ")
		return TileTypes.CORNER_BOTTOM_LEFT
	# Junction Variants
	elif left_blocked && !up_blocked && !right_blocked && !down_blocked:
		print("FOUND LEFT T JUNCTION ")
		return TileTypes.T_LEFT
	elif !left_blocked && up_blocked && !right_blocked && !down_blocked:
		print("FOUND NORMAL T JUNCTION ")
		return TileTypes.T_NORMAL
	elif !left_blocked && !up_blocked && right_blocked && !down_blocked:
		print("FOUND RIGHT T JUNCTION ")
		return TileTypes.T_RIGHT
	elif !left_blocked && !up_blocked && !right_blocked && down_blocked:
		print("FOUND UPSIDE DOWN T JUNCTION ")
		return TileTypes.T_UPSIDE_DOWN
	elif !left_blocked && !up_blocked && !right_blocked && !down_blocked:
		print("FOUND CROSSROAD JUNCTION ")
		return TileTypes.CROSSROAD
