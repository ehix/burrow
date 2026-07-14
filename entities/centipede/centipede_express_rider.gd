class_name CentipedeExpressRider
extends Node2D
## The Centipede Express hazard's own creature (design follow-up, corrected
## after playtest feedback on the first pass): unlike the obstacle Centipede
## (a stationary BLOCKING body you have to fight off), this one only ever
## moves -- entering the map from one boundary edge, crawling in a straight
## line clear across to the opposite edge at a faster pace than the obstacle
## Centipede's own crawl, carving open whatever wall stands in its way as it
## goes (rather than the whole corridor being pre-carved before it appears),
## destroying any larva/trap/item it crawls over, and shoving any spider
## caught in its path out of the way (Centipede.shove_spiders_out_of(), the
## exact primitive the obstacle Centipede's own crawl step uses). It never
## takes a hit and never becomes a permanent obstacle -- once its tail
## clears the far edge it frees itself.

const SegmentScene := preload("res://entities/centipede/centipede_segment.tscn")

@export var body_length: int = 4
## Faster than the obstacle Centipede's default crawl_step_time (0.35s) --
## Centipede Express is meant to read as a quick, disruptive pass through
## the map, not a slow crawl.
@export var step_time: float = 0.15

var _tiles: Array[Vector2i] = []
var _segments: Array[CentipedeSegment] = []
var _level: Node
var _direction := Vector2i.ZERO
var _steps_remaining := 0


func _ready() -> void:
	add_to_group("centipede_express_riders")


func bind_level(level: Node) -> void:
	_level = level


## Starts the whole body tucked off-map, `body_length` tiles behind `entry`
## along `direction` (tile_centre() is pure arithmetic, so an out-of-bounds
## tile position is perfectly safe -- Centipede._exit_step() relies on the
## same fact to crawl a fleeing body out through the boundary), so the very
## first steps crawl it INTO view at `entry` instead of popping into
## existence already mid-map. `total_steps` is how many tiles separate the
## two boundary edges along `direction` (i.e. how far the head must travel
## to clear the far side) -- body_length more steps are added on top so the
## tail also fully exits before the body frees itself.
func start_run(entry: Vector2i, direction: Vector2i, total_steps: int) -> void:
	_direction = direction
	_tiles.clear()
	for i in body_length:
		_tiles.append(entry - direction * (i + 1))
	_steps_remaining = total_steps + body_length
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		segment.global_position = _level.tile_centre(tile)
		_segments.append(segment)
	_schedule_next_step()


func _schedule_next_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(step_time).timeout.connect(_step)


## Advances one tile along `_direction` every tick, unconditionally -- no
## pathing, no fallback: Centipede Express always drives dead straight from
## one boundary edge to the other. Carves the next tile open first if it's
## currently a wall (guardrail: never the boundary ring itself, matching
## every other wall-editing path's own guardrail), then clears it exactly
## like an obstacle Centipede's own crawl step does (shove any spider out of
## the way, destroy any larva/trap/item standing there) before stepping in.
func _step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var next_tile: Vector2i = _tiles[0] + _direction
	if not _level.is_boundary(next_tile) and not _level.maze.is_open(next_tile.x, next_tile.y):
		_level.dev_remove_wall_at(next_tile)
	Centipede.shove_spiders_out_of(get_tree(), next_tile, _direction)
	_level._destroy_occupants_at(next_tile)
	_tiles.push_front(next_tile)
	_tiles.pop_back()
	_sync_segments()
	_steps_remaining -= 1
	if _steps_remaining <= 0:
		queue_free()
	else:
		_schedule_next_step()


func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])
