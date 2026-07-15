class_name PlaneComponent
extends Node
## Tracks which physical plane (ground/ceiling) the owner currently occupies
## (design §1: Dual-Plane Map Architecture). Player.gd wires its GridMover's
## block_check through `blocked(tile, dir)` here while on the ceiling (ground
## stepping keeps its existing test_move-based check unchanged — see
## Player._blocked). `level` is normally assigned directly by whoever binds
## the level (Player.bind_level, mirroring Enemy.bind_level); `level_path` is
## a fallback for a scene that wants to wire it by NodePath instead.
##
## Ceiling/plane mechanics rework: also the shared plane authority for combat
## and tile-stacking (effective_plane()/same_plane()), and owns the
## knockdown-plus-fall-damage penalty for getting hit while on the ceiling
## (apply_hit_fall()) — kept here rather than on Hurtbox so any future
## plane-aware entity gets consistent fall behavior automatically.

signal plane_changed(plane: Level.Layer)

## How many times _shove() retries when every cardinal direction is blocked
## (e.g. a Centipede body or Blockade currently seals all four sides) before
## giving up, and how long it waits between attempts. Confirmed via a live
## sweep across many real maze positions: rare (roughly 1 in 30 spots in a
## typical maze), but a one-shot attempt left the two spiders permanently
## overlapping whenever it happened, since nothing else ever revisits it.
const SHOVE_MAX_ATTEMPTS := 20
const SHOVE_RETRY_INTERVAL := 0.1

@export var level_path: NodePath
## First-pass balance number — tune during playtest.
@export var fall_damage: float = 8.0

var level: Level
var current_plane: Level.Layer = Level.Layer.GROUND


func _ready() -> void:
	if level == null and not level_path.is_empty():
		level = get_node_or_null(level_path) as Level


func transition() -> void:
	current_plane = Level.Layer.CEILING if current_plane == Level.Layer.GROUND else Level.Layer.GROUND
	_shove_occupant_out_of_the_way()
	plane_changed.emit(current_plane)
	EventBus.plane_changed.emit(get_parent(), current_plane)


## A transition swaps which plane the owner sits on *in place* -- a ground
## spider and a ceiling spider normally never contest a tile at all (see
## GridMover.spider_tile_contested), but the instant this owner arrives on
## the new plane it can find itself standing on the exact tile another
## spider already occupies there (e.g. the enemy has been holding position
## on the ground the whole time the player was up on the ceiling overhead).
## Shoves that occupant out of the way instead of letting them overlap or
## silently blocking the transition — reuses GridMover.knockback(), the same
## forced-shove primitive a landed combat hit or a crawling Centipede body
## already uses (see Centipede.shove_spiders_out_of), trying all four
## cardinal directions since there's no natural "push direction" here (both
## bodies start from the same point).
func _shove_occupant_out_of_the_way() -> void:
	if level == null:
		return
	var owner := get_parent() as Node2D
	if owner == null:
		return
	var tile := level.tile_of(owner.global_position)
	for node in owner.get_tree().get_nodes_in_group("spiders"):
		if node == owner:
			continue
		var other := node as Node2D
		if other == null or effective_plane(other) != current_plane:
			continue
		var other_mover := other.get_node_or_null("GridMover") as GridMover
		if other_mover == null or other_mover.committed_tile() != tile:
			continue
		_shove(other_mover)


## knockback() refuses to interrupt an in-flight step (by design — see its
## own doc comment: "Ignored mid-step"), but the enemy is rarely standing
## still — it's almost always mid-step from its own chase/patrol AI the
## instant a transition lands on its tile, which silently dropped the shove
## every time this actually mattered in real play. committed_tile() already
## reflects a mid-step mover's landing tile throughout its step, so the
## contested tile was correctly detected either way; this just waits for
## that in-flight step to actually land before retrying, rather than giving
## up. Retries again if a newly-landed mover immediately buffers into
## another step of its own (chase AI can do this indefinitely) — in that
## case its own movement is carrying it off the tile anyway.
##
## Also retries (bounded — SHOVE_MAX_ATTEMPTS/SHOVE_RETRY_INTERVAL) if every
## cardinal direction is genuinely blocked right now: confirmed via a live
## sweep across real maze positions that this does happen (a Centipede body
## or Blockade currently sealing every side of that specific tile) — a
## one-shot attempt left the two spiders permanently stuck overlapping
## whenever it did, since nothing else ever revisits an already-finished
## transition. attempts_left defaults via a named const rather than being
## threaded through every call site.
func _shove(mover: GridMover, attempts_left: int = SHOVE_MAX_ATTEMPTS) -> void:
	if not is_instance_valid(mover) or attempts_left <= 0:
		return
	if mover.is_moving():
		mover.step_finished.connect(func() -> void: _shove(mover, attempts_left), CONNECT_ONE_SHOT)
		return
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if mover.knockback(dir):
			return
	if mover.is_inside_tree():
		mover.get_tree().create_timer(SHOVE_RETRY_INTERVAL).timeout.connect(
			func() -> void: _shove(mover, attempts_left - 1))


## Blocking seam: whether stepping from `tile` in `dir` is blocked on
## whichever plane this owner currently occupies.
func blocked(tile: Vector2i, dir: Vector2i) -> bool:
	if level == null:
		return false
	return level.is_blocked(tile + dir, current_plane)


## A node's plane if it has a PlaneComponent child, else GROUND — the
## default for every entity that never tracks planes at all (larvae,
## decoys, hatchlings, traps, Blockade).
static func effective_plane(node: Node) -> Level.Layer:
	if node == null:
		return Level.Layer.GROUND
	var plane := node.get_node_or_null("PlaneComponent") as PlaneComponent
	return plane.current_plane if plane != null else Level.Layer.GROUND


static func same_plane(a: Node, b: Node) -> bool:
	return effective_plane(a) == effective_plane(b)


## Called by Hurtbox after a hit lands: knocks the owner down to the ground
## plane and applies bonus fall damage. No-op while already on the ground.
func apply_hit_fall(health: HealthComponent) -> void:
	if current_plane != Level.Layer.CEILING:
		return
	transition()
	if health != null:
		health.take_damage(fall_damage)
