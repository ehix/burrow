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

## Dual-Plane Map Architecture (design §1): the ground floor and the inverted
## ceiling floor directly above it. A spider's PlaneComponent tracks which one
## it currently occupies; `is_blocked()` is the single seam both planes'
## GridMover.block_check should route through.
enum Layer { GROUND, CEILING }

@onready var _canvas_modulate: CanvasModulate = $CanvasModulate
@onready var _walls: StaticBody2D = $Walls
@onready var _occluders: Node2D = $Occluders
@onready var _renderer: MazeRenderer = $Renderer
@onready var _entities: Node2D = $Entities

var maze: MazeData
## The inverted floor plane above `maze` — see CeilingData. Built alongside
## `maze` in build(); shares its wall geometry, ignores its pits.
var ceiling: CeilingData
var player: Node2D
var enemy: Node2D
var _astar: AStarGrid2D
var _larva_cap := LARVA_COUNT
var _spawn_accum := 0.0
## Wall tile -> {collision, occluder}, so the dev "remove wall" tool (and
## Seismic Compaction's collapse pass) can find/free or (re)create the exact
## nodes for a tile.
var _wall_nodes: Dictionary = {}
## Pit/flood tile -> its visual marker, so MazeData's ground-hazard overlay
## stays visible in sync — mirrors _wall_nodes.
var _pit_nodes: Dictionary = {}
var _hazard_director: HazardDirector


func _ready() -> void:
	# Lets skills/hazards find "the current level" generically (e.g.
	# RemoveWallsSkill, BlockadeSkill) without needing it threaded through
	# every call site the way Enemy.bind_level() does.
	add_to_group("level")


## Build the whole level. Called by World right after instancing.
func build() -> void:
	maze = MazeGenerator.generate(MAZE_COLS, MAZE_ROWS, GameState.maze_seed(), LOOP_CHANCE)
	ceiling = CeilingData.new(maze)
	_renderer.setup(maze, TILE_SIZE)
	_build_collision_and_occluders()
	_astar = GridNav.build(maze, TILE_SIZE)
	_larva_cap = mini(LARVA_CAP_MAX, maxi(LARVA_COUNT, maze.open_cells().size() / LARVA_TILES_PER_CAP))
	_spawn_entities()
	apply_darkness()
	_hazard_director = HazardDirector.new()
	add_child(_hazard_director)
	_hazard_director.bind_level(self)


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
	for y in maze.height:
		for x in maze.width:
			if not maze.is_open(x, y):
				_spawn_wall_node(Vector2i(x, y))


## Create and track the collision + occluder pair for a wall tile. Shared by
## the initial build pass and collapse_tile_at (Seismic Compaction's collapse
## pass) — the exact inverse of what dev_remove_wall_at frees.
func _spawn_wall_node(tile: Vector2i) -> void:
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(TILE_SIZE, TILE_SIZE)
	var half := TILE_SIZE * 0.5
	var occ_poly := OccluderPolygon2D.new()
	occ_poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])

	var centre := _tile_centre(tile.x, tile.y)
	var col := CollisionShape2D.new()
	col.shape = wall_shape
	col.position = centre
	_walls.add_child(col)
	var occ := LightOccluder2D.new()
	occ.occluder = occ_poly
	occ.position = centre
	_occluders.add_child(occ)
	_wall_nodes[tile] = {"collision": col, "occluder": occ}


## Dev tool (X): destroy the wall tile at `tile`, carving it into floor. Frees
## its collision + occluder, opens it in the maze data and the AStar grid, and
## redraws. No-op out of bounds or if the tile is already open. Deliberately
## unrestricted (even on the boundary) — this is a debug cheat, not the
## production-facing path; see RemoveWallsSkill for the boundary-gated one.
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


## True for the outermost ring of tiles — convenience wrapper for
## MazeData.is_boundary(), consulted by production wall-editing skills/
## hazards (RemoveWallsSkill, Seismic Compaction, Centipede Express), never by
## the dev cheat above.
func is_boundary(tile: Vector2i) -> bool:
	return maze != null and maze.is_boundary(tile.x, tile.y)


## Whether stepping onto `tile` is blocked on `plane` (design §1) — the single
## seam a PlaneComponent-driven GridMover.block_check should route through, so
## ground and ceiling stepping share one code path.
func is_blocked(tile: Vector2i, plane: Layer) -> bool:
	if maze == null:
		return true
	if plane == Layer.CEILING:
		return ceiling.is_blocked(tile.x, tile.y)
	return maze.is_ground_blocked(tile.x, tile.y)


## Flag/clear a ground-hazard tile (pit or flood) and keep its visual marker
## in sync with MazeData's overlay. The one entry point hazards/skills/dev
## tools should use instead of poking `maze.set_pit` directly.
func set_pit_at(tile: Vector2i, value: bool) -> void:
	if maze == null:
		return
	maze.set_pit(tile.x, tile.y, value)
	if value:
		if not _pit_nodes.has(tile):
			_pit_nodes[tile] = _spawn_pit_marker(tile)
	else:
		var marker = _pit_nodes.get(tile)
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
		_pit_nodes.erase(tile)


func _spawn_pit_marker(tile: Vector2i) -> Node2D:
	var half := TILE_SIZE * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	poly.color = Color(0.15, 0.08, 0.05, 0.85)
	poly.position = _tile_centre(tile.x, tile.y)
	add_child(poly)
	return poly


## BlockadeSkill: patch a pit tile for ground traversal by placing a blockade
## on it. No-op if `tile` isn't currently a pit.
func patch_pit_at(tile: Vector2i) -> void:
	set_pit_at(tile, false)


## Force one eligible hazard to fire right now, bypassing its schedule (dev
## tool H) — HazardDirector's own base intervals (50-120s) are far too slow to
## exercise interactively otherwise.
func trigger_random_hazard_now() -> void:
	if _hazard_director != null:
		_hazard_director.trigger_random_now()


## Inverse of dev_remove_wall_at: collapses an open, currently-unoccupied tile
## back into a wall (Seismic Compaction's collapse pass). No-op out of
## bounds, on a boundary tile (guardrail — re-checked defensively even though
## callers should already filter via MazeData.is_boundary), or if the tile is
## already a wall.
func collapse_tile_at(tile: Vector2i) -> bool:
	if maze == null or maze.is_boundary(tile.x, tile.y):
		return false
	if not (tile.x >= 0 and tile.x < maze.width and tile.y >= 0 and tile.y < maze.height):
		return false
	if not maze.is_open(tile.x, tile.y):
		return false
	maze.set_wall(tile.x, tile.y)
	_spawn_wall_node(tile)
	if _astar != null:
		_astar.set_point_solid(tile, true)
	_renderer.queue_redraw()
	return true


func _spawn_entities() -> void:
	# Player at the top-left cell, enemy at the far bottom-right cell.
	var player_cell := Vector2i(1, 1)
	var enemy_cell := Vector2i(maze.width - 2, maze.height - 2)

	player = PlayerScene.instantiate()
	player.position = _tile_centre(player_cell.x, player_cell.y)
	_entities.add_child(player)
	if player.has_method("bind_level"):
		player.bind_level(self)

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
