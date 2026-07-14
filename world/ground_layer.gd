class_name GroundLayer
extends CanvasGroup
## Everything ground-resident that should read as a hazy background layer
## while the player is on the ceiling (tunnel visual rework Phase 2, design:
## docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md) --
## FloorRenderer's floor tiles, hazard markers (pits/water), larvae, and
## items all get parented here (see Level's spawn methods). A CanvasGroup
## flattens all of that into one texture so a single shader pass can
## desaturate/darken it as a unit, rather than tinting each child
## individually. Plane-aware entities (Player/Enemy and anything they can
## place on either plane) stay outside this node -- they already have
## their own per-entity dimming (Level._refresh_plane_focus's body_alpha),
## a different question ("is this specific entity on the off-plane") from
## "is this static ground content in the background right now." Both
## Centipede types stay outside this node too, for a different reason:
## a Centipede's body is the same width as the tunnel itself, so it must
## read identically regardless of plane, unlike a loose larva or item.

const GroundDimShader := preload("res://assets/shaders/ground_dim.gdshader")

var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = GroundDimShader
	material = _material


## Toggles the hazy-background treatment -- Level calls this from
## _refresh_plane_focus() whenever the focus plane (the player's own)
## changes: dimmed while CEILING is in focus (the ground is background),
## full clarity while GROUND is in focus (the ground is what's underfoot).
func set_dimmed(dimmed: bool) -> void:
	_material.set_shader_parameter("dim_enabled", dimmed)
