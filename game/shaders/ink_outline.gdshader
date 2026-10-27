// Full-screen ink lines drawn from depth and normal discontinuities.
// Put it on a 2x2 QuadMesh in front of the camera (see style_test.gd).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec4 ink_color : source_color = vec4(0.11, 0.10, 0.15, 1.0);
uniform float thickness = 1.5;           // in pixels, each side
uniform float depth_threshold = 0.025;   // relative depth jump that counts as an edge
uniform float normal_threshold = 0.6;    // cosine below which a crease counts as an edge
uniform float fade_start = 35.0;         // metres: lines thin out with distance
uniform float fade_end = 140.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = thickness / VIEWPORT_SIZE;
	float dc = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 nc = view_normal(SCREEN_UV);
	// the ROUGHNESS a surface writes picks its lines: 0 none (grass, lawn),
	// 0.5 outer edges only (characters), 1 outer edges and creases
	float mode = texture(normal_tex, SCREEN_UV).a;
	if (mode < 0.25) {
		discard;
	}
	bool creases = mode > 0.75;
	float edge = 0.0;
	vec2 axes[2] = { vec2(px.x, 0.0), vec2(0.0, px.y) };
	for (int i = 0; i < 2; i++) {
		float da = view_depth(SCREEN_UV + axes[i], INV_PROJECTION_MATRIX);
		float db = view_depth(SCREEN_UV - axes[i], INV_PROJECTION_MATRIX);
		// second derivative: flat surfaces seen at an angle do not trigger it
		if (abs(da + db - 2.0 * dc) > depth_threshold * dc) {
			edge = 1.0;
		}
		if (creases && (dot(view_normal(SCREEN_UV + axes[i]), nc) < normal_threshold
				|| dot(view_normal(SCREEN_UV - axes[i]), nc) < normal_threshold)) {
			edge = 1.0;
		}
	}
	float fade = 1.0 - smoothstep(fade_start, fade_end, dc);
	ALBEDO = ink_color.rgb;
	ALPHA = edge * mix(0.12, 1.0, fade) * ink_color.a;
}
