shader_type canvas_item;

// Standard alpha-edge outline: if this texel is (near-)transparent but a
// neighbour is opaque, paint outline_color instead. No-op when disabled.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 1.0;
uniform bool outline_enabled = true;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (!outline_enabled || tex_color.a > 0.5) {
		COLOR = tex_color;
	} else {
		vec2 texel = outline_width / vec2(textureSize(TEXTURE, 0));
		float neighbor_alpha = 0.0;
		neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV - vec2(texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV - vec2(0.0, texel.y)).a;
		COLOR = neighbor_alpha > 0.0 ? outline_color : tex_color;
	}
}
