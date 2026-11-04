## Something that sells things for bottle caps: the kiosk, the ice cream
## freezer, the drinks fridge, the fruit stand, the corner shop. Caps are
## the game's pocket money (found lying about, see CapField); each shop has
## a short list and every use buys the next thing on it.
##
## What he does with it: a drink is drunk on the spot (drink clip), an ice
## cream or a snack makes him happy for a while.
class_name Shop
extends Interactable

## [name, price in caps, what he does: "drink", "eat"]
const STOCK := {
	"kiosk": [["Gumă turbo", 1, "eat"], ["Seminţe", 2, "eat"], ["Suc la doză", 3, "drink"]],
	"ice_cream_freezer": [["Îngheţată pe băţ", 3, "eat"], ["Cornet", 4, "eat"]],
	"drinks_fridge": [["Apă minerală", 2, "drink"], ["Suc", 3, "drink"]],
	"fruit_stand": [["Măr", 1, "eat"], ["Cireşe", 2, "eat"]],
	"mini_market": [["Covrig", 1, "eat"], ["Ciocolată", 3, "eat"], ["Suc", 3, "drink"]],
}

## opening hours [from, to]; the kiosk is NON STOP
const HOURS := {"kiosk": [0.0, 24.0], "ice_cream_freezer": [9.0, 21.0], "drinks_fridge": [7.0, 22.0],
		"fruit_stand": [7.0, 19.0], "mini_market": [7.0, 22.0]}

@export var kind := "kiosk"
var _next := 0


func _init() -> void:
	reach = 1.6


func _item() -> Array:
	var list: Array = STOCK.get(kind, STOCK.kiosk)
	return list[_next % list.size()]


func is_open() -> bool:
	var sun: Node = get_tree().current_scene.get_node_or_null("SunCycle") if get_tree().current_scene else null
	var hour: float = sun.time_of_day if sun else 12.0
	var h: Array = HOURS.get(kind, [0.0, 24.0])
	return hour >= h[0] and hour < h[1]


func prompt_for(_kid: Node3D) -> String:
	if not is_open():
		var h: Array = HOURS.get(kind, [0.0, 24.0])
		return "Closed (open %d:00 to %d:00)" % [int(h[0]), int(h[1])]
	var it := _item()
	return "Buy %s (%d %s)" % [it[0], it[1], "cap" if it[1] == 1 else "caps"]


func can_interact(_kid: Node3D) -> bool:
	return true                           # anyone can queue at a shop


func interact(kid: Node3D) -> void:
	super.interact(kid)
	if not is_open():
		kid.perform("shake_head", 0.5)
		return
	var it := _item()
	var to := global_position - kid.global_position
	kid.body_mesh.rotation.y = atan2(to.x, to.z)
	if not Save.spend(it[1], it[0]):
		kid.perform("shake_head", 0.5)
		kid.face.express("sad", 1.5)
		get_tree().call_group("hud", "toast", "Not enough bottle caps for %s: you have %d, it costs %d." % [
				it[0], Save.caps(), it[1]])
		return
	_next += 1
	var length: float = kid.perform("interact", 0.9)
	get_tree().call_group("hud", "toast", "You bought %s." % it[0])
	get_tree().call_group("sound", "play_at", "buy", global_position, 1.0)
	get_tree().create_timer(length * 0.8).timeout.connect(func() -> void:
		if it[2] == "drink":
			kid.perform("drink", 0.8)
		kid.face.express("happy", 6.0))
