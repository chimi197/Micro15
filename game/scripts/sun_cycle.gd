## Day and night: moves the sun across the sky of Satu Mare for the time
## of day (real solar position for the latitude and day of the year), and
## colours the light, sky, ambient light and fog to match: warm and low in
## the morning and evening, a soft blue moonlight at night.
##
## The clock starts paused at time_of_day (10:30 matches the game's usual
## look); running moves it on, a whole day taking day_minutes. The admin
## tool (F1) changes the time with , and . and starts or stops it with /.
class_name SunCycle
extends Node

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export_range(0.0, 24.0, 0.01) var time_of_day := 10.5      ## hours
@export var running := false
@export var day_minutes := 24.0                             ## real minutes for a whole day
@export var latitude := 47.79                               ## Satu Mare
@export_range(1, 365) var day_of_year := 230                ## mid August
@export var north_offset := 0.0                             ## degrees; north is -Z

const NOON_COLOUR := Color(1.0, 0.95, 0.86)
const LOW_COLOUR := Color(1.0, 0.62, 0.36)
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
const NIGHT_SKY := Color(0.05, 0.08, 0.17)
const NIGHT_HORIZON := Color(0.1, 0.14, 0.24)
const DUSK_HORIZON := Color(0.98, 0.66, 0.46)

var _env: Environment
var _sky: ProceduralSkyMaterial
var _base := {}
var _sun_energy := 1.35


func _ready() -> void:
	if sun:
		_sun_energy = sun.light_energy
	if world_environment and world_environment.environment:
		# a copy, so the shared environment resource is never changed
		_env = world_environment.environment.duplicate(true)
		world_environment.environment = _env
		_sky = _env.sky.sky_material as ProceduralSkyMaterial if _env.sky else null
		_base = {
			"ambient": _env.ambient_light_energy,
			"fog": _env.fog_light_color,
		}
		if _sky:
			_base["top"] = _sky.sky_top_color
			_base["horizon"] = _sky.sky_horizon_color
			_base["ground_horizon"] = _sky.ground_horizon_color
			_base["ground"] = _sky.ground_bottom_color
	apply()


func _process(delta: float) -> void:
	if running:
		time_of_day = fposmod(time_of_day + delta * 24.0 / (day_minutes * 60.0), 24.0)
		apply()


## Moves the clock by hours and updates everything.
func shift(hours: float) -> void:
	time_of_day = fposmod(time_of_day + hours, 24.0)
	apply()


func clock() -> String:
	var minutes := int(time_of_day * 60.0) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## Direction towards the sun (y up, north -Z) at hour t.
func sun_direction(t: float) -> Vector3:
	var lat := deg_to_rad(latitude)
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + day_of_year) / 365.0)
	var hour := deg_to_rad(15.0 * (t - 12.0))
	var elevation := asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hour))
	var azimuth := atan2(sin(hour), cos(hour) * sin(lat) - tan(decl) * cos(lat)) + PI \
			+ deg_to_rad(north_offset)
	return Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))


func apply() -> void:
	if sun == null:
		return
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
		sun.light_color = NOON_COLOUR.lerp(LOW_COLOUR, low * 0.85)
		sun.light_energy = _sun_energy * day * lerpf(0.65, 1.0, 1.0 - low)
	else:
		sun.light_color = MOON_COLOUR
		sun.light_energy = 0.16 * moonlit
	if _env == null:
		return
	var dusk := day * low * low                            # sunrise / sunset glow
	_env.ambient_light_energy = _base["ambient"] * lerpf(0.3, 1.0, day)
	_env.fog_light_color = _base["fog"].lerp(NIGHT_HORIZON, 1.0 - day).lerp(DUSK_HORIZON, dusk * 0.5)
	if _sky:
		_sky.sky_top_color = _base["top"].lerp(NIGHT_SKY, 1.0 - day)
		_sky.sky_horizon_color = _base["horizon"].lerp(NIGHT_HORIZON, 1.0 - day).lerp(DUSK_HORIZON, dusk * 0.7)
		_sky.ground_horizon_color = _base["ground_horizon"].lerp(NIGHT_HORIZON, 1.0 - day).lerp(DUSK_HORIZON, dusk * 0.5)
		_sky.ground_bottom_color = _base["ground"].lerp(NIGHT_SKY, 1.0 - day)
