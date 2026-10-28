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
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
