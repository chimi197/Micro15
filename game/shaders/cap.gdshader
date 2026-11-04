// Bottle caps (scripts/interact/cap_field.gd): painted metal, the instance
// colour on the top, bare crimped metal round the side, and a glint that
// passes over each cap every few seconds (its own phase in INSTANCE_CUSTOM.r)
// so a cap in the grass can be spotted from a few metres away.
shader_type spatial;
render_mode cull_back;

uniform float specular = 0.9;
uniform float glint_every = 3.5;          // seconds between glints
uniform float glint_strength = 1.6;

#include "res://shaders/soft_light.gdshaderinc"

varying vec3 colour;
varying float phase;
varying float side;

void vertex() {
	colour = COLOR.rgb;
	phase = INSTANCE_CUSTOM.r;
	side = 1.0 - smoothstep(0.6, 0.9, abs(NORMAL.y));
}

void fragment() {
	vec3 metal = vec3(0.72, 0.7, 0.66);
	ALBEDO = mix(colour, metal, side * 0.8);
	METALLIC = mix(0.25, 0.85, side);
	ROUGHNESS = mix(0.35, 0.3, side);
	float t = fract(TIME / glint_every + phase);
	float glint = smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.04, 0.12, t));
	EMISSION = vec3(1.0, 0.96, 0.85) * glint * glint_strength;
}
