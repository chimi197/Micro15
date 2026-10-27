// Tree canopies and bushes: toon bands on bent normals plus a gentle sway.
// They do not receive shadows: self-shadowing on the bent normals shows as
// acne, and the bent normals already darken the underside.
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.3, 0.65, 0.26, 1.0);
uniform vec3 shadow_tint : source_color = vec3(0.70, 0.72, 0.90);
uniform float sway = 0.06;
uniform float sway_from = 2.0;      // metres above the origin where swaying starts

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y - sway_from, 0.0);
	float t = TIME * 1.3 + world.x * 0.2 + world.z * 0.15;
	VERTEX.x += sin(t) * sway * h * 0.15;
	VERTEX.z += cos(t * 0.8) * sway * h * 0.1;
}

void fragment() {
	ALBEDO = tint.rgb;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float facing = smoothstep(-0.05, 0.05, ndl);
	float full = smoothstep(0.38, 0.45, ndl);
	float lit = facing * mix(0.5, 1.0, full) * smoothstep(0.4, 0.6, ATTENUATION);
	DIFFUSE_LIGHT += lit * (vec3(1.0) - shadow_tint) * LIGHT_COLOR / PI;
}
