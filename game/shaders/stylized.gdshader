// Surfaces of the world and the characters (see docs/art_direction.md):
// soft_light.gdshaderinc lighting (a soft, wrapped terminator), real
// roughness and specular per material family, and restrained painted
// variation: large-scale mottling, optional fine speckle, optional paving
// seams and a darker band near the ground (grime). No outlines, no bands.
shader_type spatial;
render_mode cull_back;

uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float specular : hint_range(0.0, 1.0) = 0.25;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
// MultiMesh details: multiply by the per-instance colour in INSTANCE_CUSTOM
// (glass tints, curtain and parapet colours, garage doors)
uniform bool instance_tint = false;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float variation = 0.0;          // strength of the large-scale value mottling
uniform float variation_scale = 7.0;    // metres per noise tile
uniform float speckle = 0.0;            // strength of fine grain (asphalt, gravel)
uniform float grime = 0.0;              // how much darker the surface gets at the ground
uniform float grime_height = 1.2;       // metres the grime fades over
uniform float seams = 0.0;              // strength of paving-slab seams (horizontal surfaces)
uniform float seam_size = 1.0;          // slab size in metres

// night (scripts/sun_cycle.gd): 0 by day, 1 at night
global uniform float world_night;
uniform float lit_windows = 0.0;        // glass: share of windows lit at night (by instance)
uniform float night_glow = 0.0;         // lamp glass: extra emission at night

#include "res://shaders/soft_light.gdshaderinc"

varying vec3 v_origin;
varying vec3 v_tint;
varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_tint = instance_tint ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	v_origin = MODEL_MATRIX[3].xyz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float sample_noise(float scale) {
	// walls use (along the wall, height); ground uses (x, z)
	vec2 uv_side = vec2(v_world.x + v_world.z, v_world.y) / scale;
	vec2 uv_top = v_world.xz / scale;
	float up = smoothstep(0.5, 0.8, abs(v_world_normal.y));
	return mix(texture(noise_tex, uv_side).r, texture(noise_tex, uv_top).r, up);
}

void fragment() {
	vec3 c = tint.rgb * v_tint;
	if (variation > 0.0) {
		float n = sample_noise(variation_scale) * 0.7 + sample_noise(variation_scale * 0.23) * 0.3;
		c *= 1.0 + variation * (n - 0.5) * 2.0;
	}
	if (speckle > 0.0) {
		float s = texture(noise_tex, v_world.xz * 1.7).r;
		c *= 1.0 + speckle * (s - 0.5) * 2.0;
	}
	if (seams > 0.0 && v_world_normal.y > 0.8) {
		vec2 g = abs(fract(v_world.xz / seam_size) - 0.5) * 2.0;           // 1 at a seam
		float w = fwidth(v_world.x / seam_size) * 2.0 + 0.02;
		float line = max(smoothstep(1.0 - w, 1.0, g.x), smoothstep(1.0 - w, 1.0, g.y));
		c *= 1.0 - seams * line;
	}
	if (grime > 0.0) {
		c *= 1.0 - grime * (1.0 - smoothstep(0.0, grime_height, v_world.y));
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = metallic;
	EMISSION = emission * (1.0 + night_glow * world_night);
	if (lit_windows > 0.0 && world_night > 0.01) {
		// each window (instance) is lit or not, with its own warmth; a few
		// flicker blue with a television
		vec3 o = floor(v_origin * 2.0);
		float h = fract(sin(dot(o, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float h2 = fract(h * 91.7);
		float lit = step(1.0 - lit_windows, h);
		vec3 warm = mix(vec3(1.0, 0.72, 0.38), vec3(1.0, 0.86, 0.6), h2);
		if (h2 > 0.9) {
			warm = vec3(0.55, 0.7, 1.0) * (0.75 + 0.25 * sin(TIME * 7.0 + h * 40.0) * sin(TIME * 2.3 + h2 * 9.0));
		}
		EMISSION += warm * lit * world_night * 1.6;
		ALBEDO *= 1.0 - lit * world_night * 0.6;
	}
}
