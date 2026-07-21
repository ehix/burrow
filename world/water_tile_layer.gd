class_name WaterTileLayer
extends Node2D
## A single textured square, drawn to exactly fill one maze tile -- used as
## a child layer of Level's water-tile marker (see
## Level._spawn_water_marker()). Two of these stack per flooded tile: a
## static wet-floor base (GroundLayer.dim_material()) and an animated
## water overlay on top (GroundLayer.water_overlay_material()). Both use
## TileTextureVariant.draw_varied() (docs/superpowers/specs/2026-07-20-
## tile-texture-variation-design.md) so a flooded tile doesn't show the
## identical crop every other flooded tile does -- the same fix applied
## to FloorRenderer/MazeRenderer/WallOverdrawMask. Whether this layer
## should wrap (needed for the overlay's TIME-scrolled shader UV to not
## clamp at the texture edge) is set directly on the CanvasItem's own
## texture_repeat property by Level._spawn_water_marker(), not by a field
## on this class -- draw_texture_rect_region (unlike the old
## draw_texture_rect(tile=true) this replaced) has no repeat argument of
## its own.

var texture: Texture2D
var tile_size: float
var modulate_color := Color(1, 1, 1, 1)
var tile: Vector2i


func _draw() -> void:
	var half := tile_size * 0.5
	var rect := Rect2(-half, -half, tile_size, tile_size)
	TileTextureVariant.draw_varied(self, texture, rect, tile, modulate_color)
