shader_type canvas_item;

// Standard alpha-edge outline: if this texel is (near-)transparent but a
// same-distance neighbour (8-tap: 4 cardinal + 4 diagonal, so corners get
// full coverage too) is opaque, paint outline_color instead. body_alpha
// dims normal body pixels only — kept independent of outline_color's own
// alpha so a caller (Camouflage) can fade the body to near-invisible while
// the outline stays fully visible, which node `modulate` can't do (it
// multiplies everything this shader outputs, outline included).
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 2.0;
uniform bool outline_enabled = true;
uniform float body_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (tex_color.a > 0.5) {
		COLOR = vec4(tex_color.rgb, tex_color.a * body_alpha);
		return;
	}
	if (!outline_enabled) {
		COLOR = vec4(tex_color.rgb, tex_color.a * body_alpha);
		return;
	}
	vec2 texel = outline_width / vec2(textureSize(TEXTURE, 0));
	float neighbor_alpha = 0.0;
	neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
	neighbor_alpha += texture(TEXTURE, UV - vec2(texel.x, 0.0)).a;
	neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
	neighbor_alpha += texture(TEXTURE, UV - vec2(0.0, texel.y)).a;
	neighbor_alpha += texture(TEXTURE, UV + texel).a;
	neighbor_alpha += texture(TEXTURE, UV - texel).a;
	neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, -texel.y)).a;
	neighbor_alpha += texture(TEXTURE, UV + vec2(-texel.x, texel.y)).a;
	COLOR = neighbor_alpha > 0.0 ? outline_color : vec4(tex_color.rgb, tex_color.a * body_alpha);
}
