class_name GroundLayer
extends Node2D
## Everything ground-resident that should read as a hazy background layer
## while the player is on the ceiling (tunnel visual rework Phase 2, design:
## docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md) --
## FloorRenderer's floor tiles, hazard markers (pits/water), larvae, and
## items all get parented here (see Level's spawn methods). Every ground
## child gets the *same* ShaderMaterial instance (dim_material()) assigned
## directly, rather than this node compositing them via CanvasGroup (the
## original design): a CanvasGroup with a ShaderMaterial attached silently
## drops any child added *after* the material was assigned and never
## renders it again -- confirmed via an isolated repro with no game code
## involved at all (a bare CanvasGroup + trivial passthrough shader +
## one child added 5 frames late; the late child never appeared, no matter
## how long we waited or how many times the material was reassigned).
## That's a dealbreaker here since larvae spawn continuously all game.
## One shared material + toggling its dim_enabled uniform gets the same
## "whole layer dims/undims together" result already proven out by Player/
## Enemy's shared outline.gdshader material (OutlineFx) -- just applied
## per-child here instead of via a buffer. Plane-aware entities (Player/
## Enemy and anything they can place on either plane) stay outside this
## node -- they already have their own per-entity dimming (Level.
## _refresh_plane_focus's body_alpha), a different question ("is this
## specific entity on the off-plane") from "is this static ground content
## in the background right now." Both Centipede types stay outside this
## node too, for a different reason: a Centipede's body is the same width
## as the tunnel itself, so it must read identically regardless of plane,
## unlike a loose larva or item.

const GroundDimShader := preload("res://assets/shaders/ground_dim.gdshader")

var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = GroundDimShader
	$FloorRenderer.material = _material


## The one ShaderMaterial instance every ground-resident CanvasItem (floor,
## larvae, items, hazard markers) must have assigned -- see this file's own
## doc comment for why a shared per-child material replaces the original
## CanvasGroup compositing approach. Level's spawn methods call this right
## after add_child()ing anything into this layer.
func dim_material() -> ShaderMaterial:
	return _material


## Toggles the hazy-background treatment -- Level calls this from
## _refresh_plane_focus() whenever the focus plane (the player's own)
## changes: dimmed while CEILING is in focus (the ground is background),
## full clarity while GROUND is in focus (the ground is what's underfoot).
func set_dimmed(dimmed: bool) -> void:
	_material.set_shader_parameter("dim_enabled", dimmed)
