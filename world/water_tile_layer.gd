class_name WaterTileLayer
extends Node2D
## A single textured square, drawn to exactly fill one maze tile -- used as
## a child layer of Level's water-tile marker (see
## Level._spawn_water_marker()). Two of these stack per flooded tile: a
## static wet-floor base (GroundLayer.dim_material(), repeat=false) and an
## animated water overlay on top (GroundLayer.water_overlay_material(),
## repeat=true so the overlay shader's TIME-scrolled UV sampling wraps
## instead of clamping at the texture edge -- see water_overlay.gdshader).
## draw_texture_rect is the same texture-fill idiom FloorRenderer/
## MazeRenderer already use (9205bbc); a plain Node2D + draw_texture_rect
## sidesteps Polygon2D's own UV-mapping rules entirely, which aren't
## needed here since this always draws exactly one texture onto exactly
## one tile-sized rect.

var texture: Texture2D
var tile_size: float
var modulate_color := Color(1, 1, 1, 1)
var repeat := false


func _draw() -> void:
	var half := tile_size * 0.5
	draw_texture_rect(texture, Rect2(-half, -half, tile_size, tile_size), repeat, modulate_color)
