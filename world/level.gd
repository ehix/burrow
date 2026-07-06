class_name Level
extends Node2D
## One depth's playfield. Generates a maze from the depth-derived seed, renders
## it, builds collision + light occluders + a navigation polygon from it, then
## spawns the player, enemy and larvae. Freed and rebuilt on descent.

const TILE_SIZE := 48
const MAZE_COLS := 9   # fixed size — map-size progression is out of slice 1
const MAZE_ROWS := 9
const LARVA_COUNT := 4
## Fraction of dead-ends to braid into loops (0 = perfect maze). Tunable feel.
const LOOP_CHANCE := 0.7

const PlayerScene := preload("res://entities/player/player.tscn")
const EnemyScene := preload("res://entities/enemy/enemy.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")

## Fog-of-war ambient when darkness is on. White (no darkening) when off.
const DARK_MODULATE := Color(0.05, 0.05, 0.07)

@onready var _canvas_modulate: CanvasModulate = $CanvasModulate
@onready var _nav_region: NavigationRegion2D = $NavRegion
@onready var _walls: StaticBody2D = $Walls
@onready var _occluders: Node2D = $Occluders
@onready var _renderer: MazeRenderer = $Renderer
@onready var _entities: Node2D = $Entities

var maze: MazeData
var player: Node2D
var enemy: Node2D


## Build the whole level. Called by World right after instancing.
func build() -> void:
	maze = MazeGenerator.generate(MAZE_COLS, MAZE_ROWS, GameState.maze_seed(), LOOP_CHANCE)
	_renderer.setup(maze, TILE_SIZE)
	_build_collision_and_occluders()
	_build_navigation()
	_spawn_entities()
	apply_darkness()


func get_player() -> Node2D:
	return player


## Total maze size in pixels (including the outer wall border).
func map_pixel_size() -> Vector2:
	return Vector2(maze.width, maze.height) * TILE_SIZE


func map_center() -> Vector2:
	return map_pixel_size() * 0.5


## Apply the current GameState.darkness_enabled flag: dark ambient + player
## vision light when on, fully-lit map when off. Safe to call any time.
func apply_darkness() -> void:
	var on := GameState.darkness_enabled
	_canvas_modulate.color = DARK_MODULATE if on else Color(1, 1, 1)
	if player != null:
		var light := player.get_node_or_null("VisionLight") as PointLight2D
		if light != null:
			light.enabled = on


func _build_collision_and_occluders() -> void:
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(TILE_SIZE, TILE_SIZE)
	var occ_poly := OccluderPolygon2D.new()
	var half := TILE_SIZE * 0.5
	occ_poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])

	for y in maze.height:
		for x in maze.width:
			if maze.is_open(x, y):
				continue
			var centre := _tile_centre(x, y)
			var col := CollisionShape2D.new()
			col.shape = wall_shape
			col.position = centre
			_walls.add_child(col)
			var occ := LightOccluder2D.new()
			occ.occluder = occ_poly
			occ.position = centre
			_occluders.add_child(occ)


func _build_navigation() -> void:
	# Two floor triangles per open tile, sharing corner vertices with adjacent
	# tiles so the region connects into one walkable navmesh. `verts` is a plain
	# Array (reference type) so the corner-dedup helper can append to it.
	var verts: Array[Vector2] = []
	var index_of := {} # Vector2i grid corner -> vertex index
	var polys: Array[PackedInt32Array] = []
	for y in maze.height:
		for x in maze.width:
			if not maze.is_open(x, y):
				continue
			var a := _corner_index(Vector2i(x, y), verts, index_of)
			var b := _corner_index(Vector2i(x + 1, y), verts, index_of)
			var c := _corner_index(Vector2i(x + 1, y + 1), verts, index_of)
			var d := _corner_index(Vector2i(x, y + 1), verts, index_of)
			polys.append(PackedInt32Array([a, b, c]))
			polys.append(PackedInt32Array([a, c, d]))

	var nav := NavigationPolygon.new()
	nav.set_vertices(PackedVector2Array(verts))
	for poly in polys:
		nav.add_polygon(poly)
	_nav_region.navigation_polygon = nav


func _corner_index(grid: Vector2i, verts: Array[Vector2], index_of: Dictionary) -> int:
	if index_of.has(grid):
		return index_of[grid]
	var idx := verts.size()
	verts.push_back(Vector2(grid.x * TILE_SIZE, grid.y * TILE_SIZE))
	index_of[grid] = idx
	return idx


func _spawn_entities() -> void:
	# Player at the top-left cell, enemy at the far bottom-right cell.
	var player_cell := Vector2i(1, 1)
	var enemy_cell := Vector2i(maze.width - 2, maze.height - 2)

	player = PlayerScene.instantiate()
	player.position = _tile_centre(player_cell.x, player_cell.y)
	_entities.add_child(player)

	enemy = EnemyScene.instantiate()
	enemy.position = _tile_centre(enemy_cell.x, enemy_cell.y)
	_entities.add_child(enemy)

	_spawn_larvae([player_cell, enemy_cell])


func _spawn_larvae(reserved: Array) -> void:
	var cells := maze.open_cells()
	cells.shuffle()
	var placed := 0
	for cell in cells:
		if placed >= LARVA_COUNT:
			break
		if cell in reserved:
			continue
		var larva := LarvaScene.instantiate()
		larva.position = _tile_centre(cell.x, cell.y)
		_entities.add_child(larva)
		if larva.has_method("set_facing"):
			larva.set_facing(TileTypes.default_facing(maze.classify(cell.x, cell.y)))
		placed += 1


func _tile_centre(tx: int, ty: int) -> Vector2:
	return Vector2((tx + 0.5) * TILE_SIZE, (ty + 0.5) * TILE_SIZE)
