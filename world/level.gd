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
## Pits seeded naturally at build time (design §7), away from both spawns —
## without these the ceiling plane has nothing to bypass in a normal
## playthrough short of the Water Ingress hazard or the dev pit-toggle tool.
const NATURAL_PIT_COUNT := 2
## World items seeded per depth (design §5): a mix of Fungus Poison/Sense,
## Seed Pod, and Lure pickups — all picked up the same way now.
const ITEM_SPAWN_COUNT := 3
## Earthworm obstacles seeded per depth (design §6).
const EARTHWORM_COUNT := 1

const PlayerScene := preload("res://entities/player/player.tscn")
const EnemyScene := preload("res://entities/enemy/enemy.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")
const EarthwormScene := preload("res://entities/earthworm/earthworm.tscn")
const WorldItemPickupScene := preload("res://entities/items/world_item_pickup.tscn")

## Fog-of-war ambient when darkness is on. White (no darkening) when off.
const DARK_MODULATE := Color(0.05, 0.05, 0.07)
## One consistent "sensed" colour/style for everything Sense reveals —
## spiders/larvae/traps get the real outline shader; walls/pits (no per-tile
## sprite to shader-outline — the whole maze is one batched MazeRenderer
## draw) get a hand-drawn boundary trace in the same colour; items/
## earthworms (placeholder `_draw()`-only visuals, no sprite either) get a
## hand-drawn box outline in the same colour. One visual language, not three.
const SENSE_OUTLINE_COLOR := Color(0.75, 0.9, 1.0, 0.9)

## Dual-Plane Map Architecture (design §1): the ground floor and the inverted
## ceiling floor directly above it. A spider's PlaneComponent tracks which one
## it currently occupies; `is_blocked()` is the single seam both planes'
## GridMover.block_check should route through.
enum Layer { GROUND, CEILING }

## Sense's structural (wall/pit) outline: traces only the true boundary of
## the given tile sets against their non-member/out-of-radius neighbours —
## a proper edge outline, not a filled rectangle per tile. Repopulated and
## redrawn from scratch each frame while Sense is active.
class SenseStructureOutline:
	extends Node2D

	var wall_tiles: Dictionary = {}
	var pit_tiles: Dictionary = {}
	var tile_size: float = 48.0
	var line_color: Color = Color.WHITE

	func _draw() -> void:
		_draw_region_boundary(wall_tiles)
		_draw_region_boundary(pit_tiles)

	func _draw_region_boundary(region: Dictionary) -> void:
		var half := tile_size * 0.5
		for tile in region.keys():
			var centre := Vector2((tile.x + 0.5) * tile_size, (tile.y + 0.5) * tile_size)
			if not region.has(tile + Vector2i(0, -1)):
				draw_line(centre + Vector2(-half, -half), centre + Vector2(half, -half), line_color, 2.0)
			if not region.has(tile + Vector2i(0, 1)):
				draw_line(centre + Vector2(-half, half), centre + Vector2(half, half), line_color, 2.0)
			if not region.has(tile + Vector2i(-1, 0)):
				draw_line(centre + Vector2(-half, -half), centre + Vector2(-half, half), line_color, 2.0)
			if not region.has(tile + Vector2i(1, 0)):
				draw_line(centre + Vector2(half, -half), centre + Vector2(half, half), line_color, 2.0)


## Sense's point-entity outline (items, earthworms — placeholder `_draw()`-
## only visuals with no sprite for the shader technique): a simple box
## stroke, parented directly to the sensed entity so it moves for free.
class SensePointOutline:
	extends Node2D

	var half_size: Vector2 = Vector2(10, 10)
	var line_color: Color = Color.WHITE

	func _draw() -> void:
		draw_rect(Rect2(-half_size, half_size * 2.0), line_color, false, 2.0)


## Sense's silhouette for a sprite-bearing entity (spider/larva/trap): the
## real entity's own sprite stays wherever CanvasModulate's darkness put it
## — no per-sprite shader can opt out of a canvas-wide tint. This ghost
## mirrors the real sprite's texture and transform on the un-darkened
## SenseLayer instead, with body_alpha forced to 0 so only the outline
## silhouette shows — "sensed", not "seen"; the real body stays hidden.
class SenseGhost:
	extends Sprite2D

	func sync_to(real_sprite: Sprite2D) -> void:
		texture = real_sprite.texture
		global_position = real_sprite.global_position
		global_rotation = real_sprite.global_rotation
		scale = real_sprite.scale
		flip_h = real_sprite.flip_h
		flip_v = real_sprite.flip_v

@onready var _canvas_modulate: CanvasModulate = $CanvasModulate
@onready var _walls: StaticBody2D = $Walls
@onready var _occluders: Node2D = $Occluders
@onready var _renderer: MazeRenderer = $Renderer
@onready var _entities: Node2D = $Entities
## Sense's overlays live here, not under Level directly: CanvasModulate
## darkens the whole default canvas and no per-CanvasItem shader can opt
## out of that — only a separate CanvasLayer can. `follow_viewport_enabled`
## keeps it tracking the camera/world positions like normal gameplay
## content, while staying outside CanvasModulate's tint.
@onready var _sense_layer: CanvasLayer = $SenseLayer

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
var _sense_active: bool = false
var _sense_radius: float = 0.0
## Sprite-bearing node (spider/larva/trap) currently outlined via Sense ->
## true, so entry/exit toggles the refcounted OutlineFx on/off exactly once
## each, not every frame.
var _sense_outlined: Dictionary = {}
## Point entity (item/earthworm) currently highlighted via Sense -> its
## highlight node (a child of the entity itself, so it moves for free).
var _sense_point_highlights: Dictionary = {}
## Single shared node that draws the wall/pit boundary trace — lazily
## created, redrawn from scratch each frame while Sense is active rather
## than one spawned node per tile.
var _sense_structure_outline: Node2D = null


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
	_seed_natural_pits()
	_seed_world_items()
	_seed_earthworms()
	apply_darkness()
	_hazard_director = HazardDirector.new()
	add_child(_hazard_director)
	_hazard_director.bind_level(self)


## Keep the maze stocked (larva spawns), and while Sense is active, keep its
## outline in sync with the player's live position every frame.
func _process(delta: float) -> void:
	if maze == null:
		return
	_spawn_accum += delta
	if _spawn_accum >= LARVA_SPAWN_INTERVAL:
		_spawn_accum = 0.0
		if get_tree().get_nodes_in_group("larvae").size() < _larva_cap:
			_spawn_larva_at_random()
	if _sense_active:
		_update_sense_outlines()


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


## SenseSkill's outline cue (design round 2): "sensed", not "seen" — every
## spider/larva/trap within `radius` of the player gets the shared outline
## shader; wall/pit tiles get a hand-drawn boundary trace; item/earthworm
## placeholders get a hand-drawn box outline. Everything Sense reveals reads
## as an outline, not a lit-up patch — no more light-through-walls (the old
## set_sense_active()). Continuous while active: _process() re-syncs every
## frame as the player moves, so entering/leaving the radius toggles the
## effect on/off in real time. `radius` is ignored when `active` is false.
func set_sense_outline(active: bool, radius: float = 0.0) -> void:
	_sense_active = active
	_sense_radius = radius
	if active:
		_update_sense_outlines()
		return
	for ghost in _sense_outlined.values():
		if ghost != null and is_instance_valid(ghost):
			ghost.queue_free()
	_sense_outlined.clear()
	for highlight in _sense_point_highlights.values():
		if highlight != null and is_instance_valid(highlight):
			highlight.queue_free()
	_sense_point_highlights.clear()
	if _sense_structure_outline != null and is_instance_valid(_sense_structure_outline):
		_sense_structure_outline.wall_tiles.clear()
		_sense_structure_outline.pit_tiles.clear()
		_sense_structure_outline.queue_redraw()


func _update_sense_outlines() -> void:
	if player == null:
		return
	_update_sense_sprite_outlines()
	_update_sense_point_highlights()
	_update_sense_structure_outline()


## Spiders (incl. the player itself), larvae, and web traps all carry a real
## `Sprite`/`Visual` texture — a SenseGhost mirrors it on the un-darkened
## _sense_layer with body_alpha at 0, so only the silhouette outline shows.
## The ghost is spawned once on entry and re-synced to the real sprite's
## current transform every frame while it stays in range (the real entity
## keeps moving), then freed on exit.
func _update_sense_sprite_outlines() -> void:
	var still_in_range: Dictionary = {}
	for group in ["spiders", "larvae", "traps"]:
		for node in get_tree().get_nodes_in_group(group):
			var n2d := node as Node2D
			if n2d == null or not is_instance_valid(n2d):
				continue
			if n2d.global_position.distance_to(player.global_position) > _sense_radius:
				continue
			var sprite := _sense_sprite_of(n2d) as Sprite2D
			if sprite == null:
				continue
			still_in_range[n2d] = true
			var ghost: SenseGhost = _sense_outlined.get(n2d)
			if ghost == null:
				ghost = SenseGhost.new()
				OutlineFx.set_outline(ghost, true, SENSE_OUTLINE_COLOR)
				OutlineFx.set_body_alpha(ghost, 0.0)
				_sense_layer.add_child(ghost)
				_sense_outlined[n2d] = ghost
			ghost.sync_to(sprite)
	for node in _sense_outlined.keys().duplicate():
		if not still_in_range.has(node):
			var ghost = _sense_outlined[node]
			if ghost != null and is_instance_valid(ghost):
				ghost.queue_free()
			_sense_outlined.erase(node)


## Most entities name their visual node "Sprite"; WebTrap names its "Visual".
func _sense_sprite_of(node: Node) -> CanvasItem:
	var sprite := node.get_node_or_null("Sprite") as CanvasItem
	if sprite != null:
		return sprite
	return node.get_node_or_null("Visual") as CanvasItem


## Per-group box half-size for the point-entity outline, roughly matching
## each placeholder's own `_draw()` shape.
const SENSE_POINT_HALF_SIZE := {
	"world_items": Vector2(9, 9),
	"earthworms": Vector2(18, 8),
}


## World items and earthworms are placeholder `_draw()`-only visuals (no
## sprite/texture for the shader technique) — they get a hand-drawn box
## outline instead, parented under the un-darkened _sense_layer (not the
## entity itself, which lives in the normal, darkened tree) and re-synced
## to the entity's position every frame while it stays in range.
func _update_sense_point_highlights() -> void:
	var still_in_range: Dictionary = {}
	for group in SENSE_POINT_HALF_SIZE.keys():
		var half_size: Vector2 = SENSE_POINT_HALF_SIZE[group]
		for node in get_tree().get_nodes_in_group(group):
			var n2d := node as Node2D
			if n2d == null or not is_instance_valid(n2d):
				continue
			if n2d.global_position.distance_to(player.global_position) > _sense_radius:
				continue
			still_in_range[n2d] = true
			var outline: SensePointOutline = _sense_point_highlights.get(n2d)
			if outline == null:
				outline = SensePointOutline.new()
				outline.half_size = half_size
				outline.line_color = SENSE_OUTLINE_COLOR
				_sense_layer.add_child(outline)
				_sense_point_highlights[n2d] = outline
			outline.global_position = n2d.global_position
	for node in _sense_point_highlights.keys().duplicate():
		if not still_in_range.has(node):
			var outline = _sense_point_highlights[node]
			if outline != null and is_instance_valid(outline):
				outline.queue_free()
			_sense_point_highlights.erase(node)


## Walls and pits have no per-tile sprite — recomputes which tiles are
## currently within radius and hands the sets to the single shared
## SenseStructureOutline drawer (parented under the un-darkened
## _sense_layer), which traces just their boundary.
func _update_sense_structure_outline() -> void:
	if _sense_structure_outline == null or not is_instance_valid(_sense_structure_outline):
		var outline := SenseStructureOutline.new()
		outline.tile_size = TILE_SIZE
		outline.line_color = SENSE_OUTLINE_COLOR
		_sense_layer.add_child(outline)
		_sense_structure_outline = outline
	var walls: Dictionary = {}
	for tile in _wall_nodes.keys():
		if centre_of(tile).distance_to(player.global_position) <= _sense_radius:
			walls[tile] = true
	var pits: Dictionary = {}
	for tile in _pit_nodes.keys():
		if centre_of(tile).distance_to(player.global_position) <= _sense_radius:
			pits[tile] = true
	var drawer := _sense_structure_outline as SenseStructureOutline
	drawer.wall_tiles = walls
	drawer.pit_tiles = pits
	drawer.queue_redraw()


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
	if Blockade.at_tile(get_tree(), tile, TILE_SIZE) != null:
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
	# Add to the tree before bind_level (mirroring the player above): Enemy's
	# PlaneComponent is an @onready var, so bind_level's `_plane.level = level`
	# needs _ready() to have already run — calling bind_level first left
	# _plane null (ceiling/plane mechanics rework surfaced this).
	_entities.add_child(enemy)
	enemy.bind_level(self)

	_spawn_larvae([player_cell, enemy_cell])


## Flag a handful of random open, non-spawn tiles as pits so the ceiling
## plane has something to bypass in a normal playthrough, not just via the
## Water Ingress hazard or the dev pit-toggle tool.
func _seed_natural_pits() -> void:
	var reserved := {tile_of(player.global_position): true, tile_of(enemy.global_position): true}
	var cells := maze.open_cells()
	cells.shuffle()
	var placed := 0
	for cell in cells:
		if placed >= NATURAL_PIT_COUNT:
			break
		if reserved.has(cell):
			continue
		set_pit_at(cell, true)
		placed += 1


## Scatter a mix of Fungus Poison/Sense, Seed Pod, and Lure pickups (design
## §5) across random open, non-spawn, non-pit tiles — a pit-tile spawn would
## be permanently unreachable, since pits block all ground-plane movement.
func _seed_world_items() -> void:
	var reserved := {tile_of(player.global_position): true, tile_of(enemy.global_position): true}
	var cells := maze.open_cells()
	cells.shuffle()
	var placed := 0
	for cell in cells:
		if placed >= ITEM_SPAWN_COUNT:
			break
		if reserved.has(cell) or maze.is_pit(cell.x, cell.y):
			continue
		_spawn_random_item_at(cell)
		reserved[cell] = true
		placed += 1


## One of four roughly-equal outcomes — Lure, Fungus Poison, Fungus Sense,
## or Seed Pod — all picked up the same way now (item/inventory rework).
## Deployment/consumption happens on InventoryComponent.use(), not on
## pickup; a picked-up Lure deploys a LurePulse wherever it's used.
func _spawn_random_item_at(cell: Vector2i) -> void:
	var world_pos := _tile_centre(cell.x, cell.y)
	match randi() % 4:
		0:
			_spawn_pickup_at(world_pos, LureItem.new())
		1:
			_spawn_pickup_at(world_pos, FungusPoisonItem.new())
		2:
			_spawn_pickup_at(world_pos, FungusSenseItem.new())
		_:
			_spawn_pickup_at(world_pos, SeedPodItem.new())


func _spawn_pickup_at(world_pos: Vector2, item: ConsumableItem) -> void:
	var pickup := WorldItemPickupScene.instantiate()
	pickup.item = item
	_entities.add_child(pickup)
	pickup.global_position = world_pos


## Seed a handful of Earthworm obstacles (design §6) across random open,
## non-spawn tiles.
func _seed_earthworms() -> void:
	var reserved := {tile_of(player.global_position): true, tile_of(enemy.global_position): true}
	var cells := maze.open_cells()
	cells.shuffle()
	var placed := 0
	for cell in cells:
		if placed >= EARTHWORM_COUNT:
			break
		if reserved.has(cell):
			continue
		var worm := EarthwormScene.instantiate()
		worm.global_position = _tile_centre(cell.x, cell.y)
		worm.bind_level(self)
		_entities.add_child(worm)
		placed += 1


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
	larva.bind_level(self)
	if larva.has_method("set_facing"):
		larva.set_facing(TileTypes.default_facing(maze.classify(cell.x, cell.y)))


func _tile_centre(tx: int, ty: int) -> Vector2:
	return Vector2((tx + 0.5) * TILE_SIZE, (ty + 0.5) * TILE_SIZE)
