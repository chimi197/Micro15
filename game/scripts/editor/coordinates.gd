## The map's coordinate system, shared by the editor, the play-mode readout
## and pins: metres from the centre of the map, x growing to the east and z
## to the south (north is -z), y the height above the ground. A location is
## written "x 357.6, z 18.5" (and pasted the same way into "Go to").
class_name Coordinates
extends RefCounted

const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


static func text(p: Vector3, with_height := false) -> String:
	var out := "x %.1f, z %.1f" % [p.x, p.z]
	if with_height:
		out += ", height %.1f" % p.y
	return out


## Compass direction of a flat vector (x east, y = world z south).
static func compass(dir: Vector2) -> String:
	if dir.length() < 0.001:
		return "-"
	var angle := fposmod(rad_to_deg(atan2(dir.x, -dir.y)), 360.0)    # 0 = north, 90 = east
	return DIRECTIONS[int(round(angle / 45.0)) % 8]


## Reads "x 357.6, z 18.5", "357.6 18.5", "357.6, 18.5" or "x=357.6 z=18.5":
## Vector2(x, z), or Vector2.INF if it is not a location.
static func parse(s: String) -> Vector2:
	var numbers := []
	var regex := RegEx.create_from_string("-?\\d+(\\.\\d+)?")
	for m in regex.search_all(s):
		numbers.append(m.get_string().to_float())
	if numbers.size() == 2:
		return Vector2(numbers[0], numbers[1])
	if numbers.size() == 3:
		return Vector2(numbers[0], numbers[2])            # x, height, z
	return Vector2.INF
