class_name CombatFx
extends Object
## Tiny stateless helpers for combat "juice" shared by the spiders.
##
## flash() signals distress by pulsing a sprite red and tweening back to normal.
## shunt() gives a sprite a small offset nudge (a non-committal bump) and slides
## it home. spawn_slash() drops a placeholder melee-impact graphic at a world
## position. All are visual-only: they never touch a body's grid position, so
## they can't desync the GridMover.

const FLASH_COLOR := Color(1.0, 0.35, 0.35)
const FLASH_TIME := 0.25
const SHUNT_TIME := 0.12
const SLASH_TIME := 0.18
const SLASH_COLOR := Color(1.0, 0.95, 0.85, 0.9)


## Placeholder melee-impact graphic: a short arc drawn at the strike point,
## facing `direction`, that fades out and frees itself. Swap for real VFX later.
class SlashVisual:
	extends Node2D

	var _facing := Vector2.RIGHT

	func face(direction: Vector2) -> void:
		if direction != Vector2.ZERO:
			_facing = direction.normalized()

	func _draw() -> void:
		var angle := _facing.angle()
		var radius := 14.0
		var spread := deg_to_rad(50.0)
		draw_arc(Vector2.ZERO, radius, angle - spread, angle + spread, 8, SLASH_COLOR, 3.0)


## Pulse `sprite` red, then fade back to white. No-op if it can't tween yet.
static func flash(sprite: CanvasItem) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	sprite.modulate = FLASH_COLOR
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, FLASH_TIME)


## Nudge `sprite` by `offset` pixels (in its parent's space) and slide it back
## to its rest position. Used for the tiny shunt when a spider crosses a larva.
static func shunt(sprite: Node2D, offset: Vector2) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	var rest := sprite.position
	sprite.position = rest + offset
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "position", rest, SHUNT_TIME)


## Drop a placeholder slash/bite graphic at `world_position`, oriented toward
## `direction`, parented under `holder`. Fades out and frees itself.
static func spawn_slash(holder: Node, world_position: Vector2, direction: Vector2) -> void:
	if holder == null:
		return
	var visual := SlashVisual.new()
	holder.add_child(visual)
	visual.global_position = world_position
	visual.face(direction)
	visual.queue_redraw()
	var tween := visual.create_tween()
	tween.tween_property(visual, "modulate:a", 0.0, SLASH_TIME)
	tween.tween_callback(visual.queue_free)
