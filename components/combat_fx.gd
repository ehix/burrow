class_name CombatFx
extends Object
## Tiny stateless helpers for combat "juice" shared by the spiders.
##
## flash() signals distress by pulsing a sprite red and tweening back to normal.
## shunt() gives a sprite a small offset nudge (a non-committal bump) and slides
## it home. Both are visual-only: they never touch the body's grid position, so
## they can't desync the GridMover.

const FLASH_COLOR := Color(1.0, 0.35, 0.35)
const FLASH_TIME := 0.25
const SHUNT_TIME := 0.12


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
