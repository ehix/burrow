class_name OutlineFx
extends RefCounted
## Static-only helper (mirrors CombatFx's pattern) for toggling the shared
## outline shader on a sprite — used by Sense (blanket reveal cue) and
## Camouflage (silhouette-while-hidden). Lazily creates and caches a
## ShaderMaterial on the sprite itself on first use, so repeated calls never
## stack a new material.

const OutlineShader := preload("res://assets/shaders/outline.gdshader")


## Toggle the outline effect on `sprite`. No-op if `sprite` is null.
static func set_outline(sprite: CanvasItem, enabled: bool, color: Color = Color.WHITE) -> void:
	if sprite == null:
		return
	var mat := _material_of(sprite)
	mat.set_shader_parameter("outline_enabled", enabled)
	mat.set_shader_parameter("outline_color", color)


static func _material_of(sprite: CanvasItem) -> ShaderMaterial:
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != OutlineShader:
		mat = ShaderMaterial.new()
		mat.shader = OutlineShader
		sprite.material = mat
	return mat
