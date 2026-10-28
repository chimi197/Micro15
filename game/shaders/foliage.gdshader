// Tree canopies, bushes and hedges built from leaf clusters (double-sided
// leaf cards around a small core). Normals are bent outwards from the
// canopy in Blender so the whole crown lights like one soft volume. Leaves
// facing up are lighter and yellower, leaves facing down darker, and each
// clump varies a little; the crown sways gently.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.36, 0.6, 0.29, 1.0);
uniform vec3 top_tint : source_color = vec3(1.12, 1.12, 0.92);   // multiplies the colour on top
uniform vec3 under_tint : source_color = vec3(0.62, 0.7, 0.72);  // ... and underneath
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float variation = 0.12;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.15;
uniform float sway = 0.06;
uniform float sway_from = 2.0;      // metres above the origin where swaying starts

varying float v_up;
varying vec3 v_world;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y - sway_from, 0.0);
	float t = TIME * 1.3 + origin.x * 0.2 + origin.z * 0.15;
	VERTEX.x += sin(t) * sway * h * 0.15;
	VERTEX.z += cos(t * 0.8) * sway * h * 0.1;
	v_up = NORMAL.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// keep the bent normal on both sides of a leaf card
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	float n = texture(noise_tex, v_world.xz * 0.35 + v_world.y * 0.2).r;
	vec3 shade = mix(under_tint, top_tint, smoothstep(-0.6, 0.8, v_up));
	ALBEDO = tint.rgb * shade * (1.0 + variation * (n - 0.5) * 2.0);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	// a little light through the leaves when the sun is behind them
	BACKLIGHT = tint.rgb * 0.25;
}
