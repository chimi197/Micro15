// The distant blocks of flats round the edge of the map (scripts/boundary.gd):
// pastel walls with a grid of windows and a darker foot, lit like the rest
// of the world, fading into the sky's horizon colour with distance so the
// town seems to carry on. UV is in metres along the wall and up; vertex
// colour is each block's wall colour, its alpha is 0 on the roofs.
shader_type spatial;
render_mode cull_back;

uniform vec3 window_colour : source_color = vec3(0.36, 0.42, 0.48);
uniform vec3 roof_colour : source_color = vec3(0.49, 0.48, 0.45);
uniform vec2 bay = vec2(3.2, 2.8);              // window spacing: along, up
uniform float plinth = 1.0;
uniform vec3 haze_colour : source_color = vec3(0.78, 0.86, 0.9);
uniform float haze_start = 250.0;               // metres from the camera
uniform float haze_end = 1400.0;
uniform float haze_max : hint_range(0.0, 1.0) = 0.85;
uniform float specular = 0.15;

#include "res://shaders/soft_light.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = roof_colour;
	if (COLOR.a > 0.5) {
		vec2 cell = fract((UV - vec2(0.0, plinth)) / bay);
		float win = step(0.28, cell.x) * step(cell.x, 0.72) * step(0.3, cell.y) * step(cell.y, 0.82)
				* step(plinth + 0.5, UV.y);
		c = mix(COLOR.rgb, window_colour, win);
		c *= mix(0.78, 1.0, smoothstep(0.0, 6.0, UV.y));
	}
	float haze = smoothstep(haze_start, haze_end, distance(world_pos, CAMERA_POSITION_WORLD)) * haze_max;
	ALBEDO = c * (1.0 - haze);
	EMISSION = haze_colour * haze;
	ROUGHNESS = 0.9;
}
