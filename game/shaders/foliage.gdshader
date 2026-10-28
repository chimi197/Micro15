// Tree canopies, bushes and hedges: balls of double-sided leaf cards, each
// showing a painted bunch of leaves (style/leaf_*.png, cut out with alpha
// scissor), around small untextured cores. Normals are bent outwards from
// the crown in Blender so the whole crown lights like one soft volume.
// Leaves facing up are lighter and yellower, leaves facing down darker,
// and each clump varies a little; the crown sways gently.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 tint : source_color = vec4(0.36, 0.6, 0.29, 1.0);
uniform vec3 top_tint : source_color = vec3(1.12, 1.12, 0.92);   // multiplies the colour on top
uniform vec3 under_tint : source_color = vec3(0.7, 0.77, 0.77);  // ... and underneath
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;   // leaf cards; cores and spruce needles are untextured
uniform sampler2D leaf_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float variation = 0.12;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.15;
uniform float sway = 0.06;
uniform float sway_from = 2.0;      // metres above the origin where swaying starts

#include "res://shaders/soft_light.gdshaderinc"

varying float v_up;
varying vec3 v_world;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y - sway_from, 0.0);
	float t = TIME * 1.3 + origin.x * 0.2 + origin.z * 0.15;
	VERTEX.x += sin(t) * sway * h * 0.15;
	VERTEX.z += cos(t * 0.8) * sway * h * 0.1;
	v_up = NORMAL.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// keep the bent normal on both sides of a leaf card
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	float n = texture(noise_tex, v_world.xz * 0.35 + v_world.y * 0.2).r;
	vec3 shade = mix(under_tint, top_tint, smoothstep(-0.6, 0.8, v_up));
	vec4 leaf = vec4(1.0);
	if (use_texture) {
		leaf = texture(leaf_tex, UV);
		// keep the leaves' coverage in the smaller mipmaps (far trees)
		vec2 px = UV * vec2(textureSize(leaf_tex, 0));
		float mip = max(0.0, 0.5 * log2(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px)))));
		leaf.a *= 1.0 + mip * 0.25;
		// cards seen edge-on would show as thin streaks: let their leaves
		// thin out instead (the flat card's own normal, not the bent one)
		vec3 card_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		leaf.a *= smoothstep(0.1, 0.4, abs(dot(card_n, VIEW)));
	}
	ALBEDO = tint.rgb * shade * leaf.rgb * (1.0 + variation * (n - 0.5) * 2.0);
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	// a little light through the leaves when the sun is behind them
	BACKLIGHT = tint.rgb * 0.25;
}
