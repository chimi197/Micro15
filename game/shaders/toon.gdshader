// Flat "vector" shading: a texture or flat colour, two hard light bands
// (lit / shadow) and sun shadows. No specular, no gradients.
shader_type spatial;
render_mode cull_back, specular_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
// Must match the environment's ambient colour: shadowed areas show
// albedo * shadow_tint, lit areas show the plain albedo.
uniform vec3 shadow_tint : source_color = vec3(0.70, 0.72, 0.90);

void fragment() {
	vec4 tex = texture(albedo_tex, UV * uv_scale);
	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

void light() {
	float facing = smoothstep(0.0, 0.04, dot(NORMAL, LIGHT));
	float unshadowed = smoothstep(0.4, 0.6, ATTENUATION);
	DIFFUSE_LIGHT += facing * unshadowed * (vec3(1.0) - shadow_tint) * LIGHT_COLOR / PI;
}
