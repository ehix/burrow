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
