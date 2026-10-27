// 3D grass blades and flowers drawn with MultiMesh. Vertex colours carry the
// root-to-tip gradient; per-instance custom data varies the shade. Blades
// sway in the wind and are hidden from the ink outline pass (ROUGHNESS 0).
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec3 shadow_tint : source_color = vec3(0.70, 0.72, 0.90);
uniform float wind_strength = 0.18;
uniform vec2 wind_direction = vec2(1.0, 0.35);

varying float shade;

void vertex() {
	float h = UV.y;                                   // 0 at the root, 1 at the tip
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.7 + world.x * 0.31 + world.z * 0.23) * 0.6
			+ sin(TIME * 3.3 + world.x * 1.1 - world.z * 0.7) * 0.25;
	vec3 push = vec3(wind_direction.x, 0.0, wind_direction.y) * gust * wind_strength * h * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	shade = INSTANCE_CUSTOM.r;
}

void fragment() {
	// vertex colours are sRGB
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * mix(0.85, 1.12, shade);
	ROUGHNESS = 0.0;
}

void light() {
	float lit = smoothstep(0.4, 0.6, ATTENUATION);
	DIFFUSE_LIGHT += lit * (vec3(1.0) - shadow_tint) * LIGHT_COLOR / PI * max(dot(vec3(0.0, 1.0, 0.0), LIGHT), 0.0) * 1.15;
}
