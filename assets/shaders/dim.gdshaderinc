// Shared desaturate/darken logic between ground_dim.gdshader and
// water_overlay.gdshader -- factored out so a tuning change to the
// darken formula doesn't require editing both shaders in lockstep.
vec4 apply_dim(vec4 base_color, bool dim_enabled, float saturation, float brightness) {
	vec4 result = base_color;
	if (dim_enabled) {
		float luminance = dot(base_color.rgb, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(vec3(luminance), base_color.rgb, saturation);
		result = vec4(desaturated * brightness, base_color.a);
	}
	return result;
}
