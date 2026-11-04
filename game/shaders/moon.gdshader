// The moon (scripts/world/star_dome.gd): a pale disc with soft grey seas,
// unlit, with a faint rim of glow, shown at night only.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, depth_draw_never;

global uniform float world_night;

float blob(vec2 p, vec2 c, float r) {
	return 1.0 - smoothstep(r * 0.6, r, length(p - c));
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec2 p = NORMAL.xy;                       // view space: across the disc
	float seas = blob(p, vec2(-0.2, 0.25), 0.35) * 0.5 + blob(p, vec2(0.25, -0.1), 0.3) * 0.4
			+ blob(p, vec2(-0.05, -0.35), 0.22) * 0.35;
	vec3 c = mix(vec3(1.0, 0.98, 0.92), vec3(0.72, 0.74, 0.78), seas);
	float edge = smoothstep(0.0, 0.35, facing);
	ALBEDO = vec3(0.0);
	EMISSION = c * edge * world_night * 1.5;
	ALPHA = world_night;
}
