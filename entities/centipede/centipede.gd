class_name Centipede
extends Node2D
## Multi-tile segmented obstacle creature (Centipede entity, sub-project H,
## replaces Earthworm): stationary and non-combatant while intact, blocking
## a corridor on BOTH ground and ceiling planes at once (see
## Level.is_blocked()) across `body_length` tiles. `_tiles` is the single
## source of truth for which tiles the body currently occupies (head first,
## `_tiles[0]`); CentipedeSegment children are pure visual/physical mirrors
## of it, repositioned whenever `_tiles` changes. Any combative hit --
## melee or web-shot, from Player or Enemy, landing on ANY segment -- adds
## to one shared `_hits` counter (mirrors Blockade's plain counter, not
## HealthComponent: this creature can't be killed, only driven off).

const SegmentScene := preload("res://entities/centipede/centipede_segment.tscn")

enum State { BLOCKING, FLEEING, RELOCATING }

@export var hits_to_flee: int = 4
@export var body_length: int = 4
@export var crawl_step_time: float = 0.35

var state: State = State.BLOCKING
var _tiles: Array[Vector2i] = []
var _hits := 0
var _level: Node
var _segments: Array[CentipedeSegment] = []
var _target: Vector2i
var _path: Array[Vector2i] = []


func _ready() -> void:
	add_to_group("centipedes")


func bind_level(level: Node) -> void:
	_level = level


## Lays out the body at `tiles` (head first) and (re)builds its segment
## visuals to match. Called once by Level._seed_centipedes() right after
## instancing and bind_level().
func spawn_at(tiles: Array[Vector2i]) -> void:
	_tiles = tiles.duplicate()
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		segment.global_position = _level.tile_centre(tile)
		_segments.append(segment)


## Any segment being hit lands here (CentipedeSegment.take_hit() forwards to
## its parent) -- one shared counter for the whole body. A no-op once
## already FLEEING/RELOCATING, mirroring Earthworm.take_hit()'s guard
## against re-triggering mid-retreat.
func take_hit() -> void:
	if state != State.BLOCKING:
		return
	_hits += 1
	if _hits >= hits_to_flee:
		_begin_flee()


func _begin_flee() -> void:
	state = State.FLEEING
	_target = _nearest_boundary_tile()
	_start_crawl()
	_schedule_next_step()


## Closest of the four map edges to the current head, as a real tile
## coordinate (not a raw direction -- unlike Earthworm's own
## _direction_to_nearest_boundary(), which moved in a straight line that
## could clip through walls, this feeds a real wall-aware BFS target).
func _nearest_boundary_tile() -> Vector2i:
	var head: Vector2i = _tiles[0]
	var maze: Object = _level.maze
	var candidates: Dictionary = {
		Vector2i(0, head.y): head.x,
		Vector2i(maze.width - 1, head.y): maze.width - 1 - head.x,
		Vector2i(head.x, 0): head.y,
		Vector2i(head.x, maze.height - 1): maze.height - 1 - head.y,
	}
	var best_tile: Vector2i = Vector2i(0, head.y)
	var best_dist := INF
	for tile in candidates:
		if candidates[tile] < best_dist:
			best_dist = candidates[tile]
			best_tile = tile
	return best_tile


func _start_crawl() -> void:
	_path = _find_path(_tiles[0], _target)


## Schedules one crawl tick crawl_step_time seconds from now, real-timer-
## paced like WaterIngress's own ring scheduling (not per-frame movement --
## this is a slow, deliberate crawl, not player-speed motion).
func _schedule_next_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(crawl_step_time).timeout.connect(_crawl_step)


func _crawl_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	if _path.is_empty():
		# Nowhere to go yet (e.g. still boxed in) -- retry the search next
		# tick rather than freezing or falsely "arriving".
		_start_crawl()
		_schedule_next_step()
		return
	if _path.size() == 1:
		_arrive()
		return
	var next_tile: Vector2i = _path[1]
	if not _level.maze.is_open(next_tile.x, next_tile.y) or _level.is_water_at(next_tile):
		# Something changed underfoot mid-crawl (e.g. a fresh flood) --
		# recompute from where we are now instead of stepping into it.
		_start_crawl()
		_schedule_next_step()
		return
	_level._destroy_occupants_at(next_tile)
	_tiles.push_front(next_tile)
	_tiles.pop_back()
	_sync_segments()
	_path.remove_at(0)
	if next_tile == _target:
		_arrive()
	else:
		_schedule_next_step()


func _arrive() -> void:
	if state == State.FLEEING:
		queue_free()
	elif state == State.RELOCATING:
		state = State.BLOCKING


func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])


## The live Centipede whose body occupies `tile`, or null. Mirrors
## Blockade.at_tile()'s shape but deliberately drops the `tile_size`
## parameter Blockade takes: Blockade only stores `global_position` and
## needs `tile_size` to convert it back to a tile coordinate for comparison,
## but Centipede already stores `_tiles` directly (the whole body's single
## source of truth), so no conversion is needed here.
static func segment_at_tile(tree: SceneTree, tile: Vector2i) -> Centipede:
	for node in tree.get_nodes_in_group("centipedes"):
		var centipede := node as Centipede
		if centipede == null:
			continue
		if tile in centipede._tiles:
			return centipede
	return null


## Local BFS from `from` to `to` (design §6): a tile is passable if it's
## open, not flooded, and not currently occupied by this body's own
## trailing tiles (so a crawl step never tries to path through itself).
## Deliberately separate from the shared Enemy/Player AStar (Level._astar/
## GridNav) -- that grid doesn't treat water as solid at all today, and
## Centipede's own pathing needs (reach a boundary tile, reach a fresh spot)
## are much simpler than Enemy's chase-a-moving-target. Returns [] if
## unreachable.
func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	var occupied := {}
	for tile in _tiles:
		occupied[tile] = true
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var came_from := {from: from}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == to:
			break
		for dir in dirs:
			var next: Vector2i = current + dir
			if came_from.has(next):
				continue
			if not _level.maze.is_open(next.x, next.y):
				continue
			if _level.is_water_at(next):
				continue
			if occupied.has(next):
				continue
			came_from[next] = current
			frontier.append(next)
	if not came_from.has(to):
		return []
	var path: Array[Vector2i] = [to]
	var walk: Vector2i = to
	while walk != from:
		walk = came_from[walk]
		path.append(walk)
	path.reverse()
	return path
