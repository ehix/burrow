shader_type canvas_item;

// Standard alpha-edge outline: if this texel is (near-)transparent but a
// same-distance neighbour (8-tap: 4 cardinal + 4 diagonal, so corners get
// full coverage too) is opaque, paint outline_color instead. body_alpha
// dims normal body pixels only — kept independent of outline_color's own
// alpha so a caller (Camouflage) can fade the body to near-invisible while
// the outline stays fully visible, which node `modulate` can't do (it
// multiplies everything this shader outputs, outline included).
//
// dim_enabled/saturation/brightness (tunnel visual rework Phase 2): the
// same desaturate+darken formula GroundLayer's ground_dim.gdshader uses
// for "hazy background" content, merged into this shader instead of a
// second material — a CanvasItem can only ever hold one material, and
// Player/Enemy sprites already depend on this one for outline/Camouflage.
// Applies to the body color only, never outline_color (a deliberately
// chosen flat color, not sampled texture content, so there's nothing to
// desaturate).
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 2.0;
uniform bool outline_enabled = true;
uniform float body_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float saturation : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 1.0) = 0.75;
uniform bool dim_enabled = false;

void fragment() {
	// No early `return` in fragment() — this project's renderer rejects it
	// ("SHADER ERROR: Using 'return' in the 'fragment' processor function
	// is incorrect."), silently failing the whole shader's compilation.
	// Every branch below funnels into one COLOR assignment instead.
	vec4 tex_color = texture(TEXTURE, UV);
	vec3 body_rgb = tex_color.rgb;
	if (dim_enabled) {
		float luminance = dot(body_rgb, vec3(0.299, 0.587, 0.114));
		body_rgb = mix(vec3(luminance), body_rgb, saturation) * brightness;
	}
	if (tex_color.a > 0.5 || !outline_enabled) {
		COLOR = vec4(body_rgb, tex_color.a * body_alpha);
	} else {
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
		COLOR = neighbor_alpha > 0.0 ? outline_color : vec4(body_rgb, tex_color.a * body_alpha);
	}
}
