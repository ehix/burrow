class_name CentipedeExpressRider
extends Node2D
## The Centipede Express hazard's own creature (design follow-up, corrected
## after playtest feedback on the first pass): unlike the obstacle Centipede
## (a stationary BLOCKING body you have to fight off), this one only ever
## moves -- entering the map from one boundary edge, crawling in a straight
## line at a faster pace than the obstacle Centipede's own crawl, carving
## open whatever wall stands in its way as it goes (rather than the whole
## corridor being pre-carved before it appears), destroying any larva/trap/
## item it crawls over, and shoving any spider caught in its path out of the
## way (Centipede.shove_spiders_out_of(), the exact primitive the obstacle
## Centipede's own crawl step uses). If it runs into another Centipede's own
## body it deflects 90 degrees rather than plowing through or stopping dead,
## and keeps going -- so it doesn't necessarily exit from the edge directly
## opposite where it came in. It never takes a hit and never becomes a
## permanent obstacle -- once its tail clears whichever edge it eventually
## reaches, it frees itself.

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
## Once the head's next step would be the boundary ring, travel is done and
## the body just keeps advancing in a straight line off the map -- no more
## carving/shoving/deflecting, mirrors Centipede._exit_step()'s own
## "skip every ordinary guard" reasoning.
var _exiting := false
## Counts down body_length + 1 once _exiting starts: body_length steps
## alone only brings the tail as far as the boundary ring tile itself --
## still a solid, rendered wall block, not genuinely off-map -- so it would
## still look like it's sitting right at the edge the instant it frees
## (the same off-by-one found in Centipede._begin_exit(), fixed there too).
var _exit_steps_remaining := 0


func _ready() -> void:
	add_to_group("centipede_express_riders")


func bind_level(level: Node) -> void:
	_level = level


## Starts the whole body tucked off-map, `body_length` tiles behind `entry`
## along `direction` (tile_centre() is pure arithmetic, so an out-of-bounds
## tile position is perfectly safe -- Centipede._exit_step() relies on the
## same fact), so the very first steps crawl it INTO view at `entry` instead
## of popping into existence already mid-map.
func start_run(entry: Vector2i, direction: Vector2i) -> void:
	_direction = direction
	_exiting = false
	_tiles.clear()
	for i in body_length:
		_tiles.append(entry - direction * (i + 1))
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


## A 90-degree clockwise turn: RIGHT -> DOWN -> LEFT -> UP -> RIGHT.
static func _turn_clockwise(direction: Vector2i) -> Vector2i:
	return Vector2i(-direction.y, direction.x)


## A 90-degree counter-clockwise turn: RIGHT -> UP -> LEFT -> DOWN -> RIGHT.
static func _turn_counter_clockwise(direction: Vector2i) -> Vector2i:
	return Vector2i(direction.y, -direction.x)


## Advances one tile every tick. While still traveling: deflects 90 degrees
## whenever the next tile in its current heading is another Centipede's own
## body -- it doesn't plow through one obstacle Centipede to reach another,
## it turns and keeps going. The turn direction (clockwise or counter-
## clockwise) is picked once per collision, at random, rather than always
## the same way, and re-tried up to all 4 headings (so it can't get stuck
## oscillating between two Centipede-occupied neighbors); if every heading
## is blocked (fully boxed in -- extremely unlikely), it just waits and
## retries next tick rather than forcing its way through. Every Centipede
## it collides with along the way registers as a real hit on that body --
## Centipede.hit_segment_at() both nudges the exact segment struck
## (CombatFx.shunt, the same visual a melee/web-shot hit already gives) and
## counts toward its shared hits_to_flee counter, so repeatedly running into
## the express train can drive an obstacle Centipede off just like combat
## does. Once the next tile would be the boundary ring, travel is over
## regardless of heading and it switches to a straight, unconditional exit
## crawl (no more carving/shoving/deflecting -- past the ring is solid
## boundary and beyond, by design never carved or walkable, see
## Centipede._exit_step()'s identical reasoning).
func _step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	if _exiting:
		_tiles.push_front(_tiles[0] + _direction)
		_tiles.pop_back()
		_sync_segments()
		_exit_steps_remaining -= 1
		if _exit_steps_remaining <= 0:
			queue_free()
		else:
			_schedule_next_step()
		return
	var next_tile: Vector2i = _tiles[0] + _direction
	var turn_clockwise := randi() % 2 == 0
	var deflect_attempts := 0
	while not _level.is_boundary(next_tile) and deflect_attempts < 4:
		var blocked := Centipede.segment_at_tile(get_tree(), next_tile)
		if blocked == null:
			break
		blocked.hit_segment_at(next_tile, Vector2(_direction))
		_direction = _turn_clockwise(_direction) if turn_clockwise else _turn_counter_clockwise(_direction)
		next_tile = _tiles[0] + _direction
		deflect_attempts += 1
	if not _level.is_boundary(next_tile) and Centipede.segment_at_tile(get_tree(), next_tile) != null:
		# Boxed in on all 4 sides by other Centipedes -- exceedingly
		# unlikely, but wait for one to move rather than forcing through.
		_schedule_next_step()
		return
	if _level.is_boundary(next_tile):
		_exiting = true
		_exit_steps_remaining = body_length + 1
		_schedule_next_step()
		return
	if not _level.maze.is_open(next_tile.x, next_tile.y):
		_level.dev_remove_wall_at(next_tile)
	Centipede.shove_spiders_out_of(get_tree(), next_tile, _direction)
	_level._destroy_occupants_at(next_tile)
	_tiles.push_front(next_tile)
	_tiles.pop_back()
	_sync_segments()
	_schedule_next_step()


func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])
