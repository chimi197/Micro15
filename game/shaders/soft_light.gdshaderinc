// The game's direct lighting (docs/art_direction.md), shared by every world
// and character shader. Lambert with a small wrap, so the terminator is soft
// while lit and shaded sides keep clear contrast (Godot's own
// diffuse_lambert_wrap wraps by roughness, which on our rough materials
// halves the sun and flattens every form), plus a broad GGX highlight
// scaled by the material's specular. Ambient light and sky reflections
// stay Godot's.
//
// A shader that includes this declares `uniform float specular`.

uniform float light_wrap : hint_range(0.0, 1.0) = 0.2;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;
	// leaves let a little light through when the sun is behind them
	DIFFUSE_LIGHT += BACKLIGHT * clamp(-ndl, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;

	if (specular > 0.0 && ndl > 0.0) {
		vec3 h = normalize(VIEW + LIGHT);
		float ndh = max(dot(NORMAL, h), 0.0);
		float ndv = max(dot(NORMAL, VIEW), 0.001);
		float a = max(ROUGHNESS * ROUGHNESS, 0.01);
		float a2 = a * a;
		float k = ndh * ndh * (a2 - 1.0) + 1.0;
		float d = a2 / (PI * k * k);
		float vis = 0.5 / mix(2.0 * ndl * ndv, ndl + ndv, a);
		vec3 f0 = mix(vec3(0.08 * specular), ALBEDO, METALLIC);
		vec3 f = f0 + (1.0 - f0) * pow(1.0 - max(dot(VIEW, h), 0.0), 5.0);
		SPECULAR_LIGHT += d * vis * f * ndl * ATTENUATION * LIGHT_COLOR;
	}
}
