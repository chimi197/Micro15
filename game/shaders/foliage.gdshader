// Trees, bushes and hedges, modelled leaf by leaf (blender/trees.py).
// Normals are bent outwards from the crown in Blender so the whole crown
// lights like one soft volume while each leaf keeps a little of its own
// direction. UV.x is a random shade per leaf, UV.y runs from a leaf's base
// to its tip (slightly darker at the base). Leaves facing up are lighter
// and yellower, leaves facing down darker; the crown sways gently.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 tint : source_color = vec4(0.36, 0.6, 0.29, 1.0);
uniform vec3 top_tint : source_color = vec3(1.12, 1.12, 0.92);   // multiplies the colour on top
uniform vec3 under_tint : source_color = vec3(0.7, 0.77, 0.77);  // ... and underneath
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float leaf_shade = 0.0;     // how much leaves differ from each other (modelled leaves)
uniform float variation = 0.12;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.15;
uniform float sway = 0.06;
uniform float sway_from = 2.0;      // metres above the origin where swaying starts
uniform float flutter = 0.0;

#include "res://shaders/soft_light.gdshaderinc"

varying float v_up;
varying vec3 v_world;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y - sway_from, 0.0);
	float t = TIME * 1.3 + origin.x * 0.2 + origin.z * 0.15;
	VERTEX.x += sin(t) * sway * h * 0.15;
	VERTEX.z += cos(t * 0.8) * sway * h * 0.1;
	// each leaf flutters a little, its tip more than its base
	VERTEX += NORMAL * sin(TIME * 3.1 + UV.x * 40.0) * flutter * UV.y;
	v_up = NORMAL.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// keep the bent normal on both sides of a leaf
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	float n = texture(noise_tex, v_world.xz * 0.35 + v_world.y * 0.2).r;
	vec3 shade = mix(under_tint, top_tint, smoothstep(-0.6, 0.8, v_up));
	float leaf = 1.0;
	if (leaf_shade > 0.0) {
		leaf = mix(1.0 - leaf_shade, 1.0 + leaf_shade * 0.4, UV.x) * mix(0.88, 1.0, smoothstep(0.0, 0.5, UV.y));
	}
	ALBEDO = tint.rgb * shade * leaf * (1.0 + variation * (n - 0.5) * 2.0);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	// a little light through the leaves when the sun is behind them
	BACKLIGHT = tint.rgb * 0.25;
}
