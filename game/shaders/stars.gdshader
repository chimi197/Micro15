// Night sky stars (scripts/world/star_dome.gd): a dome round the camera,
// drawn unlit behind the world. Stars are cells of a grid on the sphere
// with a random star in some of them, twinkling slowly; fewer near the
// horizon, where the town's glow washes them out.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, blend_add, shadows_disabled;

global uniform float world_night;
uniform float density = 0.16;          // share of cells with a star
uniform float cells = 220.0;           // grid cells round the sky

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 d = normalize(dir);
	if (d.y < 0.02) {
		discard;
	}
	vec2 uv = vec2(atan(d.z, d.x) / 6.2831853 + 0.5, asin(d.y) / 3.14159265 + 0.5);
	uv.x *= mix(1.0, cos(asin(d.y)), 0.9);     // keep cells roughly square towards the top
	vec2 g = uv * cells;
	vec2 id = floor(g);
	float h = hash(id);
	float star = 0.0;
	if (h < density) {
		vec2 at = vec2(hash(id + 3.1), hash(id + 7.7)) * 0.6 + 0.2;
		float r = length(fract(g) - at);
		float size = mix(0.05, 0.16, pow(hash(id + 1.3), 6.0));
		star = smoothstep(size, 0.0, r);
		star *= 0.6 + 0.4 * sin(TIME * mix(0.8, 2.6, hash(id + 5.5)) + h * 60.0);
		star *= mix(0.4, 1.4, pow(hash(id + 9.1), 3.0));
	}
	float horizon = smoothstep(0.03, 0.35, d.y);
	vec3 tint = mix(vec3(0.8, 0.86, 1.0), vec3(1.0, 0.92, 0.82), hash(id + 2.2));
	ALBEDO = vec3(0.0);
	EMISSION = tint * star * horizon * world_night * 1.6;
}
