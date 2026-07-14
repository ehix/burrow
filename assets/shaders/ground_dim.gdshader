shader_type canvas_item;

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
	// one COLOR assignment instead.
	vec4 tex_color = texture(TEXTURE, UV);
	if (dim_enabled) {
		float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(vec3(luminance), tex_color.rgb, saturation);
		COLOR = vec4(desaturated * brightness, tex_color.a);
	} else {
		COLOR = tex_color;
	}
}
