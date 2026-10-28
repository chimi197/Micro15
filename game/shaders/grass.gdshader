// 3D grass blades and flowers drawn with MultiMesh. Vertex colours carry the
// root-to-tip gradient; per-instance custom data varies the shade. Blades
// sway in the wind and are lit with the ground's normal, so a lawn reads as
// one surface with the blades as texture.
shader_type spatial;
render_mode cull_disabled;

uniform float wind_strength = 0.18;
uniform vec2 wind_direction = vec2(1.0, 0.35);

const float specular = 0.0;
#include "res://shaders/soft_light.gdshaderinc"

varying float shade;

void vertex() {
	float h = UV.y;                                   // 0 at the root, 1 at the tip
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.7 + world.x * 0.31 + world.z * 0.23) * 0.6
			+ sin(TIME * 3.3 + world.x * 1.1 - world.z * 0.7) * 0.25;
	vec3 push = vec3(wind_direction.x, 0.0, wind_direction.y) * gust * wind_strength * h * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	shade = INSTANCE_CUSTOM.r;
}

void fragment() {
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	// vertex colours are sRGB. With MSAA a pixel can be shaded outside a thin
	// blade, where COLOR extrapolates below 0 and pow() gives NaN, which glow
	// spreads into white discs; hence the clamp.
	ALBEDO = pow(clamp(COLOR.rgb, 0.0, 1.0), vec3(2.2)) * mix(0.88, 1.08, shade);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
