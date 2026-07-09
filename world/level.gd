class_name Level
extends Node2D
## One depth's playfield. Generates a maze from the depth-derived seed, renders
## it, builds collision + light occluders + a navigation polygon from it, then
## spawns the player, enemy and larvae. Freed and rebuilt on descent.

const TILE_SIZE := 48
const MAZE_COLS := 9   # fixed size — map-size progression is out of slice 1
const MAZE_ROWS := 9
const LARVA_COUNT := 6
## Fraction of dead-ends to braid into loops (0 = perfect maze). Tunable feel.
const LOOP_CHANCE := 0.7
## Seconds between larva spawns while below the map's cap.
const LARVA_SPAWN_INTERVAL := 3.5
## One larva per this many open tiles sets the on-board cap (map-size scaled).
const LARVA_TILES_PER_CAP := 10
const LARVA_CAP_MAX := 18

const PlayerScene := preload("res://entities/player/player.tscn")
const EnemyScene := preload("res://entities/enemy/enemy.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")

## Fog-of-war ambient when darkness is on. White (no darkening) when off.
const DARK_MODULATE := Color(0.05, 0.05, 0.07)

@onready var _canvas_modulate: CanvasModulate = $CanvasModulate
@onready var _walls: StaticBody2D = $Walls
@onready var _occluders: Node2D = $Occluders
@onready var _renderer: MazeRenderer = $Renderer
@onready var _entities: Node2D = $Entities

var maze: MazeData
var player: Node2D
var enemy: Node2D
var _astar: AStarGrid2D
var _larva_cap := LARVA_COUNT
var _spawn_accum := 0.0
## Wall tile -> {collision, occluder}, so the dev "remove wall" tool can find
## and free the exact nodes for a carved-out tile.
var _wall_nodes: Dictionary = {}


## Build the whole level. Called by World right after instancing.
func build() -> void:
	maze = MazeGenerator.generate(MAZE_COLS, MAZE_ROWS, GameState.maze_seed(), LOOP_CHANCE)
	_renderer.setup(maze, TILE_SIZE)
	_build_collision_and_occluders()
	_astar = GridNav.build(maze, TILE_SIZE)
	_larva_cap = mini(LARVA_CAP_MAX, maxi(LARVA_COUNT, maze.open_cells().size() / LARVA_TILES_PER_CAP))
	_spawn_entities()
	apply_darkness()


## Keep the maze stocked: spawn a larva every interval while under the cap.
func _process(delta: float) -> void:
	if maze == null:
		return
	_spawn_accum += delta
	if _spawn_accum < LARVA_SPAWN_INTERVAL:
		return
	_spawn_accum = 0.0
	if get_tree().get_nodes_in_group("larvae").size() < _larva_cap:
		_spawn_larva_at_random()


func get_player() -> Node2D:
	return player


## Total maze size in pixels (including the outer wall border).
func map_pixel_size() -> Vector2:
	return Vector2(maze.width, maze.height) * TILE_SIZE


func map_center() -> Vector2:
	return map_pixel_size() * 0.5


## Grid <-> world conversions and pathing, used by grid-moving entities.
func tile_of(world: Vector2) -> Vector2i:
	return Vector2i(int(world.x / TILE_SIZE), int(world.y / TILE_SIZE))


func centre_of(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TILE_SIZE, (tile.y + 0.5) * TILE_SIZE)


func path_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _astar == null:
		return []
	return GridNav.path(_astar, from, to)


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
			_wall_nodes[Vector2i(x, y)] = {"collision": col, "occluder": occ}


## Dev tool (X): destroy the wall tile at `tile`, carving it into floor. Frees
## its collision + occluder, opens it in the maze data and the AStar grid, and
## redraws. No-op out of bounds or if the tile is already open.
func dev_remove_wall_at(tile: Vector2i) -> bool:
	if maze == null or not (tile.x >= 0 and tile.x < maze.width and tile.y >= 0 and tile.y < maze.height):
		return false
	if maze.is_open(tile.x, tile.y):
		return false
	maze.set_open(tile.x, tile.y)
	var nodes: Dictionary = _wall_nodes.get(tile, {})
	if nodes.get("collision") != null and is_instance_valid(nodes["collision"]):
		nodes["collision"].queue_free()
	if nodes.get("occluder") != null and is_instance_valid(nodes["occluder"]):
		nodes["occluder"].queue_free()
	_wall_nodes.erase(tile)
	if _astar != null:
		_astar.set_point_solid(tile, false)
	_renderer.queue_redraw()
	return true


func _spawn_entities() -> void:
	# Player at the top-left cell, enemy at the far bottom-right cell.
	var player_cell := Vector2i(1, 1)
	var enemy_cell := Vector2i(maze.width - 2, maze.height - 2)

	player = PlayerScene.instantiate()
	player.position = _tile_centre(player_cell.x, player_cell.y)
	_entities.add_child(player)

	enemy = EnemyScene.instantiate()
	enemy.position = _tile_centre(enemy_cell.x, enemy_cell.y)
	enemy.bind_level(self)
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
		_spawn_larva_at(cell)
		placed += 1


## Spawn one larva at a random open cell that no spider is standing on.
func _spawn_larva_at_random() -> void:
	var cells := maze.open_cells()
	if cells.is_empty():
		return
	var occupied := {}
	for spider in get_tree().get_nodes_in_group("spiders"):
		var s := spider as Node2D
		if s != null:
			occupied[tile_of(s.global_position)] = true
	cells.shuffle()
	for cell in cells:
		if not occupied.has(cell):
			_spawn_larva_at(cell)
			return


func _spawn_larva_at(cell: Vector2i) -> void:
	var larva := LarvaScene.instantiate()
	larva.position = _tile_centre(cell.x, cell.y)
	_entities.add_child(larva)
	if larva.has_method("set_facing"):
		larva.set_facing(TileTypes.default_facing(maze.classify(cell.x, cell.y)))


func _tile_centre(tx: int, ty: int) -> Vector2:
	return Vector2((tx + 0.5) * TILE_SIZE, (ty + 0.5) * TILE_SIZE)
