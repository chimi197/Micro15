// Full-screen ink lines drawn from depth and normal discontinuities.
// Put it on a 2x2 QuadMesh in front of the camera (WorldStyle.add_ink_outline).
//
// The lines are soft rather than black: each one takes a darker, cooler
// shade of the surface it outlines, its strength grows smoothly with the
// size of the depth or angle jump (so it does not pop on and off as the
// camera moves), it is about one pixel wide at 1080p, and it fades out with
// distance: creases first, then silhouettes.
//
// Since the art direction pass (docs/art_direction.md) the game draws its
// forms with light and this pass is off; the admin tool's F2 still shows
// it, as silhouettes only, for comparison.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 ink_shade : source_color = vec3(0.42, 0.40, 0.55);   // multiplies the outlined surface's colour
uniform vec3 ink_dark : source_color = vec3(0.10, 0.10, 0.16);    // and is mixed with this fixed ink colour
uniform float ink_mix = 0.35;
uniform float strength = 0.85;
uniform float thickness = 1.0;           // in pixels at 1080p, each side
uniform float depth_threshold = 0.03;    // relative depth jump where a line starts
uniform bool creases = false;           // also draw lines at sharp creases
uniform float normal_threshold = 0.55;   // cosine below which a crease starts
uniform float crease_fade_start = 8.0;   // metres
uniform float crease_fade_end = 30.0;
uniform float fade_start = 20.0;
uniform float fade_end = 110.0;

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
	vec2 px = thickness * (VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	px = max(px, 1.0 / VIEWPORT_SIZE);
	float dc = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	if (dc > fade_end) {
		discard;
	}
	float crease_fade = creases ? 1.0 - smoothstep(crease_fade_start, crease_fade_end, dc) : 0.0;
	vec3 nc = view_normal(SCREEN_UV);
	float edge = 0.0;
	// the line takes its colour from the nearest surface around it
	vec2 near_uv = SCREEN_UV;
	float near_d = dc;
	vec2 axes[2] = { vec2(px.x, 0.0), vec2(0.0, px.y) };
	for (int i = 0; i < 2; i++) {
		vec2 ua = SCREEN_UV + axes[i];
		vec2 ub = SCREEN_UV - axes[i];
		float da = view_depth(ua, INV_PROJECTION_MATRIX);
		float db = view_depth(ub, INV_PROJECTION_MATRIX);
		// second derivative: flat surfaces seen at an angle do not trigger it
		float jump = abs(da + db - 2.0 * dc) / dc;
		edge = max(edge, smoothstep(depth_threshold, depth_threshold * 2.5, jump));
		if (crease_fade > 0.0) {
			float c = min(dot(view_normal(ua), nc), dot(view_normal(ub), nc));
			edge = max(edge, crease_fade * smoothstep(normal_threshold, normal_threshold - 0.3, c));
		}
		if (da < near_d) { near_d = da; near_uv = ua; }
		if (db < near_d) { near_d = db; near_uv = ub; }
	}
	if (edge < 0.01) {
		discard;
	}
	vec3 surface = texture(screen_tex, near_uv).rgb;
	ALBEDO = mix(surface * ink_shade, ink_dark, ink_mix);
	ALPHA = edge * strength * (1.0 - smoothstep(fade_start, fade_end, dc));
}
