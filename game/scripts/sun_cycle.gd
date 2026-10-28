## Day and night, and the look of the light: moves the sun across the sky
## of Satu Mare for the time of day (real solar position for the latitude
## and day of the year), and colours the light, sky, ambient light and fog
## to match: warm and low in the morning and evening, a soft blue moonlight
## at night.
##
## time_of_day is the local clock (summer time in Romania, so the sun is
## highest at about 13:30). The clock starts paused at time_of_day (12:00
## matches the game's usual look); running moves it on, a whole day taking
## day_minutes.
##
## look holds everything the map editor's Sky & light panel changes (sun
## strength and colour, sky colours, clouds, fog, ambient light, exposure,
## contrast...). PRESETS are ready-made looks. The level's look is saved
## to look_file and used every time the level starts.
class_name SunCycle
extends Node

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export_range(0.0, 24.0, 0.01) var time_of_day := 12.0      ## hours, local clock
@export var running := false
@export var day_minutes := 24.0                             ## real minutes for a whole day
@export var latitude := 47.79                               ## Satu Mare
@export var longitude := 22.88
@export var utc_offset := 3.0                               ## EEST
@export_range(1, 365) var day_of_year := 230                ## mid August
@export var north_offset := 0.0                             ## degrees; north is -Z
@export_file("*.json") var look_file := ""                  ## the level's saved look

const LOW_COLOUR := Color(1.0, 0.62, 0.36)
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
const NIGHT_SKY := Color(0.05, 0.08, 0.17)
const NIGHT_HORIZON := Color(0.1, 0.14, 0.24)
const DUSK_HORIZON := Color(0.98, 0.66, 0.46)

## The game's usual look (summer noon); every key the editor can change.
const DEFAULT_LOOK := {
	"time": 12.0, "day_of_year": 230, "north_offset": 0.0,
	"sun_energy": 1.35, "sun_colour": Color(1.0, 0.95, 0.86), "shadow_softness": 1.0,
	"sky_top": Color(0.42, 0.6, 0.8), "sky_horizon": Color(0.78, 0.86, 0.9),
	"ground_bottom": Color(0.42, 0.44, 0.36), "sky_energy": 1.0,
	"clouds": 0.0, "cloud_colour": Color(1.0, 1.0, 1.0),
	"ambient": 0.8, "ambient_colour": Color(0.74, 0.74, 0.71), "ambient_sky": 0.7,
	"fog": 0.00025, "fog_colour": Color(0.76, 0.84, 0.9),
	"exposure": 1.0, "contrast": 1.0, "saturation": 1.0, "glow": 0.0, "ssao": 1.2,
}

## Ready-made looks: each changes some keys of DEFAULT_LOOK.
const PRESETS := {
	"Summer noon": {},
	"Morning": {"time": 8.0, "fog": 0.0012, "fog_colour": Color(0.86, 0.87, 0.86), "saturation": 0.95,
			"sky_horizon": Color(0.86, 0.88, 0.88)},
	"Golden hour": {"time": 19.6, "saturation": 1.12, "glow": 0.35, "contrast": 1.05,
			"sun_colour": Color(1.0, 0.86, 0.66)},
	"Sunset": {"time": 20.35, "saturation": 1.15, "glow": 0.5, "clouds": 0.35,
			"cloud_colour": Color(1.0, 0.72, 0.6), "sky_top": Color(0.34, 0.42, 0.68)},
	"Blue hour": {"time": 21.0, "exposure": 1.25, "saturation": 0.95},
	"Night": {"time": 23.5, "exposure": 1.35, "ambient": 1.0, "saturation": 0.85},
	"Overcast": {"time": 13.0, "sun_energy": 0.35, "shadow_softness": 5.0, "clouds": 1.0,
			"cloud_colour": Color(0.86, 0.87, 0.89), "sky_top": Color(0.6, 0.64, 0.69),
			"sky_horizon": Color(0.8, 0.82, 0.84), "ambient": 1.35, "ambient_sky": 0.9,
			"fog": 0.0012, "fog_colour": Color(0.8, 0.82, 0.84), "saturation": 0.85},
	"Foggy morning": {"time": 9.0, "sun_energy": 0.7, "shadow_softness": 3.0, "fog": 0.012,
			"fog_colour": Color(0.84, 0.86, 0.87), "clouds": 0.5, "sky_horizon": Color(0.86, 0.88, 0.89),
			"ambient": 1.1, "saturation": 0.85},
	"Autumn": {"day_of_year": 290, "time": 15.5, "sun_colour": Color(1.0, 0.87, 0.7), "saturation": 1.05,
			"sky_top": Color(0.45, 0.58, 0.76), "fog": 0.0008, "fog_colour": Color(0.84, 0.82, 0.78)},
	"Winter": {"day_of_year": 15, "time": 12.5, "sun_colour": Color(1.0, 0.97, 0.94),
			"sky_top": Color(0.56, 0.67, 0.82), "sky_horizon": Color(0.85, 0.88, 0.9),
			"ground_bottom": Color(0.6, 0.6, 0.58), "ambient": 1.0, "saturation": 0.75, "fog": 0.0009,
			"fog_colour": Color(0.86, 0.88, 0.9), "clouds": 0.3},
	"Storm": {"time": 16.0, "sun_energy": 0.2, "shadow_softness": 6.0, "clouds": 1.0,
			"cloud_colour": Color(0.55, 0.57, 0.6), "sky_top": Color(0.28, 0.31, 0.36),
			"sky_horizon": Color(0.5, 0.53, 0.56), "ground_bottom": Color(0.3, 0.32, 0.3), "ambient": 0.75,
			"ambient_sky": 0.9, "fog": 0.0025, "fog_colour": Color(0.5, 0.53, 0.56), "saturation": 0.7,
			"contrast": 1.1},
}

var look := {}

var _env: Environment
var _sky: ProceduralSkyMaterial
var _clouds: NoiseTexture2D


func _ready() -> void:
	if world_environment and world_environment.environment:
		# a copy, so the shared environment resource is never changed
		_env = world_environment.environment.duplicate(true)
		world_environment.environment = _env
		_sky = _env.sky.sky_material as ProceduralSkyMaterial if _env.sky else null
	look = DEFAULT_LOOK.duplicate()
	look.time = time_of_day
	look.day_of_year = day_of_year
	look.north_offset = north_offset
	if not look_file.is_empty() and FileAccess.file_exists(look_file):
		set_look(look_from_json(FileAccess.get_file_as_string(look_file)))
	else:
		apply()


func _process(delta: float) -> void:
	if running:
		time_of_day = fposmod(time_of_day + delta * 24.0 / (day_minutes * 60.0), 24.0)
		look.time = time_of_day
		apply()


## Moves the clock by hours and updates everything.
func shift(hours: float) -> void:
	time_of_day = fposmod(time_of_day + hours, 24.0)
	look.time = time_of_day
	apply()


func clock() -> String:
	var minutes := int(time_of_day * 60.0) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Takes a whole look (missing keys keep the default) and shows it.
func set_look(new_look: Dictionary) -> void:
	look = DEFAULT_LOOK.duplicate()
	look.merge(new_look, true)
	time_of_day = look.time
	day_of_year = int(look.day_of_year)
	north_offset = look.north_offset
	apply()


func preset(preset_name: String) -> Dictionary:
	var out := DEFAULT_LOOK.duplicate()
	out.merge(PRESETS.get(preset_name, {}), true)
	return out


## The look as JSON (colours as "#rrggbb"), for look_file or the clipboard.
func look_to_json() -> String:
	var out := {}
	for key: String in look:
		var v: Variant = look[key]
		out[key] = "#" + (v as Color).to_html(false) if v is Color else v
	return JSON.stringify(out, "  ", false)


static func look_from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	var out := {}
	if not parsed is Dictionary:
		return out
	for key: String in parsed:
		var v: Variant = parsed[key]
		out[key] = Color.html(v) if v is String and (v as String).begins_with("#") else v
	return out


func save_look() -> bool:
	if look_file.is_empty():
		return false
	var f := FileAccess.open(look_file, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(look_to_json())
	return true


## Direction towards the sun (y up, north -Z) at clock hour t.
func sun_direction(t: float) -> Vector3:
	var lat := deg_to_rad(latitude)
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + day_of_year) / 365.0)
	var solar := t - utc_offset + longitude / 15.0
	var hour := deg_to_rad(15.0 * (solar - 12.0))
	var elevation := asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hour))
	var azimuth := atan2(sin(hour), cos(hour) * sin(lat) - tan(decl) * cos(lat)) + PI \
			+ deg_to_rad(north_offset)
	return Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))


func apply() -> void:
	if sun == null:
		return
	if look.is_empty():
		look = DEFAULT_LOOK.duplicate()
	var to_sun := sun_direction(time_of_day)
	var elevation := rad_to_deg(asin(to_sun.y))
	var day := smoothstep(-4.0, 8.0, elevation)            # 0 at night, 1 by day
	var low := 1.0 - smoothstep(4.0, 30.0, elevation)      # warm, low light
	var moonlit := 1.0 - smoothstep(-9.0, -3.0, elevation)
	var to_light := to_sun
	if elevation < -6.0:
		# the moon: opposite the sun, kept well up in the sky
		to_light = Vector3(-to_sun.x, 0.0, -to_sun.z).normalized() * cos(deg_to_rad(40.0)) \
				+ Vector3.UP * sin(deg_to_rad(40.0))
	sun.global_basis = Basis.looking_at(-to_light, Vector3.UP if absf(to_light.y) < 0.999 else Vector3.FORWARD)
	if elevation >= -6.0:
		sun.light_color = (look.sun_colour as Color).lerp(LOW_COLOUR, low * 0.85)
		sun.light_energy = look.sun_energy * day * lerpf(0.65, 1.0, 1.0 - low)
	else:
		sun.light_color = MOON_COLOUR
		sun.light_energy = 0.16 * moonlit * minf(look.sun_energy / 1.35, 1.0)
	sun.light_angular_distance = 0.6 * look.shadow_softness
	sun.shadow_blur = 1.5 * look.shadow_softness
	if _env == null:
		return
	var dusk := day * low * low                            # sunrise / sunset glow
	_env.ambient_light_energy = look.ambient * lerpf(0.3, 1.0, day)
	_env.ambient_light_color = look.ambient_colour
	_env.ambient_light_sky_contribution = look.ambient_sky
	_env.fog_density = look.fog
	_env.fog_light_color = (look.fog_colour as Color).lerp(NIGHT_HORIZON, 1.0 - day).lerp(DUSK_HORIZON, dusk * 0.5)
	_env.tonemap_exposure = look.exposure
	_env.adjustment_enabled = look.contrast != 1.0 or look.saturation != 1.0
	_env.adjustment_contrast = look.contrast
	_env.adjustment_saturation = look.saturation
	_env.glow_enabled = look.glow > 0.0
	_env.glow_intensity = look.glow
	_env.glow_bloom = look.glow * 0.1
	_env.ssao_enabled = look.ssao > 0.0
	_env.ssao_intensity = look.ssao
	if _sky:
		var horizon: Color = look.sky_horizon
		_sky.sky_top_color = (look.sky_top as Color).lerp(NIGHT_SKY, 1.0 - day)
		_sky.sky_horizon_color = horizon.lerp(NIGHT_HORIZON, 1.0 - day).lerp(DUSK_HORIZON, dusk * 0.7)
		_sky.ground_horizon_color = horizon.lerp(NIGHT_HORIZON, 1.0 - day).lerp(DUSK_HORIZON, dusk * 0.5)
		_sky.ground_bottom_color = (look.ground_bottom as Color).lerp(NIGHT_SKY, 1.0 - day)
		_sky.sky_energy_multiplier = look.sky_energy
		if look.clouds > 0.0:
			if _clouds == null:
				_clouds = _make_clouds()
			_sky.sky_cover = _clouds
			var tint: Color = (look.cloud_colour as Color) * lerpf(0.12, 1.0, day)
			tint = tint.lerp(DUSK_HORIZON, dusk * 0.4)
			_sky.sky_cover_modulate = Color(tint.r, tint.g, tint.b, look.clouds)
		else:
			_sky.sky_cover = null


## A soft, wrapping cloud cover for the sky (equirectangular noise).
func _make_clouds() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 5
	noise.seed = 15
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 1))
	ramp.set_offset(0, 0.42)
	ramp.set_offset(1, 0.78)
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex
