// Cel shading for 3D models: flat colour (or texture) with three hard light
// bands (lit / half / shadow) plus sun shadows. No specular. The band edges
// are a few degrees wide so they stay smooth on distant and moving surfaces.
shader_type spatial;
render_mode cull_back, specular_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
// Must match the environment's ambient colour: fully shadowed areas show
// albedo * shadow_tint, lit areas show the plain albedo.
uniform vec3 shadow_tint : source_color = vec3(0.70, 0.72, 0.90);
uniform float half_band = 0.35;     // N.L below this is drawn in the half tone
uniform float half_level = 0.55;
// Ink lines for this surface (see ink_outline.gdshader): 0 none, 0.5 outer
// edges only, 1 outer edges and creases
uniform float ink = 1.0;
// MultiMesh details: multiply by the per-instance colour in INSTANCE_CUSTOM
// (glass tints, curtain and parapet colours, garage doors)
uniform bool instance_tint = false;

varying vec3 v_tint;

void vertex() {
	v_tint = instance_tint ? INSTANCE_CUSTOM.rgb : vec3(1.0);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV * uv_scale);
	ALBEDO = tex.rgb * tint.rgb * v_tint;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = ink;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float facing = smoothstep(-0.02, 0.06, ndl);
	float full = smoothstep(half_band - 0.045, half_band + 0.045, ndl);
	float lit = facing * mix(half_level, 1.0, full) * smoothstep(0.4, 0.6, ATTENUATION);
	DIFFUSE_LIGHT += lit * (vec3(1.0) - shadow_tint) * LIGHT_COLOR / PI;
}
