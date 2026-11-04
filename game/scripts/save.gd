## The game's save file (user://save.json) and settings, an autoload named
## Save. Everything that should survive quitting goes through here: bottle
## caps found and spent, memory spots read, photos taken, where the boy was
## standing, and the options from the pause menu.
##
## Writes are batched: `changed()` marks the file dirty and it is written a
## second later (and on quit), so picking up ten caps in a row is one write.
extends Node

signal settings_changed
signal caps_changed(total: int)

const PATH := "user://save.json"
const VERSION := 1
const DEFAULT_SETTINGS := {
	"mouse_sensitivity": 0.003,
	"stick_sensitivity": 2.6,
	"invert_y": false,
	"fov": 60.0,
	"volume_master": 0.9,
	"volume_ambience": 0.8,
	"volume_effects": 0.9,
	"show_prompts": true,
	"camera_shake": true,
}

var data := {}
## The self-test and preview shots run on a fresh, unsaved game, so they
## never touch the player's real save.
var testing := "--selftest" in OS.get_cmdline_user_args() or "--shots" in OS.get_cmdline_user_args()
var _dirty := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_file()


func load_file() -> void:
	data = {"version": VERSION, "caps": 0, "caps_found": [], "memories": [], "photos": [],
			"bought": {}, "player": {}, "settings": DEFAULT_SETTINGS.duplicate(), "played_seconds": 0.0}
	if testing or not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		for k: String in parsed:
			if k == "settings":
				data.settings.merge(parsed.settings, true)
			else:
				data[k] = parsed[k]


func write_now() -> void:
	_dirty = 0.0
	if testing:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func changed() -> void:
	if _dirty <= 0.0:
		_dirty = 1.0


func _process(delta: float) -> void:
	if not get_tree().paused:
		data.played_seconds = float(data.get("played_seconds", 0.0)) + delta
	if _dirty > 0.0:
		_dirty -= delta
		if _dirty <= 0.0:
			write_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty > 0.0:
			write_now()


# --- settings ---------------------------------------------------------------

func setting(key: String) -> Variant:
	return data.settings.get(key, DEFAULT_SETTINGS.get(key))


func set_setting(key: String, value: Variant) -> void:
	data.settings[key] = value
	changed()
	settings_changed.emit()


# --- bottle caps ------------------------------------------------------------

func caps() -> int:
	return int(data.caps)


func has_found(id: String) -> bool:
	return id in data.caps_found


func find_cap(id: String, worth := 1) -> void:
	if has_found(id):
		return
	data.caps_found.append(id)
	data.caps = caps() + worth
	changed()
	caps_changed.emit(caps())


## false (and nothing spent) when there are not enough caps.
func spend(amount: int, what: String) -> bool:
	if caps() < amount:
		return false
	data.caps = caps() - amount
	data.bought[what] = int(data.bought.get(what, 0)) + 1
	changed()
	caps_changed.emit(caps())
	return true


# --- memories and photos ----------------------------------------------------

func has_memory(id: String) -> bool:
	return id in data.memories


func remember(id: String) -> bool:
	if has_memory(id):
		return false
	data.memories.append(id)
	changed()
	return true


func add_photo(file: String, where: Vector3) -> void:
	data.photos.append({"file": file, "x": snappedf(where.x, 0.1), "z": snappedf(where.z, 0.1),
			"time": Time.get_datetime_string_from_system()})
	changed()


# --- where he was -----------------------------------------------------------

func store_player(p: Vector3, yaw: float) -> void:
	data.player = {"x": p.x, "y": p.y, "z": p.z, "yaw": yaw}
	changed()


func player_spot() -> Dictionary:
	return data.get("player", {})
