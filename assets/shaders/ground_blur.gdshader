shader_type canvas_item;

// Screen-space blur for GroundLayer's ceiling-focus "hazy background" look
// (tunnel visual rework Phase 2 follow-up, escalating from the plain
// desaturate/darken version per the original design doc's own stated
// fallback: "only escalate [to a blur pass] if it doesn't read as
// intended"). GroundLayer can't composite its own children into one
// buffer to blur directly -- a Godot CanvasGroup silently drops any child
// added after a ShaderMaterial is attached to it and never renders it
// again (see world/ground_layer.gd's own doc comment for the isolated
// repro that proved this), which ruled out a CanvasGroup for GroundLayer
// entirely. Instead, world/level.tscn places a BackBufferCopy ("GroundBlur/
// Capture") immediately after GroundLayer in the scene tree, then this
// shader (on "GroundBlur/Overlay", a ColorRect sized to the maze bounds
// right after that BackBufferCopy) blurs whatever was on screen at that
// point in the draw order -- exactly GroundLayer's own already-darkened
// content. Renderer/Walls/Entities, drawn afterward, land on top of this
// blurred overlay and stay perfectly crisp.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float blur_radius_px : hint_range(0.0, 32.0) = 10.0;

void fragment() {
	// No early `return` in fragment() -- this project's renderer rejects it
	// (see outline.gdshader's identical note). Single-pass 9-tap "tent"
	// blur (center 4, cardinals 2, diagonals 1, /16 total) -- good enough
	// for a stylized hazy background, no need for a true two-pass Gaussian.
	vec2 texel = SCREEN_PIXEL_SIZE * blur_radius_px;
	vec4 sum = textureLod(screen_texture, SCREEN_UV, 0.0) * 4.0;
	sum += textureLod(screen_texture, SCREEN_UV + vec2(texel.x, 0.0), 0.0) * 2.0;
	sum += textureLod(screen_texture, SCREEN_UV - vec2(texel.x, 0.0), 0.0) * 2.0;
	sum += textureLod(screen_texture, SCREEN_UV + vec2(0.0, texel.y), 0.0) * 2.0;
	sum += textureLod(screen_texture, SCREEN_UV - vec2(0.0, texel.y), 0.0) * 2.0;
	sum += textureLod(screen_texture, SCREEN_UV + texel, 0.0);
	sum += textureLod(screen_texture, SCREEN_UV - texel, 0.0);
	sum += textureLod(screen_texture, SCREEN_UV + vec2(texel.x, -texel.y), 0.0);
	sum += textureLod(screen_texture, SCREEN_UV + vec2(-texel.x, texel.y), 0.0);
	COLOR = sum / 16.0;
}
