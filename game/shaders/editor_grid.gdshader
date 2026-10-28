// Map editor coordinate grid, drawn on the ground (and roofs) from the depth
// buffer: thin lines every `minor` metres, bright ones every `major` metres,
// fading out with distance. Put it on a 2x2 QuadMesh (like the ink pass).
// The labels at the crossings are Label3D nodes made by the editor.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform float minor = 10.0;
uniform float major = 100.0;
uniform float fade_end = 450.0;
uniform vec4 minor_colour : source_color = vec4(1.0, 1.0, 1.0, 0.32);
uniform vec4 major_colour : source_color = vec4(1.0, 0.82, 0.25, 0.85);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// 1 on a line every `spacing` metres, `width` pixels wide, 0 away from it
float lines(vec2 p, float spacing, float width) {
	vec2 fw = max(fwidth(p), vec2(1e-4));
	vec2 d = abs(fract(p / spacing - 0.5) - 0.5) * spacing / fw;
	return 1.0 - clamp(min(d.x, d.y) - width * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float dist = length(view.xyz);
	if (dist > fade_end) {
		discard;
	}
	vec3 n = texture(normal_tex, SCREEN_UV).xyz * 2.0 - 1.0;
	vec3 world_n = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	if (world_n.y < 0.6) {
		discard;
	}
	vec2 p = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xz;
	float l_minor = lines(p, minor, 1.0);
	float l_major = lines(p, major, 2.5);
	float fade = 1.0 - smoothstep(fade_end * 0.55, fade_end, dist);
	float minor_fade = 1.0 - smoothstep(fade_end * 0.2, fade_end * 0.45, dist);
	ALBEDO = mix(minor_colour.rgb, major_colour.rgb, l_major);
	ALPHA = max(l_minor * minor_colour.a * minor_fade, l_major * major_colour.a) * fade;
}
