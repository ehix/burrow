shader_type canvas_item;

#include "res://assets/shaders/dim.gdshaderinc"

// Same desaturate/darken pass as ground_dim.gdshader, sharing its logic via
// dim.gdshaderinc rather than a separate ShaderMaterial: this material still
// needs its own shader *file* because it also carries a TIME-driven UV
// scroll uniform, which the single shared dim_material() instance every
// other ground-resident node uses can't carry without scrolling every other
// ground texture too (see GroundLayer's own doc comment on why one shared
// instance is otherwise the rule here).
uniform float saturation : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 1.0) = 0.75;
uniform bool dim_enabled = false;
uniform vec2 scroll_speed = vec2(0.02, 0.015);

void fragment() {
	// No early `return` in fragment() -- this project's renderer rejects it
	// (see ground_dim.gdshader / outline.gdshader). Every branch funnels
	// into one COLOR assignment instead.
	vec2 scrolled_uv = UV + TIME * scroll_speed;
	vec4 base_color = texture(TEXTURE, scrolled_uv) * COLOR;
	COLOR = apply_dim(base_color, dim_enabled, saturation, brightness);
}
