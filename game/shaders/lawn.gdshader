// Ground under the grass: flat lawn colour broken up by soft-edged darker
// and lighter patches (procedural, no painted texture).
shader_type spatial;
render_mode cull_back, specular_disabled;

uniform vec4 tint : source_color = vec4(0.55, 0.77, 0.34, 1.0);
uniform vec4 patch_dark : source_color = vec4(0.45, 0.68, 0.28, 1.0);
uniform vec4 patch_light : source_color = vec4(0.64, 0.83, 0.40, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 shadow_tint : source_color = vec3(0.70, 0.72, 0.90);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, world_pos.xz / 40.0).r;
	vec3 c = tint.rgb;
	c = mix(c, patch_dark.rgb, smoothstep(0.59, 0.65, n));
	c = mix(c, patch_light.rgb, 1.0 - smoothstep(0.33, 0.39, n));
	ALBEDO = c;
	ROUGHNESS = 0.0;
}

void light() {
	float facing = smoothstep(0.0, 0.03, dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += facing * smoothstep(0.4, 0.6, ATTENUATION) * (vec3(1.0) - shadow_tint) * LIGHT_COLOR / PI;
}
