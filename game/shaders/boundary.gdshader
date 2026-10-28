// The shadowed blocks around the edge of the playable area
// (scripts/boundary.gd): dark, unlit silhouettes of blocks of flats with a
// faint grid of windows, darker at the foot, which the haze fades into the
// sky with distance. UV is in metres along the wall and up; vertex colour
// tints each block, its alpha is 0 on the roofs.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 wall_colour : source_color = vec3(0.24, 0.26, 0.31);
uniform vec3 window_colour : source_color = vec3(0.16, 0.18, 0.23);
uniform vec3 roof_colour : source_color = vec3(0.30, 0.32, 0.37);
uniform vec2 bay = vec2(3.2, 2.8);              // window spacing: along, up
uniform float plinth = 1.0;

void fragment() {
	vec3 c = roof_colour;
	if (COLOR.a > 0.5) {
		vec2 cell = fract((UV - vec2(0.0, plinth)) / bay);
		float win = step(0.28, cell.x) * step(cell.x, 0.72) * step(0.3, cell.y) * step(cell.y, 0.82)
				* step(plinth + 0.5, UV.y);
		c = mix(wall_colour, window_colour, win);
		c *= mix(0.7, 1.0, smoothstep(0.0, 18.0, UV.y));
	}
	ALBEDO = c * COLOR.rgb;
}
