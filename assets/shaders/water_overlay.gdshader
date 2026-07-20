shader_type canvas_item;

// Same desaturate/darken pass as ground_dim.gdshader, duplicated rather
// than shared: this material also carries a TIME-driven UV scroll
// uniform, which the single shared dim_material() instance every other
// ground-resident node uses can't carry without scrolling every other
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
	if (dim_enabled) {
		float luminance = dot(base_color.rgb, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(vec3(luminance), base_color.rgb, saturation);
		COLOR = vec4(desaturated * brightness, base_color.a);
	} else {
		COLOR = base_color;
	}
}
