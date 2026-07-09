class_name Earthworm
extends StaticBody2D
## Hazard/obstacle creature (design §6): highly durable, inedible, blocks a
## corridor tile like a wall until melee'd enough times — on the world
## collision layer, so it blocks spiders via their existing test_move checks
## with zero changes to Player/Enemy's own collision masks (same approach as
## Blockade). A landed melee hit doesn't kill it — it flips to RETREATING and
## burrows toward the nearest map-boundary tile, then despawns there.
## "Burrows out of map bounds" is flavour for "despawns at the edge, freeing
## the corridor": it never actually steps outside the maze grid, so the
## outer-boundary guardrail is never at stake here. Instanced by
## Level._seed_earthworms(); `take_hit()` is called from Player._melee only
## (not Enemy — Enemy's own melee only ever targets the player directly, it
## has no "hit whatever's in front" sweep to extend). Placeholder visual: a
## drawn worm silhouette, no art asset yet.

enum State { BLOCKING, RETREATING }

@export var hits_to_flee: int = 4
@export var retreat_speed: float = 60.0

var state: State = State.BLOCKING

var _hits := 0
var _level: Node
var _retreat_dir := Vector2.ZERO


func _ready() -> void:
	add_to_group("earthworms")


func _draw() -> void:
	draw_rect(Rect2(Vector2(-16, -6), Vector2(32, 12)), Color(0.65, 0.5, 0.35, 0.9))


func bind_level(level: Node) -> void:
	_level = level


## Called by a landed melee/web hit. Does not use HealthComponent — an
## earthworm can't be killed, only driven off.
func take_hit() -> void:
	if state == State.RETREATING:
		return
	_hits += 1
	if _hits >= hits_to_flee:
		_begin_retreat()


func _begin_retreat() -> void:
	state = State.RETREATING
	_retreat_dir = _direction_to_nearest_boundary()


func _physics_process(delta: float) -> void:
	if state != State.RETREATING or _level == null:
		return
	global_position += _retreat_dir * retreat_speed * delta
	if _is_at_boundary():
		queue_free()


func _direction_to_nearest_boundary() -> Vector2:
	if _level == null or not _level.has_method("map_pixel_size"):
		return Vector2.RIGHT
	var size: Vector2 = _level.map_pixel_size()
	var candidates := {
		Vector2.LEFT: global_position.x,
		Vector2.RIGHT: size.x - global_position.x,
		Vector2.UP: global_position.y,
		Vector2.DOWN: size.y - global_position.y,
	}
	var best_dir := Vector2.RIGHT
	var best_dist := INF
	for dir in candidates:
		if candidates[dir] < best_dist:
			best_dist = candidates[dir]
			best_dir = dir
	return best_dir


func _is_at_boundary() -> bool:
	if _level == null or not _level.has_method("map_pixel_size"):
		return false
	var size: Vector2 = _level.map_pixel_size()
	return global_position.x <= 0.0 or global_position.y <= 0.0 \
		or global_position.x >= size.x or global_position.y >= size.y
