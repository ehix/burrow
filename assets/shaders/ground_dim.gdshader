shader_type canvas_item;

#include "res://assets/shaders/dim.gdshaderinc"

// Desaturate + darken pass for GroundLayer's "hazy background" read while
// viewed from the ceiling (tunnel visual rework Phase 2) -- no blur
// convolution, matching the design doc's own recommendation to start with
// the cheaper version and only reach for a true blur pass if playtesting
// shows it's needed. dim_enabled is a plain on/off switch, not a strength
// dial -- GroundLayer is either the background (dimmed) or the plane in
// focus (undimmed), never a partial blend between the two.
uniform float saturation : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 1.0) = 0.75;
uniform bool dim_enabled = false;

void fragment() {
	// No early `return` in fragment() -- this project's renderer rejects it
	// (see outline.gdshader's identical note); every branch funnels into
	// one COLOR assignment instead. Reads the built-in COLOR (Godot's own
	// TEXTURE-sample-times-vertex-color default going into fragment()),
	// not a fresh texture(TEXTURE, UV) sample -- re-sampling TEXTURE
	// directly silently discards the vertex/primitive color for anything
	// drawn untextured (draw_rect/draw_circle/Polygon2D.color -- TEXTURE is
	// then just Godot's flat-white 1x1 dummy), which is how FloorRenderer's
	// floor tiles, WorldItemPickup's dot, and the pit/water Polygon2D
	// markers all get their actual color. Only Sprite2D-based children
	// (larvae) have a real bound texture, so this stayed hidden until every
	// untextured ground draw rendered solid white and vanished into the
	// equally-wrong-white floor.
	vec4 base_color = COLOR;
	COLOR = apply_dim(base_color, dim_enabled, saturation, brightness);
}
