// Ground under the grass: the lawn colour broken up by soft-edged darker
// and lighter patches (procedural, no painted texture), lit like every
// other surface (stylized.gdshader).
shader_type spatial;
render_mode cull_back;

uniform vec4 tint : source_color = vec4(0.52, 0.65, 0.34, 1.0);
uniform vec3 patch_dark : source_color = vec3(0.85, 0.9, 0.82);     // multiplies the tint
uniform vec3 patch_light : source_color = vec3(1.08, 1.06, 0.95);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform float specular : hint_range(0.0, 1.0) = 0.1;
// far away the lawn can fade into the sky's horizon colour (the outer
// lawn round the map, scripts/boundary.gd); off by default
uniform vec3 haze_colour : source_color = vec3(0.78, 0.86, 0.9);
uniform float haze_start = 500.0;
uniform float haze_end = 1700.0;
uniform float haze_max : hint_range(0.0, 1.0) = 0.0;

#include "res://shaders/soft_light.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, world_pos.xz / 40.0).r;
	float fine = texture(noise_tex, world_pos.xz / 6.0).r;
	vec3 c = tint.rgb;
	c *= mix(vec3(1.0), patch_dark, smoothstep(0.55, 0.7, n));
	c *= mix(vec3(1.0), patch_light, 1.0 - smoothstep(0.3, 0.45, n));
	c *= 0.96 + 0.08 * fine;
	float haze = smoothstep(haze_start, haze_end, distance(world_pos, CAMERA_POSITION_WORLD)) * haze_max;
	ALBEDO = c * (1.0 - haze);
	EMISSION = haze_colour * haze;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
